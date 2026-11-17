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

/// What a note's card in the notch shows: its title and a one-line preview. Display only; the stored note is
/// never changed.
///
/// The cards had two habits that spent their space on nothing. A note saved without a title reads "Untitled
/// Note", so the first card, where the eye lands first, could say nothing at all. And Apple Notes' text starts
/// with the title line, so a synced note's preview repeated its title, then stopped at the first line break with
/// half the card empty. Foundation only, in the test target.
enum NoteDisplayText {
    /// Enough text for one line of preview: a 4 KB meeting summary is not split whole on every redraw.
    static let previewSourceLimit = 600

    /// The note's title, or, when it has none or only the default one (`untitled`), its first line of text.
    static func title(title: String, content: String, untitled: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == untitled else { return trimmed }
        return lines(of: content).first ?? (trimmed.isEmpty ? untitled : trimmed)
    }

    /// The text after the title, on one line: the first line goes when it says the title again, Markdown's
    /// heading and bullet markers go, and the lines are joined with spaces so the preview fills its card.
    static func preview(title: String, content: String) -> String {
        var lines = lines(of: content)
        let shownTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = lines.first, first.compare(shownTitle, options: [.caseInsensitive]) == .orderedSame {
            lines.removeFirst()
        }
        return lines.joined(separator: " ")
    }

    /// The non-empty lines of the start of `content`, without leading Markdown markers.
    private static func lines(of content: String) -> [String] {
        String(content.prefix(previewSourceLimit))
            .components(separatedBy: .newlines)
            .map(stripMarkers)
            .filter { !$0.isEmpty }
    }

    /// `### Decisions` reads "Decisions", `- Ship it` reads "Ship it". Numbered items keep their numbers.
    static func stripMarkers(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.range(of: #"^(#{1,6}|[-*+>])\s+"#, options: .regularExpression) else { return trimmed }
        return String(trimmed[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
