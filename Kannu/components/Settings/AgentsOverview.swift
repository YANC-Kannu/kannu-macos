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

import Combine
import Defaults
import SwiftUI

/// Brain › Agents' product, above its settings: the agent that matters most, the other recent ones, and a status row
/// (docs/SETTINGS.md, "Product pages").
///
/// Brain's content is built once and kept for the app's life, and Agents is the page it opens on, so this follows the
/// live-data contract (docs/SETTINGS.md, "Live data"):
/// 1. **Throttled and scoped.** The sessions are copied into `@State` from one subscription to the monitor's
///    `$sessions`, at most twice a second. Nothing here observes the monitor, which publishes on every hook write.
/// 2. **Stopped while Brain is not on screen.** That subscription is a `.task(id:)` on `BrainVisibility.isOnScreen`,
///    so it ends when Brain is closed, minimised, hidden, covered or in another Space, and starts again on its return.
/// 3. **No work while nothing is on screen.** The live leaves, the metrics that observe the token follower and tick
///    once a second and the status row that observes the usage store and follows the findings store, give way to a
///    static copy.
///
/// A click resolves where it goes in its action (`AgentSessionOpener.open`), never in `body`: finding the target walks
/// parent processes and asks `NSWorkspace`.
struct AgentsOverview: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @ObservedObject private var hookInstaller = AgentHookInstaller.shared
    @Default(.enableAgentStatusFeature) private var enabled
    @State private var sessions: [AgentSessionStatus] = []
    @State private var tools: [AgentToolDetector.Tool] = []

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's sessions, tools, readings and
    /// findings, so no real data lands in a PNG. Set, the page never subscribes and draws its live leaves.
    static var snapshotFixture: AgentsOverviewFixture?
    #endif

    /// Whether the live leaves are drawn: while Brain is on screen, and on a board, which has fixtures.
    private var drawsLive: Bool {
        #if DEBUG
        if Self.snapshotFixture != nil { return true }
        #endif
        return visibility.isOnScreen
    }

    private var offers: [AgentToolDetector.Tool] {
        AgentToolDetector.hookOffers(in: tools) { isInstalled($0) }
    }

    private func isInstalled(_ hook: AgentHookProvider) -> Bool {
        #if DEBUG
        if let fixture = Self.snapshotFixture { return fixture.installedHooks.contains(hook) }
        #endif
        return hookInstaller.isInstalled(hook)
    }

    var body: some View {
        // One card per conversation, as the notch lists them; the one it ranks first leads, the rest newest first.
        let visible = AgentTrafficLightMapper.latestSessions(sessions).filter(\.isVisible)
        let primary = AgentTrafficLightMapper.primarySession(from: visible)
        let recent = visible.filter { $0.id != primary?.id }.sorted { $0.updatedAt > $1.updatedAt }
        // The install offer shows once: in the empty state when that is shown, otherwise in Editors & hooks.
        let leadShowsInstall = enabled && primary == nil && !offers.isEmpty
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            lead(primary: primary)
            if enabled, !recent.isEmpty {
                VStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
                    SettingsSectionHeader("Recent chats")
                        .padding(.horizontal, SettingsTheme.sectionPadding.leading)
                    ForEach(recent) { session in
                        AgentsSessionRow(session: session, live: drawsLive)
                    }
                }
                .accessibilityElement(children: .contain)
            }
            statusRow(showsInstall: !leadShowsInstall)
        }
        .onAppear {
            #if DEBUG
            if let fixture = Self.snapshotFixture {
                sessions = fixture.sessions
                tools = fixture.tools
                return
            }
            #endif
            // One read, not a subscription: the page opens on what is happening, and the subscription below takes
            // over once Brain is on screen. A visit's file checks, never a render's.
            sessions = CursorAgentStatusMonitor.shared.sessions
            tools = AgentToolDetector.detect()
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if Self.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            for await latest in CursorAgentStatusMonitor.shared.$sessions
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                sessions = latest
            }
        }
    }

    // MARK: - The lead: the hero, or the card in its place

    @ViewBuilder
    private func lead(primary: AgentSessionStatus?) -> some View {
        if !enabled {
            AgentsMessageCard(title: String(localized: "Agent Status is off"), message: nil) {
                Button("Turn On") { enabled = true }
                    .buttonStyle(SettingsButtonStyle(.primary))
            }
        } else if let primary {
            AgentsHeroCard(session: primary, live: drawsLive)
        } else {
            AgentsMessageCard(
                title: String(localized: "No agents running"),
                message: String(localized: "Start a session in Cursor, Claude Code, Codex, Antigravity, Warp or Claude Desktop and its light shows here.")
            ) {
                if let offer = offers.first {
                    AgentsInstallButton(tool: offer)
                }
            }
        }
    }

    // MARK: - The status row: live while Brain is on screen, a static copy while not

    @ViewBuilder
    private func statusRow(showsInstall: Bool) -> some View {
        #if DEBUG
        if let fixture = Self.snapshotFixture {
            AgentsStatusRow(tools: tools, offers: offers, showsInstall: showsInstall, nearLimit: fixture.nearLimit,
                            security: fixture.security)
        } else {
            liveOrFrozenStatusRow(showsInstall: showsInstall)
        }
        #else
        liveOrFrozenStatusRow(showsInstall: showsInstall)
        #endif
    }

    @ViewBuilder
    private func liveOrFrozenStatusRow(showsInstall: Bool) -> some View {
        if visibility.isOnScreen {
            AgentsLiveStatusRow(tools: tools, offers: offers, showsInstall: showsInstall)
        } else {
            // Read once as it froze, not observed: nothing is on screen to show a change.
            AgentsStatusRow(tools: tools, offers: offers, showsInstall: showsInstall, nearLimit: UsageAlertManager.shared.nearLimit,
                            security: AgentsSecuritySummary(SecurityFindingsStore.shared.groupRanking))
        }
    }
}

