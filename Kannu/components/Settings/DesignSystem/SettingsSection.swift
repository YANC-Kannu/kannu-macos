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

/// A group of rows on a `SettingsPage`, in place of a `Section`, called the same way: the rows, then `header:` and
/// `footer:`. The rows sit in a soft card, apart by space and never by a divider. The header and the footer sit
/// outside the card, in line with the rows' text, as a grouped `Form` placed them; the footer is secondary, as the
/// `Form` drew it. A modifier on a section reaches the whole of it, header and footer too.
struct SettingsSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        // A missing header or footer adds no gap: an empty view is no child of the stack.
        VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
            header
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, SettingsTheme.sectionPadding.leading)
            VStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {
                content
            }
            .padding(SettingsTheme.sectionPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
            footer
                .foregroundStyle(SettingsTheme.inkSecondary)
                .padding(.horizontal, SettingsTheme.sectionPadding.leading)
        }
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SettingsSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}
