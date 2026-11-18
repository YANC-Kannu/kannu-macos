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

/// Onboarding step: what the agent light looks like in the notch. A showcase, not a choice: since 2.0 the
/// light is one lit dot beside the notch with the agent's app icon across it (David, 2026-11-18: "no need
/// clasic"), so there is nothing to pick here and nothing is written to Defaults.
///
/// One card holds the real pill at a real notch's 32 pt, with a real housing's ratio, in its three states.
/// Everything is still (docs/REGRESSIONS.md entry 22): plain dots, never the breathing ones, and a symbol
/// stand-in for each app icon, never another company's logo.
struct AgentLightShowcaseView: View {
    let onContinue: () -> Void

    /// A real notch's closed height: the size the pill is on a 14" MacBook Pro.
    private static let closedHeight: CGFloat = 32

    private struct Example: Identifiable {
        let id: String
        let state: AgentTrafficLightState
        let icon: AgentProviderIconSource
        let label: String
    }

    private var examples: [Example] {
        [
            Example(id: "working", state: .executing, icon: .claude, label: String(localized: "Working")),
            Example(id: "needsYou", state: .awaitingInput, icon: .cursor, label: String(localized: "Needs you")),
            Example(id: "finished", state: .stopped, icon: .codex, label: String(localized: "Finished")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("Your agents, in the notch")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("One light beside the notch shows how your AI agents are doing.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            // The card and its explanation sit centred between the header and Continue, so the step has
            // no empty band under its content.
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
                VStack(spacing: SettingsTheme.sectionRowGap) {
                    ForEach(examples) { example in
                        VStack(spacing: SettingsMetrics.labelStack) {
                            AgentPillPreview(state: example.state, iconSource: example.icon,
                                                   closedHeight: Self.closedHeight)
                            Text(example.label)
                                .font(SettingsTheme.description)
                                .foregroundStyle(SettingsTheme.inkSecondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(example.label)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SettingsMetrics.cardPadding)
                .background(SettingsTheme.card,
                            in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))

                Text("It shows for a few seconds after each change, with the agent's app icon across the notch. You can change its colors in Brain.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button("Continue", action: onContinue)
                .buttonStyle(SettingsButtonStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, SettingsTheme.pageInset)
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    AgentLightShowcaseView(onContinue: {})
        .frame(width: 400, height: 600)
}
