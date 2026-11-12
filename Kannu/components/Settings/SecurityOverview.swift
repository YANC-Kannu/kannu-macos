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

/// Brain › Security's product, above its settings: how many findings wait, the findings, then the newest scan, Kannu's
/// own scans and the agent policy, and the recent analyses (docs/SETTINGS.md, "Product pages").
///
/// It shows what the findings store holds and starts nothing of its own: no scan, no ADR check, no policy read and no
/// analysis. Its one verb, Scan now or Connect ADR, acts only on a press, through the paths the settings already use.
///
/// The store republishes on every hook write while a session runs with permission checks off, so nothing here observes
/// it. `AgentSecuritySettings`, which holds this and the settings below, copies what both show into one value,
/// `SecurityPageData`, at most twice a second while Brain is on screen, and hands it down; off screen the copy stays as
/// it was (docs/SETTINGS.md, "Live data"). The page keeps no clock.
struct SecurityOverview: View {
    let data: SecurityPageData
    /// Publishes only around a check of ADR's tools, which runs at start, on a press, or once a visit while never run.
    @ObservedObject private var adr = ADRConnection.shared
    @Default(.enableAgentStatusFeature) private var enabled
    @Default(.adrDetectionEnabled) private var detectionEnabled

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's findings, scans, policy and
    /// analyses, so none of them lands in a PNG. Set, the page never subscribes to the store.
    static var snapshotFixture: SecurityOverviewFixture?
    #endif

    /// Whether ADR Discovery was found, which picks the page's verb: Scan now, or Connect ADR. On a board, the fixture's.
    static func adrConnected(_ adr: ADRConnection) -> Bool {
        #if DEBUG
        if let fixture = snapshotFixture { return fixture.adrConnected }
        #endif
        return adr.isConnected
    }

    /// Recent analyses show while session analysis is on, as they did among its settings.
    private var showsAnalyses: Bool {
        #if DEBUG
        if let fixture = Self.snapshotFixture { return fixture.detectionEnabled }
        #endif
        return detectionEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if !enabled {
                // The store stops with Agent Status, so there is nothing current to show.
                SettingsSection {
                    SecurityMessage(title: String(localized: "Agent Status is off"), message: nil) {
                        Button("Turn on") { enabled = true }
                    }
                }
            } else {
                // Gone while all three counts are zero: every group is to review or acknowledged, and High is a part of
                // To review.
                if !data.groups.isEmpty {
                    SecurityCountStrip(groups: data.groups)
                }
                findings
                SecurityStatusRow(data: data, connected: Self.adrConnected(adr))
                if showsAnalyses, data.lastAnalysisError != nil || !data.analyses.isEmpty {
                    analyses
                }
            }
        }
    }

    // MARK: - The findings

    /// Every finding that waits for review, worst first, or the card in their place. One row per problem, not per
    /// sighting: 21 rotations of one credential are one thing to act on. The notch's link and search land on the header,
    /// which is always built.
    private var findings: some View {
        let visible = data.groups.visible
        return SettingsSection {
            if visible.isEmpty {
                SecurityMessage(
                    title: data.lastScan == nil ? String(localized: "No findings yet") : String(localized: "No open findings"),
                    message: String(localized: "Findings from ADR's scans and Kannu's own checks show here.")
                ) {
                    SecurityVerb(connected: Self.adrConnected(adr), scanning: data.isScanning)
                }
            } else {
                // Lazy: findings pile up across scans, and a plain stack builds every row as the page opens. A search
                // or the notch's deep link lands on this section's header, never on a row (docs/SETTINGS.md, "Pages
                // and sections").
                LazyVStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {
                    ForEach(visible, id: \.group.id) { row in
                        let finding = row.group.representative
                        SecurityFindingRow(
                            row: row,
                            copyForAgent: { SecurityFindingsStore.shared.copyAgentPrompt(for: finding) },
                            acknowledge: { SecurityFindingsStore.shared.acknowledgeGroup(row.group, projects: $0) },
                            snooze: { SecurityFindingsStore.shared.snooze(row.group.id, for: 24 * 3600) },
                            openChat: data.hasChat(for: finding)
                                ? { if !SecurityFindingsStore.shared.openChat(for: finding) { NSSound.beep() } }
                                : nil
                        )
                    }
                }
            }
        } header: {
            SettingsSectionHeader("Security findings")
                .settingsHighlight(id: SettingsDeepLink.securityFindingsHighlightID)
        } footer: {
            SettingsFooter("Detection is best-effort: an empty list is not proof that nothing happened. Kannu never changes your agent or MCP settings, and nothing leaves this Mac unless you turn on push notifications or session analysis.")
        }
    }

    // MARK: - Recent analyses

    private var analyses: some View {
        SettingsSection {
            if let error = data.lastAnalysisError {
                SettingsErrorText(error)
            }
            ForEach(data.analyses.prefix(5)) { analysis in
                SecurityAnalysisRow(analysis: analysis)
            }
        } header: {
            SettingsSectionHeader("Recent analyses")
        }
    }
}

