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

/// The words on the timer tab's expanded task card. The title is the issue's own and is never
/// prefixed by a key (a GitLab path key once ate the whole card); the key is short; the facts
/// come in the order they matter on 240 pt; "you" is the connected account.
final class TaskDetailSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09 08:53:20 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func remote(key: String, status: String = "", kind: GitLabKind? = nil, iid: Int? = nil,
                        spent: Int? = nil, estimate: Int? = nil, category: String? = nil,
                        labels: [String]? = nil) -> RemoteTaskInfo {
        RemoteTaskInfo(remoteID: key, key: key, hostScope: "https://example.test", status: status,
                       isDoneRemotely: false, remoteEstimateSeconds: estimate, remoteSpentSeconds: spent,
                       gitlabProjectID: nil, gitlabIID: iid, lastSeenAt: now, gitlabKind: kind,
                       gitlabWebURL: nil, statusCategory: category, labels: labels)
    }

    private func summary(_ task: TaskItem, tracked: Int = 0, selfNames: Set<String> = []) -> TaskDetailSummary {
        TaskDetailSummary(task: task, tracked: tracked, now: now, selfNames: selfNames, calendar: calendar)
    }

    /// "20 Oct" as the card formats it, so the assertions hold in every locale.
    private func day(_ ymd: String) -> String {
        RemoteTaskInfo.dayDate(ymd, calendar: calendar)!.formatted(TaskDetailSummary.dayStyle(calendar))
    }

    // MARK: - Title and key

    func testTheTitleIsTheIssuesOwnAndTheGitLabKeyIsShort() {
        let task = TaskItem(source: .gitlab, title: "hc: convert AWS EC2 instance checks to datapoints",
                            remote: remote(key: "discern_security/applications/ds-vendors#4264", status: "opened", kind: .issue, iid: 4264))
        let card = summary(task)
        XCTAssertEqual(card.title, "hc: convert AWS EC2 instance checks to datapoints")
        XCTAssertEqual(card.shortKey, "ds-vendors #4264", "the project's last path component and the number")
    }

    func testAMergeRequestKeyUsesItsMark() {
        let task = TaskItem(source: .gitlab, title: "Add tests",
                            remote: remote(key: "group/app!12", status: "opened", kind: .mergeRequest, iid: 12))
        XCTAssertEqual(summary(task).shortKey, "app !12")
    }

    func testAnIDOnlyProjectAndAJiraKeyAndALocalTask() {
        var byID = TaskItem(source: .gitlab, title: "Known by id", remote: remote(key: "#7", kind: .issue, iid: 7))
        byID.remote?.gitlabProjectID = 42
        XCTAssertEqual(summary(byID).shortKey, "Project 42 #7")
        let jira = TaskItem(source: .jira, title: "Fix login", remote: remote(key: "PROJ-123"))
        XCTAssertEqual(summary(jira).shortKey, "PROJ-123")
        XCTAssertNil(summary(TaskItem(title: "Mine")).shortKey)
    }

    // MARK: - Status and labels

    func testStatusReadsTheSourcesWordWithTheFacetsPhase() {
        let jira = TaskItem(source: .jira, title: "J", remote: remote(key: "P-1", status: "In Review", category: "indeterminate"))
        XCTAssertEqual(summary(jira).status, .init(name: "In Review", phase: .inProgress))
        let gitlab = TaskItem(source: .gitlab, title: "G", remote: remote(key: "g/a#1", status: "opened", kind: .issue, iid: 1))
        XCTAssertEqual(summary(gitlab).status, .init(name: "Open", phase: .toDo))
        let fresh = TaskItem(title: "Local")
        XCTAssertEqual(summary(fresh).status, .init(name: "To Do", phase: .toDo))
        var started = TaskItem(title: "Started")
        started.segments = [WorkSegment(start: now, end: now.addingTimeInterval(60), origin: .timer)]
        XCTAssertEqual(summary(started).status, .init(name: "In Progress", phase: .inProgress))
    }

    func testLabelsComeBeforeTagsAndChipsFitABudget() {
        let task = TaskItem(source: .gitlab, title: "L", remote: remote(key: "g/a#1", kind: .issue, iid: 1,
                                                                           labels: ["workflow::sprint_backlog", "backend", "needs-review"]),
                            tags: ["urgent"])
        let labelled = summary(task)
        XCTAssertEqual(labelled.labels, ["workflow::sprint_backlog", "backend", "needs-review", "#urgent"])
        let fitted = labelled.chips(fitting: 36)
        XCTAssertEqual(fitted.shown, ["workflow::sprint_backlog", "backend"], "24+2 then 7+2 fit in 36; the next (12+2) does not")
        XCTAssertEqual(fitted.hidden, 2)
        let tight = labelled.chips(fitting: 5)
        XCTAssertEqual(tight.shown, ["workflow::sprint_backlog"], "the first chip always shows")
        XCTAssertEqual(tight.hidden, 3)
        XCTAssertEqual(summary(TaskItem(title: "Bare")).chips(fitting: 30).shown, [])
    }

    // MARK: - Facts

    func testTheFactsComeInTheOrderTheyMatter() {
        var info = remote(key: "PROJ-9", status: "To Do", spent: 3 * 3600)
        info.dueDate = RemoteTaskInfo.dayDate("2025-10-20", calendar: calendar)
        info.milestone = "Sprint 42"
        info.weight = 8
        info.assignee = "Dana Example"
        info.parentTitle = "Login epic"
        info.priority = "High"
        info.issueType = "Bug"
        let task = TaskItem(source: .jira, title: "All of it", remote: info)
        XCTAssertEqual(summary(task).facts.map(\.text),
                       ["Due \(day("2025-10-20"))", "Sprint 42", "Weight 8", "Dana Example", "Login epic", "High", "Bug", "Jira logged 3h"])
        XCTAssertEqual(summary(task, selfNames: ["dana example"]).facts[3].text, "you", "the connected account, case-insensitively")
    }

    func testARemoteDueDateIsOverdueFromTheNextDay() {
        var info = remote(key: "g/a#1", kind: .issue, iid: 1)
        info.dueDate = RemoteTaskInfo.dayDate("2025-10-09", calendar: calendar)   // today
        let today = summary(TaskItem(source: .gitlab, title: "T", remote: info))
        XCTAssertEqual(today.facts.first, .init(text: "Due today", isAlert: false))

        info.dueDate = RemoteTaskInfo.dayDate("2025-10-08", calendar: calendar)
        let yesterday = summary(TaskItem(source: .gitlab, title: "Y", remote: info))
        XCTAssertEqual(yesterday.facts.first, .init(text: "Overdue \(day("2025-10-08"))", isAlert: true))
    }

    func testALocalScheduleKeepsBrainsWords() {
        let due = TaskItem(title: "Due", scheduledAt: now.addingTimeInterval(2 * 3600))
        XCTAssertTrue(summary(due).facts[0].text.hasPrefix("Due Today "), summary(due).facts[0].text)
        XCTAssertFalse(summary(due).facts[0].isAlert)
        let late = TaskItem(title: "Late", scheduledAt: now.addingTimeInterval(-3600))
        XCTAssertTrue(summary(late).facts[0].text.hasPrefix("Overdue "), summary(late).facts[0].text)
        XCTAssertTrue(summary(late).facts[0].isAlert)
    }

    // MARK: - Time, delete, open

    func testTimeOvertimeAndTheSourceRules() {
        let local = TaskItem(title: "Over", localEstimateSeconds: 30 * 60)
        let over = summary(local, tracked: 40 * 60)
        XCTAssertEqual(over.time, "40m of 30m")
        XCTAssertEqual(over.overtime, "10m over")
        XCTAssertTrue(over.canDelete)
        XCTAssertNil(over.browseLabel)
        XCTAssertEqual(summary(TaskItem(title: "Fresh")).time, "No estimate")

        let jira = summary(TaskItem(source: .jira, title: "J", remote: remote(key: "P-1")))
        XCTAssertFalse(jira.canDelete, "a remote task would come back on the next sync")
        XCTAssertEqual(jira.browseLabel, "Open in Jira")
        let gitlab = summary(TaskItem(source: .gitlab, title: "G", remote: remote(key: "g/a#1", kind: .issue, iid: 1)))
        XCTAssertEqual(gitlab.browseLabel, "Open in GitLab")
    }
}
