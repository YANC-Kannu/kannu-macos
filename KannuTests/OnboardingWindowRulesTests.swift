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

/// Onboarding's window, as a window. It was ordered to the front once, as it opened, so after a trip to System
/// Settings for a permission it could sit behind another app's window and look stuck. It now comes forward each time
/// Kannu becomes active, and only then: it never activates Kannu, so it cannot take the keyboard from System Settings.
/// The second rule keeps a branch that can never run out of the steps: the welcome carried an `if false` "PRO" badge
/// from the app Kannu was forked from. Both are AppKit and SwiftUI, so their text is read, each rule checked against
/// planted offenders.
final class OnboardingWindowRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let onboardingPath = "Kannu/components/Onboarding/OnboardingView.swift"
    private static let appPath = "Kannu/KannuApp.swift"

    // MARK: - The window comes back to the front

    /// The one statement that brings the window forward: the window with onboarding's identifier, while it is on
    /// screen, ordered front and made key. Nothing else, so no other window moves and a window closed at Finish stays
    /// closed.
    private static let bringForward = "NSApp.windows.first { $0.identifier?.rawValue == windowIdentifier && $0.isVisible }?.makeKeyAndOrderFront(nil)"

    static func refocusProblems(onboarding: String, app: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(onboarding)
        var problems: [String] = []
        let observer = ".onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))"
        let action = ClosedNotchTimerRulesTests.body(after: observer, in: code).map(squeezed)
        if action != "_ in Self.bringWindowForward()" || code.components(separatedBy: "bringWindowForward(").count - 1 != 2 {
            problems.append("the window does not come forward when Kannu becomes active, and only then")
        }
        let forward = ClosedNotchTimerRulesTests.body(after: "static func bringWindowForward()", in: code).map(squeezed)
        if forward != bringForward {
            problems.append("coming forward does more than order onboarding's own window, while it is on screen")
        }
        // Activating is what would pull focus from System Settings; the window's maker does it once, as it opens.
        for call in [".activate(", "orderFrontRegardless", "setActivationPolicy", "NSRunningApplication"] where code.contains(call) {
            problems.append("onboarding's view activates Kannu itself: \(call)")
        }
        if !code.contains(#"static let windowIdentifier = "OnboardingWindow""#)
            || !SettingsDesignSystemRulesTests.code(app).contains(#"window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")"#) {
            problems.append("the view looks for a window its maker does not name")
        }
        return problems
    }

    func testTheWindowComesForwardOnlyWhenKannuBecomesActive() throws {
        let onboarding = try Self.read(Self.onboardingPath)
        let app = try Self.read(Self.appPath)
        XCTAssertEqual(Self.refocusProblems(onboarding: onboarding, app: app), [])

        let observer = "        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in\n"
            + "            Self.bringWindowForward()\n        }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            // The fix removed: the window is ordered front once, as it opens, and never again.
            (observer, ""),
            ("NSApplication.didBecomeActiveNotification", "NSApplication.didResignActiveNotification"),
            ("            Self.bringWindowForward()\n", "            NSApp.activate(ignoringOtherApps: true)\n            Self.bringWindowForward()\n"),
            ("    var body: some View {\n        ZStack {", "    var body: some View {\n        let _ = Self.bringWindowForward()\n        ZStack {"),
            (" && $0.isVisible }", " }"),
            ("$0.identifier?.rawValue == windowIdentifier && $0.isVisible", "$0.isVisible"),
            ("?.makeKeyAndOrderFront(nil)", "?.orderFrontRegardless()"),
            ("?.makeKeyAndOrderFront(nil)", "?.makeKeyAndOrderFront(nil)\n        NSApp.setActivationPolicy(.regular)"),
            (#"windowIdentifier = "OnboardingWindow""#, #"windowIdentifier = "Onboarding""#),
        ], in: onboarding) { Self.refocusProblems(onboarding: $0, app: app) }
        XCTAssertFalse(Self.refocusProblems(onboarding: onboarding, app: app.replacingOccurrences(
            of: #"NSUserInterfaceItemIdentifier("OnboardingWindow")"#, with: #"NSUserInterfaceItemIdentifier("FirstRunWindow")"#)).isEmpty)
    }

    // MARK: - No branch that never runs

    /// A condition written as a literal: its branch either never runs or always does, and a reader has to work out
    /// which. Keyed by file name.
    static func deadBranches(in sources: [String: String]) -> [String] {
        sources.filter { _, source in
            SettingsDesignSystemRulesTests.code(source).range(of: #"\bif\s+(?:false|true)\b"#, options: .regularExpression) != nil
        }.keys.sorted()
    }

    func testNoOnboardingStepKeepsABranchThatNeverRuns() throws {
        let folder = Self.root.appendingPathComponent("Kannu/components/Onboarding", isDirectory: true)
        var sources: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            sources[name] = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }
        let welcome = try XCTUnwrap(sources["WelcomeView.swift"], "the scan no longer reaches Onboarding/")
        XCTAssertEqual(Self.deadBranches(in: sources), [])
        XCTAssertFalse(welcome.contains(#"Text("PRO")"#), "the badge of the app Kannu was forked from is back")
        // The catalog's key went with its one use, so no translator is asked for a string nothing shows.
        let catalog = try Self.read("Kannu/Localizable.xcstrings")
        XCTAssertFalse(catalog.contains("\n    \"PRO\" : {"), "the catalog keeps a string no view shows")

        let badge = "                        .padding(.bottom, 30)\n                    if false {\n                        Text(\"PRO\")\n                    }\n"
        let planted = welcome.replacingOccurrences(of: "                        .padding(.bottom, 30)\n", with: badge)
        XCTAssertNotEqual(planted, welcome, "the plant's anchor moved")
        XCTAssertEqual(Self.deadBranches(in: ["WelcomeView.swift": planted]), ["WelcomeView.swift"])
        XCTAssertEqual(Self.deadBranches(in: ["Planted.swift": "if true {\n}\n"]), ["Planted.swift"])
        // A comment or a longer name is not a dead branch.
        XCTAssertEqual(Self.deadBranches(in: ["Planted.swift": "// if false, the step is skipped\nif falseAlarm {\n}\n"]), [])
    }

    // MARK: - Plumbing

    /// One space for every run of whitespace, and none at either end, so a rule reads a statement however it wraps.
    private static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