/// Agents' header action (docs/SETTINGS.md, "Product pages"): the gear, which goes to the page's settings. The install
/// offer is the page's, never the header's: in the empty state when that is shown, otherwise in Editors & hooks.
struct AgentsHeaderActions: View {
    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            Button {
                // The first settings row, which is always built.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.agentMonitoringHighlightID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Agent settings"))
            .accessibilityLabel(String(localized: "Agent settings"))
        }
    }
}

/// "Install Cursor hook": offered only for a tool on this Mac whose hook is missing.
private struct AgentsInstallButton: View {
    let tool: AgentToolDetector.Tool

    var body: some View {
        Button(String(localized: "Install \(tool.name) hook")) {
            if let hook = tool.hook { AgentHookInstaller.shared.install(hook) }
        }
        .buttonStyle(SettingsButtonStyle(.primary))
    }
}

// MARK: - The hero and the rows

/// The session that matters most, titled by its state: a stopped run ranks above one awaiting input
/// (`AgentTrafficLightMapper.primarySession`). Three bands: the state in its light's colour, with the light; the session
/// as a row shows it; and, pinned to the bottom, the run's figures from the text column, with "Open chat ›". The whole
/// card is one button, so a click anywhere opens its chat.
private struct AgentsHeroCard: View {
    let session: AgentSessionStatus
    let live: Bool

    private var title: String {
        switch session.displayState {
        case .awaitingInput: return String(localized: "Needs you")
        case .executing, .thinking: return String(localized: "Working")
        case .stopped, .inactive: return String(localized: "Finished")
        }
    }

