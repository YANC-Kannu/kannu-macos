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
import Defaults

struct UserProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let description: String
}

struct ProfileSelectionView: View {
    @State private var selectedProfiles: Set<String> = []
    let onContinue: (Set<String>) -> Void
    
    let profiles: [UserProfile] = [
        UserProfile(
            id: "developer",
            name: String(localized: "Developer"),
            icon: "light.beacon.max",
            description: String(localized: "Track AI agent activity with traffic-light status, stats monitoring, and editor hooks.")
        ),
        UserProfile(
            id: "designer",
            name: String(localized: "Designer"),
            icon: "paintbrush.fill",
            description: String(localized: "Create and design with custom notch skins and visual effects.")
        ),
        UserProfile(
            id: "lightuse",
            name: String(localized: "Light Use"),
            icon: "sparkles",
            description: String(localized: "Just the essentials for everyday tasks, with fewer features switched on.")
        ),
        UserProfile(
            id: "student",
            name: String(localized: "Student"),
            icon: "book.fill",
            description: String(localized: "Stay organized with timer, battery monitoring, and media controls.")
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("Choose Your Profile")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("Select one or more profiles to customize your experience")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            // Two tiles a row, apart as Timer's start tiles are.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SettingsMetrics.cardPadding), GridItem(.flexible())],
                      spacing: SettingsMetrics.cardPadding) {
                ForEach(profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        isSelected: selectedProfiles.contains(profile.id),
                        onTap: {
                            toggleProfile(profile.id)
                        }
                    )
                }
            }

            Spacer(minLength: 0)

            Button("Continue") {
                if !selectedProfiles.isEmpty {
                    onContinue(selectedProfiles)
                }
            }
            .buttonStyle(SettingsButtonStyle(.primary))
            .disabled(selectedProfiles.isEmpty)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, SettingsTheme.pageInset)
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleProfile(_ profileId: String) {
        if selectedProfiles.contains(profileId) {
            selectedProfiles.remove(profileId)
        } else {
            selectedProfiles.insert(profileId)
        }
    }
}

/// A profile as a choice card (docs/SETTINGS.md, "Choices"), any number of them chosen: the ring says which.
struct ProfileCard: View {
    let profile: UserProfile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
                // One height for every glyph, so the four names line up: the symbols draw 25 to 32 pt tall at this size.
                Image(systemName: profile.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(SettingsTheme.accentStrong)
                    .frame(height: 34, alignment: .leading)
                    .accessibilityHidden(true)

                // A label inside the card's button, so it stays unselectable: selectable text swallows the click.
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(profile.name)
                        .settingsChoiceLabel(isSelected: isSelected)

                    Text(profile.description)
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(SettingsMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // At least this tall, so the grid's rows match; a longer translation grows the card, never spills past it.
            .frame(minHeight: 160, alignment: .topLeading)
            .background(SettingsTheme.card, in: shape)
            .settingsChoiceRing(shape, isSelected: isSelected)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Profile Settings Configuration

func applyProfileSettings(_ profiles: Set<String>) {
    // Record the choice itself, not only the settings it implies: this used to flip feature keys
    // and forget who asked for them, so nothing later could tell a developer from anyone else.
    Defaults[.userProfiles] = profiles.sorted()

    // Clipboard is ALWAYS enabled (per user request)
    Defaults[.enableClipboardManager] = true
    
    // Developer Profile Settings
    let isDeveloper = profiles.contains("developer")
    if isDeveloper {
        Defaults[.enableAgentStatusFeature] = true
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = true
        Defaults[.enableScreenAssistant] = true
        // Developers and testers are who can act on a freeze report, and who accept the tick.
        Defaults[.hangWatchdogEnabled] = true
    }

    // Designer Profile Settings
    let isDesigner = profiles.contains("designer")
    if isDesigner {
        Defaults[.lightingEffect] = true
        Defaults[.inlineHUD] = true
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = false
        Defaults[.enableScreenAssistant] = false
    }

    // Light Use Profile Settings
    let isLightUse = profiles.contains("lightuse")
    if isLightUse {
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = true
        Defaults[.inlineHUD] = true
        Defaults[.enableScreenAssistant] = false
        Defaults[.enableLyrics] = false
    }

    // Student Profile Settings
    let isStudent = profiles.contains("student")
    if isStudent {
        Defaults[.enableTimerFeature] = true
        Defaults[.enableStatsFeature] = false
        Defaults[.enableScreenAssistant] = false
    }
    
    // Common settings for all profiles
    Defaults[.menubarIcon] = true
    Defaults[.enableHaptics] = true
    
    // Lyrics disabled by default for all profiles
    Defaults[.enableLyrics] = false
    
    // Weather widget defaults to inline style
    Defaults[.lockScreenWeatherWidgetStyle] = .inline
    
    // Auto-detect notch: Dynamic Island for non-notch Macs, standard notch otherwise.
    // Without a physical notch there is no hardware cutout to hide behind, so a permanently
    // visible island reads as clutter — keep it tucked off-screen until hovered or until an
    // agent does something. Notched Macs keep the global default (visible) since the pill
    // sits inside the cutout anyway.
    //
    // Asks the built-in display specifically. Reading `NSScreen.main` meant onboarding while
    // docked sampled the external monitor and handed a notched MacBook the wrong shape.
    if macHasNotchedBuiltInDisplay() {
        Defaults[.externalDisplayStyle] = .notch
    } else {
        Defaults[.externalDisplayStyle] = .dynamicIsland
    }
    
    // Lock screen glass: custom liquid glass v11 on macOS 26+
    if #available(macOS 26.0, *) {
        Defaults[.lockScreenGlassStyle] = .liquid
        Defaults[.lockScreenGlassCustomizationMode] = .customLiquid
        Defaults[.lockScreenMusicLiquidGlassVariant] = .v11
    }
    
    print("✅ Applied profile settings for: \(profiles.joined(separator: ", "))")
}


#Preview {
    ProfileSelectionView(onContinue: { profiles in
        print("Selected profiles: \(profiles)")
    })
}
