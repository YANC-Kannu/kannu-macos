/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
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

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: SettingsTheme.sectionLabelGap) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(SettingsTheme.accentStrong)
                .padding()
                .accessibilityHidden(true)

            Text("You're All Set!")
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            Text("You can now enjoy the app. If you want to tweak things further, you can always open Brain.")
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
                Button(action: onOpenSettings) {
                    Label("Customize in Brain", systemImage: "brain")
                }

                Button("Finish", action: onFinish)
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
