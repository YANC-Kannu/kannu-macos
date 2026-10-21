//
//  AppleRemindersMappingTests.swift
//  KannuTests
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest

/// Apple Reminders as a task source, the part that needs no EventKit: which reminders a sync keeps,
/// in what order, and what each says.
final class AppleRemindersMappingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func reminder(_ id: String, list: String = "Groceries", due: TimeInterval? = nil, priority: Int = 0,
                          modified: TimeInterval = 0, done: Bool = false) -> ReminderSnapshot {
        ReminderSnapshot(id: id, title: "Buy \(id)", listTitle: list, dueDate: due.map { now.addingTimeInterval($0) },
                         priority: priority, lastModified: now.addingTimeInterval(modified), isCompleted: done)
    }

    func testAReminderReadsAsATaskInItsList() {
        let issue = AppleReminders.remoteIssue(from: reminder("milk", list: "Groceries", due: 3600, priority: 1))
        XCTAssertEqual(issue.remoteID, "milk")
        XCTAssertEqual(issue.key, "Groceries", "the list is the key, and so the project")
        XCTAssertEqual(issue.title, "Buy milk")
        XCTAssertEqual(issue.dueDate, now.addingTimeInterval(3600))
        XCTAssertEqual(issue.priority, String(localized: "High"))
        XCTAssertEqual(issue.statusCategory, TaskFacets.toDoCategory)
        XCTAssertNil(issue.webURL, "a reminder has no page to open")
    }

    func testPrioritiesAsRemindersNamesThem() {
        XCTAssertNil(AppleReminders.priorityName(0))
        XCTAssertEqual(AppleReminders.priorityName(1), String(localized: "High"))
        XCTAssertEqual(AppleReminders.priorityName(5), String(localized: "Medium"))
        XCTAssertEqual(AppleReminders.priorityName(9), String(localized: "Low"))
    }

    func testSoonestDueFirstThenRecentlyChangedAndNeverACompletedOne() {
        let fetch = AppleReminders.fetch([
            reminder("undated-old", modified: 10), reminder("later", due: 7200), reminder("soon", due: 60),
            reminder("undated-new", modified: 99), reminder("done", due: 1, done: true),
        ])
        XCTAssertEqual(fetch.issues.map(\.remoteID), ["soon", "later", "undated-new", "undated-old"])
        XCTAssertTrue(fetch.complete)
    }

    func testABigListIsCappedAndSaysSo() {
        let many = (0..<(AppleReminders.cap + 5)).map { reminder("r\($0)", due: TimeInterval($0)) }
        let fetch = AppleReminders.fetch(many)
        XCTAssertEqual(fetch.issues.count, AppleReminders.cap)
        XCTAssertFalse(fetch.complete, "incomplete, so nothing is marked gone on its account")
        XCTAssertEqual(fetch.issues.first?.remoteID, "r0")
    }

    func testAReminderTaskMergesUnderRemindersScope() {
        let merged = TaskMerge.apply(.fetched(AppleReminders.fetch([reminder("milk")])), source: .appleReminders,
                                     hostScope: AppleReminders.scope, to: [], now: now, keepingActive: [])
        XCTAssertEqual(merged.tasks.first?.source, .appleReminders)
        XCTAssertEqual(merged.tasks.first?.remote?.key, "Groceries")
        XCTAssertEqual(merged.tasks.first.flatMap(TaskFacets.project(for:)), "Groceries")
        XCTAssertNil(merged.tasks.first.flatMap { TaskDetailSummary.shortKey(for: $0) })
    }
}
