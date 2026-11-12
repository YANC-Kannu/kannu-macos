/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Combine
import Defaults
import SwiftUI

/// The Agent Security tab: what was found, ADR's scans, Kannu's own checks, the agent policy,
/// and opt-in session analysis. Split out of the Agents tab, which keeps the behaviour controls
/// (traffic light, indicator, click-through, hooks, notifications) — one tab says how agents
/// look, this one says whether they are safe. A product page: the findings lead
/// (`SecurityOverview`), and these settings follow.
struct AgentSecuritySettings: View {
    @ObservedObject private var adr = ADRConnection.shared
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.adrSnapshotDirectory) var adrSnapshotDirectory
    @Default(.adrToolDirectory) var adrToolDirectory
    @Default(.adrHighAlertMode) var adrHighAlertMode
    @Default(.adrPolicyFile) var adrPolicyFile
    @Default(.adrRunScansEnabled) var adrRunScansEnabled
    @Default(.adrDetectionEnabled) var adrDetectionEnabled
    @Default(.detectHiddenText) var detectHiddenText
    @Default(.adrDetectionConsentedAt) var adrDetectionConsentedAt
    @Default(.adrDetectionCheckout) var adrDetectionCheckout
    @Default(.adrDetectionConfirmEachRun) var adrDetectionConfirmEachRun
    @Default(.adrDetectionTriageEnabled) var adrDetectionTriageEnabled
    @Default(.adrDetectionTriageModel) var adrDetectionTriageModel
    @Default(.adrDetectionReasoningModel) var adrDetectionReasoningModel
    @Default(.adrDetectionUseAnthropicAPIKey) var adrDetectionUseAnthropicAPIKey
    @Default(.adrDetectionContextThreatIntelligence) var adrDetectionContextThreatIntelligence
    @Default(.adrDetectionContextSourceCode) var adrDetectionContextSourceCode
    @Default(.adrDetectionContextPolicy) var adrDetectionContextPolicy
    @Default(.adrDetectionTimeoutSeconds) var adrDetectionTimeoutSeconds
    @Default(.adrDetectionMaxMessages) var adrDetectionMaxMessages
    @Default(.adrDetectionMaxCharacters) var adrDetectionMaxCharacters
    @Default(.enableAgentStatusFeature) var enableAgentStatusFeature
    @State private var adrOpenAIKeyText = ""
    @State private var adrAnthropicKeyText = ""
    @State private var showDetectionConsent = false
    /// The rule editor's draft while its sheet is open.
    @State private var policyDraft: AgentPolicyDraft?
    /// Which ADR Detection keys the keychain holds; see `adrSecretRow`.
    @State private var storedADRSecrets: Set<SecureSecretKey> = []
    /// What the page shows from the findings store, the product and these settings alike: a copy, never the store
    /// itself, which republishes on every hook write while a session runs with permission checks off. Read as the page
    /// appears and as Brain comes back on screen, then followed at most twice a second while it is on screen, and
    /// assigned only when it changed. Off screen it stays as it was (docs/SETTINGS.md, "Live data").
    @State private var security = SecurityPageData()

    /// The literal form: the highlight inventory test accepts exactly this shape (the UsageSettings
    /// precedent).
    private func highlightID(_ title: String) -> String {
        "agentSecurity-\(title)"
    }

    var body: some View {
        // The product first, then its settings (docs/SETTINGS.md, "Product pages").
        SettingsProductPage(settingsTitle: String(localized: "Security settings")) {
            SecurityOverview(data: security)
        } settings: {
            if enableAgentStatusFeature {
                alertsSection
                adrDiscoverySection
                kannuChecksSection
                agentPolicySection
                sessionAnalysisSections
            } else {
                SettingsSection {
                    SettingsFooter("Agent monitoring is off. Turn on Enable Agent Status in the Agents tab and the security checks, findings and scans appear here.")
                } header: {
                    SettingsSectionHeader("Agent security")
                }
            }
        }
        .onAppear {
            refreshStoredADRSecrets()
            #if DEBUG
            if let fixture = SecurityOverview.snapshotFixture {
                security = fixture.data
                return
            }
            #endif
            // One read, not a subscription: the page opens on what the store holds, and the subscription below takes
            // over once Brain is on screen.
            copyFromStore()
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if SecurityOverview.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            // Back on screen: what changed while Brain was not, which `objectWillChange` will not send again.
            copyFromStore()
            // `objectWillChange` comes before a change; read through the run loop, the copy comes after it.
            for await _ in SecurityFindingsStore.shared.objectWillChange
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                copyFromStore()
            }
        }
        .navigationTitle("Security")
    }

    /// The one place the page reads the store's state: a fresh copy, assigned only when it changed.
    private func copyFromStore() {
        let latest = SecurityPageData(SecurityFindingsStore.shared)
        if latest != security { security = latest }
    }

    // MARK: - Alerts

    /// How a high-severity finding shows in the closed notch. The findings themselves lead the page, above.
    private var alertsSection: some View {
        SettingsSection {
            SettingsRow("High-severity alerts in the notch", description: adrHighAlertMode.description) {
                SettingsSelect("High-severity alerts in the notch", selection: $adrHighAlertMode,
                               options: ADRHighAlertMode.allCases, optionTitle: \.localizedName)
            }
            .settingsHighlight(id: highlightID("High-severity alerts in the notch"))
        } header: {
            SettingsSectionHeader("Alerts")
        }
    }

    /// The ADR area, glance-first: the scanner's status, the scan controls, the newest result —
    /// then everything a first-time user does not need (folders, the scan policy, the optional
    /// Sensor) behind one Advanced disclosure. Search entries for the tucked-away rows land on
    /// the disclosure itself, so search never points at a hidden row.
    private var adrDiscoverySection: some View {
        SettingsSection {
            adrToolRow(.discovery)
                .settingsHighlight(id: highlightID("Connect ADR"))
            if !adr.discovery.isFound && adr.discovery.state != .unchecked {
                adrInstallGuidance(.discovery)
            }

            if adr.discovery.isFound {
                SettingsRow("Let Kannu run scans", description: "Scans daily and whenever an AI tool's MCP servers change.") {
                    Defaults.Toggle(key: .adrRunScansEnabled) {
                        Text("Let Kannu run scans")
                    }
                }
                .settingsHighlight(id: highlightID("Let Kannu run scans"))

                LabeledContent {
                    Button(security.isScanning ? "Scanning…" : "Scan now") {
                        SecurityFindingsStore.shared.runScanNow(reason: "manual")
                    }
                    .disabled(security.isScanning)
                } label: {
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                        Text("Scan this Mac")
                        Group {
                            if let at = security.lastKannuScanAt {
                                Text("Last run by Kannu \(at.formatted(date: .abbreviated, time: .shortened))")
                            } else {
                                Text("Not run by Kannu yet")
                            }
                        }
                        .settingsDescriptionStyle()
                        if adrRunScansEnabled, security.automaticScansActive, !security.isScanning {
                            Text(verbatim: security.nextAutomaticScanText)
                                .settingsDescriptionStyle()
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Scan now"))
                if let error = security.lastScanError {
                    SettingsErrorText(error)
                }
            }

            // Folders, ADR's own scan policy and the optional Sensor: needed rarely, and the
            // reason this section used to read as a wall. Entries in the search index for these
            // rows point at this disclosure's id (docs/SETTINGS.md).
            DisclosureGroup {
                LabeledContent {
                    HStack(spacing: SettingsMetrics.rowContent) {
                        SettingsValueText(adrToolDirectory.isEmpty
                                          ? String(localized: "Standard places")
                                          : adrToolDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        Button("Choose…") { chooseToolDirectory() }
                        if !adrToolDirectory.isEmpty {
                            Button("Clear") {
                                adrToolDirectory = ""
                                adr.checkAgain()
                                adr.checkDetection()
                            }
                        }
                    }
                } label: {
                    SettingsRowLabel("ADR tools folder", description: "Only needed if the tools are somewhere else.")
                }
                if let protected = ADRToolFolder.protectedFolderName(for: adrToolDirectory, home: NSHomeDirectory()) {
                    SettingsErrorText(String(localized: "This folder is in \(protected). macOS asks for permission whenever Kannu looks for the tools there; a folder outside it avoids the prompt."))
                }

                LabeledContent {
                    HStack(spacing: SettingsMetrics.rowContent) {
                        SettingsValueText(SecurityFindingsStore.snapshotDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        Button("Choose…") { chooseSnapshotDirectory() }
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([SecurityFindingsStore.snapshotDirectory])
                        }
                    }
                } label: {
                    SettingsRowLabel("Snapshot folder", description: "Where scan snapshots are saved and read.")
                }

                if adr.discovery.isFound {
                    LabeledContent {
                        HStack(spacing: SettingsMetrics.rowContent) {
                            SettingsValueText(adrPolicyFile.isEmpty ? String(localized: "none") : adrPolicyFile.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            Button("Choose…") { choosePolicyFile() }
                            if !adrPolicyFile.isEmpty {
                                Button("Clear") { adrPolicyFile = "" }
                            }
                        }
                    } label: {
                        SettingsRowLabel("ADR scan policy", description: "Your organization's domains and, optionally, what it forbids.")
                    }
                    // Its own line, so Choose… and Clear do not crowd the caption.
                    SettingsActionRow {
                        Button("Copy a prompt that drafts a policy") { SecurityFindingsStore.shared.copyADRPolicyDraftingPrompt() }
                    }
                    if SecurityFindingsStore.policyFileIsMissing {
                        SettingsErrorText(String(localized: "That policy file is not there any more, so scans run without it. Choose it again, or clear it."))
                    }
                }

                adrToolRow(.sensor)
            } label: {
                SettingsRowLabel("Advanced", description: "Folders, ADR's scan policy, and the optional Sensor.")
            }
            .settingsHighlight(id: highlightID("ADR advanced"))
        } header: {
            SettingsSectionHeader("ADR scans")
        } footer: {
            SettingsFooter("Scans this Mac's AI tools and MCP servers for risky setups — unpinned or plain-HTTP servers, servers nothing declares. From ADR, Uber's open-source toolkit (Apache-2.0): you install it once, Kannu runs it and reads the results.")
        }
        // The settings' own checks, once a visit, as they ran before the findings moved up: ADR's tools if never
        // looked for, and the Detection checkout while analysis is on and it was never checked. Nothing else checks
        // the checkout at launch, and the notch's Analyze menu waits for it.
        .onAppear {
            if adr.discovery.state == .unchecked { adr.checkAgain() }
            if adrDetectionEnabled, adr.detection.state == .unchecked { adr.checkDetection() }
        }
    }

    private var kannuChecksSection: some View {
        SettingsSection {
            SettingsRow("Look for hidden text in what agents read", description: "Flags invisible characters that can hide instructions.") {
                Defaults.Toggle(key: .detectHiddenText) {
                    Text("Look for hidden text in what agents read")
                }
            }
            .settingsHighlight(id: highlightID("Look for hidden text in what agents read"))

            SettingsRow("Tell the agent when hidden text is found", description: "Gives the agent a short note, never the hidden text.") {
                Defaults.Toggle(key: .warnAgentAboutHiddenText) {
                    Text("Tell the agent when hidden text is found")
                }
            }
            .disabled(!detectHiddenText)
            .settingsHighlight(id: highlightID("Tell the agent when hidden text is found"))

            SettingsRow("Look for secrets in prompts and tool calls", description: "Flags API keys and private keys.") {
                Defaults.Toggle(key: .detectSecrets) {
                    Text("Look for secrets in prompts and tool calls")
                }
            }
            .settingsHighlight(id: highlightID("Look for secrets in prompts and tool calls"))

            SettingsRow("Watch for agents touching sensitive files", description: "Flags agents reading secrets or changing auto-run files.") {
                Defaults.Toggle(key: .detectSensitivePaths) {
                    Text("Watch for agents touching sensitive files")
                }
            }
            .settingsHighlight(id: highlightID("Watch for agents touching sensitive files"))

            SettingsRow("Notice new MCP servers", description: "Tells you when an AI tool gains an MCP server.") {
                Defaults.Toggle(key: .watchMCPServers) {
                    Text("Notice new MCP servers")
                }
            }
            .settingsHighlight(id: highlightID("Notice new MCP servers"))
        } header: {
            SettingsSectionHeader("Kannu's own checks")
        } footer: {
            SettingsFooter("These checks run on this Mac and send nothing anywhere. A finding about a key never stores the key. Kannu also flags sessions started with permission checks turned off; that check has no setting.")
        }
    }

    /// The user's own block list, enforced where a host's hook can refuse a call.
    private var agentPolicySection: some View {
        SettingsSection {
            // A raw LabeledContent, NOT SettingsRow: the row component applies `.labelsHidden()`
            // to its whole control slot (meant for the Toggle/Picker case), and a Menu in that
            // slot inherits it — the ellipsis collapsed and the "…" menu was dead. Same shape as
            // `SecurityAnalysisRow`, the working SettingsMoreMenu site. See docs/SETTINGS.md.
            LabeledContent {
                HStack(spacing: SettingsMetrics.rowContent) {
                    if security.policyIsEditable {
                        // No file yet opens an empty editor; Save creates the file.
                        Button(String(localized: "Edit rules")) { openRuleEditor() }
                    } else {
                        // The editor cannot read a broken file, so the file's own editor is the way in.
                        Button(String(localized: "Open in editor")) { openAgentPolicyInEditor() }
                    }
                    SettingsMoreMenu {
                        if security.policyIsEditable {
                            Button("Open in editor") { openAgentPolicyInEditor() }
                                .disabled(!security.policyExists)
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([AgentPolicy.fileURL])
                        }
                        .disabled(!security.policyExists)
                        Button("Check again") { SecurityFindingsStore.shared.checkAgentPolicy() }
                    }
                }
            } label: {
                // Status under the title, as in `adrToolRow`: beside the buttons it squeezed the
                // caption into a narrow column of four short lines.
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text("Policy rules")
                    SettingsStatusText(security.policyStatusText, isReady: security.policyIsReady)
                    Text("Commands and tools your agents may not use.")
                        .settingsDescriptionStyle()
                }
            }
            .settingsHighlight(id: highlightID("Policy rules"))
            if security.policyIgnoredByHook {
                // The hook ignores a malformed file whole (docs/REGRESSIONS.md entry 1: it never
                // fails closed), so say what that costs rather than only what is wrong.
                SettingsErrorText(String(localized: "Until this is fixed, none of these rules apply."))
            }
            SettingsActionRow("Get a policy", description: "Write rules, have an agent draft them, or import.") {
                Button("Import…") { importAgentPolicy() }
                Button("Copy a prompt that drafts a policy") { SecurityFindingsStore.shared.copyPolicyDraftingPrompt() }
            }
            .settingsHighlight(id: highlightID("Get a policy"))
            if let importError = security.policyImportError {
                SettingsErrorText(String(localized: "Not imported — \(importError)"))
            }
            SettingsRow("Block matching tool calls", description: Text("Claude Code, Cursor and Antigravity (untested) refuse matching calls.")) {
                Defaults.Toggle(key: .enforceAgentPolicy) {
                    Text("Block matching tool calls")
                }
            }
            .settingsHighlight(id: highlightID("Block matching tool calls"))
        } header: {
            SettingsSectionHeader("Agent policy")
        } footer: {
            SettingsFooter("A command rule matches the command's first word, so \"ssh\" catches \"ssh host\" but not \"sshd\". A tool rule matches the tool's exact name. Other agents are only flagged.")
        }
        .onAppear {
            SecurityFindingsStore.shared.agentPolicyImportError = nil
            SecurityFindingsStore.shared.checkAgentPolicy()
        }
        .sheet(item: $policyDraft) { draft in
            PolicyRulesEditor(draft: draft)
        }
    }

    /// The "Import…" button: pick a JSON file, validate it with the same parser the status row
    /// uses, and only then copy it into place — with a confirm when a policy already exists.
    private func importAgentPolicy() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a policy file to import")
        ModalPresenter.present(panel) { response in
            // A fresh copy first: Replace is asked on what the store holds now, never on a copy half a second old.
            copyFromStore()
            guard response == .OK, let url = panel.url else { return }
            let proceed = { SecurityFindingsStore.shared.importPolicyFile(from: url) }
            if security.policyExists {
                let alert = NSAlert()
                alert.messageText = String(localized: "Replace the current policy?")
                alert.informativeText = String(localized: "Your current rules will be replaced by the ones in this file.")
                alert.addButton(withTitle: String(localized: "Replace"))
                alert.addButton(withTitle: String(localized: "Cancel"))
                ModalPresenter.present(alert) { answer in
                    if answer == .alertFirstButtonReturn { proceed() }
                }
            } else {
                proceed()
            }
        }
    }

    private func openRuleEditor() {
        SecurityFindingsStore.shared.openAgentPolicyDraft { draft in
            if let draft { policyDraft = draft } else { SecurityFindingsStore.shared.checkAgentPolicy() }
        }
    }

    /// "Open in Editor": the file in the user's default app for JSON, for anyone who would rather
    /// edit it there. The store's watcher re-checks on every save. If no app claims JSON, show the
    /// file in Finder instead of doing nothing.
    private func openAgentPolicyInEditor() {
        if !NSWorkspace.shared.open(AgentPolicy.fileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([AgentPolicy.fileURL])
        }
    }

    /// ADR Detection — off by default, behind a consent alert, and every run is the user's click.
    @ViewBuilder
    private var sessionAnalysisSections: some View {
        SettingsSection {
            // Consent is asked through a SwiftUI alert, not a modal inside the binding setter: a
            // nested run loop there fought the toggle's own state update and the switch fell back.
            SettingsRow("Analyze chats with ADR Detection", description: "Opt-in: right-click a finished Claude Code chat in the notch.") {
                Toggle(isOn: Binding(
                    get: { adrDetectionEnabled },
                    set: { newValue in
                        guard newValue else { adrDetectionEnabled = false; return }
                        if adrDetectionConsentedAt == nil {
                            showDetectionConsent = true
                            return
                        }
                        adrDetectionEnabled = true
                        adr.checkDetection()
                    }
                )) {
                    Text("Analyze chats with ADR Detection")
                }
            }
            .settingsHighlight(id: highlightID("Analyze chats with ADR Detection"))
            .alert("Turn on ADR Detection session analysis?", isPresented: $showDetectionConsent) {
                Button("Turn on") {
                    adrDetectionConsentedAt = Date()
                    adrDetectionEnabled = true
                    adr.checkDetection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(detectionConsentText)
            }

            if adrDetectionEnabled {
                detectionCheckoutRows
            }
        } header: {
            SettingsSectionHeader("Session analysis")
        } footer: {
            SettingsFooter("Each analysis sends one chat's transcript to your model providers under your own keys. Nothing is sent automatically.")
        }

        if adrDetectionEnabled {
            detectionSetupSections
        }
    }

    /// Where ADR Detection lives and whether it is ready; shown once analysis is on.
    @ViewBuilder
    private var detectionCheckoutRows: some View {
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                SettingsValueText(adrDetectionCheckout.isEmpty ? String(localized: "none") : adrDetectionCheckout.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                Button("Choose…") { chooseDetectionCheckout() }
                Button("Check") { adr.checkDetection() }
            }
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text("Detection checkout")
                SettingsStatusText(adr.detection.caption, isReady: adr.detection.isReady)
            }
        }
        .settingsHighlight(id: highlightID("Detection checkout"))

        LabeledContent {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ADRConnection.detectionCloneCommand, forType: .string)
            }
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: ADRConnection.detectionCloneCommand)
                    .settingsDescriptionStyle()
                    .monospaced()
                Text("Needs uv and Python 3.10–3.12 (uv fetches one). ADR Detection is Uber's research tool (Apache-2.0); it runs an unattended Claude session on this Mac to reason about the chat, with file edits disallowed.")
                    .settingsDescriptionStyle()
            }
        }
    }

    /// Models, keys, context and limits for ADR Detection. The recent analyses lead the page, above.
    @ViewBuilder
    private var detectionSetupSections: some View {
        SettingsSection {
            SettingsRow("Reasoning model (Claude)") {
                TextField("Reasoning model (Claude)", text: $adrDetectionReasoningModel)
                    .settingsField()
            }
            .settingsHighlight(id: highlightID("Reasoning model"))
            SettingsRow("Use an Anthropic API key instead of your Claude Code login",
                        description: adrDetectionUseAnthropicAPIKey
                            ? String(localized: "Analyses are billed to the API key below.")
                            : String(localized: "Analyses count against your Claude subscription's 5-hour and weekly limits.")) {
                Toggle("Use an Anthropic API key instead of your Claude Code login", isOn: $adrDetectionUseAnthropicAPIKey)
            }
            .settingsHighlight(id: highlightID("Use an Anthropic API key"))
            if adrDetectionUseAnthropicAPIKey {
                adrSecretRow(title: "Anthropic API key", key: .claudeAPIKey, text: $adrAnthropicKeyText)
            }

            SettingsRow("Triage with OpenAI first", description: "A cheap gpt-4o pass decides whether Claude runs.") {
                Toggle("Triage with OpenAI first", isOn: $adrDetectionTriageEnabled)
            }
            .settingsHighlight(id: highlightID("Triage with OpenAI first"))
            if adrDetectionTriageEnabled {
                SettingsRow("Triage model (OpenAI)") {
                    TextField("Triage model (OpenAI)", text: $adrDetectionTriageModel)
                        .settingsField()
                }
                adrSecretRow(title: "OpenAI API key", key: .openaiAPIKey, text: $adrOpenAIKeyText)
            }
        } header: {
            SettingsSectionHeader("Analysis models")
        }

        SettingsSection {
            Toggle("Context: threat intelligence", isOn: $adrDetectionContextThreatIntelligence)
                .settingsHighlight(id: highlightID("Context servers"))
            Toggle("Context: source code analyzer", isOn: $adrDetectionContextSourceCode)
            Toggle("Context: policy store", isOn: $adrDetectionContextPolicy)
            SettingsRow("Reasoning timeout") {
                SettingsSelect("Reasoning timeout", selection: $adrDetectionTimeoutSeconds, choices: [
                    120: String(localized: "2 minutes"),
                    300: String(localized: "5 minutes"),
                    600: String(localized: "10 minutes"),
                ])
            }
            SettingsRow("Messages sent (newest)") {
                SettingsSelect("Messages sent (newest)", selection: $adrDetectionMaxMessages, choices: [
                    100: String(localized: "100"),
                    200: String(localized: "200"),
                    400: String(localized: "400"),
                    800: String(localized: "800"),
                ])
            }
            .settingsHighlight(id: highlightID("Messages sent"))
            SettingsRow("Transcript budget") {
                SettingsSelect("Transcript budget", selection: $adrDetectionMaxCharacters, choices: [
                    60_000: String(localized: "60k characters"),
                    150_000: String(localized: "150k characters"),
                    400_000: String(localized: "400k characters"),
                    0: String(localized: "No limit"),
                ])
            }
            .settingsHighlight(id: highlightID("Transcript budget"))
            Toggle("Confirm before every analysis", isOn: $adrDetectionConfirmEachRun)
                .settingsHighlight(id: highlightID("Confirm before every analysis"))
        } header: {
            SettingsSectionHeader("Analysis context and limits")
        } footer: {
            SettingsFooter("The context options are ADR's local MCP servers and read only bundled data and this Mac. The transcript budget caps what one analysis sends.")
        }
    }

    /// `stored` comes from `storedADRSecrets`, read when the tab appears and updated by Save and
    /// Remove — never a keychain read per render (the tab re-renders whenever what it shows changes).
    @ViewBuilder
    private func adrSecretRow(title: String, key: SecureSecretKey, text: Binding<String>) -> some View {
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                SecureField(title, text: text)
                    .settingsField()
                Button("Save") {
                    SecureSecretsStore.set(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines), for: key)
                    text.wrappedValue = ""
                    refreshStoredADRSecrets()
                }
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if storedADRSecrets.contains(key) {
                    Text("stored")
                        .settingsDescriptionStyle()
                    Button("Remove") {
                        SecureSecretsStore.removeValue(for: key)
                        refreshStoredADRSecrets()
                    }
                }
            }
        } label: {
            SettingsRowLabel(verbatim: title)
        }
    }

    private func refreshStoredADRSecrets() {
        storedADRSecrets = Set([SecureSecretKey.claudeAPIKey, .openaiAPIKey].filter { !SecureSecretsStore.value(for: $0).isEmpty })
    }

    /// The one-time consent, in plain words: what leaves the Mac, where, and when.
    private var detectionConsentText: String {
        String(localized: """
        Nothing is analysed automatically. When you right-click a finished chat and choose "Analyze with ADR Detection", that one chat's transcript is sent out:

        • to Anthropic, through your Claude Code login (uses your Claude quota) or an API key you store;
        • to OpenAI, only if you turn triage on.

        By default Kannu asks before every run. ADR Detection is a research tool from Uber (Apache-2.0); it runs an unattended Claude session on this Mac with file edits disallowed.
        """)
    }

    private func chooseDetectionCheckout() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use checkout")
        panel.message = String(localized: "Choose the ADR/Detection folder you cloned and synced with uv")
        ModalPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            adrDetectionCheckout = url.path
            adr.checkDetection()
        }
    }

    /// An ADR tool: its name, and a status line with a dot (green when installed); Discovery also
    /// gets "Check again".
    private func adrToolRow(_ tool: ADRConnection.Tool) -> some View {
        let status = tool == .discovery ? adr.discovery : adr.sensor
        return LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                // Kannu never installs software: the command is copied for the user to run.
                if tool == .sensor, status.state == .notFound {
                    Button("Copy install command") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(tool.installCommand, forType: .string)
                    }
                }
                Button(adr.isChecking ? "Checking…" : "Check again") { adr.checkAgain() }
                    .disabled(adr.isChecking)
            }
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                if tool == .sensor {
                    (Text("ADR Sensor") + Text(verbatim: " · ") + Text("Optional").foregroundStyle(.secondary))
                        .textSelection(.enabled)
                } else {
                    Text(tool.displayName)
                }
                SettingsStatusText(adrStatusCaption(status, optional: tool == .sensor), isReady: status.isFound)
                if tool == .sensor {
                    Text("Not needed for findings, and Kannu does not use it yet. It exports agent sessions for a security team's SIEM.")
                        .settingsDescriptionStyle()
                }
            }
        }
    }

    private func chooseToolDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use folder")
        ModalPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            adrToolDirectory = url.path
            adr.checkAgain()
            adr.checkDetection()
        }
    }

    private func adrStatusCaption(_ status: ADRConnection.Status, optional: Bool = false) -> String {
        switch status.state {
        case .unchecked: return String(localized: "Not checked yet")
        case .notFound: return optional ? String(localized: "Not installed — optional") : String(localized: "Not installed")
        case .found(let executable, let version):
            let shortPath = executable.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return version.map { "\($0) · \(shortPath)" } ?? shortPath
        }
    }

    @ViewBuilder
    private func adrInstallGuidance(_ tool: ADRConnection.Tool) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.footerStack) {
            SettingsPermissionCallout(
                title: String(localized: "Connect ADR"),
                message: String(localized: "Install ADR Discovery once with uv (or pipx), then press Check again. Requires Python 3.11 or newer; uv brings its own."),
                icon: "shield.lefthalf.filled",
                iconColor: SettingsTheme.accentStrong,
                requestButtonTitle: String(localized: "Copy install command"),
                openSettingsButtonTitle: String(localized: "Open ADR on GitHub"),
                requestAction: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(tool.installCommand, forType: .string)
                },
                openSettingsAction: { NSWorkspace.shared.open(ADRConnection.projectURL) }
            )
            Text(verbatim: tool.installCommand)
                .settingsDescriptionStyle()
                .monospaced()
        }
    }

    private func choosePolicyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = String(localized: "Use policy")
        ModalPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            adrPolicyFile = url.path
        }
    }

    private func chooseSnapshotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = SecurityFindingsStore.snapshotDirectory
        panel.prompt = String(localized: "Use folder")
        ModalPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            adrSnapshotDirectory = url.path
            SecurityFindingsStore.shared.directoryChanged()
        }
    }
}

