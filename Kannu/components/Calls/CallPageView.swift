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

/// "Call · Media", the media screen's two page labels while a call exists: the shown page bright,
/// the other dimmed. Clicking one shows it; VoiceOver reads the pair as a two-option picker (the
/// timer tab's "Tasks · Presets" pattern, `TimerSideColumn`).
struct HomePagerLabels: View {
    @Environment(\.notchForeground) private var notchForeground

    let shown: HomePage
    let onSelect: (HomePage) -> Void

    private let pages = HomePage.pages(hasCall: true)

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(pages.enumerated()), id: \.element) { index, item in
                if index > 0 {
                    Text(verbatim: "·")
                        .foregroundStyle(notchForeground.opacity(0.3))
                }
                Button {
                    onSelect(item)
                } label: {
                    Text(Self.title(of: item))
                        .foregroundStyle(item == shown ? notchForeground : notchForeground.opacity(0.4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(SettingsTheme.font(size: 11, weight: .semibold))
        .frame(height: HomePage.pagerHeight)
        .accessibilityRepresentation {
            Picker(String(localized: "Media screen page"), selection: Binding(get: { shown }, set: { onSelect($0) })) {
                ForEach(pages) { item in
                    Text(Self.title(of: item)).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    static func title(of page: HomePage) -> String {
        switch page {
        case .call: return String(localized: "Call")
        case .media: return String(localized: "Media")
        }
    }
}

/// The call's page on the open notch's media screen: the calling app's icon where the album art
/// sits, a title (the caller's name when a ring gave one, the app's name otherwise), and under it
/// "Ringing" or the elapsed time.
///
/// Parameters only, like everything in this folder. It shows what Kannu saw and offers no control
/// over the call: answering, declining and hanging up stay in the calling app.
struct CallPageView: View {
    @Environment(\.notchForeground) private var notchForeground

    let icon: CallIconSource
    let title: String
    /// Nil while it rings.
    let elapsed: CallElapsed?
    let accessibilityLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The album art's square: as tall as the screen, as wide as it is tall.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CallAppIcon(source: icon)
                        .padding(14)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SettingsTheme.font(size: 15, weight: .semibold))
                    .foregroundStyle(notchForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Image(systemName: CallGlyph.symbol(isRinging: elapsed == nil))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                    if let elapsed {
                        CallElapsedText(elapsed: elapsed)
                            .monospacedDigit()
                    } else {
                        Text("Ringing")
                    }
                }
                .font(SettingsTheme.font(size: 13, weight: .medium))
                .foregroundStyle(notchForeground.opacity(0.7))
                .lineLimit(1)
            }
            .padding(.top, 10)
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
