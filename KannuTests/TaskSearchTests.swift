//
//  TaskSearchTests.swift
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

/// The timer tab's task search: it finds a task by any word the user can see on it — title, key,
/// short key, tag, label — whatever the case or accents, and every word typed must be found. A
/// `#word` finds a whole tag or label, or its own text with the `#`; a row's chips put what it found first.
final class TaskSearchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func remote(key: String, kind: GitLabKind? = nil, iid: Int? = nil, labels: [String]? = nil) -> RemoteTaskInfo {
        RemoteTaskInfo(remoteID: key, key: key, hostScope: "https://example.test", status: "",
                       isDoneRemotely: false, remoteEstimateSeconds: nil, remoteSpentSeconds: nil,
                       gitlabProjectID: nil, gitlabIID: iid, lastSeenAt: now, gitlabKind: kind,
                       gitlabWebURL: nil, statusCategory: nil, labels: labels)
    }

    private lazy var local = TaskItem(title: "Write the Café release notes", tags: ["docs"])
    private lazy var jira = TaskItem(source: .jira, title: "Fix login", remote: remote(key: "PROJ-123"))
    private lazy var gitlab = TaskItem(source: .gitlab, title: "hc: convert EC2 checks",
                                       remote: remote(key: "discern/applications/ds-vendors#4264", kind: .issue, iid: 4264,
                                                      labels: ["workflow::sprint_backlog", "backend"]))

    func testAnEmptyQueryKeepsEveryTaskInOrder() {
        let tasks = [gitlab, local, jira]
        XCTAssertEqual(TaskSearch.filter(tasks, query: "").map(\.id), tasks.map(\.id))
        XCTAssertEqual(TaskSearch.filter(tasks, query: "   ").map(\.id), tasks.map(\.id), "spaces alone search nothing")
    }

    func testTheTitleMatchesWhateverTheCaseOrAccents() {
        XCTAssertTrue(TaskSearch.matches(local, query: "release"))
        XCTAssertTrue(TaskSearch.matches(local, query: "RELEASE"))
        XCTAssertTrue(TaskSearch.matches(local, query: "cafe"), "accents never matter")
        XCTAssertFalse(TaskSearch.matches(local, query: "deploy"))
    }

    func testTheKeyAndTheShortKeyMatch() {
        XCTAssertTrue(TaskSearch.matches(jira, query: "proj-123"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#4264"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "ds-vendors #4264"), "the short key the card shows")
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "discern"), "the full path key")
    }

    func testTagsAndLabelsMatchAScopedLabelByItsValueToo() {
        XCTAssertTrue(TaskSearch.matches(local, query: "docs"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "backend"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "sprint_backlog"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "workflow::"))
    }

    func testEveryWordTypedMustBeFoundSomewhere() {
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "convert backend"), "title and label")
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "convert frontend"))
    }

    func testTheFilterKeepsTheOrderGiven() {
        let tasks = [gitlab, local, jira]
        XCTAssertEqual(TaskSearch.filter(tasks, query: "e").map(\.id), [gitlab.id, local.id], "jira's words have no e")
        XCTAssertEqual(TaskSearch.filter(tasks, query: "login").map(\.id), [jira.id])
        XCTAssertEqual(TaskSearch.filter(tasks, query: "nothing like it"), [])
    }

    // MARK: - #word: a whole tag, or its text with the #

    /// `#work` finds a tag or label that is "work" as a whole (Stage 5): never the word inside
    /// "Homework", never the longer tag "workshop". Typed without `#`, the word is found anywhere,
    /// as before.
    func testAHashWordFindsAWholeTagNotAWordThatHoldsIt() {
        let homework = TaskItem(title: "Homework for Monday")
        let tagged = TaskItem(title: "Plan the week", tags: ["work"])
        let workshop = TaskItem(title: "Plan the offsite", tags: ["workshop"])
        let labelled = TaskItem(source: .gitlab, title: "Fix", remote: remote(key: "g/a#1", kind: .issue, iid: 1, labels: ["Work"]))
        let network = TaskItem(source: .gitlab, title: "Fix", remote: remote(key: "g/a#2", kind: .issue, iid: 2, labels: ["network"]))
        XCTAssertFalse(TaskSearch.matches(homework, query: "#work"), "not a word inside a title")
        XCTAssertTrue(TaskSearch.matches(tagged, query: "#work"))
        XCTAssertTrue(TaskSearch.matches(labelled, query: "#work"), "a label is a tag")
        XCTAssertFalse(TaskSearch.matches(workshop, query: "#work"), "a tag that begins with it is another tag")
        XCTAssertFalse(TaskSearch.matches(network, query: "#work"), "nor one that ends with it")
        XCTAssertTrue(TaskSearch.matches(workshop, query: "#workshop"))
        XCTAssertFalse(TaskSearch.matches(tagged, query: "#workshop"))
        for task in [homework, tagged, workshop, labelled, network] {
            XCTAssertTrue(TaskSearch.matches(task, query: "work"), "\(task.title): the plain word, anywhere")
        }
    }

    /// A scoped label is a tag by its value and by its full name, never by its scope alone.
    func testAHashWordFindsAScopedLabelByItsValueOrFullName() {
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#sprint_backlog"), "the value the card shows")
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#workflow::sprint_backlog"), "the full name")
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#backend"))
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "#workflow"), "the scope alone")
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "#backlog"), "part of the value")
    }

    /// `#4264` still finds its key: a `#word` is also found as its text, `#` and all, anywhere a
    /// plain word would be, so an issue number typed as it is written finds the issue.
    func testAHashWordStillFindsItsTextWithTheHash() {
        let bareKey = TaskItem(source: .gitlab, title: "Rotate keys", remote: remote(key: "#4264", kind: .issue, iid: 4264))
        let mentioned = TaskItem(title: "Follow up on #4264")
        let tagged = TaskItem(title: "Budget", tags: ["4264"])
        let numbered = TaskItem(title: "Review 4264")
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#4264"), "the path key and the short key")
        XCTAssertTrue(TaskSearch.matches(bareKey, query: "#4264"), "a key that is the number alone")
        XCTAssertTrue(TaskSearch.matches(mentioned, query: "#4264"), "in a title")
        XCTAssertTrue(TaskSearch.matches(tagged, query: "#4264"), "a tag named 4264, as a whole")
        XCTAssertFalse(TaskSearch.matches(numbered, query: "#4264"), "the number without its #")
        XCTAssertTrue(TaskSearch.matches(numbered, query: "4264"), "which the number typed alone finds")
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#426"), "the text anywhere, as a plain word's is")
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "#42640"))
    }

    /// Case and accents never matter to a `#word`, as a whole tag or as its text.
    func testAHashWordIgnoresCaseAndAccents() {
        let cafe = TaskItem(title: "Order beans", tags: ["Café"])
        XCTAssertTrue(TaskSearch.matches(cafe, query: "#cafe"))
        XCTAssertTrue(TaskSearch.matches(cafe, query: "#CAFÉ"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#BACKEND"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#Sprint_Backlog"))
        XCTAssertTrue(TaskSearch.matches(TaskItem(title: "Ship #Kannu notes"), query: "#kannu"), "its text too")
        XCTAssertFalse(TaskSearch.matches(local, query: "#cafe"), "a title's word is no tag, accents or not")
    }

    /// A `#` alone is no word yet: the list stays whole while a tag is being typed, as before.
    func testAHashAloneHidesNothing() {
        let tasks = [gitlab, local, jira]
        for query in ["#", "##", "# #", "  #  "] {
            XCTAssertEqual(TaskSearch.filter(tasks, query: query).map(\.id), tasks.map(\.id), "\(query)")
        }
        XCTAssertTrue(TaskSearch.matches(local, query: "release #"), "beside a word, only the word counts")
        XCTAssertFalse(TaskSearch.matches(jira, query: "release #"))
    }

    /// A `#word` is one of the words typed, each of which must be found; more `#`s read as one.
    func testAHashWordCombinesWithTheOtherWords() {
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "#backend convert"), "a label and a title word")
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "#backend frontend"))
        XCTAssertFalse(TaskSearch.matches(gitlab, query: "#backend #docs"), "both tags, or no match")
        XCTAssertTrue(TaskSearch.matches(local, query: "#docs cafe"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "##backend"))
        XCTAssertTrue(TaskSearch.matches(gitlab, query: "##4264"))
        XCTAssertFalse(TaskSearch.matches(TaskItem(title: "Homework"), query: "##work"))
    }

    // MARK: - Chips

    /// A row shows one chip and +N (David, 2026-11-01), so a tag the search finds moves first: the
    /// chip shown is the tag searched for. The rest keep the order `displayTags` gives.
    func testATagTheSearchFindsIsTheFirstChip() {
        let task = TaskItem(source: .gitlab, title: "Fix",
                            remote: remote(key: "g/a#1", kind: .issue, iid: 1, labels: ["workflow::sprint_backlog", "backend"]),
                            tags: ["today", "deep"])
        let shown = ["today", "deep", "sprint_backlog", "backend"]
        XCTAssertEqual(TaskFacets.displayTags(of: task), shown)
        for query in ["", "   ", "#", "convert", "#back"] {
            XCTAssertEqual(TaskSearch.chipTags(of: task, query: query), shown, "nothing found, nothing moves: \(query)")
        }
        XCTAssertEqual(TaskSearch.chipTags(of: task, query: "#backend"), ["backend", "today", "deep", "sprint_backlog"])
        XCTAssertEqual(TaskSearch.chipTags(of: task, query: "#BACKEND fix"), ["backend", "today", "deep", "sprint_backlog"],
                       "ignoring case, beside a title word")
        XCTAssertEqual(TaskSearch.chipTags(of: task, query: "#workflow::sprint_backlog"),
                       ["sprint_backlog", "today", "deep", "backend"], "a scoped label's chip, by its full name")
        XCTAssertEqual(TaskSearch.chipTags(of: task, query: "#backend #deep"), ["deep", "backend", "today", "sprint_backlog"],
                       "those found keep their order")
        XCTAssertEqual(TaskSearch.chipTags(of: task, query: "back"), ["sprint_backlog", "backend", "today", "deep"],
                       "a plain word anywhere in a tag, as the search finds it")
        XCTAssertEqual(TaskSearch.chipTags(of: TaskItem(title: "Order beans", tags: ["tea", "Café"]), query: "#cafe"),
                       ["Café", "tea"], "accents ignored")
        XCTAssertEqual(TaskSearch.chipTags(of: TaskItem(title: "Bare"), query: "#work"), [])
    }
}
