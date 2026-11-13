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

import XCTest

/// Brain's sidebar badges (Stage 6, layout-proposal.md D2) keep Brain's live-data rules (docs/SETTINGS.md, "Live data"):
/// each badge copies one value through a subscription throttled to 500 ms, in a `.task(id:)` on Brain's visibility that
/// returns at once while Brain is not on screen; nothing observes a store whole; nothing ticks; and the sidebar's root
/// and row read no state for them (docs/REGRESSIONS.md, entry 10). Read from the source and proved against planted
/// offenders, as `AgentsPageLiveDataRulesTests` does.
final class SidebarBadgeLiveDataRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static func code(_ text: String) -> String {
        SettingsDesignSystemRulesTests.code(text)
    }

    private static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        SettingsDesignSystemRulesTests.matches(of: pattern, in: text)
    }

    /// The four live badges: the agents' light, high findings, usage near its limit, the timer's glyph.
    private static let liveBadges = 4

    // MARK: - The badges

    static func liveProblems(in source: String) -> [String] {
        var problems: [String] = []
        let code = Self.code(source)
        // Only while Brain is on screen: a `.task(id:)` on its visibility that returns at once while it is not.
        let gated = matches(#"\.task\(id: visibility\.isOnScreen\) \{\s*guard visibility\.isOnScreen else \{ return \}"#, in: code).count
        if gated != liveBadges || count(".task", in: code) != liveBadges {
            problems.append("a badge follows its source while Brain is not on screen")
        }
        if count(".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)", in: code) != liveBadges {
            problems.append("a badge is not throttled to 500 ms")
        }
        // A `Task` inside the `.task` would outlive its cancel.
        if code.contains("Task {") || code.contains("Task.detached") {
            problems.append("a badge subscribes in a Task its .task cannot cancel")
        }
        // Nothing observes a store whole: Brain's visibility is the only observed object.
        let observed = matches(#"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*"#, in: code)
            .filter { !$0.hasSuffix("= BrainVisibility.shared") }
        if !observed.isEmpty { problems.append("a badge observes a store whole: \(observed)") }
        // The agents' light comes from the monitor's projection, never the monitor, which publishes on every hook write.
        if !matches(#"CursorAgentStatusMonitor\.shared(?!\.projection)"#, in: code).isEmpty {
            problems.append("a badge reads the agent monitor itself")
        }
        // The timer's glyph follows whether a timer runs, never its time, which ticks three times a second.
        for ticking in ["$remainingTime", "$elapsedTime", "$lastUpdated", "TimerManager.shared.objectWillChange"] where code.contains(ticking) {
            problems.append("the timer's badge follows its time: \(ticking)")
        }
        // Nothing ticks or animates.
        for clock in ["TimelineView", "Timer.", ".publish(every", "repeatForever", "withAnimation", ".animation("] where code.contains(clock) {
            problems.append("a badge keeps a clock or an animation: \(clock)")
        }
        // A state is said in words too, for VoiceOver and the pointer: the dot's, the count's and the glyph's.
        if count(".accessibilityLabel(", in: code) != 3 || count(".help(", in: code) != 3 {
            problems.append("a badge's state rests on colour alone")
        }
        // The light's and the timer's chains drop repeats before the throttle, so a repeat never wakes a badge.
        if count(".removeDuplicates()\n                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)", in: code) != 2 {
            problems.append("a badge throttles before it drops repeats")
        }
        // Back on screen, Security reads the store before it follows it: `objectWillChange` does not send again what
        // changed while Brain was away.
        if !code.contains("high = Self.read()\n            for await _ in SecurityFindingsStore.shared.objectWillChange") {
            problems.append("Security's badge comes back on screen with the count it left with")
        }
        // Security's and Usage's pages show nothing of theirs while Agent Status is off, and neither do their badges.
        if !code.contains("if agentStatusOn && high > 0 {") || !code.contains("if agentStatusOn && nearLimit {") {
            problems.append("a badge shows a state its page hides while Agent Status is off")
        }
        return problems
    }

    func testEachBadgeFollowsItsSourceThrottledAndOnlyOnScreen() throws {
        let badges = try Self.read("Kannu/components/Settings/SidebarBadges.swift")
        XCTAssertEqual(Self.liveProblems(in: badges), [])
        let plantedTask = "            let timer = TimerManager.shared\n"
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .task(id: visibility.isOnScreen) {\n            guard visibility.isOnScreen else { return }\n            let timer",
             "        .task(id: visibility.isOnScreen) {\n            let timer"),
            ("        .task(id: visibility.isOnScreen) {\n            guard visibility.isOnScreen else { return }\n            let light",
             "        .task {\n            guard visibility.isOnScreen else { return }\n            let light"),
            ("            for await readings in UsageAlertManager.shared.$nearLimit\n                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n",
             "            for await readings in UsageAlertManager.shared.$nearLimit\n"),
            (plantedTask, plantedTask + "            Task { await TimerManager.shared.isTimerActive }\n"),
            ("    @State private var runs = false\n", "    @State private var runs = false\n    @ObservedObject private var timer = TimerManager.shared\n"),
            ("        return light.shouldShowTrafficLight", "        _ = CursorAgentStatusMonitor.shared.sessions\n        return light.shouldShowTrafficLight"),
            ("timer.$isPaused", "timer.$remainingTime"),
            ("            if runs {\n", "            TimelineView(.periodic(from: .now, by: 1)) { _ in EmptyView() }\n            if runs {\n"),
            ("                    .accessibilityLabel(String(localized: \"Running\"))\n", ""),
            ("                .map { active, paused in active && !paused }\n                .removeDuplicates()\n                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n",
             "                .map { active, paused in active && !paused }\n                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .removeDuplicates()\n"),
            ("            high = Self.read()\n            for await", "            for await"),
            ("if agentStatusOn && high > 0 {", "if high > 0 {"),
            ("if agentStatusOn && nearLimit {", "if nearLimit {"),
        ], in: badges, by: Self.liveProblems)
    }

    // MARK: - The sidebar places them and reads nothing for them

    static func placementProblems(view: String, row: String) -> [String] {
        var problems: [String] = []
        let view = Self.code(view), row = Self.code(row)
        if !view.contains("badge: SidebarBadge(tab)") { problems.append("the sidebar's tab rows have no badge") }
        // The root observes nothing for a badge: it would redraw the whole of Brain as a store changes.
        for store in ["SecurityFindingsStore", "UsageAlertManager", "TimerManager", "CursorAgentStatusMonitor"] where view.contains(store) {
            problems.append("the sidebar's root names \(store)")
        }
        // The row takes a view the caller builds, and draws no badge of its own.
        if !row.contains("struct SettingsSidebarRow<Badge: View>: View {") || row.contains("badge: String?") || row.contains("Capsule()") {
            problems.append("the row draws a badge of its own")
        }
        return problems
    }

    func testTheSidebarPlacesTheBadgesAndReadsNothingForThem() throws {
        let view = try Self.read("Kannu/components/Settings/SettingsView.swift")
        let row = try Self.read("Kannu/components/Settings/DesignSystem/SettingsSidebarRow.swift")
        XCTAssertEqual(Self.placementProblems(view: view, row: row), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("badge: SidebarBadge(tab)", "badge: Text(verbatim: \"\\(TimerManager.shared.isTimerActive)\")"),
            ("badge: SidebarBadge(tab)", "badge: EmptyView()"),
        ], in: view) { Self.placementProblems(view: $0, row: row) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("                badge\n", "                badge\n                Text(verbatim: \"BETA\").background(Capsule().fill(SettingsTheme.ink))\n"),
        ], in: row) { Self.placementProblems(view: view, row: $0) }
    }

    // MARK: - The boards

    /// No board reads this Mac's agents, findings, usage or timer: every one is quiet but `shellBadges`, which shows all
    /// four from a fixture.
    func testTheBoardsDrawTheBadgesFromFixtures() throws {
        let snapshots = Self.code(try Self.read("Kannu/helpers/DebugSnapshot.swift"))
        let quiet = try XCTUnwrap(snapshots.range(of: "SidebarBadge.snapshotFixture = .quiet"), "boards read this Mac's stores")
        let firstBoard = try XCTUnwrap(snapshots.range(of: "for (name, view) in boards {"))
        XCTAssertLessThan(quiet.lowerBound, firstBoard.lowerBound, "a board renders before the badges are quiet")
        XCTAssertTrue(snapshots.contains("SidebarBadge.snapshotFixture = .busy"), "no board draws the badges")
        let badges = Self.code(try Self.read("Kannu/components/Settings/SidebarBadges.swift"))
        // Each badge's first read takes the fixture when there is one, so a board never touches a store.
        XCTAssertEqual(Self.count("if let fixture = SidebarBadge.snapshotFixture { return fixture.", in: badges), Self.liveBadges)
    }
}
