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

/// The call's page on the open notch's media screen. The screen, its pager and the track-skip
/// gate are SwiftUI and AppKit with no unit surface, so they are pinned by reading the source,
/// each rule against a planted offender.
///
/// What David decided (2026-11-24): opening the notch during a call shows the call first and a
/// sideways swipe brings media back; with no call the media screen is exactly as it was, and a
/// sideways swipe there still skips tracks.
final class HomeCallPageRulesTests: XCTestCase {
    private static let homePath = "Kannu/components/Notch/NotchHomeView.swift"
    private static let contentViewPath = "Kannu/ContentView.swift"
    private static let swipeMonitorPath = "Kannu/components/Notch/HorizontalSwipeMonitor.swift"
    private static let callViewPaths = ["Kannu/components/Calls/CallLiveActivity.swift",
                                        "Kannu/components/Calls/CallPageView.swift"]

    // MARK: - The pager exists only while a call does

    func testThePagerExistsOnlyWithACall() throws {
        XCTAssertEqual(Self.pagerProblems(in: try Self.read(Self.homePath)), [])
    }

    func testAPagerWithNoCallIsCaught() throws {
        let real = try Self.read(Self.homePath)
        let always = real.replacingOccurrences(of: """
                        if call != nil {
                            HorizontalSwipeMonitor(current: shownPage, onSwipe: select)
                        }
            """, with: "                HorizontalSwipeMonitor(current: shownPage, onSwipe: select)")
        XCTAssertEqual(Self.pagerProblems(in: always), ["the page swipe is installed with no call, where it would take the track skip"])
        let labelled = real.replacingOccurrences(of: """
                        if call != nil {
                            pager
            """, with: """
                        if true {
                            pager
            """)
        XCTAssertEqual(Self.pagerProblems(in: labelled), ["the Call and Media labels show with no call"])
        let noPlayer = real.replacingOccurrences(of: "MusicPlayerView(albumArtNamespace: albumArtNamespace)", with: "EmptyView()")
        XCTAssertEqual(Self.pagerProblems(in: noPlayer), ["the media screen no longer draws the music player"])
        let pageAlways = real.replacingOccurrences(of: "if let call, shownPage == .call {", with: "if let call {")
        XCTAssertEqual(Self.pagerProblems(in: pageAlways), ["the call's page does not follow the shown page"])
        let whole = real.replacingOccurrences(of: "@ObservedObject private var callActivity = CallActivityManager.shared",
                                              with: "@ObservedObject private var monitor = CursorAgentStatusMonitor.shared")
        XCTAssertEqual(Self.pagerProblems(in: whole), ["the media screen does not read the one published call"])
    }

    /// The monitor takes the page type, and still serves the timer tab unchanged.
    func testTheSwipeMonitorTakesThePageType() throws {
        let monitor = try Self.read(Self.swipeMonitorPath)
        XCTAssertTrue(monitor.contains("struct HorizontalSwipeMonitor<Page: SwipeablePage>: View"))
        XCTAssertTrue(monitor.contains("extension TimerSidePage: SwipeablePage { typealias Swipe = TimerSideSwipe }"))
        XCTAssertTrue(monitor.contains("extension HomePage: SwipeablePage { typealias Swipe = HomePageSwipe }"))
        XCTAssertFalse(ClosedCallPillRulesTests.code(monitor).contains("current: TimerSidePage"), "the monitor still names one page type")
    }

    // MARK: - A sideways swipe: the page during a call, the track otherwise

