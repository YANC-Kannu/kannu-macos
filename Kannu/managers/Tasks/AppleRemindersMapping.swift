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

/// One reminder as EventKit gave it, already reduced to plain values off the EventKit thread
/// (`AppleRemindersSource`), so the mapping below is tested without EventKit or a permission.
struct ReminderSnapshot: Equatable {
    /// `EKReminder.calendarItemIdentifier`: stable for the reminder on this Mac.
    var id: String
    var title: String
    /// The list it is in ("Groceries"): its project in Kannu.
    var listTitle: String
    var dueDate: Date?
    /// EventKit's 0 (none), 1–4 (high), 5 (medium), 6–9 (low).
    var priority: Int
    var lastModified: Date?
    var isCompleted: Bool
}

/// Apple Reminders has no token: the "credential" is macOS's permission, granted once on Connect.
/// Kept nowhere: its store asks macOS each time (`AppleRemindersAccessKeeper`).
struct AppleRemindersAccess: Equatable {}

/// Apple Reminders as a task source, the pure part: which reminders a sync keeps and what each says.
/// Read-only: Kannu never changes a reminder.
enum AppleReminders {
    /// What a reminder task's `hostScope` is: every reminder comes from this Mac's Reminders.
    static let scope = "reminders"
    /// At most this many a sync keeps, soonest due first: a list of a thousand old reminders is not a
    /// task list, and the cap keeps a sync small. More than this marks the fetch incomplete, so
    /// nothing is marked gone on its account.
    static let cap = 200

    /// The incomplete reminders, soonest due first (undated ones after), then the most recently
    /// changed, at most `cap`.
    static func fetch(_ snapshots: [ReminderSnapshot]) -> RemoteFetch {
        let open = snapshots.filter { !$0.isCompleted && !$0.id.isEmpty }
        let ordered = open.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return (lhs.lastModified ?? .distantPast) > (rhs.lastModified ?? .distantPast)
            }
        }
        return RemoteFetch(issues: ordered.prefix(cap).map(remoteIssue(from:)), complete: open.count <= cap)
    }

    static func remoteIssue(from snapshot: ReminderSnapshot) -> RemoteIssue {
        let list = snapshot.listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteIssue(
            remoteID: snapshot.id,
            key: list.isEmpty ? String(localized: "Reminders") : list,
            title: snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "New Reminder") : snapshot.title,
            status: "",
            isDoneRemotely: snapshot.isCompleted,
            estimateSeconds: nil,
            spentSeconds: nil,
            statusCategory: TaskFacets.toDoCategory,
            dueDate: snapshot.dueDate,
            priority: priorityName(snapshot.priority),
            updatedAt: snapshot.lastModified
        )
    }

    /// EventKit's priority as Reminders names it; nil for none.
    static func priorityName(_ priority: Int) -> String? {
        switch priority {
        case 1...4: return String(localized: "High")
        case 5: return String(localized: "Medium")
        case 6...9: return String(localized: "Low")
        default: return nil
        }
    }
}
