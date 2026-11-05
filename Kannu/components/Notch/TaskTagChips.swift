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

import SwiftUI

/// A task's tags on a notch row, beside its caption (`TimerTasksPage`): the first tag as a chip,
/// "#docs", and "+2" for the rest, on the house chip (`SideChip`). The tags come in the order
/// `TaskSearch.chipTags(of:query:)` gives — own tags, then labels, those the search found first —
/// so while `#docs` is searched for, the chip shown is #docs. Names come bare; the `#` is added here.
///
/// A short tag shows whole and the caption gives way (it slides into view on hover). A long one
/// shares the line with the caption and shortens in the middle, so a long label never pushes the
/// caption out of the row. VoiceOver reads every tag.
struct TaskTagChips: View {
    /// Bare names, in the order to show them.
    let tags: [String]

    /// Up to this many characters, the first tag shows whole.
    private static let wholeTagLength = 12

    var body: some View {
        if let first = tags.first {
            HStack(spacing: 4) {
                SideChip("#\(first)", truncates: first.count > Self.wholeTagLength)
                if tags.count > 1 {
                    SideChip("+\(tags.count - 1)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: tags.map { "#\($0)" }.joined(separator: ", ")))
        }
    }
}
