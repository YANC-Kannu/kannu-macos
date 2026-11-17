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

import Defaults
import Foundation

/// Kannu's one set of tags, across tasks and notes (David, 2026-11-16: "tags will be system wide
/// concept"): what every tag field suggests, and the colour each tag has wherever it shows.
///
/// Nothing is stored here, so it is a stateless enum rather than an `XxxManager`. The tags are read
/// from what carries them, as tasks' have always been (`TaskFacets.tags(in:)`), and their colours stay
/// where tasks keep them, in tasks.json (`TasksFile.tagColors`): no second copy to drift, and no
/// migration. With Tasks off, tags draw uncoloured; colours are edited only in Brain › Tasks › Tag
/// colours, which is gone then too.
///
/// Callers read it once, as a tag field gains focus or a sheet appears, never in a view's body: the
/// saved notes can be hundreds, with their text.
@MainActor
enum SharedTags {
    /// Every tag in use, first spelling of each, sorted ignoring case: tasks' own tags (labels stay
    /// tasks' alone and are never suggested), saved notes' tags, and the tags of the Wispr Flow
    /// meetings listed now — never those of a meeting Wispr no longer lists.
    static func inUse() -> [String] {
        #if DEBUG
        // A board draws the task fixtures, never this Mac's notes or meetings.
        if let file = TasksManager.snapshotFile {
            return TaskFacets.tags(in: file.tasks)
        }
        #endif
        var tags: [String] = []
        if Defaults[.enableTasks] {
            tags += TasksManager.shared.tasks.flatMap(\.tags)
        }
        if Defaults[.enableNotes] {
            tags += Defaults[.savedNotes].flatMap(\.tags)
            if Defaults[.enableWisprFlowMeetings] {
                let byMeeting = Defaults[.wisprMeetingTags]
                tags += WisprFlowMeetingsManager.shared.notes.flatMap { byMeeting[$0.wisprMeetingId ?? ""] ?? [] }
            }
        }
        return TaskFacets.firstSpellings(tags)
    }

    /// Tag colours, keyed by `TaskColoring.key(for:)`. Empty while Tasks is off: the task file is
    /// touched only with tasks on.
    static func colors() -> [String: TaskColor] {
        Defaults[.enableTasks] ? TasksManager.shared.tagColors : [:]
    }
}
