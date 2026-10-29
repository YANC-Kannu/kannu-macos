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

/// The hook payloads that hook scripts v41 to v46 could leave in the status directory.
///
/// Those scripts copied each event's stdin — the whole hook payload, a Claude Code prompt included —
/// to `.kannu-input.XXXXXX` in `~/.kannu/agent-status/` and deleted it once Python had read it. A
/// hook killed in between (the host's timeout, an interrupt, the host quitting) left the file there
/// for good: one Mac had 33 of them, up to six weeks old. v47 never writes the payload to disk; this
/// removes what the older scripts left, once per launch. It never reads a file, only its name and
/// modification date.
enum HookInputLeftovers {
    static let namePrefix = ".kannu-input."

    /// Far older than any hook still running: hosts kill a hook after 10 seconds, and an old
    /// script still installed when Kannu launches may be mid-event.
    static let maxAge: TimeInterval = 10 * 60

    static func isStale(name: String, modified: Date, now: Date) -> Bool {
        name.hasPrefix(namePrefix) && now.timeIntervalSince(modified) > maxAge
    }

    /// Removes every stale payload file directly inside `directory`; returns how many went. Does
    /// file I/O: call it off the main thread.
    @discardableResult
    static func removeStale(in directory: URL, now: Date = Date()) -> Int {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasPrefix(namePrefix) {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  isStale(name: name, modified: modified, now: now),
                  (try? fileManager.removeItem(at: url)) != nil else { continue }
            removed += 1
        }
        return removed
    }
}