/// Security's header actions (docs/SETTINGS.md, "Product pages"): the gear, which goes to the page's settings, then the
/// page's one primary verb, Scan now, or Connect ADR while ADR Discovery is not found. Nothing while Agent Status is off,
/// since the scans and the settings below wait for it.
struct SecurityHeaderActions: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @ObservedObject private var adr = ADRConnection.shared
    @Default(.enableAgentStatusFeature) private var enabled
    /// Whether a scan Kannu started is running, followed only while Brain is on screen.
    @State private var scanning = false

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            if enabled {
                Button {
                    // The first settings row, which is built whenever Agent Status is on.
                    SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.securityAlertsHighlightID)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SettingsButtonStyle(.quiet))
                .help(String(localized: "Security settings"))
                .accessibilityLabel(String(localized: "Security settings"))
                SecurityVerb(connected: SecurityOverview.adrConnected(adr), scanning: scanning)
                    .buttonStyle(SettingsButtonStyle(.primary))
            }
        }
        // One value, passed on only when it changes; `$isScanning` sends the current one as it subscribes.
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            for await busy in SecurityFindingsStore.shared.$isScanning
                .removeDuplicates()
                .values {
                scanning = busy
            }
        }
    }
}

/// The page's one verb: Scan now while ADR Discovery is found, off while a scan runs, or Connect ADR. Each acts only on a
/// press, through today's paths: Scan now is the manual scan the settings' Scan this Mac runs, and Connect ADR goes to
/// ADR Discovery's row below, with its install command and Check again. The header draws it primary, the empty state
/// in the standard style.
private struct SecurityVerb: View {
    let connected: Bool
    let scanning: Bool

    var body: some View {
        if connected {
            Button("Scan now") {
                SecurityFindingsStore.shared.runScanNow(reason: "manual")
            }
            .disabled(scanning)
        } else {
            Button("Connect ADR") {
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.securityConnectADRHighlightID)
            }
        }
    }
}

// MARK: - The count strip

/// How many findings wait for review, how many of them are high, and how many are acknowledged or snoozed, with the way to
/// show those again while there are any. Each count over its label, as the hero's figures read.
private struct SecurityCountStrip: View {
    let groups: SecurityFindingGroups

