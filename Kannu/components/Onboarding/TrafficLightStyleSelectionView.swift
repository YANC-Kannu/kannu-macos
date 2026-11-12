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

/// Onboarding step: pick how the agent traffic light looks in the closed notch.
///
/// The selection is held in local state and only written to Defaults on Continue, matching
/// `MusicControllerSelectionView` — so backing out of onboarding doesn't leave a half-applied
/// choice behind.
struct TrafficLightStyleSelectionView: View {
    let onContinue: () -> Void

    @Default(.agentTrafficLightStyle) var agentTrafficLightStyle
    @State private var selectedStyle: AgentTrafficLightStyle = Defaults[.agentTrafficLightStyle]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("Agent Traffic Light")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("Kannu shows a light in the notch while your AI agents work: green while running, yellow when one needs you, red when it finishes. Choose how it looks. You can change this later in Brain.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(spacing: SettingsTheme.listRowGap) {
                ForEach(AgentTrafficLightStyle.allCases) { style in
                    TrafficLightStyleCard(
                        style: style,
                        isSelected: selectedStyle == style,
                        onTap: {
                            selectedStyle = style
                        }
                    )
                }
            }

            Spacer(minLength: 0)

            Button("Continue") {
                agentTrafficLightStyle = selectedStyle
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

/// A style as a choice card (docs/SETTINGS.md, "Choices"): its notch preview, its name and what it shows.
private struct TrafficLightStyleCard: View {
    let style: AgentTrafficLightStyle
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
        Button(action: onTap) {
            HStack(spacing: SettingsMetrics.cardPadding) {
                // A real notch preview: same view the closed notch draws, on the same dark
                // background, showing the "agent is running" state.
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black)
                    AgentTrafficLightDots(style: style, state: .executing)
                }
                .frame(width: 76, height: 34)
                .accessibilityHidden(true)

                // A label inside the card's button, so it stays unselectable: selectable text swallows the click.
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(style.localizedName)
                        .settingsChoiceLabel(isSelected: isSelected)
                    Text(style.description)
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
    TrafficLightStyleSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
