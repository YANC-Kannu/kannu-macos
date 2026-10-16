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

import Foundation

/// Everything the timer tab's expanded task card says about one task, as text, so the view stays
/// a layout and the words are tested. It reads like the ticket page: the title first, a short key,
/// where the task stands, its labels, then the standard facts (due date, milestone, weight,
/// assignee, parent, priority, type) and its time.
///
/// Wording follows Brain › Tasks' row caption (`TasksSettings.progressText`) so the same task
/// reads the same everywhere: "42m of 2h", "10m over", "Jira logged 3h", "Due Today 15:00".
struct TaskDetailSummary: Equatable {
    struct Status: Equatable {
        /// "To do", "In Progress", "Open", "Review requested" — the source's own word, or the
        /// facet's for a local task.
        let name: String
        let phase: TaskStatusFacet
    }

    /// One fact on the facts line; `isAlert` reads in orange (an overdue date).
    struct Fact: Equatable {
        let text: String
        var isAlert = false
    }

    /// The issue's title, never prefixed by its key: a GitLab path key would eat the lines.
    let title: String
    /// "PROJ-123", "ds-vendors #4264", "ds-vendors !12"; nil for a local task.
    let shortKey: String?
    let status: Status
    /// The source's labels, then the user's own tags as "#tag".
    let labels: [String]
    /// In the order they matter on a 240 pt card: due, milestone, weight, assignee, parent,
    /// priority, type, then the time the server already has logged.
    let facts: [Fact]
    /// Time against the estimate: "42m of 2h", "42m tracked", "No estimate".
    let time: String
    /// "10m over" once a minute or more past the estimate; the view shows it in orange.
    let overtime: String?
    /// Only a local task can be deleted: a remote one would come back on the next sync.
    let canDelete: Bool
    /// "Open in Jira" / "Open in GitLab"; nil for a local task.
    let browseLabel: String?

    /// `selfNames`: the connected accounts' display names and usernames, so an assignee that is
    /// the user reads as "you".
    init(task: TaskItem, tracked: Int, now: Date, selfNames: Set<String> = [], calendar: Calendar = .current) {
        title = task.title
        shortKey = Self.shortKey(for: task)

        let phase = TaskFacets.status(for: task)
        let phaseName = phase == .inProgress ? TaskStatusFilter.inProgress.localizedName : TaskStatusFilter.toDo.localizedName
        status = Status(name: TaskFacets.statusName(for: task) ?? phaseName, phase: phase)

        labels = (task.remote?.labels ?? []) + task.tags.map { "#\($0)" }

        let progress = TaskTimeMath.progress(tracked: tracked, estimate: task.effectiveEstimateSeconds)
        time = progress.text
        overtime = progress.over.map { String(localized: "\(WorkDuration.format($0)) over") }

        var facts: [Fact] = []
        if task.source == .local, let scheduled = task.scheduledAt {
            let when = TaskReminderPlan.when(scheduled, now: now, calendar: calendar)
            facts.append(Fact(text: Self.dueText(scheduled, when: when), isAlert: when == .overdue))
        } else if let due = task.remote?.dueDate {
            let day = Self.dueDayText(due, now: now, calendar: calendar)
            facts.append(Fact(text: day.text, isAlert: day.isOverdue))
        }
        if let milestone = task.remote?.milestone { facts.append(Fact(text: milestone)) }
        if let weight = task.remote?.weight { facts.append(Fact(text: String(localized: "Weight \(weight)"))) }
        if let assignee = task.remote?.assignee {
            let isSelf = selfNames.contains { $0.caseInsensitiveCompare(assignee) == .orderedSame }
            facts.append(Fact(text: isSelf ? String(localized: "you") : assignee))
        }
        if let parent = task.remote?.parentTitle { facts.append(Fact(text: parent)) }
        if let priority = task.remote?.priority { facts.append(Fact(text: priority)) }
        if let type = task.remote?.issueType { facts.append(Fact(text: type)) }
        if let spent = task.remote?.remoteSpentSeconds, spent > 0 {
            switch task.source {
            case .jira: facts.append(Fact(text: String(localized: "Jira logged \(WorkDuration.format(spent))")))
            case .gitlab: facts.append(Fact(text: String(localized: "GitLab spent \(WorkDuration.format(spent))")))
            case .local: break
            }
        }
        self.facts = facts

        canDelete = task.source == .local
        switch task.source {
        case .local: browseLabel = nil
        case .jira: browseLabel = String(localized: "Open in Jira")
        case .gitlab: browseLabel = String(localized: "Open in GitLab")
        }
    }

    /// The chips that fit a character budget, in order, and how many did not. The first always
    /// shows, however long: a row with nothing on it says less than a truncated chip.
    func chips(fitting characters: Int) -> (shown: [String], hidden: Int) {
        var shown: [String] = []
        var used = 0
        for label in labels {
            let cost = label.count + 2
            if !shown.isEmpty, used + cost > characters { break }
            shown.append(label)
            used += cost
        }
        return (shown, labels.count - shown.count)
    }

    /// "PROJ-123" as Jira writes it; for GitLab, the project's last path component and the number,
    /// "ds-vendors #4264" / "ds-vendors !12" — the full `group/sub/project#4264` key is what used to
    /// eat the card. A project known only by its id reads "Project 42 #7". Nil for a local task.
    static func shortKey(for task: TaskItem) -> String? {
        guard let remote = task.remote else { return nil }
        switch task.source {
        case .local:
            return nil
        case .jira:
            return remote.key
        case .gitlab:
            guard let iid = remote.gitlabIID else { return remote.key }
            let mark = remote.gitlabKind == .mergeRequest ? "!" : "#"
            guard let project = TaskFacets.project(for: task) else { return mark + String(iid) }
            let name = project.hasPrefix(TaskFacets.projectIDPrefix)
                ? TaskFacets.projectName(project)
                : String(project.split(separator: "/").last ?? Substring(project))
            return "\(name) \(mark)\(iid)"
        }
    }

    /// "Due Today 15:00", "Due Tomorrow 09:30", "Overdue Mon 10:00", or "Due Thu 9 Oct, 15:00" —
    /// a local task's reminder, in the words Brain's row uses (`TasksSettings.scheduleText`).
    static func dueText(_ date: Date, when: TaskReminderPlan.When) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        switch when {
        case .today:
            return String(localized: "Due Today \(time)")
        case .tomorrow:
            return String(localized: "Due Tomorrow \(time)")
        case .overdue:
            return String(localized: "Overdue \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
        case .later:
            return String(localized: "Due \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))")
        }
    }

    /// A server's date-only due date: "Due today", "Due 20 Oct", or "Overdue 14 Oct" once the day
    /// has passed — a due date has no time, so it is overdue from the next day on.
    static func dueDayText(_ date: Date, now: Date, calendar: Calendar) -> (text: String, isOverdue: Bool) {
        let day = date.formatted(dayStyle(calendar))
        if calendar.isDate(date, inSameDayAs: now) {
            return (String(localized: "Due today"), false)
        }
        if date < calendar.startOfDay(for: now) {
            return (String(localized: "Overdue \(day)"), true)
        }
        return (String(localized: "Due \(day)"), false)
    }

    /// "20 Oct" in the user's locale, in the calendar (and so the time zone) the date was made in.
    static func dayStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
            .day()
            .month(.abbreviated)
    }
}
