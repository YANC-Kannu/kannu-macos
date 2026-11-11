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

/// Brain › Usage's product, above its settings: each provider's limits as bars, then the models it ran this week
/// (docs/SETTINGS.md, "Product pages"). The bars are the notch's provider cards in Brain's style, built from the usage
/// store's readings (`UsageAlertManager`), the ones the alerts and the forecast read.
///
/// The page never reads usage of its own (docs/REGRESSIONS.md, entry 8). Claude's limits come from the agent monitor's
/// reads, Codex's and Cursor's from the notch's Usage tab, the opt-in background check or Refresh, so a reading can be
/// hours old, and each says when it was taken. Brain's content is built once and kept for the app's life, so the page
/// follows the live-data contract (docs/SETTINGS.md, "Live data"):
/// 1. **Throttled and scoped.** The readings, their outlooks and the models are copied into `@State` from one
///    subscription, at most twice a second, and assigned only when they changed. Nothing here observes a store whole.
/// 2. **Stopped while Brain is not on screen.** That subscription is a `.task(id:)` on `BrainVisibility.isOnScreen`, so
///    it ends when Brain is closed, minimised, hidden, covered or in another Space, and starts again on its return.
/// 3. **No work while nothing is on screen.** The page keeps no clock: a reset and a reading are told by the time of
///    day, and the usage store drops a window itself when it resets. Off screen, the copy simply stays as it was.
struct UsageOverview: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableLLMUsageFeature) private var usageOn
    @Default(.enableClaudeProvider) private var claudeOn
    @Default(.enableCodexProvider) private var codexOn
    @Default(.enableCursorProvider) private var cursorOn
    @State private var data = UsageOverviewData()

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's switches and readings, so no real
    /// data lands in a PNG. Set, the page never subscribes.
    static var snapshotFixture: UsageOverviewFixture?
    #endif

    /// The providers on, among those whose limits the usage store keeps, in the notch's order. The store keeps no
    /// Antigravity reading, so Antigravity has no card here; the notch's Usage tab shows its quotas.
    private var shownProviders: [ProviderID] {
        #if DEBUG
        if let fixture = Self.snapshotFixture { return fixture.providers }
        #endif
        return Self.providersOn(usage: usageOn, claude: claudeOn, codex: codexOn, cursor: cursorOn)
    }

    var body: some View {
        let providers = shownProviders
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if providers.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardPadding) {
                    ForEach(providers) { provider in
                        UsageProviderCard(provider: provider,
                                          readings: Self.ordered(data.readings.filter { $0.provider == provider.rawValue }),
                                          outlooks: data.outlooks)
                    }
                }
                let models = data.models.filter { providers.contains($0.provider) }
                if !models.isEmpty {
                    UsageModelList(models: models)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if let fixture = Self.snapshotFixture {
                data = fixture.data
                return
            }
            #endif
            // One read, not a subscription: the page opens on what the stores hold, and the subscription below takes
            // over once Brain is on screen.
            data = UsageOverviewData(readings: UsageAlertManager.shared.readings, outlooks: UsageAlertManager.shared.outlooks,
                                     models: Self.modelRows(LLMUsageManager.shared.results))
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if Self.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            for await (readings, outlooks, results) in UsageAlertManager.shared.$readings
                .combineLatest(UsageAlertManager.shared.$outlooks, LLMUsageManager.shared.$results)
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                let latest = UsageOverviewData(readings: readings, outlooks: outlooks, models: Self.modelRows(results))
                if latest != data { data = latest }
            }
        }
    }

    /// No provider on whose limits the page can show: the status, one line that teaches, and the way to the switches.
    private var emptyState: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.llmUsage.systemImage)
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .accessibilityHidden(true)
            Text("No limits to show")
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
            // The body's size on the secondary ink: an empty state's one line teaches, so it reads as text.
            Text("Turn on Claude, Codex or Cursor and its limits show here.")
                .font(SettingsTheme.body)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: SettingsTheme.proseMaxWidth)
            Button("Turn on a provider") {
                // To the switches below: the providers' first row, or the monitor's while it is off, which hides them.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(
                    highlightID: usageOn ? SettingsDeepLink.usageProvidersHighlightID : SettingsDeepLink.usageMonitorHighlightID)
            }
            .buttonStyle(SettingsButtonStyle())
        }
        .padding(SettingsTheme.heroPadding)
        .frame(maxWidth: .infinity, minHeight: SettingsTheme.heroMinHeight)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Which of the providers the usage store reads are on: none while the monitor is off.
    static func providersOn(usage: Bool, claude: Bool, codex: Bool, cursor: Bool) -> [ProviderID] {
        guard usage else { return [] }
        var on: [ProviderID] = []
        if claude { on.append(.claude) }
        if codex { on.append(.codex) }
        if cursor { on.append(.cursor) }
        return on
    }

    /// The 5-hour window first, then the whole week, then each other window, as the notch orders its bars. The store
    /// sorts by id, which would put "Fable weekly" before "weekly".
    static func ordered(_ readings: [UsageWindowReading]) -> [UsageWindowReading] {
        func rank(_ key: String) -> Int {
            if UsageForecast.isShortWindow(key) { return 0 }
            return key == ClaudeUsageSnapshot.sevenDayKey || key == "week" ? 1 : 2
        }
        return readings.sorted { (rank($0.key), $0.id) < (rank($1.key), $1.id) }
    }

    /// The models of each provider's last read, the busiest first. A model that took no new tokens says nothing. Its
    /// cost shows only where the provider bills per token (Cursor): Claude's and Codex's are plans, not prices.
    static func modelRows(_ results: [ProviderID: UsageResult]) -> [UsageModelRow] {
        ProviderID.allCases.flatMap { provider -> [UsageModelRow] in
            guard case .success(let snapshot)? = results[provider] else { return [] }
            return snapshot.models
                .filter { $0.totals.totalTokens > 0 }
                .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
                .map { usage in
                    let totals = usage.totals
                    let billed = !snapshot.billedCostOnly && totals.costUSD > 0
                    return UsageModelRow(provider: provider, model: usage.model,
                                         tokensIn: totals.uncachedInputTokens + totals.cacheWriteTokens,
                                         tokensOut: totals.outputTokens,
                                         cost: billed ? totals.costUSD.formatted(.currency(code: "USD")) : nil)
                }
        }
    }
}

