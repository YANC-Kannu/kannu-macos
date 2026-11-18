/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

/// Onboarding's last step, in Brain's theme: Kannu's eye logo, one line, and a sheet's buttons. Done
/// closes onboarding and plays the welcome in the notch (`AppDelegate.startWelcome`); Open Brain plays it
/// too and opens Brain. Nothing here moves: the welcome is the notch's.
struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    static let logoSize: CGFloat = 72

    var body: some View {
        VStack(spacing: SettingsTheme.sectionLabelGap) {
            Spacer()

            Image("logo2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.logoSize, height: Self.logoSize)
                .clipShape(RoundedRectangle(cornerRadius: Self.logoSize * 0.22, style: .continuous))
                .padding(.bottom, SettingsTheme.sectionLabelGap)
                .accessibilityHidden(true)

            Text("You're set")
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            Text("Kannu lives in your notch. Brain is a click away.")
                .font(SettingsTheme.body)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, SettingsTheme.pageInset)

            Spacer()
            Spacer()

            // A sheet's buttons: trailing, the other choice before the verb, which Return presses.
            HStack(spacing: SettingsMetrics.rowContent) {
                Button("Open Brain", action: onOpenSettings)

                Button("Done", action: onFinish)
                    .buttonStyle(SettingsButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, SettingsTheme.pageInset)
        }
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
