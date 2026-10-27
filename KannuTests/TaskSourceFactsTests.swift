//
//  TaskSourceFactsTests.swift
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

/// What Kannu knows about each source, in one place (`TaskSourceFacts`), so a new source is a case
/// and its facts — David: GitHub, Linear, Todoist and Apple Reminders beside Jira and GitLab.
final class TaskSourceFactsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func task(_ source: TaskSource, key: String) -> TaskItem {
        TaskItem(source: source, title: "T", remote: RemoteTaskInfo(remoteID: "1", key: key, hostScope: "h", status: "",
                                                                    isDoneRemotely: false, lastSeenAt: now))
    }

    func testTheSourcesAndTheirStoredNames() {
        XCTAssertEqual(TaskSource.allCases, [.local, .jira, .gitlab, .github, .linear, .todoist, .appleReminders],
                       "the order Brain and the notch list them")
        XCTAssertEqual(TaskSource.allCases.map(\.rawValue),
                       ["local", "jira", "gitlab", "github", "linear", "todoist", "appleReminders"],
                       "stored in tasks.json: never renamed")
        XCTAssertEqual(TaskSource.remoteSources.first, .jira)
        XCTAssertFalse(TaskSource.remoteSources.contains(.local))
    }

    func testOnlyJiraAndGitLabTakeTime() {
        XCTAssertEqual(TaskSource.allCases.filter(\.logsTime), [.jira, .gitlab])
        XCTAssertEqual(TaskSource.allCases.filter(\.usesToken), [.jira, .gitlab, .github, .linear, .todoist],
                       "Reminders asks macOS instead")
    }

    func testTheProjectFollowsHowKeysRead() {
        XCTAssertEqual(TaskFacets.project(for: task(.linear, key: "ENG-42")), "ENG")
        XCTAssertEqual(TaskFacets.project(for: task(.github, key: "acme/app#7")), "acme/app")
        XCTAssertEqual(TaskFacets.project(for: task(.todoist, key: "Inbox")), "Inbox", "the key is the project")
        XCTAssertEqual(TaskFacets.project(for: task(.appleReminders, key: "Groceries")), "Groceries")
        XCTAssertEqual(TaskFacets.project(for: task(.appleReminders, key: "  ")), nil)
        XCTAssertNotEqual(TaskFacets.project(for: task(.todoist, key: "#none")), TaskFacets.noProject,
                          "a list named like Kannu's own key never passes for it")
    }

    func testShortKeysAndLabels() {
        XCTAssertEqual(TaskDetailSummary.shortKey(for: task(.github, key: "acme/app#7")), "app #7")
        XCTAssertEqual(TaskDetailSummary.shortKey(for: task(.github, key: "acme/app#7"), withProject: false), "#7")
        XCTAssertEqual(TaskDetailSummary.shortKey(for: task(.linear, key: "ENG-42")), "ENG-42")
        XCTAssertNil(TaskDetailSummary.shortKey(for: task(.todoist, key: "Inbox")), "a list is not a key")
        XCTAssertEqual(TaskSource.github.browseLabel, "Open in GitHub")
        XCTAssertNil(TaskSource.appleReminders.browseLabel, "a reminder has no page to open")
        XCTAssertEqual(TaskSourceFilter(.linear), .linear)
        XCTAssertEqual(TaskSourceFilter.todoist.source, .todoist)
        XCTAssertNil(TaskSourceFilter.all.source)
    }

    /// A task from a newer source round-trips through tasks.json, and only Jira and GitLab tasks
    /// make Time to log drafts.
    func testNewSourcesStoreAndNeverAskToLog() throws {
        var linear = task(.linear, key: "ENG-42")
        linear.segments = [WorkSegment(start: now, end: now.addingTimeInterval(3600), origin: .timer)]
        let data = try JSONEncoder().encode(linear)
        XCTAssertEqual(try JSONDecoder().decode(TaskItem.self, from: data).source, .linear)
        XCTAssertTrue(WorklogDrafts.folding(linear, into: []).drafts.isEmpty, "Linear takes no time")
        var jira = linear
        jira.source = .jira
        XCTAssertFalse(WorklogDrafts.folding(jira, into: []).drafts.isEmpty)
    }
}