    var body: some View {
        HStack(spacing: SettingsTheme.sectionGap) {
            count(groups.visible.count, label: String(localized: "To review"))
            count(groups.pendingHighCount, label: AgentSecurityFinding.Severity.high.label)
            count(groups.acknowledged.count, label: String(localized: "Acknowledged"))
            Spacer(minLength: SettingsMetrics.rowContent)
            // Only while a group is acknowledged or snoozed: an acknowledgement whose finding is gone brings nothing back.
            if !groups.acknowledged.isEmpty {
                Button("Show acknowledged and snoozed again") { SecurityFindingsStore.shared.clearAcknowledgements() }
                    .controlSize(.small)
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func count(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
            Text(verbatim: value.formatted())
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .monospacedDigit()
                .textSelection(.enabled)
            Text(verbatim: label)
                .settingsDescriptionStyle()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The status row

/// Three cells of equal width and height: the newest scan, Kannu's own scans and the agent policy, each in the words the
/// settings use. A cell says only what the store last held: it never checks anything itself.
private struct SecurityStatusRow: View {
    let data: SecurityPageData
    let connected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SettingsMetrics.cardPadding) {
            cell(String(localized: "Newest scan result")) { newestScan }
            cell(String(localized: "Scan this Mac")) { scans }
            cell(String(localized: "Policy rules")) { policy }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
            Text(verbatim: title)
                .font(SettingsTheme.sectionTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// What the newest snapshot said about itself, so a partial scan is never mistaken for a clean one: in orange, as a
    /// partial result is everywhere in Brain.
    @ViewBuilder
    private var newestScan: some View {
        if let scan = data.lastScan {
            Text(verbatim: SecurityPageData.scanLine(scan))
                .settingsDescriptionStyle(tint: scan.coverageComplete ? nil : Color.orange)
        } else {
            Text("No scans yet")
                .settingsDescriptionStyle()
        }
        if let error = data.snapshotError {
            SettingsErrorText(error)
        }
        if data.reviewCount > 0 {
            Text("Needs review: \(data.reviewCount) uncatalogued AI tool(s) — see the snapshot for paths.")
                .settingsDescriptionStyle()
        }
    }

    /// The scans Kannu runs itself: one running, the last and the next, or why there are none.
    @ViewBuilder
    private var scans: some View {
        if !connected {
            Text("ADR Discovery is not connected.")
                .settingsDescriptionStyle()
        } else if data.isScanning {
            Text("Scanning…")
                .settingsDescriptionStyle()
        } else {
            Group {
                if let at = data.lastKannuScanAt {
                    Text("Last run by Kannu \(at.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Not run by Kannu yet")
                }
            }
            .settingsDescriptionStyle()
            if data.automaticScansActive {
                Text(verbatim: data.nextAutomaticScanText)
                    .settingsDescriptionStyle()
            }
        }
        if let error = data.lastScanError {
            SettingsErrorText(error)
        }
    }

    @ViewBuilder
    private var policy: some View {
        SettingsStatusText(data.policyStatusText, isReady: data.policyIsReady)
        if data.policyIgnoredByHook {
            SettingsErrorText(String(localized: "Until this is fixed, none of these rules apply."))
        }
    }
}

// MARK: - An analysis, and the card in the findings' place

/// One analysis: the chat, when it ran, its verdict and cost; Copy for agent on a malicious one, and Reveal Report and
/// Forget in its menu. The row the settings drew under Session analysis, moved up with Recent analyses.
private struct SecurityAnalysisRow: View {
    let analysis: ADRSessionAnalysis

    var body: some View {
        let cost = analysis.costUSD.map { String(format: " · $%.3f", $0) } ?? ""
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                if analysis.isMalicious {
                    CopyForAgentButton {
                        if let finding = analysis.finding() { SecurityFindingsStore.shared.copyAgentPrompt(for: finding) }
                    }
                }
                SettingsMoreMenu {
                    if let path = analysis.reportPath {
                        Button("Reveal report in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    Button("Forget") { SecurityFindingsStore.shared.forgetAnalysis(for: analysis.conversationID) }
                }
            }
        } label: {
            SettingsRowLabel(
                verbatim: analysis.chatName ?? analysis.conversationID,
                description: "\(analysis.date.formatted(date: .abbreviated, time: .shortened)) · \(analysis.shortLabel)\(cost)"
            )
            .lineLimit(2)
        }
    }
}

/// The findings' place when none wait, or the page's while Agent Status is off: the status, at most one line that
/// teaches, and at most one action (docs/SETTINGS.md, "Product pages"). It sits in a section's card, whose padding is
/// the hero's, so it is as tall as the hero less that padding.
private struct SecurityMessage<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.agentSecurity.systemImage)
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
            if let message {
                // The body's size on the secondary ink: an empty state's one line teaches, so it reads as text.
                Text(verbatim: message)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: SettingsTheme.proseMaxWidth)
            }
            action()
        }
        .frame(maxWidth: .infinity,
               minHeight: SettingsTheme.heroMinHeight - SettingsTheme.sectionPadding.top - SettingsTheme.sectionPadding.bottom)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The data

/// What Brain › Security shows from the findings store, copied in one value, so one throttled subscription carries it
/// and the page redraws only when it changed (docs/SETTINGS.md, "Live data"). The product and the settings below both
/// read it; nothing on the page reads the store's state another way.
struct SecurityPageData: Equatable {
    var groups = SecurityFindingGroups(rows: [])
    /// Chats that have a card now, for a finding's Open Chat.
    var chatIDs: Set<String> = []
    var snapshotError: String?
    /// Uncatalogued AI tools in the newest snapshot.
    var reviewCount = 0
    var lastScan: ADRScanRecord?
    var isScanning = false
    var lastKannuScanAt: Date?
    var lastScanError: String?
    var automaticScansActive = false
    var nextAutomaticScanAt: Date?
    var consecutiveScanFailures = 0
    var policyStatus: Result<AgentPolicy, AgentPolicy.LoadError> = .failure(.notFound)
    var policyImportError: String?
    var analyses: [ADRSessionAnalysis] = []
    var lastAnalysisError: String?

    init() {}

    /// The store as it is now.
    @MainActor
    init(_ store: SecurityFindingsStore) {
        groups = store.groupRanking
        chatIDs = store.chatConversationIDs
        snapshotError = store.snapshotError
        reviewCount = store.reviewQueue.count
        lastScan = store.lastScan
        isScanning = store.isScanning
        lastKannuScanAt = store.lastKannuScanAt
        lastScanError = store.lastScanError
        automaticScansActive = store.automaticScansActive
        nextAutomaticScanAt = store.nextAutomaticScanAt
        consecutiveScanFailures = store.consecutiveScanFailures
        policyStatus = store.agentPolicyStatus
        policyImportError = store.agentPolicyImportError
        analyses = store.analyses
        lastAnalysisError = store.lastAnalysisError
    }

    /// Whether a finding's chat has a card to go back to, as the store's `hasChat(for:)` reads it.
    func hasChat(for finding: AgentSecurityFinding) -> Bool {
        finding.sessionID.map(chatIDs.contains) ?? false
    }

    /// The newest scan in one line, as Settings has always written it.
    static func scanLine(_ scan: ADRScanRecord) -> String {
        let coverage = scan.coverageComplete
            ? String(localized: "full coverage")
            : String(localized: "partial coverage (\(scan.coverageGaps) gaps)")
        return String(localized: "\(scan.date.formatted(date: .abbreviated, time: .shortened)) · \(scan.assetCount) assets · \(scan.findingCount) findings · \(coverage) · catalog \(scan.catalogVersion) · schema \(scan.schemaVersion)")
    }

    /// "Next scan Sep 12, 5:54 AM · the last scan failed" — the sooner-than-daily time is the retry, so the
    /// line says why rather than naming the mechanism.
    var nextAutomaticScanText: String {
        let when: String
        if let next = nextAutomaticScanAt, next > Date().addingTimeInterval(60) {
            when = String(localized: "Next scan \(next.formatted(date: .abbreviated, time: .shortened))")
        } else {
            when = String(localized: "Next scan within a minute")
        }
        guard consecutiveScanFailures > 0 else { return when }
        return when + " · " + String(localized: "the last scan failed")
    }

    var policyStatusText: String {
        switch policyStatus {
        case .success(let policy):
            return String(localized: "\(policy.rules.count) rules")
        case .failure(let error):
            return error.message
        }
    }

    var policyIsReady: Bool {
        if case .success = policyStatus { return true }
        return false
    }

    var policyExists: Bool {
        if case .failure(.notFound) = policyStatus { return false }
        return true
    }

    /// Edit rules is offered when there is a policy the editor can read, or none yet. A broken file is not: the editor
    /// would have to save over something it could not read.
    var policyIsEditable: Bool { policyIsReady || !policyExists }

    /// A file the hook ignores whole (docs/REGRESSIONS.md entry 1: it never fails closed), so none of its rules apply.
    var policyIgnoredByHook: Bool {
        if case .failure(let error) = policyStatus, policyExists, error.hookIgnoresFile { return true }
        return false
    }
}

#if DEBUG
/// DEBUG snapshot boards only: what Brain › Security shows in place of this Mac's findings store, and whether ADR
/// Discovery is found and session analysis on.
struct SecurityOverviewFixture {
    var data: SecurityPageData
    var adrConnected: Bool
    var detectionEnabled: Bool
}
#endif