/// Usage's header actions (docs/SETTINGS.md, "Product pages"): the gear, which goes to the page's settings, then
/// Refresh, the page's one primary verb.
struct UsageHeaderActions: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableLLMUsageFeature) private var usageOn
    @Default(.enableClaudeProvider) private var claudeOn
    @Default(.enableCodexProvider) private var codexOn
    @Default(.enableCursorProvider) private var cursorOn
    /// Whether the providers' refresh or Claude's `/usage` is running, followed only while Brain is on screen.
    @State private var refreshing = false

    private var providers: [ProviderID] {
        #if DEBUG
        if let fixture = UsageOverview.snapshotFixture { return fixture.providers }
        #endif
        return UsageOverview.providersOn(usage: usageOn, claude: claudeOn, codex: codexOn, cursor: cursorOn)
    }

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            Button {
                // The first settings row, which is always built.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.usageMonitorHighlightID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Usage settings"))
            .accessibilityLabel(String(localized: "Usage settings"))
            Button("Refresh") {
                // On a press only, through the notch's own paths, unchanged (docs/REGRESSIONS.md, entry 8): its Refresh
                // usage, then Claude's `/usage` as its automatic refresh runs it, so a press here never starts a browser
                // sign-in. That stays a press of the notch's Claude ↻, beside the status line and Cancel it needs.
                LLMUsageManager.shared.refreshRequestedByUser()
                if providers.contains(.claude) {
                    CursorAgentStatusMonitor.shared.refreshClaudeUsageFromCLI(manual: false)
                }
            }
            .buttonStyle(SettingsButtonStyle(.primary))
            .disabled(refreshing || providers.isEmpty)
        }
        // `combineLatest`'s closure goes in its parentheses: a `for` statement takes a trailing brace as its body.
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            for await busy in LLMUsageManager.shared.$isRefreshing
                .combineLatest(CursorAgentStatusMonitor.shared.$isRefreshingClaudeUsage, { $0 || $1 })
                .removeDuplicates()
                .values {
                refreshing = busy
            }
        }
    }
}

// MARK: - The cards

