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

/// A product page: what the page is about first, then its settings (docs/SETTINGS.md, "Product pages"). The product
/// stands in a column as wide as `productMaxWidth`; a full-width "<Page> settings" rule starts the settings, which keep
/// `SettingsPage`'s `pageMaxWidth` column, so a label stays near its switch. Like `SettingsPage`, one scroll view across
/// the panel, held the page inset from its leading edge and never centred, and plain stacks: a search or a deep link
/// scrolls to a settings row's id, and a lazy stack cannot scroll to a row it has not built.
struct SettingsProductPage<Product: View, Settings: View>: View {
    @Environment(\.settingsPageInset) private var inset
    private let settingsTitle: String
    private let product: Product
    private let settings: Settings

    init(settingsTitle: String, @ViewBuilder product: () -> Product, @ViewBuilder settings: () -> Settings) {
        self.settingsTitle = settingsTitle
        self.product = product()
        self.settings = settings()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
                product
                    .frame(maxWidth: SettingsTheme.productMaxWidth, alignment: .leading)
                HStack(spacing: SettingsTheme.sectionLabelGap) {
                    Text(verbatim: settingsTitle)
                        .font(SettingsTheme.sectionTitle)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle()
                        .fill(SettingsTheme.line)
                        .frame(height: SettingsTheme.hairline)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: SettingsTheme.productMaxWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
                    settings
                }
                .frame(maxWidth: SettingsTheme.pageMaxWidth, alignment: .leading)
            }
            .padding(.horizontal, inset)
            // As `SettingsPage`: less the scroll view's own inset below, so the page at rest starts where it did.
            .padding(.top, SettingsTheme.sectionGap - SettingsTheme.pageScrollInset)
            .padding(.bottom, SettingsTheme.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A scrolled page is cut this far under the title, never against it.
        .padding(.top, SettingsTheme.pageScrollInset)
    }
}
