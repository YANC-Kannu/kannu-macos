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

/// Brain's layout: a title row, the sidebar on the paper, and the page in an inset panel. Generic
/// slots, so it knows no page, and `SettingsView`'s navigation types stay private to that file.
struct BrainShell<Sidebar: View, HeaderAccessory: View, Detail: View>: View {
    private let sidebar: Sidebar
    private let headerAccessory: HeaderAccessory
    private let detail: Detail

    init(@ViewBuilder sidebar: () -> Sidebar,
         @ViewBuilder headerAccessory: () -> HeaderAccessory,
         @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.headerAccessory = headerAccessory()
        self.detail = detail()
    }

    var body: some View {
        VStack(spacing: 0) {
            // The top centre stays empty: a closed notch or island can sit over it in full screen.
            HStack {
                Spacer()
                headerAccessory
            }
            .frame(height: SettingsTheme.titleRowHeight)
            .padding(.horizontal, SettingsTheme.panelInset)

            HStack(spacing: 0) {
                VStack(spacing: SettingsTheme.sidebarStack) { sidebar }
                    .padding(.horizontal, SettingsTheme.panelInset)
                    .padding(.bottom, SettingsTheme.panelInset)
                    .frame(width: SettingsTheme.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SettingsTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous))
                    .padding([.trailing, .bottom], SettingsTheme.panelInset)
            }
        }
        .background(SettingsTheme.paper)
        // The title row lies under the transparent title bar, level with the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
    }
}
