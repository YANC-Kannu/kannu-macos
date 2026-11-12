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

/// Clipboard history's launch cleanup of its image folder.
///
/// An image copy writes its file before the history decides to keep it, so a copy it drops (the
/// same image again) leaves the file behind; each launch removes every file no item names. Pinned
/// Items are items too: pinning moves an item out of History, so a cleanup that read History alone
/// deleted every pinned image's file at each launch.
enum ClipboardDataCleanup {
    /// Removes every file directly inside `directory` that neither a History item nor a pinned item
    /// names; returns how many went. Does file I/O.
    @discardableResult
    static func removeUnreferencedFiles(in directory: URL, history: [String], pinned: [String]) -> Int {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let referenced = Set(history).union(pinned)
        var removed = 0
        for file in files where !referenced.contains(file.lastPathComponent) {
            guard (try? fileManager.removeItem(at: file)) != nil else { continue }
            removed += 1
        }
        return removed
    }
}
