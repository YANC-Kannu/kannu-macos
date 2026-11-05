/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

import Defaults
import SwiftUI

struct AgentStatusSettings: View {
    // Deliberately not observing CursorAgentStatusMonitor: it publishes on every rescan while
    // agents run, and the only thing here that shows its state is the preview, which observes it
    // on its own (AgentTrafficLightStylePreview).
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @ObservedObject var hookInstaller = AgentHookInstaller.shared
    @ObservedObject private var notificationBridge = AgentStatusNotificationBridge.shared
    @Default(.enableAgentStatusFeature) var enableAgentStatusFeature
    @Default(.agentStatusStaleMinutes) var agentStatusStaleMinutes
    @Default(.agentStoppedCollapseSeconds) var agentStoppedCollapseSeconds
    @Default(.agentInactiveDisplaySeconds) var agentInactiveDisplaySeconds
    @Default(.showAgentStoppedIndicator) var showAgentStoppedIndicator
    @Default(.agentTrafficLightStyle) var agentTrafficLightStyle
    @Default(.agentActiveColor) var agentActiveColor
    @Default(.agentAwaitingInputColor) var agentAwaitingInputColor
    @Default(.agentStoppedColor) var agentStoppedColor
    @Default(.smartCaffeinate) var smartCaffeinate
    @Default(.enableAgentStatusMobileNotifications) var enableMobileNotifications
    @Default(.agentStatusNotificationProvider) var notificationProvider
    @Default(.agentStatusNtfyTopic) var ntfyTopic
    @Default(.agentStatusNtfyServerURL) var ntfyServerURL
    @State private var pushoverUserKey = ""
    @State private var pushoverAppToken = ""
    @State private var webhookURL = ""
    @Default(.agentStatusNotifyOnInactive) var notifyOnInactive
    @Default(.agentWaitReminderMinutes) var agentWaitReminderMinutes
    @State private var isSendingTestNotification = false
    /// File checks, read when the tab appears rather than on every render.
    @State private var detectedEditors: [DetectedEditor] = []
    @State private var presentHookTools: Set<AgentHookProvider> = Set(AgentHookProvider.allCases)

    private func highlightID(_ title: String) -> String {
        SettingsTab.agentStatus.highlightID(for: title)
    }