/// One provider's limits, as the notch's card shows them: each window a bar, with its reset, when it was read, and
/// where it is heading once Kannu has seen enough of it. A provider with no reading yet says so in one line.
private struct UsageProviderCard: View {
    let provider: ProviderID
    let readings: [UsageWindowReading]
    let outlooks: [String: UsageForecast.Outlook]

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {
            HStack(spacing: SettingsMetrics.cardPadding) {
                AgentProviderIconView(source: .init(providerID: provider), size: SettingsTheme.listRowIcon)
                    .accessibilityHidden(true)
                Text(verbatim: provider.displayName)
                    .font(SettingsTheme.sectionTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            if readings.isEmpty {
                Text("No reading yet")
                    .settingsDescriptionStyle()
            } else {
                ForEach(readings, id: \.id) { reading in
                    UsageReadingRow(reading: reading, outlook: outlooks[reading.id], now: now)
                }
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// One window: its name over when it resets and when it was read, and the forecast when it says something; the bar and
/// the percentage in a trailing column of a fixed width, so the eye travels a bounded distance. Near the limit, as the
/// alerts count it, the bar and the percentage turn red.
private struct UsageReadingRow: View {
    let reading: UsageWindowReading
    let outlook: UsageForecast.Outlook?
    let now: Date

    var body: some View {
        let forecast = outlook.flatMap { UsageForecast.caption($0, resetsAt: reading.resetsAt, now: now) }
        let nearLimit = !UsageAlertPolicy.nearLimit([reading], now: now).isEmpty
        HStack(spacing: SettingsMetrics.rowContent) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: Self.title(reading.label))
                    .font(SettingsTheme.bodyStrong)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                Text(verbatim: Self.when(reading, now: now))
                    .settingsDescriptionStyle()
                if let forecast {
                    Text(verbatim: forecast.text)
                        .settingsDescriptionStyle(tint: forecast.isWarning ? SettingsTheme.destructive : nil)
                }
            }
            Spacer(minLength: SettingsMetrics.rowContent)
            HStack(spacing: SettingsMetrics.rowContent) {
                UsageBar(fraction: reading.percent / 100, tint: nearLimit ? SettingsTheme.destructive : SettingsTheme.accent)
                Text(verbatim: (reading.percent / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(SettingsTheme.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(nearLimit ? SettingsTheme.destructive : SettingsTheme.ink)
                    .textSelection(.enabled)
                    .fixedSize()
                    .frame(minWidth: SettingsMetrics.valueColumn, alignment: .trailing)
            }
            .frame(width: SettingsTheme.listTrailingWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// The alerts' own name for the window ("weekly", "Max 5-hour"), written to follow a provider's name. A row starts
    /// with it, so with a capital.
    private static func title(_ label: String) -> String {
        label.prefix(1).uppercased() + label.dropFirst()
    }

    /// "Resets 7:09 PM · As of 4:57 PM", each with its weekday when it is not today.
    private static func when(_ reading: UsageWindowReading, now: Date) -> String {
        let asOf = String(localized: "As of \(UsageForecast.clock(reading.observedAt, now: now))")
        guard let reset = reading.resetsAt else { return asOf }
        return String(localized: "Resets \(UsageForecast.clock(reset, now: now))") + " · " + asOf
    }
}

/// A window's bar: the slider's track, filled up to the share used. At nothing used it keeps a dot, so the fill's
/// start still shows.
private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    /// The trailing column, less the percentage's readout and the gap before it.
    private static let width = SettingsTheme.listTrailingWidth - SettingsMetrics.valueColumn - SettingsMetrics.rowContent

    var body: some View {
        Capsule()
            .fill(SettingsTheme.line)
            .frame(width: Self.width, height: SettingsTheme.sliderTrackHeight)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: max(SettingsTheme.sliderTrackHeight, Self.width * min(max(fraction, 0), 1)),
                           height: SettingsTheme.sliderTrackHeight)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - The models

/// The models each provider ran this week, from its last read, in Recent chats' rows: the provider over the model, and
/// in the trailing column the tokens in and out, with the cost where the provider bills per token. Hidden when empty.
private struct UsageModelList: View {
    let models: [UsageModelRow]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
            SettingsSectionHeader("Models this week")
                .padding(.horizontal, SettingsTheme.sectionPadding.leading)
            ForEach(models) { row in
                HStack(spacing: SettingsMetrics.cardPadding) {
                    AgentProviderIconView(source: .init(providerID: row.provider), size: SettingsTheme.listRowIcon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                        Text(verbatim: row.provider.displayName)
                            .settingsDescriptionStyle()
                            .lineLimit(1)
                        Text(verbatim: row.model)
                            .font(SettingsTheme.bodyStrong)
                            .foregroundStyle(SettingsTheme.ink)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: SettingsMetrics.rowContent)
                    VStack(alignment: .trailing, spacing: SettingsMetrics.labelStack) {
                        // "83k in · 40k out", as Agents' rows count a turn's tokens: new input, then output.
                        Text(verbatim: String(localized: "\(AgentTurnFormat.compact(row.tokensIn)) in · \(AgentTurnFormat.compact(row.tokensOut)) out"))
                            .font(SettingsTheme.body)
                            .foregroundStyle(SettingsTheme.ink)
                            .textSelection(.enabled)
                        if let cost = row.cost {
                            Text(verbatim: cost)
                                .settingsDescriptionStyle()
                        }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: SettingsTheme.listTrailingWidth, alignment: .trailing)
                }
                .padding(.horizontal, SettingsMetrics.cardPadding)
                .frame(maxWidth: .infinity, minHeight: SettingsTheme.listRowHeight)
                .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The data

/// What the page shows, copied from the usage stores: one value, so one subscription carries it, and it is assigned
/// only when it changed.
struct UsageOverviewData: Equatable {
    var readings: [UsageWindowReading] = []
    var outlooks: [String: UsageForecast.Outlook] = [:]
    var models: [UsageModelRow] = []
}

/// One model a provider ran this week, as its row shows it.
struct UsageModelRow: Equatable, Identifiable {
    let provider: ProviderID
    let model: String
    /// New input (uncached, and written to the cache) and output; context read back from the cache is left out.
    let tokensIn: Int
    let tokensOut: Int
    /// Formatted, and only where the provider bills per token.
    let cost: String?

    var id: String { provider.rawValue + "/" + model }
}

#if DEBUG
/// DEBUG snapshot boards only: what `UsageOverview` and its header show in place of this Mac's switches and readings.
struct UsageOverviewFixture {
    var providers: [ProviderID]
    var data: UsageOverviewData
}
#endif
