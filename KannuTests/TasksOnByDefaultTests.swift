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

/// Tasks is on by default since 2.0 (David, 2026-11-18: "Also enable tasks by default"), updaters who never
/// touched the switch included. That is safe only because turning it on raises no macOS dialog: Reminders
/// access is asked on Connect, Notifications on a task's first schedule.
final class TasksOnByDefaultTests: XCTestCase {
    func testTasksIsOnByDefault() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let constants = try String(contentsOf: root.appendingPathComponent("Kannu/models/Constants.swift"), encoding: .utf8)
        XCTAssertTrue(constants.contains(#"static let enableTasks = Key<Bool>("enableTasks", default: true)"#))
    }
}
