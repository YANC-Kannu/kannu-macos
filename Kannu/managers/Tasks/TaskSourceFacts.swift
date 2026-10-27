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

/// What Kannu knows about each place tasks come from, without asking it anything: its names, what
/// one of its items is called, whether its time can be logged there, and how its keys read. One
/// switch per fact, here, so a new source is a new case and a few lines — not a hunt through every
/// view (docs/TASK-SOURCES.md). Pure Foundation, so the logic target tests it.
///
/// The settings each source keeps (its Sync switch, its colour, Show in notch) are the app's, in
/// `TaskSourceSettings`.
extension TaskSource {
    /// The sources that hold tasks fetched from elsewhere, in the order Brain and the notch list them.
    static var remoteSources: [TaskSource] { allCases.filter { $0 != .local } }

    /// The source's name in running text: "Jira", "GitLab", "GitHub", "Linear", "Todoist",
    /// "Reminders"; "Local" for the user's own. Product names, so never translated.
    var name: String {
        switch self {
        case .local: return String(localized: "Local")
        case .jira: return "Jira"
        case .gitlab: return "GitLab"
        case .github: return "GitHub"
        case .linear: return "Linear"
        case .todoist: return "Todoist"
        case .appleReminders: return String(localized: "Reminders")
        }
    }

    /// The source's own row and page title: "Local tasks", "Jira Cloud", "Apple Reminders".
    var title: String {
        switch self {
        case .local: return String(localized: "Local tasks")
        case .jira: return "Jira Cloud"
        case .appleReminders: return String(localized: "Apple Reminders")
        case .gitlab, .github, .linear, .todoist: return name
        }
    }

    /// Whether time recorded on its tasks can be logged there, so Time to log offers it. Only Jira
    /// (worklogs) and GitLab (spent time) take time; the others have no such thing.
    var logsTime: Bool { self == .jira || self == .gitlab }

    /// Whether connecting it takes a token kept in the Keychain. Apple Reminders asks macOS for
    /// permission instead.
    var usesToken: Bool {
        switch self {
        case .local, .appleReminders: return false
        case .jira, .gitlab, .github, .linear, .todoist: return true
        }
    }

    /// How a source's keys read, which also says where its project is.
    enum KeyStyle: Equatable {
        /// A local task: no key, no project.
        case none
        /// "PROJ-123", "ENG-42": the project is the prefix before the last "-".
        case dashed
        /// "group/app#45", "group/app!12", "owner/repo#7": the project is the path before the last
        /// "#" or "!".
        case path
        /// No key of its own: `RemoteTaskInfo.key` holds the item's project or list ("Inbox",
        /// "Groceries"), which is its project.
        case list
    }

    var keyStyle: KeyStyle {
        switch self {
        case .local: return .none
        case .jira, .linear: return .dashed
        case .gitlab, .github: return .path
        case .todoist, .appleReminders: return .list
        }
    }

    /// What one of its items is called, and several: the Refresh row's "12 issues".
    var itemNoun: (one: String, many: String) {
        switch self {
        case .local, .todoist: return (String(localized: "task"), String(localized: "tasks"))
        case .jira, .linear: return (String(localized: "issue"), String(localized: "issues"))
        case .gitlab, .github: return (String(localized: "item"), String(localized: "items"))
        case .appleReminders: return (String(localized: "reminder"), String(localized: "reminders"))
        }
    }

    /// "Open in Jira", "Open in GitHub"; nil for a source with no page to open (local, Reminders).
    var browseLabel: String? {
        switch self {
        case .local, .appleReminders: return nil
        case .jira, .gitlab, .github, .linear, .todoist: return String(localized: "Open in \(name)")
        }
    }
}
