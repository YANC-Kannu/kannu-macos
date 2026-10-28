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

/// David, 2026-10-28: "# would create a tag and @noon would mean reminder at 12:00 pm".
final class TaskQuickAddTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 28 October 2026 at `hour`:`minute`, UTC.
    private func wednesday(_ hour: Int, _ minute: Int = 0) -> Date {
        date(day: 28, hour, minute)
    }

    private func date(month: Int = 10, day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ text: String, at now: Date) -> TaskQuickAdd.Parsed {
        TaskQuickAdd.parse(text, now: now, calendar: calendar)
    }

    func testDavidsExample() {
        let parsed = parse("Write release notes #kannu @noon", at: wednesday(10, 30))
        XCTAssertEqual(parsed.title, "Write release notes")
        XCTAssertEqual(parsed.tags, ["kannu"])
        XCTAssertEqual(parsed.reminder, wednesday(12))
    }

    func testATimeThatHasPassedRollsToTomorrow() {
        XCTAssertEqual(parse("Lunch @noon", at: wednesday(13)).reminder, date(day: 29, 12))
        XCTAssertEqual(parse("Lunch @noon", at: wednesday(12)).reminder, date(day: 29, 12), "noon itself has passed")
        XCTAssertEqual(parse("Stand-up @morning", at: wednesday(10, 30)).reminder, date(day: 29, 9))
    }

    func testTheTimesOfDay() {
        let now = wednesday(8)
        XCTAssertEqual(parse("a @morning", at: now).reminder, wednesday(9))
        XCTAssertEqual(parse("a @evening", at: now).reminder, wednesday(18))
        XCTAssertEqual(parse("a @tonight", at: now).reminder, wednesday(20))
        XCTAssertEqual(parse("a @tonight", at: wednesday(21)).reminder, date(day: 29, 20))
    }

    func testTheDays() {
        let now = wednesday(10, 30)
        XCTAssertEqual(parse("a @today", at: now).reminder, wednesday(11), "the next whole hour, as Add a reminder picks")
        XCTAssertEqual(parse("a @tomorrow", at: now).reminder, date(day: 29, 9))
        XCTAssertEqual(parse("a @tmrw", at: now).reminder, date(day: 29, 9))
        XCTAssertEqual(parse("a @fri", at: now).reminder, date(day: 30, 9))
        XCTAssertEqual(parse("a @Friday", at: now).reminder, date(day: 30, 9))
        XCTAssertEqual(parse("a @mon", at: now).reminder, date(month: 11, day: 2, 9))
        XCTAssertEqual(parse("a @wed", at: now).reminder, date(month: 11, day: 4, 9), "today's 9:00 has passed: next week")
        XCTAssertEqual(parse("a @wed", at: wednesday(8)).reminder, wednesday(9), "today, while 9:00 is still ahead")
    }

    func testTodayWithATimeStaysToday() {
        let now = wednesday(10, 30)
        XCTAssertEqual(parse("a @today @9am", at: now).reminder, wednesday(9), "the day was said: past, and overdue")
        XCTAssertEqual(parse("a @today @5pm", at: now).reminder, wednesday(17))
        XCTAssertEqual(parse("a @9am", at: now).reminder, date(day: 29, 9), "no day said: it rolls")
    }

    func testTheTokenWordsAreKeptAsTyped() {
        let parsed = parse("Deep work #Kannu @noon, later", at: wednesday(8))
        XCTAssertEqual(parsed.tokenText, "#Kannu @noon,")
        XCTAssertEqual(parse("Deep work", at: wednesday(8)).tokenText, "")
    }

    func testADayAndATimeCombine() {
        let now = wednesday(10, 30)
        XCTAssertEqual(parse("Ship it @tomorrow @5pm", at: now).reminder, date(day: 29, 17))
        XCTAssertEqual(parse("Ship it @5pm @tomorrow", at: now).reminder, date(day: 29, 17), "in either order")
        XCTAssertEqual(parse("Review @wed @5pm", at: now).reminder, wednesday(17))
        XCTAssertEqual(parse("Review @fri @noon", at: now).reminder, date(day: 30, 12))
        XCTAssertEqual(parse("a @today @tomorrow", at: now).reminder, date(day: 29, 9), "the later day word wins")
    }

    func testClockTimes() {
        let now = wednesday(8)
        XCTAssertEqual(parse("a @5pm", at: now).reminder, wednesday(17))
        XCTAssertEqual(parse("a @5:30pm", at: now).reminder, wednesday(17, 30))
        XCTAssertEqual(parse("a @9am", at: now).reminder, wednesday(9))
        XCTAssertEqual(parse("a @12pm", at: now).reminder, wednesday(12))
        XCTAssertEqual(parse("a @12am", at: now).reminder, date(day: 29, 0), "midnight, which has passed today")
        XCTAssertEqual(parse("a @17:30", at: now).reminder, wednesday(17, 30))
        XCTAssertEqual(parse("a @09:05", at: now).reminder, wednesday(9, 5))
        XCTAssertEqual(parse("a @NOON", at: now).reminder, wednesday(12), "case does not matter")
    }

    func testWhatIsNotATokenStaysInTheTitle() {
        let now = wednesday(8)
        for text in ["Fix #123", "Mail a@b.com", "Call @5", "Call @17", "Ask @someone", "Price # tag", "Meet @ noon",
                     "a @13pm", "a @5:7pm", "a @24:00", "a @5:60pm", "a #-tag"] {
            let parsed = parse(text, at: now)
            XCTAssertEqual(parsed.title, text, text)
            XCTAssertFalse(parsed.hasTokens, text)
        }
    }

    func testPunctuationAfterATokenIsNotPartOfIt() {
        let parsed = parse("Call Sam @noon, then #follow-up.", at: wednesday(8))
        XCTAssertEqual(parsed.title, "Call Sam then")
        XCTAssertEqual(parsed.tags, ["follow-up"])
        XCTAssertEqual(parsed.reminder, wednesday(12))
    }

    func testTagsAreCleanedAsTheTagFieldCleansThem() {
        let parsed = parse("Plan #Work #work #deep_work #2026plan", at: wednesday(8))
        XCTAssertEqual(parsed.tags, ["Work", "deep_work"], "same tag once, case ignored; a tag starts with a letter")
        XCTAssertEqual(parsed.title, "Plan #2026plan")
    }

    func testOnlyTokensLeaveNoTitle() {
        let parsed = parse("#work @noon", at: wednesday(8))
        XCTAssertEqual(parsed.title, "")
        XCTAssertTrue(parsed.hasTokens)
        XCTAssertNil(TaskItem.cleanedTitle(parsed.title), "nothing to make a task of")
    }

    func testNoTokensChangesNothing() {
        let parsed = parse("  Deep   work  ", at: wednesday(8))
        XCTAssertEqual(parsed.title, "Deep work")
        XCTAssertEqual(parsed.tags, [])
        XCTAssertNil(parsed.reminder)
        XCTAssertFalse(parsed.hasTokens)
    }

    func testTheTitleNeedsNoClock() {
        XCTAssertEqual(TaskQuickAdd.title(of: "Write release notes #kannu @tomorrow @5pm"), "Write release notes")
    }

    // MARK: - Where the name is read

    func testTheBarRoutesByTheNameAlone() {
        XCTAssertEqual(TimerTypedStart.route(tasksAvailable: true, typed: "#work @noon", pick: nil), .plain,
                       "only tokens: no name to make a task of")
        XCTAssertEqual(TimerTypedStart.route(tasksAvailable: true, typed: "Deep work #work", pick: nil), .typed(reuse: true))
    }

    func testTheTypedSearchLooksForTheNameAlone() {
        let tasks = [TaskItem(title: "Write release notes"), TaskItem(title: "Other")]
        XCTAssertEqual(TaskSearch.suggestions(tasks, typed: "Write rel #kannu @noon").map(\.title), ["Write release notes"])
    }

    func testTheNewRowIsNamedAsTheTaskWillBe() {
        let task = TaskItem(title: "Deep work")
        XCTAssertEqual(TaskSuggestionState.rows(for: [task], typed: "Deep #kannu @noon").last, .newTask("Deep"))
        XCTAssertEqual(TaskSuggestionState.rows(for: [task], typed: "#kannu @noon"), [], "no name, no New row")
    }

    // MARK: - The task form

    func testOnlyTokensCannotBeSaved() {
        var draft = TaskFormDraft()
        draft.title = "#work @noon"
        XCTAssertFalse(draft.canSave, "Add would make nothing")
        draft.title = "Plan #work @noon"
        XCTAssertTrue(draft.canSave)
    }

    func testTheBarAndTheFormAreTheSameNameWhateverTheirWords() {
        var draft = TaskFormDraft()
        draft.title = "Deep work #a"
        XCTAssertTrue(draft.isTitled("Deep work @noon"))
        XCTAssertFalse(draft.isTitled("Deep"))
    }

    func testANewTasksWordsFoldIntoTheForm() {
        var draft = TaskFormDraft()
        draft.title = "Write release notes #kannu @noon"
        draft.tagsText = "docs"
        let folded = draft.foldingQuickAdd(now: wednesday(10, 30), calendar: calendar)
        XCTAssertEqual(folded.title, "Write release notes")
        XCTAssertEqual(folded.tags, ["docs", "kannu"], "the form's tags, then the typed ones")
        XCTAssertEqual(folded.reminder, wednesday(12))
    }

    func testATypedTimeWinsOverTheFormsReminder() {
        var draft = TaskFormDraft()
        draft.title = "Call @5pm"
        draft.reminder = wednesday(11)
        XCTAssertEqual(draft.foldingQuickAdd(now: wednesday(10), calendar: calendar).reminder, wednesday(17))
        draft.title = "Call"
        XCTAssertEqual(draft.foldingQuickAdd(now: wednesday(10), calendar: calendar).reminder, wednesday(11),
                       "no word: the form's own")
    }

    func testAnEditsWordsFoldToo() {
        var draft = TaskFormDraft(editing: TaskItem(title: "Plan"))
        draft.title = "Plan #work"
        let folded = draft.foldingQuickAdd(now: wednesday(8), calendar: calendar)
        XCTAssertEqual(folded.title, "Plan")
        XCTAssertEqual(folded.tags, ["work"])
        XCTAssertEqual(folded.edits(to: TaskItem(title: "Plan")), [.tags(["work"])], "the title stays; the tag is added")
    }

    func testARemoteTasksTitleIsNeverRead() {
        let remote = TaskItem(source: .gitlab, title: "Ticket #work")
        let draft = TaskFormDraft(editing: remote)
        XCTAssertEqual(draft.foldingQuickAdd(now: wednesday(8), calendar: calendar), draft, "its server's title, untouched")
    }

    // MARK: - Search

    func testSearchingAHashTagFindsTheTag() {
        var tagged = TaskItem(title: "Plan the week")
        tagged.tags = ["work"]
        XCTAssertTrue(TaskSearch.matches(tagged, query: "#work"))
        XCTAssertFalse(TaskSearch.matches(TaskItem(title: "Plan the week"), query: "#work"))
    }
}
