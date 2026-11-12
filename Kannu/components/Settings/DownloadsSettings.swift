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

import Defaults
import SwiftUI

struct Downloads: View {
    @Default(.enableDownloadListener) var enableDownloadListener
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.downloads.highlightID(for: title)
    }

    var body: some View {
        SettingsPage {
            SettingsSection {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Enable download detection")
                }
                .settingsHighlight(id: highlightID("Enable download detection"))
                VStack(alignment: .leading, spacing: 12) {
                    // Was hard-coded white, which vanished on the light background.
                    Text("Download indicator style")

                    HStack(spacing: 16) {
                        DownloadStyleButton(
                            style: .progress,
                            isSelected: selectedDownloadIndicatorStyle == .progress,
                            disabled: !enableDownloadListener
                        ) {
                            selectedDownloadIndicatorStyle = .progress
                        }

                        DownloadStyleButton(
                            style: .circle,
                            isSelected: selectedDownloadIndicatorStyle == .circle,
                            disabled: !enableDownloadListener
                        ) {
                            selectedDownloadIndicatorStyle = .circle
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Download indicator style"))
            } header: {
                SettingsSectionHeader("Download detection")
            } footer: {
                SettingsFooter("Monitor your Downloads folder for Chromium-style downloads (.crdownload files) and show a live activity in the Dynamic Island while downloads are in progress.")
            }
        }
        .navigationTitle("Downloads")
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            // A button, so the keyboard reaches the card and VoiceOver hears which one is selected and, while detection
            // is off, that it is unavailable. Disabled, it does nothing, as the click did; `.plain` dims it by half, as
            // the card's own opacity did, so the card no longer adds one.
            Button {
                if !disabled {
                    action()
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(backgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(borderColor, lineWidth: 1)
                            )
                            .settingsChoiceRing(RoundedRectangle(cornerRadius: 12), isSelected: isSelected)

                        if style == .progress {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(.accentColor)
                                .frame(width: 40)
                        } else {
                            SpinningCircleDownloadView()
                        }
                    }
                    .frame(width: 80, height: 60)
                    .onHover { hovering in
                        if !disabled {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHovering = hovering
                            }
                        }
                    }

                    Text(style.rawValue)
                        .settingsChoiceLabel(isSelected: isSelected)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 100)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .disabled(disabled)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}
