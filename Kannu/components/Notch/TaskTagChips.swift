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

/// A notch row's caption and its tags, on one line (`TimerTasksPage`), the tags on the house chip
/// (`SideChip`). The caption wins: it carries the time and the overtime, and the row is already
/// tinted in its first tag's colour. So a chip never takes a character from it (only "+N" may, on the
/// last line below), and the line is the first of these that fits (`ViewThatFits`):
///
/// - the whole caption, then the first tag whole as a chip, "#docs", and "+N" for the rest;
/// - the whole caption, then that chip shortened in the middle into what is left, never under
///   `TimerComposerMetrics.sideTaskChipMinWidth` (60 pt), and "+N" for the rest;
/// - the caption, first to the line's room (`layoutPriority`), then one "+N" for every tag. That
///   pill is about 25 pt, so the caption keeps the rest of the line: 93 pt at the narrowest notch,
///   beside a done tick.
///
/// The tags come in the order `TaskSearch.chipTags(of:query:)` gives — own tags, then labels, those
/// the search found first — so while `#docs` is searched for, the chip shown is #docs. When only "+N"
/// fits, that pill is tinted in the accent while it hides a tag the search found (`foundFirst`), so the
/// find still shows. Names come bare; the `#` is added here. VoiceOver reads every tag, whichever pills show. With no tags, the
/// caption is the whole line.
struct TaskTagChips<Caption: View>: View {
    private typealias M = TimerComposerMetrics

    /// Bare names, in the order to show them.
    let tags: [String]
    /// The first tag is one the search found (`TaskSearch.foundTags`): a lone "+N" hiding it is tinted.
    let foundFirst: Bool
    /// The row's caption, "42m of 2h · 10m over", drawn first.
    let caption: Caption

    init(tags: [String], foundFirst: Bool = false, @ViewBuilder caption: () -> Caption) {
        self.tags = tags
        self.foundFirst = foundFirst
        self.caption = caption()
    }

    var body: some View {
        if let first = tags.first {
            ViewThatFits(in: .horizontal) {
                besideWholeCaption(SideChip("#\(first)"))
                besideWholeCaption(
                    SideChip("#\(first)", truncates: true)
                        .frame(minWidth: M.sideTaskChipMinWidth, idealWidth: M.sideTaskChipMinWidth)
                )
                HStack(spacing: 4) {
                    caption.layoutPriority(1)
                    SideChip("+\(tags.count)", tint: foundFirst ? .accentColor : nil)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(everyTag)
                }
            }
        } else {
            caption
        }
    }

    /// The whole caption, then `chip` (the first tag) and "+N" for the tags after it.
    private func besideWholeCaption(_ chip: some View) -> some View {
        HStack(spacing: 4) {
            caption.fixedSize()
            HStack(spacing: 4) {
                chip
                if tags.count > 1 {
                    SideChip("+\(tags.count - 1)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(everyTag)
        }
    }

    private var everyTag: Text {
        Text(verbatim: tags.map { "#\($0)" }.joined(separator: ", "))
    }
}
