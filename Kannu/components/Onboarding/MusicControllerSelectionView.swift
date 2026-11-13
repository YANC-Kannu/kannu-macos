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
import Defaults


struct MusicControllerSelectionView: View {
    /// Hands the choice back without applying it: switching to Spotify or Apple Music talks to the
    /// app at once, which raises the Automation dialog. The Permissions step asks for that, and
    /// onboarding applies the source when it finishes.
    let onContinue: (MediaControllerType) -> Void

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedMediaController: MediaControllerType = Defaults[.mediaController]
    
    var body: some View {
        // The scroll view spans the window, so its bar sits at the window's edge; its cards keep the page's inset.
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("Choose a Music Source")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("Select the music source you want to use. You can change this later in Brain.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, SettingsTheme.pageInset)

            ScrollView {
                VStack(spacing: SettingsTheme.listRowGap) {
                    ForEach(availableMediaControllers) { controller in
                        ControllerOptionView(
                            controller: controller,
                            isSelected: self.selectedMediaController == controller,
                            onSelect: { self.selectedMediaController = controller }
                        )
                    }
                }
                .padding(.horizontal, SettingsTheme.pageInset)
            }

            Button("Continue", action: {
                onContinue(selectedMediaController)
            })
            .buttonStyle(SettingsButtonStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, SettingsTheme.pageInset)
        }
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A source as a choice card (docs/SETTINGS.md, "Choices"): a plain button, so the keyboard reaches it and VoiceOver
/// hears which one is selected.
struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let onSelect: () -> Void

    private var gitHubURL: URL? {
        controller == .youtubeMusic ? URL(string: "https://github.com/th-ch/youtube-music") : nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
        Button(action: onSelect) {
            // A label inside the card's button, so it stays unselectable: selectable text swallows the click.
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(controller.rawValue)
                    .settingsChoiceLabel(isSelected: isSelected)

                Text(controller.description)
                    .font(SettingsTheme.description)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if gitHubURL != nil {
                    // Room for the link, which sits over the card, never inside its button.
                    Text("View on GitHub: th-ch/youtube-music")
                        .font(SettingsTheme.description)
                        .hidden()
                }
            }
            .padding(SettingsMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.card, in: shape)
            .settingsChoiceRing(shape, isSelected: isSelected)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottomLeading) {
            if let gitHubURL {
                Link("View on GitHub: th-ch/youtube-music", destination: gitHubURL)
                    .font(SettingsTheme.description)
                    .buttonStyle(.link)
                    .padding(SettingsMetrics.cardPadding)
            }
        }
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return String(localized: "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version.")
        case .spotify:
            return String(localized: "Connects directly to the Spotify app.")
        case .appleMusic:
            return String(localized: "Connects directly to the Apple Music app.")
        case .youtubeMusic:
            return String(localized: "Requires a third-party client with API plugin enabled.")
        case .amazonMusic:
            return String(localized: "Uses macOS Now Playing when the Amazon Music app is the active media source. Playback controls follow the system Now Playing target. Scrubbing the timeline may not work if the Amazon Music app does not support remote seek.")
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: { _ in })
        .frame(width: 400, height: 600)
}
