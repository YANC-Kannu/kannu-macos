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
/// a layout and the words are tested. A task has no description or body (`TaskItem`): its detail
/// is where it comes from, where it stands, and its time.
///
/// Wording follows Brain › Tasks' row caption (`TasksSettings.progressText`) so the same task
/// reads the same everywhere: "42m of 2h", "10m over", "Jira logged 3h", "Due Today 15:00".
struct TaskDetailSummary: Equatable {
    /// "PROJ-123" for a Jira or GitLab task; nil for a local one.
    let key: String?
    let title: String
    /// Where the task comes from and stands: "Jira · PROJ · In Progress",
    /// "GitLab · group/app · Merge request · Open", or "Local".
    let identity: String
    /// Time against the estimate: "42m of 2h", "42m tracked", "No estimate".
    let time: String
    /// "10m over" once a minute or more past the estimate; the view shows it in orange.
    let overtime: String?
    /// The rest, in order: "Jira logged 3h" / "GitLab spent 3h", the due date, "#tag #tag".
    let extras: [String]
    /// True when the due date has passed; the view shows that extra in orange.
    let isOverdue: Bool
    /// Only a local task can be deleted: a remote one would come back on the next sync.
    let canDelete: Bool
    /// "Open in Jira" / "Open in GitLab"; nil for a local task.
    let browseLabel: String?

    init(task: TaskItem, tracked: Int, now: Date, calendar: Calendar = .current) {
        key = task.remote?.key
        title = task.title

        var identityParts: [String] = []
        switch task.source {
        case .local: identityParts.append(String(localized: "Local"))
        case .jira: identityParts.append(String(localized: "Jira"))
        case .gitlab: identityParts.append(String(localized: "GitLab"))
        }
        if let project = TaskFacets.project(for: task) {
            identityParts.append(TaskFacets.projectName(project))
        }
        if task.source == .gitlab, let kind = task.remote?.gitlabKind {
            identityParts.append(kind == .mergeRequest ? String(localized: "Merge request") : String(localized: "Issue"))
        }
        if let status = TaskFacets.statusName(for: task) {
            identityParts.append(status)
        }
        identity = identityParts.joined(separator: " · ")

        let progress = TaskTimeMath.progress(tracked: tracked, estimate: task.effectiveEstimateSeconds)
        time = progress.text
        overtime = progress.over.map { String(localized: "\(WorkDuration.format($0)) over") }

        var extras: [String] = []
        if let spent = task.remote?.remoteSpentSeconds, spent > 0 {
            switch task.source {
            case .jira: extras.append(String(localized: "Jira logged \(WorkDuration.format(spent))"))
            case .gitlab: extras.append(String(localized: "GitLab spent \(WorkDuration.format(spent))"))
            case .local: break
            }
        }
        var overdue = false
        if task.source == .local, let scheduled = task.scheduledAt {
            let when = TaskReminderPlan.when(scheduled, now: now, calendar: calendar)
            overdue = when == .overdue
            extras.append(Self.dueText(scheduled, when: when))
        }
        if !task.tags.isEmpty {
            extras.append(task.tags.map { "#\($0)" }.joined(separator: " "))
        }
        self.extras = extras
        isOverdue = overdue

        canDelete = task.source == .local
        switch task.source {
        case .local: browseLabel = nil
        case .jira: browseLabel = String(localized: "Open in Jira")
        case .gitlab: browseLabel = String(localized: "Open in GitLab")
        }
    }

    /// "Due Today 15:00", "Due Tomorrow 09:30", "Overdue Mon 10:00", or "Due Thu 9 Oct, 15:00" —
    /// the words Brain's row uses (`TasksSettings.scheduleText`).
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
}
