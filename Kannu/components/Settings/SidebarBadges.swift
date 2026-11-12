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

/// A sidebar row's badge, only for a state that needs you: an agent waiting for input, high-severity findings to
/// review, usage near its limit. A running timer gets a static glyph. No open-task count: it is never zero, so people
/// stop seeing it (layout-proposal.md D2). A Settings page in beta gets the pages' one badge (finding 12).
///
/// Live data, as docs/SETTINGS.md "Live data" has it: each badge copies its one value from a subscription throttled to
/// 500 ms, assigned only on a change, in a `.task(id:)` on `BrainVisibility.isOnScreen` that returns at once while
/// Brain is not on screen, and reads its source once as it appears. Nothing here observes a store whole, and nothing
/// ticks: the timer's glyph follows whether a timer runs, never its time. `SettingsView` only places them, so the root
/// observes nothing new (docs/REGRESSIONS.md, entry 10).
struct SidebarBadge: View {
    private let tab: SettingsTab

    init(_ tab: SettingsTab) {
        self.tab = tab
    }

    var body: some View {
        switch tab {
        case .agentStatus: AgentsNeedYouBadge()
        case .agentSecurity: SecurityHighBadge()
        case .llmUsage: UsageNearLimitBadge()
        case .timer: TimerRunsGlyph()
        default:
            if tab.isBeta { SettingsBadge(String(localized: "Beta")) }
        }
    }

    #if DEBUG
    /// DEBUG snapshot boards only: what each badge shows, so no board reads this Mac's agents, findings, usage or timer.
    static var snapshotFixture: SidebarBadgeFixture?
    #endif
}

#if DEBUG
struct SidebarBadgeFixture {
    var agentsNeedYou = false
    var highFindings = 0
    var usageNearLimit = false
    var timerRuns = false

    static let quiet = SidebarBadgeFixture()
    static let busy = SidebarBadgeFixture(agentsNeedYou: true, highFindings: 2, usageNearLimit: true, timerRuns: true)
}
#endif

/// The agents' light, as the notch shows it: yellow while an agent waits for input. It follows the monitor's
/// projection, which moves only when the light does, never the session list.
private struct AgentsNeedYouBadge: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.agentAwaitingInputColor) private var awaiting
    @Environment(\.colorScheme) private var colorScheme
    @State private var needsYou = false

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if needsYou {
                // Paper is light, so the light's own hue is shaded until it reads, as Agents' state word does.
                SidebarDot(colour: colorScheme == .light ? awaiting.color.shadedForLightNotch : awaiting.color,
                           label: String(localized: "Needs you"))
            }
        }
        .onAppear { needsYou = Self.read() }
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            let light = CursorAgentStatusMonitor.shared.projection
            let waiting = light.$trafficLightState.combineLatest(light.$shouldShowTrafficLight)
                .map { state, shows in shows && state == .awaitingInput }
                .removeDuplicates()
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            for await value in waiting.values {
                if value != needsYou { needsYou = value }
            }
        }
    }

    private static func read() -> Bool {
        #if DEBUG
        if let fixture = SidebarBadge.snapshotFixture { return fixture.agentsNeedYou }
        #endif
        let light = CursorAgentStatusMonitor.shared.projection
        return light.shouldShowTrafficLight && light.trafficLightState == .awaitingInput
    }
}

/// How many high-severity findings wait for review. The findings store republishes on every hook write while a session
/// runs with permission checks off, so it is followed through `objectWillChange`, never observed.
private struct SecurityHighBadge: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @State private var high = 0

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if high > 0 {
                Text(verbatim: "\(high)")
                    .font(SettingsTheme.micro)
                    .foregroundStyle(SettingsTheme.onPrimary)
                    .padding(.horizontal, SettingsTheme.sidebarBadgeHorizontalInset)
                    .padding(.vertical, SettingsTheme.sidebarBadgeVerticalInset)
                    .background(Capsule().fill(SettingsTheme.destructive))
                    .help(String(localized: "High: \(high)"))
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "High: \(high)"))
            }
        }
        .onAppear { high = Self.read() }
        // `objectWillChange` comes before a change; read through the run loop, the count comes after it. Back on screen
        // it reads once first, since `objectWillChange` does not send again what changed while Brain was away.
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            high = Self.read()
            for await _ in SecurityFindingsStore.shared.objectWillChange
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                let latest = Self.read()
                if latest != high { high = latest }
            }
        }
    }

    private static func read() -> Int {
        #if DEBUG
        if let fixture = SidebarBadge.snapshotFixture { return fixture.highFindings }
        #endif
        return SecurityFindingsStore.shared.groupRanking.pendingHighCount
    }
}

/// A usage window at or near its limit, by the alert's own rule (`UsageAlertPolicy.nearLimit`). A window past its reset
/// no longer counts, as on the Usage page: the store drops one only while it runs.
private struct UsageNearLimitBadge: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @State private var nearLimit = false

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if nearLimit {
                SidebarDot(colour: SettingsTheme.destructive, label: String(localized: "Near its limit"))
            }
        }
        .onAppear { nearLimit = Self.read() }
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            for await readings in UsageAlertManager.shared.$nearLimit
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                let latest = Self.isNear(readings)
                if latest != nearLimit { nearLimit = latest }
            }
        }
    }

    private static func isNear(_ readings: [UsageWindowReading]) -> Bool {
        let now = Date()
        return readings.contains { $0.isLive(now: now) }
    }

    private static func read() -> Bool {
        #if DEBUG
        if let fixture = SidebarBadge.snapshotFixture { return fixture.usageNearLimit }
        #endif
        return isNear(UsageAlertManager.shared.nearLimit)
    }
}

/// A static glyph while a timer runs. It follows whether a timer runs and is not paused, never its time, which ticks.
private struct TimerRunsGlyph: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @State private var runs = false

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if runs {
                Image(systemName: "play.fill")
                    .font(SettingsTheme.micro)
                    .foregroundStyle(SettingsTheme.accentStrong)
                    .help(String(localized: "Running"))
                    .accessibilityLabel(String(localized: "Running"))
            }
        }
        .onAppear { runs = Self.read() }
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            let timer = TimerManager.shared
            let running = timer.$isTimerActive.combineLatest(timer.$isPaused)
                .map { active, paused in active && !paused }
                .removeDuplicates()
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            for await value in running.values {
                if value != runs { runs = value }
            }
        }
    }

    private static func read() -> Bool {
        #if DEBUG
        if let fixture = SidebarBadge.snapshotFixture { return fixture.timerRuns }
        #endif
        return TimerManager.shared.isTimerActive && !TimerManager.shared.isPaused
    }
}

/// A state's dot. Colour is not the only sign: its words go to VoiceOver and the pointer.
private struct SidebarDot: View {
    let colour: Color
    let label: String

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: SettingsMetrics.statusDot, height: SettingsMetrics.statusDot)
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}