    func testASwipeSkipsNoTrackWhileACallHasAPage() throws {
        XCTAssertEqual(Self.skipProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testAnUngatedSkipIsCaught() throws {
        let real = try Self.read(Self.contentViewPath)
        XCTAssertEqual(Self.skipProblems(in: real.replacingOccurrences(of: "        guard !homeHasCallPage else { return false }\n", with: "")),
                       ["a sideways swipe skips a track while it turns the call's page"])
        // After the answer is computed is too late.
        let late = """
            private var homeHasCallPage: Bool {
                currentCall != nil
            }
            private func canPerformSkipGesture() -> Bool {
                return enableHorizontalMusicGestures
                guard !homeHasCallPage else { return false }
            }
            """
        XCTAssertEqual(Self.skipProblems(in: late), ["a sideways swipe skips a track while it turns the call's page"])
        let anyCall = real.replacingOccurrences(of: """
                private var homeHasCallPage: Bool {
                    currentCall != nil
                }
            """, with: """
                private var homeHasCallPage: Bool {
                    callActivity.activity != nil
                }
            """)
        XCTAssertEqual(Self.skipProblems(in: anyCall), ["the gate ignores the Calls switch"])
    }

    // MARK: - Opening during a call lands on the media screen

    func testAnOpenDuringACallLandsOnTheMediaScreen() throws {
        XCTAssertEqual(Self.focusProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testAnOpenThatFocusesTheTimerFirstIsCaught() throws {
        let real = try Self.read(Self.contentViewPath)
        let timerFirst = real.replacingOccurrences(of: """
                    if homeHasCallPage {
                        // A call comes first: the media screen, where its page is, ahead of the timer tab
                        // and the agents tab.
                        withAnimation(.smooth) {
                            coordinator.currentView = .home
                        }
                    } else if shouldFocusTimerTab {
            """, with: "        if shouldFocusTimerTab {")
        XCTAssertEqual(Self.focusProblems(in: timerFirst), ["a hover during a call opens on the timer or the agents tab"])
        let wings = real.replacingOccurrences(of: "        let focus: NotchViews = homeHasCallPage ? .home : focus\n", with: "")
        XCTAssertEqual(Self.focusProblems(in: wings), ["a wing's hover during a call does not open on the media screen"])
        let clicks = real.replacingOccurrences(of: "openNotch(focus: callOpenFocus)", with: "openNotch()")
        XCTAssertEqual(Self.focusProblems(in: clicks), ["a click or a swipe during a call does not open on the media screen"])
        // In `openNotch` itself it would also take a dragged file away from the shelf.
        let everywhere = real.replacingOccurrences(of: "    private func openNotch(focus: NotchViews? = nil) {\n",
                                                   with: "    private func openNotch(focus: NotchViews? = nil) {\n        let focus = focus ?? callOpenFocus\n")
        XCTAssertEqual(Self.focusProblems(in: everywhere), ["a file dragged to the notch during a call misses the shelf"])
    }

    // MARK: - The call's views: parameters only, nothing repeating

    func testTheCallViewsObserveNothingAndRunNothing() throws {
        for path in Self.callViewPaths {
            XCTAssertEqual(Self.viewProblems(in: try Self.read(path)), [], path)
        }
    }

    func testAnObservingOrRepeatingViewIsCaught() {
        let clean = """
            struct CallPageView: View {
                @Environment(\\.notchForeground) private var notchForeground
                let title: String
                var body: some View {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(SettingsTheme.font(size: 13, weight: .medium))
                }
            }
            """
        XCTAssertEqual(Self.viewProblems(in: clean), [])
        XCTAssertEqual(Self.viewProblems(in: clean.replacingOccurrences(of: "let title: String",
                                                                        with: "@ObservedObject var manager = CallActivityManager.shared")),
                       ["observes: @ObservedObject, CallActivityManager"])
        XCTAssertEqual(Self.viewProblems(in: clean.replacingOccurrences(of: "let title: String", with: "@Default(.enableCallActivity) var enabled")),
                       ["observes: @Default"])
        XCTAssertEqual(Self.viewProblems(in: clean.replacingOccurrences(of: "let title: String", with: "@State private var now = Date()")),
                       ["observes: @State"])
        XCTAssertEqual(Self.viewProblems(in: clean + "\n.animation(.easeInOut.repeatForever(), value: pulse)"),
                       ["moves or repeats: repeatForever, .animation("])
        XCTAssertEqual(Self.viewProblems(in: clean + "\nTimelineView(.periodic(from: .now, by: 1)) { _ in }"),
                       ["moves or repeats: TimelineView"])
        XCTAssertEqual(Self.viewProblems(in: clean + "\nlet tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()"),
                       ["runs a clock: Timer.publish, .autoconnect()"])
        // A comment may name what is banned.
        XCTAssertEqual(Self.viewProblems(in: clean + "\n// no @ObservedObject, no repeatForever, no Timer.publish"), [])
    }

    /// The time is one self-updating text, and the text is Geist. A symbol is sized by `.system`.
    func testTheTimeIsOneTextAndTheTextIsGeist() throws {
        let sources = try Self.callViewPaths.map { try Self.read($0) }
        let code = sources.map(ClosedCallPillRulesTests.code).joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: "Text(timerInterval:").count - 1, 1,
                       "the elapsed time is drawn by one Text(timerInterval:), in CallElapsedText")
        XCTAssertFalse(code.contains("style: .timer") || code.contains("Date()"), "the views keep no clock of their own")
        // 3 in the pill's file (the stand-in tile's symbol, the phone glyph, the camera glyph) and
        // 1 on the page (its phone glyph): symbols, which `.system` sizes. Text takes the theme's font.
        XCTAssertEqual(sources.map(NotchFontRulesTests.systemFontLines(in:)), [3, 1])
        XCTAssertGreaterThanOrEqual(code.components(separatedBy: "SettingsTheme.font(size:").count - 1, 3)
    }

    // MARK: - Rules

    static func pagerProblems(in source: String) -> [String] {
        var problems: [String] = []
        let home = source.range(of: "struct NotchHomeView: View").map { String(source[$0.lowerBound...]) } ?? ""
        if !(home.contains("@ObservedObject private var callActivity = CallActivityManager.shared")
             && home.contains("enableCallActivity ? callActivity.activity : nil")) {
            problems.append("the media screen does not read the one published call")
        }
        let main = ClosedNotchTimerRulesTests.body(after: "private var mainContent: some View", in: home) ?? ""
        if !main.contains("if let call, shownPage == .call {") { problems.append("the call's page does not follow the shown page") }
        if !main.contains("MusicPlayerView(albumArtNamespace: albumArtNamespace)") {
            problems.append("the media screen no longer draws the music player")
        }
        let swipe = ClosedNotchTimerRulesTests.body(after: ".background", in: main) ?? ""
        let hosts = home.components(separatedBy: "HorizontalSwipeMonitor(").count - 1
        if hosts != 1 || !Self.squeezed(swipe).hasPrefix("if call != nil { HorizontalSwipeMonitor(current: shownPage, onSwipe: select) }") {
            problems.append("the page swipe is installed with no call, where it would take the track skip")
        }
        let labels = ClosedNotchTimerRulesTests.body(after: ".overlay(alignment: .bottom)", in: main) ?? ""
        if !Self.squeezed(labels).hasPrefix("if call != nil { pager") {
            problems.append("the Call and Media labels show with no call")
        }
        return problems
    }

    static func skipProblems(in source: String) -> [String] {
        var problems: [String] = []
        let gate = ClosedNotchTimerRulesTests.body(after: "private func canPerformSkipGesture() -> Bool", in: source) ?? ""
        let guarded = gate.range(of: "guard !homeHasCallPage else { return false }")
        let answered = gate.range(of: "return enableHorizontalMusicGestures")
        if guarded == nil || answered == nil || guarded!.lowerBound > answered!.lowerBound {
            problems.append("a sideways swipe skips a track while it turns the call's page")
        }
        let has = ClosedNotchTimerRulesTests.body(after: "private var homeHasCallPage: Bool", in: source) ?? ""
        if !has.contains("currentCall != nil") { problems.append("the gate ignores the Calls switch") }
        return problems
    }

    static func focusProblems(in source: String) -> [String] {
        var problems: [String] = []
        let hover = ClosedNotchTimerRulesTests.body(after: "private func completeHoverOpen(shouldFocusTimerTab: Bool)", in: source) ?? ""
        let call = hover.range(of: "if homeHasCallPage {")
        let timer = hover.range(of: "shouldFocusTimerTab {")
        if call == nil || timer == nil || call!.lowerBound > timer!.lowerBound
            || !hover[call!.upperBound..<timer!.lowerBound].contains("coordinator.currentView = .home") {
            problems.append("a hover during a call opens on the timer or the agents tab")
        }
        let region = ClosedNotchTimerRulesTests.body(after: "private func handleRegionHoverOpen(_ hovering: Bool, focus: NotchViews)", in: source) ?? ""
        if !region.contains("let focus: NotchViews = homeHasCallPage ? .home : focus") {
            problems.append("a wing's hover during a call does not open on the media screen")
        }
        // The click on the closed notch, the hover-click monitor, the open after a HUD, and the swipe down.
        if source.components(separatedBy: "openNotch(focus: callOpenFocus)").count - 1 < 3
            || source.components(separatedBy: "self.openNotch(focus: self.callOpenFocus)").count - 1 != 1 {
            problems.append("a click or a swipe during a call does not open on the media screen")
        }
        let open = ClosedNotchTimerRulesTests.body(after: "private func openNotch(focus: NotchViews? = nil)", in: source) ?? ""
        let drop = source.range(of: "coordinator.currentView = .shelf").map { String(source[$0.upperBound...].prefix(60)) } ?? ""
        if open.contains("callOpenFocus") || open.contains("homeHasCallPage") || !drop.contains("openNotch()") {
            problems.append("a file dragged to the notch during a call misses the shelf")
        }
        return problems
    }

    static func viewProblems(in source: String) -> [String] {
        let code = ClosedCallPillRulesTests.code(source)
        var problems: [String] = []
        let observers = ["@ObservedObject", "@StateObject", "@EnvironmentObject", "@Default", "Defaults[", "@State", "@AppStorage",
                         "onReceive", "CallActivityManager", "KannuViewCoordinator", "NotificationCenter"].filter(code.contains)
        if !observers.isEmpty { problems.append("observes: " + observers.joined(separator: ", ")) }
        let motion = ClosedAgentPillRulesTests.motion(in: code)
        if !motion.isEmpty { problems.append("moves or repeats: " + motion.joined(separator: ", ")) }
        let clocks = ["Timer.publish", "Timer.scheduledTimer", "Timer(timeInterval", ".autoconnect()", "DispatchSourceTimer",
                      "Task.sleep", "asyncAfter("].filter(code.contains)
        if !clocks.isEmpty { problems.append("runs a clock: " + clocks.joined(separator: ", ")) }
        return problems
    }

    // MARK: - Source reading

    /// Runs of whitespace as one space, so a rule reads a block however it is wrapped.
    private static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    private static func read(_ path: String) throws -> String {
        try ClosedCallPillRulesTests.read(path)
    }
}