#if DEBUG
extension AgentSecuritySettings {
    /// DEBUG snapshot harness: the ADR Detection rows that only show once analysis is on, without
    /// turning it on (the harness shares the user's Defaults).
    static func snapshotDetectionRows() -> AnyView {
        let settings = AgentSecuritySettings()
        return AnyView(SettingsPage {
            SettingsSection { settings.detectionCheckoutRows } header: { SettingsSectionHeader("Session analysis") }
            settings.detectionSetupSections
        })
    }

    /// DEBUG snapshot harness: the findings rows as the Security findings section draws them.
    /// Groups the fixtures exactly as the real section does, so the board shows the recurrence line
    /// and the scoped Acknowledge rather than a shape the product no longer has.
    static func snapshotFindingRows(_ findings: [AgentSecurityFinding]) -> AnyView {
        let groups = SecurityFindingsStore.buildGroupRanking(
            findings: findings, acknowledgedGroups: [:], legacyAcknowledged: [], snoozes: []
        )
        return AnyView(SettingsPage {
            SettingsSection {
                ForEach(groups.rows, id: \.group.id) { row in
                    SecurityFindingRow(row: row, copyForAgent: {}, acknowledge: { _ in }, snooze: {},
                                       openChat: row.group.representative.sessionID == nil ? nil : {})
                }
            } header: {
                SettingsSectionHeader("Security findings")
            }
        })
    }
}
#endif
