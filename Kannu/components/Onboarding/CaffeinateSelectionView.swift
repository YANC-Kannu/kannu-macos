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

import Defaults
import SwiftUI

/// Onboarding step: choose how Kannu keeps the Mac awake for agent work.
/// Selection is local state, written to Defaults only on Continue.
struct CaffeinateSelectionView: View {
    let onContinue: () -> Void

    // Seeded from the stored choice so re-entering onboarding shows what is actually set,
    // not a hardcoded pre-selection.
    @State private var selectedSmart: Bool = Defaults[.smartCaffeinate]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("Keep the Mac Awake?")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("Long agent runs die if the Mac falls asleep. Choose how Kannu should handle it. You can change this later in Brain.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(spacing: SettingsTheme.listRowGap) {
                CaffeinateOptionCard(
                    icon: "sparkles",
                    title: String(localized: "Smart caffeinate"),
                    subtitle: String(localized: "Recommended: the Mac stays awake automatically while agents run, and sleeps normally when they stop."),
                    isSelected: selectedSmart,
                    onTap: { selectedSmart = true }
                )
                CaffeinateOptionCard(
                    icon: "switch.2",
                    title: String(localized: "Manual switch"),
                    subtitle: String(localized: "A switch in the notch's agent panel keeps the Mac awake while it's on. You decide when."),
                    isSelected: !selectedSmart,
                    onTap: { selectedSmart = false }
                )
            }

            Spacer(minLength: 0)

            Button("Continue") {
                Defaults[.smartCaffeinate] = selectedSmart
                onContinue()
            }
            .buttonStyle(SettingsButtonStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, SettingsTheme.pageInset)
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A way to stay awake as a choice card (docs/SETTINGS.md, "Choices"): its notch preview, its name and what it does.
private struct CaffeinateOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
        Button(action: onTap) {
            HStack(spacing: SettingsMetrics.cardPadding) {
                // The notch's own colours: a preview of what it shows.
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black)
                    HStack(spacing: 2) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                        Image(systemName: icon)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 56, height: 34)
                .accessibilityHidden(true)

                // A label inside the card's button, so it stays unselectable: selectable text swallows the click.
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(title)
                        .settingsChoiceLabel(isSelected: isSelected)
                    Text(subtitle)
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(SettingsMetrics.cardPadding)
            .background(SettingsTheme.card, in: shape)
            .settingsChoiceRing(shape, isSelected: isSelected)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CaffeinateSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