    var body: some View {
        SettingsPage {
            SettingsSection {
                Defaults.Toggle(key: .enableAgentStatusFeature) {
                    Text("Enable Agent Status")
                }
                .settingsHighlight(id: highlightID("Enable Agent Monitoring"))
            } header: {
                SettingsSectionHeader("Monitoring")
            } footer: {
                SettingsFooter("Shows a traffic light in the notch while AI agents run in your editor: green while the agent is working, yellow when it needs your input, and red when it has stopped.")
            }

            if enableAgentStatusFeature {
                SettingsSection {
                    detectedProvidersGrid
                } header: {
                    SettingsSectionHeader("Detected Editors")
                } footer: {
                    SettingsFooter("Kannu watches these editors automatically. Install a hook below for richer status on editors marked as not detected.")
                }

                // Accessibility is optional, not required: without it clicking a chat still activates
                // the right app — it just can't raise the specific window for IDE-hosted sessions.
                // Chats Claude Desktop knows deep-link to the exact chat (its session route, see
                // ClaudeDesktopSessionIndex); Terminal and iTerm2 tabs are picked by AppleScript.
                SettingsSection {
                    SettingsRow("Open the exact terminal tab", description: "Clicking a chat that runs in Terminal or iTerm2 brings its tab to the front, and switches tmux to its pane. macOS asks once for permission to control each terminal app.") {
                        Defaults.Toggle(key: .openAgentTerminalTab) {
                            Text("Open the exact terminal tab")
                        }
                    }
                    .settingsHighlight(id: highlightID("Open the exact terminal tab"))
                    if !accessibilityPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "Accessibility improves click-through",
                            message: "Clicking a recent chat brings its app forward — Claude Desktop chats open on the exact chat. With Accessibility access, Kannu can also raise the exact window for sessions running in an IDE.",
                            requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                            openSettingsAction: { accessibilityPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    SettingsSectionHeader("Click-through")
                }

                SettingsSection {
                    SettingsRow("Traffic light style", description: agentTrafficLightStyle.description) {
                        SettingsSelect("Traffic light style", selection: $agentTrafficLightStyle,
                                       options: AgentTrafficLightStyle.allCases, optionTitle: \.localizedName)
                    }
                    .settingsHighlight(id: highlightID("Traffic light style"))
                    // Live preview using the same view the notch draws, so this can't drift.
                    LabeledContent("Preview") {
                        AgentTrafficLightStylePreview(style: agentTrafficLightStyle)
                    }
                    stateColorRow(
                        key: .agentActiveColor,
                        title: String(localized: "Active"),
                        detail: String(localized: "The agent is thinking, planning, executing tools, or otherwise working"),
                        highlightTitle: "Active color"
                    )
                    stateColorRow(
                        key: .agentAwaitingInputColor,
                        title: String(localized: "Awaiting Input"),
                        detail: String(localized: "The agent needs your approval or a response"),
                        highlightTitle: "Awaiting input color"
                    )
                    stateColorRow(
                        key: .agentStoppedColor,
                        title: String(localized: "Stopped"),
                        detail: String(localized: "The agent has finished or was aborted"),
                        highlightTitle: "Stopped color"
                    )
                    SettingsActionRow {
                        Button("Reset Colors") {
                            Defaults[.agentActiveColor] = .green
                            Defaults[.agentAwaitingInputColor] = .yellow
                            Defaults[.agentStoppedColor] = .red
                        }
                        .disabled(
                            agentActiveColor == .green
                                && agentAwaitingInputColor == .yellow
                                && agentStoppedColor == .red
                        )
                    }
                    .settingsHighlight(id: highlightID("Reset traffic light colors"))
                } header: {
                    SettingsSectionHeader("Traffic Light")
                } footer: {
                    SettingsFooter("The yellow light is most reliable when hooks are installed.")
                }

                SettingsSection {
                    SettingsRow("Smart caffeinate", description: "Keeps the Mac awake automatically while any agent is running, and lets it sleep when they stop. While this is on, the manual switch in the notch is hidden.") {
                        Defaults.Toggle(key: .smartCaffeinate) {
                            Text("Smart caffeinate")
                        }
                    }
                    .settingsHighlight(id: SettingsDeepLink.smartCaffeinateHighlightID)
                } header: {
                    SettingsSectionHeader("Caffeinate")
                } footer: {
                    SettingsFooter("Only system sleep is prevented, so the display may still sleep while agents keep running. Closing the lid always sleeps the Mac.")
                }

                SettingsSection {
                    SettingsRow("Show a red light when no agents are running", description: "When off, the light hides once agents go quiet.") {
                        Defaults.Toggle(key: .showAgentStoppedIndicator) {
                            Text("Show a red light when no agents are running")
                        }
                    }
                    .settingsHighlight(id: highlightID("Show a red light when no agents are running"))

                    SettingsRow("Hide indicator after agent stops for") {
                        SettingsSelect("Hide indicator after agent stops for", selection: $agentStoppedCollapseSeconds, choices: [
                            3: String(localized: "3 seconds"),
                            5: String(localized: "5 seconds"),
                            10: String(localized: "10 seconds"),
                            15: String(localized: "15 seconds"),
                            30: String(localized: "30 seconds"),
                            60: String(localized: "1 minute"),
                            120: String(localized: "2 minutes"),
                            300: String(localized: "5 minutes"),
                        ])
                    }
                    .disabled(showAgentStoppedIndicator)
                    .opacity(showAgentStoppedIndicator ? 0.5 : 1.0)
                    .settingsHighlight(id: highlightID("Hide red light after"))

                    SettingsRow("Show dim traffic light for") {
                        SettingsSelect("Show dim traffic light for", selection: $agentInactiveDisplaySeconds, choices: [
                            0: String(localized: "Off"),
                            5: String(localized: "5 seconds"),
                            10: String(localized: "10 seconds"),
                            15: String(localized: "15 seconds"),
                            30: String(localized: "30 seconds"),
                            60: String(localized: "1 minute"),
                            120: String(localized: "2 minutes"),
                        ])
                    }
                    .disabled(showAgentStoppedIndicator)
                    .opacity(showAgentStoppedIndicator ? 0.5 : 1.0)
                    .settingsHighlight(id: highlightID("Dim traffic light duration"))

                    SettingsRow("Consider agents inactive after") {
                        SettingsSelect("Consider agents inactive after", selection: $agentStatusStaleMinutes, choices: [
                            10: String(localized: "10 minutes"),
                            15: String(localized: "15 minutes"),
                            30: String(localized: "30 minutes"),
                            60: String(localized: "60 minutes"),
                        ])
                    }
                    .settingsHighlight(id: highlightID("Consider agents inactive after"))
                } header: {
                    SettingsSectionHeader("Indicator")
                } footer: {
                    SettingsFooter("After an agent stops, the red light stays visible for the chosen time, then all lights dim for the inactive duration, then the traffic light disappears entirely. While the red light is kept visible when idle, the hide and dim delays have no effect.")
                }

                SettingsSection {
                    ForEach(AgentHookProvider.allCases) { provider in
                        hookRow(for: provider)
                    }
                    .settingsHighlight(id: highlightID("Cursor Hook"))

                    if let error = hookInstaller.lastError {
                        SettingsErrorText(error)
                    }
                } header: {
                    SettingsSectionHeader("Editor Hooks")
                } footer: {
                    SettingsFooter("Install hooks for Cursor, VS Code and Copilot CLI, Codex CLI, Claude Code, Antigravity, Gemini CLI, Qwen Code or opencode. Each hook writes agent status into ~/.kannu/agent-status for the notch traffic light and Recent chats list. Copilot CLI uses the VS Code hook; opencode gets a small plugin.")
                }

                mobileNotificationSections
            }
        }
        .onAppear {
            pushoverUserKey = SecureSecretsStore.value(for: .pushoverUserKey)
            pushoverAppToken = SecureSecretsStore.value(for: .pushoverAppToken)
            webhookURL = SecureSecretsStore.value(for: .webhookURL)
            detectedEditors = Self.detectEditors()
            presentHookTools = Set(AgentHookProvider.allCases.filter { AgentHookInstaller.layout.toolIsPresent($0) })
            hookInstaller.refresh()
            accessibilityPermission.refreshStatus()
        }
        .navigationTitle("Agents")
    }

    // MARK: - Mobile notifications

    @ViewBuilder
    private var mobileNotificationSections: some View {
        SettingsSection {
            Defaults.Toggle(key: .enableAgentStatusMobileNotifications) {
                Text("Enable mobile notifications")
            }
            .settingsHighlight(id: highlightID("Mobile notifications"))

            if enableMobileNotifications {
                notificationDeliveryRows
            }
        } header: {
            SettingsSectionHeader("Mobile Notifications")
        } footer: {
            SettingsFooter("Optional push alerts when agent state changes. Uses ntfy (iPhone, Apple Watch, Android), Pushover (iPhone), or a custom webhook. Public ntfy topics can be read by anyone unless you self-host with authentication. Notifications are debounced by 2 seconds to avoid spam.")
        }

        if enableMobileNotifications {
            notificationEventsSection
        }
    }

    /// Where pushes go: the provider, its address or keys, and a test push.
    @ViewBuilder
    private var notificationDeliveryRows: some View {
        SettingsRow("Provider", description: notificationProvider.description) {
            SettingsSelect("Provider", selection: $notificationProvider,
                           options: AgentStatusNotificationProvider.allCases, optionTitle: \.displayName)
        }
        .settingsHighlight(id: highlightID("Notification provider"))

        switch notificationProvider {
        case .ntfy:
            SettingsRow("Topic") {
                TextField("Topic", text: $ntfyTopic)
                    .settingsField()
            }
            SettingsRow("Server URL") {
                TextField("Server URL", text: $ntfyServerURL)
                    .settingsField()
            }
        case .pushover:
            SettingsRow("User key") {
                SecureField("User key", text: Binding(
                    get: { pushoverUserKey },
                    set: { newValue in
                        pushoverUserKey = newValue
                        SecureSecretsStore.set(newValue, for: .pushoverUserKey)
                    }
                ))
                    .settingsField()
            }
            SettingsRow("App token") {
                SecureField("App token", text: Binding(
                    get: { pushoverAppToken },
                    set: { newValue in
                        pushoverAppToken = newValue
                        SecureSecretsStore.set(newValue, for: .pushoverAppToken)
                    }
                ))
                    .settingsField()
            }
        case .webhook:
            SettingsRow("Webhook URL") {
                TextField("Webhook URL", text: Binding(
                    get: { webhookURL },
                    set: { newValue in
                        webhookURL = newValue
                        SecureSecretsStore.set(newValue, for: .webhookURL)
                    }
                ))
                    .settingsField()
            }
        }

        LabeledContent {
            Button(isSendingTestNotification ? "Sending…" : "Send test notification") {
                isSendingTestNotification = true
                Task {
                    await notificationBridge.sendTestNotification()
                    isSendingTestNotification = false
                }
            }
            .disabled(isSendingTestNotification)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test notification")
                Group {
                    if let lastSentAt = notificationBridge.lastSentAt {
                        Text("Last sent \(lastSentAt.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Sends one push to check the setup.")
                    }
                }
                .settingsDescriptionStyle()
            }
        }
        .settingsHighlight(id: highlightID("Send test notification"))

        if let error = notificationBridge.lastError {
            SettingsErrorText(error)
        }
    }

