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

/// How a `SettingsSelect` list answers the keyboard: which rows a search keeps, where an arrow lands and which
/// row typed letters pick. Foundation only, so the test target compiles it.
enum SettingsSelectNavigation {
    /// A list longer than this gets a search field and scrolls; a shorter one takes typed letters instead.
    static let searchThreshold = 10
    /// Letters typed within this long of each other make one prefix, as in a macOS menu.
    static let typeSelectPause: TimeInterval = 1

    /// The rows a query keeps, best match first; every row, in order, while the query is empty.
    static func matches(_ titles: [String], query: String) -> [Int] {
        // `rank` matches nothing for an empty query, so `ranked` alone would empty the list.
        guard !SettingsSearchRanking.normalized(query).isEmpty else { return Array(titles.indices) }
        return SettingsSearchRanking.ranked(Array(titles.indices), query: query,
                                            title: { titles[$0] }, keywords: { _ in [] })
    }

    /// Where an arrow lands: the first or the last row from none, never past either end.
    static func moved(from index: Int?, by offset: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return offset > 0 ? 0 : count - 1 }
        return min(max(index + offset, 0), count - 1)
    }

    /// The prefix typed so far: a pause longer than `typeSelectPause` starts a new one.
    static func typed(_ characters: String, after prefix: String, pause: TimeInterval) -> String {
        pause > typeSelectPause ? characters : prefix + characters
    }

    /// The first row whose title starts with the prefix, with case and accents folded.
    static func typeSelect(_ prefix: String, in titles: [String]) -> Int? {
        let prefix = SettingsSearchRanking.normalized(prefix)
        guard !prefix.isEmpty else { return nil }
        return titles.firstIndex { SettingsSearchRanking.normalized($0).hasPrefix(prefix) }
    }
}
