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

/// What the timer tab's task form holds while the user types (`TimerTaskForm`): a new task, or an
/// edit of one. Nothing is saved until Add or Save; then `edits(to:)` says what changed, so an
/// edit touches only what the user changed.
///
/// A Jira or GitLab task's title and reminder are not Kannu's to change: the title is the server's
/// and the next sync would put it back, and reminders are for local tasks
/// (`TasksManager.setSchedule`). Its estimate and tags are Kannu's own and can be edited.
///
/// Pure, in the logic target.
struct TaskFormDraft: Equatable {
    /// The estimate menu's choices, Brain's add row's too: 15m, 30m, 1h, 2h, 4h, 8h.
    static let estimateChoices = [15, 30, 60, 120, 240, 480].map { $0 * 60 }

    enum Edit: Equatable {
        case title(String)
        case estimate(Int?)
        case tags([String])
        case schedule(Date?)
    }

    /// The task being edited; nil for a new one.
    let editing: UUID?
    let source: TaskSource
    /// The source's own estimate, shown when Kannu has none of its own.
    let remoteEstimate: Int?
    var title: String
    var estimateSeconds: Int?
    /// Tags as typed, comma separated: "writing, #urgent".
    var tagsText: String
    var reminder: Date?

    /// A new local task.
    init() {
        editing = nil
        source = .local
        remoteEstimate = nil
        title = ""
        estimateSeconds = nil
        tagsText = ""
        reminder = nil
    }

    init(editing task: TaskItem) {
        editing = task.id
        source = task.source
        remoteEstimate = task.remote?.remoteEstimateSeconds
        title = task.title
        estimateSeconds = task.localEstimateSeconds
        tagsText = task.tags.joined(separator: ", ")
        reminder = task.scheduledAt
    }

    var isNew: Bool { editing == nil }
    var canEditTitle: Bool { source == .local }
    var canSchedule: Bool { source == .local }

    var tags: [String] { TaskItem.parsedTags(tagsText) }

    /// A new task or a local one needs a title; a remote one keeps its server's.
    var canSave: Bool { !canEditTitle || TaskItem.cleanedTitle(title) != nil }

    /// What saving changes on `task`, in the order the manager applies it: only what differs.
    func edits(to task: TaskItem) -> [Edit] {
        var edits: [Edit] = []
        if canEditTitle, let cleaned = TaskItem.cleanedTitle(title), cleaned != task.title {
            edits.append(.title(cleaned))
        }
        let estimate = estimateSeconds.flatMap { $0 > 0 ? $0 : nil }
        if estimate != task.localEstimateSeconds { edits.append(.estimate(estimate)) }
        if tags != task.tags { edits.append(.tags(tags)) }
        if canSchedule, reminder != task.scheduledAt { edits.append(.schedule(reminder)) }
        return edits
    }

    /// "No estimate", "2h", or the source's own "2h from Jira" while Kannu has none.
    var estimateLabel: String {
        if let estimateSeconds, estimateSeconds > 0 { return WorkDuration.format(estimateSeconds) }
        if let remoteEstimate, remoteEstimate > 0 {
            switch source {
            case .jira: return String(localized: "\(WorkDuration.format(remoteEstimate)) from Jira")
            case .gitlab: return String(localized: "\(WorkDuration.format(remoteEstimate)) from GitLab")
            case .local: break
            }
        }
        return String(localized: "No estimate")
    }

    /// The menu's choices with the current estimate among them, in order, when it is none of them
    /// (one set in Brain's Custom sheet), so the menu can show it as chosen.
    var estimateMenuChoices: [Int] {
        guard let estimateSeconds, estimateSeconds > 0, !Self.estimateChoices.contains(estimateSeconds) else {
            return Self.estimateChoices
        }
        return (Self.estimateChoices + [estimateSeconds]).sorted()
    }

    /// Where a new reminder starts: the next whole hour.
    static func defaultReminder(now: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
    }
}
