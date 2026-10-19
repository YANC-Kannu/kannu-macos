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

/// A timed task's session is named by its title, and its short key rides beside it as a chip. The
/// name used to be the raw key and the title, cut at 40 characters, so a GitLab task in a nested
/// group read "discern_security/applications/ds-vendors" — no number and no title — in the closed
/// notch, the open timer and the popover. The views are SwiftUI with no unit surface, so the
/// wiring is pinned by reading the source, each rule with a planted offender.
final class TimerTaskLabelRulesTests: XCTestCase {
    private static let tasksManagerPath = "Kannu/managers/Tasks/TasksManager.swift"
    private static let timerManagerPath = "Kannu/managers/TimerManager.swift"
    private static let notchTimerPath = "Kannu/components/Notch/NotchTimerView.swift"
    private static let popoverPath = "Kannu/components/Notch/TasksPopover.swift"

    func testATaskSessionIsNamedByItsTitleAndCarriesItsShortKey() throws {
        XCTAssertEqual(Self.startProblems(in: try Self.read(Self.tasksManagerPath)), [])
    }

    func testTheStartScannerCatchesTheRawKeyName() {
        let planted = """
            func start(_ taskID: UUID) -> Bool {
                let typed = task.remote.map { "\\($0.key) \\(task.title)" } ?? task.title
                timer.startTimer(duration: 60, name: TimerSessionName.resolved(typed: typed, fallback: fallback))
                return true
            }
            """
        XCTAssertEqual(Self.startProblems(in: planted), [
            "the session's name is prefixed by the task's raw key",
            "the session does not carry the task's short key",
        ])
        XCTAssertEqual(Self.startProblems(in: "func stop() {}"), ["start(_:) not found"])
    }

    func testTheSessionKeyLivesAndDiesWithItsSession() throws {
        XCTAssertEqual(Self.sessionKeyProblems(in: try Self.read(Self.timerManagerPath)), [])
    }

    func testTheSessionKeyScannerCatchesAKeyThatOutlivesItsSession() {
        let start = "func startTimer(duration: TimeInterval, taskKey: String? = nil) { sessionTint = tint; sessionTaskKey = taskKey }\n"
        let adopt = "func adoptExternalTimer(name: String) { sessionTint = nil; sessionTaskKey = nil }\n"
        let reset = "private func resetTimer() { sessionTint = nil; sessionTaskKey = nil }\n"
        XCTAssertEqual(Self.sessionKeyProblems(in: start + adopt + reset), [])
        XCTAssertEqual(Self.sessionKeyProblems(in: start + adopt.replacingOccurrences(of: "; sessionTaskKey = nil", with: "") + reset),
                       ["func adoptExternalTimer( does not set sessionTaskKey = nil"])
        XCTAssertEqual(Self.sessionKeyProblems(in: start + adopt + reset.replacingOccurrences(of: "; sessionTaskKey = nil", with: "")),
                       ["private func resetTimer( does not set sessionTaskKey = nil"])
        XCTAssertEqual(Self.sessionKeyProblems(in: start.replacingOccurrences(of: "; sessionTaskKey = taskKey", with: "") + adopt + reset),
                       ["func startTimer( does not set sessionTaskKey = taskKey"])
    }

    /// The open timer shows the key as a chip under the name, read from the session, so the view
    /// never reaches into `TasksManager` (`TaskColorRulesTests` pins that too).
    func testTheOpenTimerShowsTheKeyAsAChip() throws {
        let view = try Self.read(Self.notchTimerPath)
        let section = try XCTUnwrap(Self.body(after: "private var timerTitleSection: some View", in: view), "timerTitleSection is gone")
        XCTAssertTrue(section.contains("if let key = timerManager.sessionTaskKey") && section.contains("SideChip(key"),
                      "the open timer no longer shows the task's key as a chip")
    }

    func testThePopoverShowsTheShortKeyNeverTheRawOne() throws {
        let popover = try Self.read(Self.popoverPath)
        XCTAssertFalse(popover.contains("remote?.key"), "the popover shows a raw key again")
        XCTAssertEqual(popover.components(separatedBy: "TaskDetailSummary.shortKey(for: task)").count - 1, 2,
                       "the Now card and the Up next caption both read the short key")
    }

    // MARK: - Rules

    static func startProblems(in source: String) -> [String] {
        guard let start = body(after: "func start(_ taskID: UUID)", in: source) else { return ["start(_:) not found"] }
        var problems: [String] = []
        if start.contains("$0.key) \\(task.title)") {
            problems.append("the session's name is prefixed by the task's raw key")
        }
        if !start.contains("taskKey: TaskDetailSummary.shortKey(for: task)") {
            problems.append("the session does not carry the task's short key")
        }
        return problems
    }

    static func sessionKeyProblems(in source: String) -> [String] {
        let rules: [(function: String, needle: String)] = [
            ("func startTimer(", "sessionTaskKey = taskKey"),
            ("func adoptExternalTimer(", "sessionTaskKey = nil"),
            ("private func resetTimer(", "sessionTaskKey = nil"),
        ]
        return rules.compactMap { rule in
            guard let body = body(after: rule.function, in: source) else { return "\(rule.function) not found" }
            return body.contains(rule.needle) ? nil : "\(rule.function) does not set \(rule.needle)"
        }
    }

    // MARK: - Source reading

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The braces' content after `signature`, matched by depth; nil when the signature is gone.
    static func body(after signature: String, in text: String) -> String? {
        guard let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<index]) }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }
}