    var body: some View {
        Button {
            _ = AgentSessionOpener.open(session)
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardPadding) {
                HStack(spacing: SettingsMetrics.rowContent) {
                    AgentsStateWord(session: session, font: SettingsTheme.cardTitle, text: title)
                    Spacer(minLength: 0)
                    AgentTrafficLightDots(style: .classic, state: session.displayState)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: SettingsMetrics.cardPadding) {
                    AgentProviderIconView(source: .init(rawProvider: session.provider), size: SettingsTheme.heroIcon)
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                        Text(verbatim: session.providerAndProject)
                            .font(SettingsTheme.sheetTitle)
                            .foregroundStyle(SettingsTheme.ink)
                            .lineLimit(1)
                        Text(verbatim: session.displayChatName)
                            .font(SettingsTheme.body)
                            .foregroundStyle(SettingsTheme.ink)
                            .lineLimit(2)
                        AgentsStateWord(session: session, font: SettingsTheme.bodyStrong)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: SettingsMetrics.rowContent) {
                    AgentsMetrics(session: session, live: live, font: SettingsTheme.cardTitle, figures: true)
                        // On the text column: past the icon and its gap.
                        .padding(.leading, SettingsTheme.heroIcon + SettingsMetrics.cardPadding)
                    Spacer(minLength: 0)
                    // A quiet button's look, but a label: the card is the one button, never a button inside a button.
                    HStack(spacing: SettingsMetrics.iconGap) {
                        Text("Open chat")
                        Image(systemName: "chevron.right")
                    }
                    .font(SettingsTheme.bodyStrong)
                    .foregroundStyle(SettingsTheme.ink)
                }
            }
            .padding(SettingsTheme.heroPadding)
            .frame(maxWidth: .infinity, minHeight: SettingsTheme.heroMinHeight, alignment: .topLeading)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One recent session: its icon, provider and project above the chat's name, then a trailing column of a fixed
/// width with the state, the metrics and the light. A click opens its chat.
private struct AgentsSessionRow: View {
    let session: AgentSessionStatus
    let live: Bool

    var body: some View {
        Button {
            _ = AgentSessionOpener.open(session)
        } label: {
            HStack(spacing: SettingsMetrics.cardPadding) {
                AgentProviderIconView(source: .init(rawProvider: session.provider), size: SettingsTheme.listRowIcon)
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    // A label inside the row's button, so it stays unselectable: selectable text swallows the click.
                    Text(verbatim: session.providerAndProject)
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                        .lineLimit(1)
                    Text(verbatim: session.displayChatName)
                        .font(SettingsTheme.bodyStrong)
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: SettingsMetrics.rowContent)
                HStack(spacing: SettingsMetrics.rowContent) {
                    AgentsStateWord(session: session, font: SettingsTheme.description)
                    AgentsMetrics(session: session, live: live, font: SettingsTheme.description, figures: false)
                    AgentTrafficLightDots(style: .minimal, state: session.displayState)
                        .accessibilityHidden(true)
                }
                .frame(width: SettingsTheme.listTrailingWidth, alignment: .trailing)
            }
            .padding(.horizontal, SettingsMetrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: SettingsTheme.listRowHeight)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A session's state in words, in its light's colour, so the state does not rest on colour alone. The hero passes its
/// title ("Needs you") as `text`, in the same colour.
private struct AgentsStateWord: View {
    let session: AgentSessionStatus
    let font: Font
    var text: String? = nil
    @Default(.agentActiveColor) private var active
    @Default(.agentAwaitingInputColor) private var awaiting
    @Default(.agentStoppedColor) private var stopped
    @Environment(\.colorScheme) private var colorScheme

    private var colour: Color {
        guard let lit = session.displayState.litPalette(active: active, awaiting: awaiting, stopped: stopped)?.color else {
            return SettingsTheme.inkSecondary
        }
        // Paper is light, so the light's own hue is shaded until it reads, as on a light notch.
        return colorScheme == .light ? lit.shadedForLightNotch : lit
    }

    var body: some View {
        Text(verbatim: text ?? session.displayState.displayName + session.runOutcomeSuffix + session.backgroundWorkSuffix)
            .font(font)
            .foregroundStyle(colour)
            .lineLimit(1)
    }
}

/// The run's metrics. Live, `AgentTurnMetricsView`, which observes the token follower and ticks once a second; while
/// Brain is not on screen, a static copy that does neither: the run time as it froze and the tool count. The hero draws
/// them as figures, each over its label; a row, as its trailing column.
private struct AgentsMetrics: View {
    let session: AgentSessionStatus
    let live: Bool
    let font: Font
    let figures: Bool

    /// The figures in ink, their labels in the description's type under them, a section's gap apart.
    private static let figureStyle = AgentTurnMetricsView.Figures(numberColor: SettingsTheme.ink, labelFont: SettingsTheme.description,
                                                                  labelColor: SettingsTheme.inkSecondary, spacing: SettingsTheme.sectionGap)

    var body: some View {
        if live {
            AgentTurnMetricsView(session: session, font: font, figures: figures ? Self.figureStyle : nil)
        } else if figures, let display = AgentTurnMetricsView.display(for: session) {
            AgentTurnMetricsView.figureRow(runTime: Text(verbatim: Self.runTime(display)), toolCalls: session.turn?.toolCalls ?? 0,
                                           tokens: nil, font: font, figures: Self.figureStyle)
        } else if let display = AgentTurnMetricsView.display(for: session) {
            VStack(alignment: .trailing, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: Self.duration(display))
                if let tools = AgentTurnFormat.metricsLines(toolCalls: session.turn?.toolCalls ?? 0, tokens: nil).first {
                    Text(verbatim: tools)
                }
            }
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(SettingsTheme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private static func duration(_ display: AgentTurnDisplay) -> String {
        switch display {
        case let .live(since): return AgentTurnFormat.duration(Date().timeIntervalSince(since))
        case let .ended(interval): return AgentTurnFormat.ran(AgentTurnFormat.duration(interval))
        }
    }

    /// A figure's run time: the time alone, since its label says what it is.
    private static func runTime(_ display: AgentTurnDisplay) -> String {
        switch display {
        case let .live(since): return AgentTurnFormat.duration(Date().timeIntervalSince(since))
        case let .ended(interval): return AgentTurnFormat.duration(interval)
        }
    }
}

/// The hero's place when there is no agent to show: the status, at most one line that teaches, and at most one
/// action (docs/SETTINGS.md, "Product pages").
private struct AgentsMessageCard<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.agentStatus.systemImage)
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
        .padding(SettingsTheme.heroPadding)
        .frame(maxWidth: .infinity, minHeight: SettingsTheme.heroMinHeight)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The status row

/// What Security's cell says: how many findings wait for review, how many are high, and the pinned one's title.
struct AgentsSecuritySummary: Equatable {
    let toReview: Int
    let high: Int
    let pinnedTitle: String?

    init(toReview: Int, high: Int, pinnedTitle: String?) {
        self.toReview = toReview
        self.high = high
        self.pinnedTitle = pinnedTitle
    }

    init(_ groups: SecurityFindingGroups) {
        self.init(toReview: groups.visible.count, high: groups.pendingHighCount, pinnedTitle: groups.pinnedFinding?.title)
    }
}

/// The status row while Brain is on screen, so it exists only then. It observes the usage store, which changes on a
/// reading, minutes apart, but not the findings store: while a session runs with permission checks off, every hook
/// write restamps its finding and the store republishes. Security's summary is read as the row appears, then at most
/// twice a second, and assigned only when it changed.
private struct AgentsLiveStatusRow: View {
    let tools: [AgentToolDetector.Tool]
    let offers: [AgentToolDetector.Tool]
    let showsInstall: Bool
    @ObservedObject private var usage = UsageAlertManager.shared
    @State private var security = AgentsSecuritySummary(toReview: 0, high: 0, pinnedTitle: nil)

    var body: some View {
        AgentsStatusRow(tools: tools, offers: offers, showsInstall: showsInstall, nearLimit: usage.nearLimit, security: security)
            .onAppear { security = AgentsSecuritySummary(SecurityFindingsStore.shared.groupRanking) }
            // `objectWillChange` comes before a change; read through the run loop, the summary comes after it.
            .task {
                for await _ in SecurityFindingsStore.shared.objectWillChange
                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                    .values {
                    let latest = AgentsSecuritySummary(SecurityFindingsStore.shared.groupRanking)
                    if latest != security { security = latest }
                }
            }
    }
}

/// Three cells of equal width and height: Editors & hooks, Usage, and Security only while there is something to
/// review. Usage never starts a read of its own; each reading says when it was taken. A cell's headline figure is a
/// card title; a quiet cell is one line.
private struct AgentsStatusRow: View {
    let tools: [AgentToolDetector.Tool]
    let offers: [AgentToolDetector.Tool]
    /// False while the empty state above offers the install, so the offer shows once.
    let showsInstall: Bool
    let nearLimit: [UsageWindowReading]
    let security: AgentsSecuritySummary

    var body: some View {
        HStack(alignment: .top, spacing: SettingsMetrics.cardPadding) {
            cell(String(localized: "Editors & hooks")) { editors }
            cell(SettingsTab.llmUsage.title) { usage }
            if security.toReview > 0 {
                cell(SettingsTab.agentSecurity.title) { findings }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
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

    /// One status line: "5 tools watched · hooks installed", or "4 of 5 hooked" and then each tool missing its hook,
    /// with Install. A tool with no hook to install, such as Warp, counts as hooked. Each hook, with its tool's icon, is
    /// in Editor Hooks below.
    @ViewBuilder
    private var editors: some View {
        let watched = tools.filter(\.detected)
        if watched.isEmpty {
            Text("No tools found")
                .settingsDescriptionStyle()
        } else if offers.isEmpty {
            Text(verbatim: watched.count == 1 ? String(localized: "1 tool watched · hooks installed")
                 : String(localized: "\(watched.count) tools watched · hooks installed"))
                .settingsDescriptionStyle()
        } else {
            Text("\(watched.count - offers.count) of \(watched.count) hooked")
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
            if showsInstall {
                ForEach(offers) { offer in
                    HStack(spacing: SettingsMetrics.rowContent) {
                        Text(verbatim: offer.name)
                            .font(SettingsTheme.body)
                            .foregroundStyle(SettingsTheme.ink)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("Install") {
                            if let hook = offer.hook { AgentHookInstaller.shared.install(hook) }
                        }
                        .buttonStyle(SettingsButtonStyle())
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Readings near their limit, each with its reset and when it was read; otherwise one quiet line.
    @ViewBuilder
    private var usage: some View {
        if nearLimit.isEmpty {
            Text("Within limits")
                .settingsDescriptionStyle()
        } else {
            let now = Date()
            ForEach(nearLimit.prefix(2), id: \.id) { reading in
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    // The figure, then what it measures, as the hero's figures read: "Claude 5-hour 82%" whole in the
                    // card title broke at its hyphen in the narrowest window's cell.
                    Text(verbatim: (reading.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                        .font(SettingsTheme.cardTitle)
                        .foregroundStyle(SettingsTheme.ink)
                        .textSelection(.enabled)
                    Text(verbatim: "\(AgentSessionStatus.providerLabel(for: reading.provider)) \(reading.label)")
                        .settingsDescriptionStyle()
                    if let reset = reading.resetsAt {
                        Text("Resets \(UsageForecast.clock(reset, now: now))")
                            .settingsDescriptionStyle()
                    }
                    Text("As of \(UsageForecast.time(reading.observedAt))")
                        .settingsDescriptionStyle()
                }
            }
        }
    }

    /// How many findings wait, how many are high, the pinned one's title, and the way to Security's list.
    @ViewBuilder
    private var findings: some View {
        Text("To review: \(security.toReview)")
            .font(SettingsTheme.cardTitle)
            .foregroundStyle(SettingsTheme.ink)
            .textSelection(.enabled)
        if security.high > 0 {
            Text("High: \(security.high)")
                .settingsDescriptionStyle()
        }
        if let title = security.pinnedTitle {
            Text(verbatim: title)
                .settingsDescriptionStyle()
                .lineLimit(2)
        }
        Button {
            SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.securityFindingsHighlightID)
        } label: {
            HStack(spacing: SettingsMetrics.iconGap) {
                Text("Open")
                Image(systemName: "chevron.right")
            }
        }
        // Alone under the cell's text, so its label sits on that text's column.
        .buttonStyle(SettingsButtonStyle(.quiet, flush: true))
    }
}

private extension AgentSessionStatus {
    /// "Claude · kannu", or the provider alone when the project is not known.
    var providerAndProject: String {
        displayProjectName.map { "\(providerLabel) · \($0)" } ?? providerLabel
    }
}

#if DEBUG
/// DEBUG snapshot boards only: what `AgentsOverview` shows in place of this Mac's data.
struct AgentsOverviewFixture {
    var sessions: [AgentSessionStatus]
    var tools: [AgentToolDetector.Tool]
    var installedHooks: Set<AgentHookProvider>
    var nearLimit: [UsageWindowReading]
    var security: AgentsSecuritySummary
}
#endif
