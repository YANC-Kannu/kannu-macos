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

/// The done tick's undo window (David, 2026-10-28: "a done button near tasks, like tick").
final class TaskDoneTicksTests: XCTestCase {
    func testOnlyALocalTaskInTheListCanBeTicked() {
        XCTAssertTrue(TaskDoneTicks.canTick(TaskItem(title: "Mine")))
        XCTAssertFalse(TaskDoneTicks.canTick(TaskItem(title: "Done", visibility: .done)), "already closed")
        XCTAssertFalse(TaskDoneTicks.canTick(TaskItem(title: "Archived", visibility: .archived)))
        XCTAssertFalse(TaskDoneTicks.canTick(TaskItem(source: .gitlab, title: "Ticket")),
                       "a remote task's status belongs to its source")
    }

    func testATickWaitsAndThenStands() {
        var ticks = TaskDoneTicks()
        let id = UUID()
        XCTAssertTrue(ticks.toggle(id), "arm the commit")
        XCTAssertTrue(ticks.isTicked(id))
        XCTAssertTrue(ticks.commit(id), "the window ran out: mark it done")
        XCTAssertFalse(ticks.isTicked(id))
        XCTAssertFalse(ticks.commit(id), "a second commit does nothing")
    }

    func testASecondClickInTheWindowTakesTheTickBack() {
        var ticks = TaskDoneTicks()
        let id = UUID()
        _ = ticks.toggle(id)
        XCTAssertFalse(ticks.toggle(id), "taken back")
        XCTAssertFalse(ticks.isTicked(id))
        XCTAssertFalse(ticks.commit(id), "the commit that was armed finds nothing to do")
    }

    func testTicksAreIndependent() {
        var ticks = TaskDoneTicks()
        let first = UUID(), second = UUID()
        _ = ticks.toggle(first)
        _ = ticks.toggle(second)
        _ = ticks.toggle(first)
        XCTAssertFalse(ticks.isTicked(first))
        XCTAssertTrue(ticks.isTicked(second))
    }

    func testAQuitMarksEveryWaitingTickDone() {
        var ticks = TaskDoneTicks()
        let first = UUID(), second = UUID()
        _ = ticks.toggle(first)
        _ = ticks.toggle(second)
        XCTAssertEqual(ticks.commitAll(), [first, second])
        XCTAssertTrue(ticks.pending.isEmpty)
    }

    func testTheWindowIsShort() {
        XCTAssertEqual(TaskDoneTicks.undoSeconds, 1.5, "long enough to take back a slip, short enough to see it go")
    }
}
