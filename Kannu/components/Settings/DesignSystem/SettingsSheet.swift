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

/// A sheet: a title, an optional line under it, its fields, then trailing buttons, Cancel then the primary.
/// It applies the root itself: a sheet is a window of its own, and whether SwiftUI passes the root's styles into
/// a presentation could never be told from source. Re-applied here, the root changes nothing a sheet holds, since
/// a sheet is a `VStack`, never a `Form`.
///
/// A field's name is a `LabeledContent` label beside it (docs/SETTINGS.md, "Section rules").
struct SettingsSheet<Content: View, Buttons: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let width: CGFloat
    private let content: Content
    private let buttons: Buttons

    init(_ title: LocalizedStringKey, subtitle: Text? = nil, width: CGFloat = SettingsTheme.sheetWidth,
         @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.init(Text(title), subtitle: subtitle, width: width, content: content, buttons: buttons)
    }

    /// For a title built at run time (already localised), such as one naming a task source.
    init(_ title: Text, subtitle: Text? = nil, width: CGFloat = SettingsTheme.sheetWidth,
         @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sheetStack) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                title
                    .font(SettingsTheme.sheetTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle.settingsDescriptionStyle()
                }
            }
            content
            // Trailing unless the caller spreads them with a `Spacer` of its own (Remove Estimate, Clear All).
            HStack(spacing: SettingsMetrics.rowContent) { buttons }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(SettingsTheme.sheetInset)
        .frame(width: width)
        .background(SettingsTheme.panel)
        .settingsDesignSystem()
    }
}