    /// What gets pushed.
    private var notificationEventsSection: some View {
        SettingsSection {
            Defaults.Toggle(key: .agentStatusNotifyOnInactive) {
                Text("Notify when inactive")
            }
            SettingsRow("Remind me when an agent is still waiting", description: "One more push if an agent is still waiting for your answer after this long. Only the app's name and how long it has waited are sent.") {
                SettingsSelect("Remind me when an agent is still waiting", selection: $agentWaitReminderMinutes, choices: [
                    0: String(localized: "Off"),
                    3: String(localized: "After 3 minutes"),
                    10: String(localized: "After 10 minutes"),
                    20: String(localized: "After 20 minutes"),
                ])
            }
            .settingsHighlight(id: highlightID("Remind me when an agent is still waiting"))
            Defaults.Toggle(key: .adrPushHighFindings) {
                Text("Push high security findings")
            }
            .settingsHighlight(id: highlightID("Push high security findings"))
            Defaults.Toggle(key: .adrPushMediumFindings) {
                Text("Push medium security findings")
            }
            .settingsHighlight(id: highlightID("Push medium security findings"))
            Defaults.Toggle(key: .pushUsageLimitAlerts) {
                Text("Push when a usage limit is almost reached")
            }
            .settingsHighlight(id: highlightID("Push when a usage limit is almost reached"))
        } header: {
            SettingsSectionHeader("Notify about")
        }
    }

