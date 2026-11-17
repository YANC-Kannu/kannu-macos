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

/// The notch Notes tab's one filter (David, 2026-11-16: "filter by tags here and source too, it should
/// be simple"): Source, Tag and Colour, each a submenu with All first, then Show all while it narrows.
/// It narrows the list only (`NoteFilter`), and the choices are kept in Defaults by the list.
///
/// A native menu, as the Tasks filter is (`TaskSourceMenu`): the notch counts a tracking menu as
/// "on the notch" (`ContentView`'s menu tracking), so it holds nothing open itself (REGRESSIONS
/// entry 23). The label is a plain glyph like the header's others, never a circle: "+" stays the one
/// filled control, and while the filter narrows the glyph turns bold and accent, as the search glyph
/// does while open.
struct NoteFilterMenu: View {
    @Environment(\.notchForeground) private var notchForeground

    /// The sources offered (`NoteFilter.sourceChoices`); no Source submenu when empty.
    let sources: [NoteSource]
    /// The Tag submenu's choices (`NoteFilter.tagChoices`).
    let tags: [String]
    /// "Enable color filtering" is on: the Colour submenu shows.
    let showsColors: Bool
    /// The effective filter narrows the list.
    let isNarrowing: Bool
    /// Each reads the effective choice and writes the kept one.
    @Binding var source: NoteSource?
    @Binding var tag: String
    @Binding var colorIndex: Int?
    let showAll: () -> Void

    var body: some View {
        Menu {
            if !sources.isEmpty {
                Picker(String(localized: "Source"), selection: $source) {
                    Text("All").tag(NoteSource?.none)
                    ForEach(sources) { source in
                        Text(verbatim: source.name).tag(Optional(source))
                    }
                }
            }
            // Nothing to pick without a tag, unless a picked one lingers.
            if !tags.isEmpty || tag != TaskFacets.anyTag {
                tagPicker
            }
            if showsColors {
                Picker(String(localized: "Colour"), selection: $colorIndex) {
                    Text("All").tag(Int?.none)
                    ForEach(NoteItem.colors.indices, id: \.self) { index in
                        Text(verbatim: NoteItem.colorNames[index]).tag(Optional(index))
                    }
                }
            }
            if isNarrowing {
                Divider()
                Button(String(localized: "Show all"), action: showAll)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: isNarrowing ? .bold : .medium))
                .foregroundStyle(glyphColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // A borderless menu may draw its label in the control's own colour; the tint carries ours.
        .tint(glyphColor)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .accessibilityLabel(String(localized: "Filter Notes"))
        .hoverTooltip(String(localized: "Filter Notes"), edge: .below)
    }

    private var glyphColor: Color {
        isNarrowing ? SettingsTheme.accent : notchForeground.opacity(0.55)
    }

    /// All, or one tag. A picked tag no note carries any more still shows, ticked, so the menu says
    /// what is hiding the list (the Tasks filter's rule).
    private var tagPicker: some View {
        let picked = tag
        return Picker(String(localized: "Tag"), selection: $tag) {
            Text("All").tag(TaskFacets.anyTag)
            ForEach(tags, id: \.self) { name in
                Text(verbatim: "#\(name)").tag(name.lowercased() == picked.lowercased() ? picked : name)
            }
            if picked != TaskFacets.anyTag, !tags.contains(where: { $0.lowercased() == picked.lowercased() }) {
                Text(verbatim: "#\(picked)").tag(picked)
            }
        }
    }
}
