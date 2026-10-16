//
//  TaskDetailSummaryTests.swift
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

/// The words on the timer tab's expanded task card. They mirror Brain's row caption, so a task
/// reads the same in both places; the deletable/openable rules follow the source.
final class TaskDetailSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09 08:53:20 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func remote(key: String, status: String = "", kind: GitLabKind? = nil,
                        spent: Int? = nil, estimate: Int? = nil, category: String? = nil) -> RemoteTaskInfo {
        RemoteTaskInfo(remoteID: key, key: key, hostScope: "https://example.test", status: status,
                       isDoneRemotely: false, remoteEstimateSeconds: estimate, remoteSpentSeconds: spent,
                       gitlabProjectID: nil, gitlabIID: nil, lastSeenAt: now, gitlabKind: kind,
                       gitlabWebURL: nil, statusCategory: category, labels: nil)
    }

    // MARK: - Identity

    func testALocalTaskIsJustLocal() {
        let task = TaskItem(title: "Write the plan")
        let summary = TaskDetailSummary(task: task, tracked: 0, now: now, calendar: calendar)
        XCTAssertNil(summary.key)
        XCTAssertEqual(summary.title, "Write the plan")
        XCTAssertEqual(summary.identity, "Local")
        XCTAssertNil(summary.browseLabel)
        XCTAssertTrue(summary.canDelete)
    }

    func testAJiraTaskNamesItsProjectAndStatus() {
        let task = TaskItem(source: .jira, title: "Fix login", remote: remote(key: "PROJ-123", status: "In Progress"))
        let summary = TaskDetailSummary(task: task, tracked: 0, now: now, calendar: calendar)
        XCTAssertEqual(summary.key, "PROJ-123")
        XCTAssertEqual(summary.identity, "Jira · PROJ · In Progress")
        XCTAssertEqual(summary.browseLabel, "Open in Jira")
        XCTAssertFalse(summary.canDelete, "a remote task would come back on the next sync")
    }

    func testAGitLabMergeRequestSaysSoWithItsStateAsAWord() {
        let task = TaskItem(source: .gitlab, title: "Add tests",
                            remote: remote(key: "group/app!12", status: "opened", kind: .mergeRequest))
        let summary = TaskDetailSummary(task: task, tracked: 0, now: now, calendar: calendar)
        XCTAssertEqual(summary.identity, "GitLab · group/app · Merge request · Open")
        XCTAssertEqual(summary.browseLabel, "Open in GitLab")
        XCTAssertFalse(summary.canDelete)
    }

    // MARK: - Time

    func testTimeReadsAsBrainsCaption() {
        let task = TaskItem(title: "Estimate", localEstimateSeconds: 2 * 3600)
        let summary = TaskDetailSummary(task: task, tracked: 42 * 60, now: now, calendar: calendar)
        XCTAssertEqual(summary.time, "42m of 2h")
        XCTAssertNil(summary.overtime)
    }

    func testOvertimeIsItsOwnWordOnceAMinuteOrMore() {
        let task = TaskItem(title: "Over", localEstimateSeconds: 30 * 60)
        XCTAssertEqual(TaskDetailSummary(task: task, tracked: 40 * 60, now: now, calendar: calendar).overtime, "10m over")
        XCTAssertNil(TaskDetailSummary(task: task, tracked: 30 * 60 + 30, now: now, calendar: calendar).overtime,
                     "under a minute over is not worth a word")
    }

    func testNoEstimateAndNoTimeSaysNoEstimate() {
        let task = TaskItem(title: "Fresh")
        XCTAssertEqual(TaskDetailSummary(task: task, tracked: 0, now: now, calendar: calendar).time, "No estimate")
        XCTAssertEqual(TaskDetailSummary(task: task, tracked: 5 * 60, now: now, calendar: calendar).time, "5m tracked")
    }

    // MARK: - Extras

    func testRemoteLoggedTimeDueAndTagsComeInThatOrder() {
        let jira = TaskItem(source: .jira, title: "Logged", remote: remote(key: "PROJ-1", spent: 3 * 3600), tags: ["backend", "urgent"])
        XCTAssertEqual(TaskDetailSummary(task: jira, tracked: 0, now: now, calendar: calendar).extras,
                       ["Jira logged 3h", "#backend #urgent"])

        let gitlab = TaskItem(source: .gitlab, title: "Spent", remote: remote(key: "g/a#1", spent: 90 * 60))
        XCTAssertEqual(TaskDetailSummary(task: gitlab, tracked: 0, now: now, calendar: calendar).extras, ["GitLab spent 1h 30m"])
    }

    func testADueDateReadsLikeBrainsAndFlagsOverdue() {
        let soon = now.addingTimeInterval(2 * 3600)
        let due = TaskItem(title: "Due", tags: ["x"], scheduledAt: soon)
        let summary = TaskDetailSummary(task: due, tracked: 0, now: now, calendar: calendar)
        XCTAssertEqual(summary.extras.count, 2)
        XCTAssertTrue(summary.extras[0].hasPrefix("Due Today "), summary.extras[0])
        XCTAssertEqual(summary.extras[1], "#x")
        XCTAssertFalse(summary.isOverdue)

        let late = TaskItem(title: "Late", scheduledAt: now.addingTimeInterval(-3600))
        let lateSummary = TaskDetailSummary(task: late, tracked: 0, now: now, calendar: calendar)
        XCTAssertTrue(lateSummary.extras[0].hasPrefix("Overdue "), lateSummary.extras[0])
        XCTAssertTrue(lateSummary.isOverdue)
    }

    func testARemoteTaskNeverShowsADueDate() {
        // `scheduledAt` is never set on a remote task; if a file ever carried one, it stays unsaid.
        let task = TaskItem(source: .jira, title: "Remote", remote: remote(key: "PROJ-2"), scheduledAt: now)
        XCTAssertEqual(TaskDetailSummary(task: task, tracked: 0, now: now, calendar: calendar).extras, [])
    }
}