    private struct DetectedEditor: Identifiable {
        let source: AgentProviderIconSource
        let name: String
        let detected: Bool
        var id: String { name }
    }

    private static func detectEditors() -> [DetectedEditor] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return [
            DetectedEditor(source: .cursor, name: "Cursor", detected: fm.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path)),
            DetectedEditor(source: .claude, name: "Claude Code", detected: fm.fileExists(atPath: home.appendingPathComponent(".claude/projects").path)),
            DetectedEditor(source: .codex, name: "Codex", detected: fm.fileExists(atPath: home.appendingPathComponent(".codex/sessions").path)),
            // Launch Services, not Warp's container (whose stat raises a permission dialog).
            DetectedEditor(source: .warp, name: "Warp", detected: LaunchPermissionManager.isWarpInstalled),
            DetectedEditor(source: .claudeDesktop, name: "Claude Desktop", detected: fm.fileExists(atPath: ClaudeDesktopAgentSessionStore.defaultRoot.path)),
        ]
    }

    private var detectedProvidersGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(detectedEditors) { editor in
                HStack(spacing: 6) {
                    AgentProviderIconView(source: editor.source, size: 16)
                        .opacity(editor.detected ? 1 : 0.35)
                    Text(editor.name)
                        .font(.subheadline)
                        .foregroundStyle(editor.detected ? .primary : .secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Circle()
                        .fill(editor.detected ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(editor.detected ? Text("\(editor.name), detected") : Text("\(editor.name), not detected"))
            }
        }
    }


    @ViewBuilder
    private func hookRow(for provider: AgentHookProvider) -> some View {
        let installed = hookInstaller.isInstalled(provider)
        let present = presentHookTools.contains(provider)
        HStack(spacing: SettingsMetrics.rowContent) {
            Circle()
                .fill(installed ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: SettingsMetrics.statusDot, height: SettingsMetrics.statusDot)
                .accessibilityHidden(true)
            AgentProviderIconView(source: .init(hookProvider: provider), size: 18)
            // Codex skips a hook until the user trusts it in /hooks, so an install alone reports nothing.
            SettingsRowLabel(verbatim: provider.displayName,
                             description: provider == .codex && installed
                                ? String(localized: "Open Codex and run /hooks to trust Kannu's hooks.")
                                : nil)
            Spacer()
            if !installed && !present {
                Text("Not found on this Mac")
                    .settingsDescriptionStyle()
            }
            Button(installed ? "Remove" : "Install") {
                if installed {
                    hookInstaller.uninstall(provider)
                } else {
                    hookInstaller.install(provider)
                }
            }
            .disabled(!installed && !present)
        }
    }


    /// A state's name and meaning, with the palette picker for its color. The popover offers only
    /// the curated palette and blocks swatches already used by another state, so two states
    /// can never share a color.
    private func stateColorRow(
        key: Defaults.Key<AgentTrafficLightPaletteColor>,
        title: String,
        detail: String,
        highlightTitle: String
    ) -> some View {
        let others: [AgentTrafficLightPaletteColor: String] = {
            var taken: [AgentTrafficLightPaletteColor: String] = [:]
            let all: [(Defaults.Key<AgentTrafficLightPaletteColor>, String)] = [
                (.agentActiveColor, String(localized: "Active")),
                (.agentAwaitingInputColor, String(localized: "Awaiting Input")),
                (.agentStoppedColor, String(localized: "Stopped")),
            ]
            for (otherKey, name) in all where otherKey != key {
                taken[Defaults[otherKey]] = name
            }
            return taken
        }()
        return LabeledContent {
            AgentPaletteSwatchButton(key: key, takenByOthers: others)
        } label: {
            SettingsRowLabel(verbatim: title, description: detail)
        }
        .settingsHighlight(id: highlightID(highlightTitle))
    }
}

/// The traffic light in Settings, in the chosen style and the monitor's current state. It observes
/// the monitor itself so the rest of the Agents tab does not re-render on every rescan.
private struct AgentTrafficLightStylePreview: View {
    let style: AgentTrafficLightStyle
    @ObservedObject private var monitor = CursorAgentStatusMonitor.shared

    var body: some View {
        AgentTrafficLightDots(
            style: style,
            state: monitor.trafficLightState == .inactive ? .executing : monitor.trafficLightState
        )
    }
}

/// The swatch button + popover for one traffic-light state. Palette-only by design: no
/// eyedropper, no custom well — the closed set is what makes duplicate colors impossible.
private struct AgentPaletteSwatchButton: View {
    let key: Defaults.Key<AgentTrafficLightPaletteColor>
    let takenByOthers: [AgentTrafficLightPaletteColor: String]
    // Observed via the runtime key so the swatch recolors in the same transaction as the
    // selection write — the struct's other inputs don't change when its own key does, so
    // without this SwiftUI may skip the re-render and show a stale color.
    @Default private var selection: AgentTrafficLightPaletteColor

    init(key: Defaults.Key<AgentTrafficLightPaletteColor>, takenByOthers: [AgentTrafficLightPaletteColor: String]) {
        self.key = key
        self.takenByOthers = takenByOthers
        self._selection = Default(key)
    }

    var body: some View {
        KannuColorPickerButton(
            color: selection.color,
            accessibilityLabel: selection.localizedName
        ) {
            AgentPalettePopover(key: key, takenByOthers: takenByOthers)
        }
    }
}

/// The traffic-light palette: a closed set, and a colour already assigned to another state is
/// unpickable — that is what makes two states sharing a colour impossible. The rule travels as
/// each item's `disabledReason`, so the shared grid enforces it rather than a local copy.
private struct AgentPalettePopover: View {
    let key: Defaults.Key<AgentTrafficLightPaletteColor>
    let takenByOthers: [AgentTrafficLightPaletteColor: String]
    @Default private var selection: AgentTrafficLightPaletteColor
    @Environment(\.dismiss) private var dismiss

    init(key: Defaults.Key<AgentTrafficLightPaletteColor>, takenByOthers: [AgentTrafficLightPaletteColor: String]) {
        self.key = key
        self.takenByOthers = takenByOthers
        self._selection = Default(key)
    }

    private var items: [KannuColorSwatchGrid.Item] {
        AgentTrafficLightPaletteColor.allCases.map { option in
            KannuColorSwatchGrid.Item(
                id: option.rawValue,
                color: option.color,
                disabledReason: takenByOthers[option].map { String(localized: "Used by \($0)") },
                accessibilityLabel: option.localizedName
            )
        }
    }

    var body: some View {
        KannuColorSwatchGrid(
            items: items,
            selectedID: selection.rawValue,
            columns: 5,
            swatchSize: 20
        ) { item in
            guard let picked = AgentTrafficLightPaletteColor(rawValue: item.id) else { return }
            selection = picked
            dismiss()
        }
        .padding(12)
    }
}

#if DEBUG
extension AgentStatusSettings {
    /// DEBUG snapshot harness: the mobile-notification rows that only show once pushes are on.
    static func snapshotNotificationRows() -> AnyView {
        let settings = AgentStatusSettings()
        return AnyView(SettingsPage {
            SettingsSection { settings.notificationDeliveryRows } header: { SettingsSectionHeader("Mobile Notifications") }
            settings.notificationEventsSection
        })
    }

}
#endif
