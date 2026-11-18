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

/// Onboarding's welcome line in the open notch: "Welcome to Kannu" in Geist, after an Iris dot, the
/// logo's eye colour. It replaced boring.notch's rainbow "hello" (David, 2026-11-18: "the final animation
/// and welcoming to the app, that to be cleaner"). `AppDelegate.startWelcome` opens and closes the notch
/// around it; the line itself only fades in, once, and nothing repeats (docs/REGRESSIONS.md entry 22).
struct NotchWelcomeView: View {
    /// Iris, the logo's eye (#4A9EFF): the site's brand accent.
    static let iris = Color(red: 0x4A / 255, green: 0x9E / 255, blue: 0xFF / 255)
    static let dotSize: CGFloat = 8

    /// Boards draw it settled: a renderer captures the first frame, before any fade.
    var fadesIn = true

    @Environment(\.notchForeground) private var notchForeground
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Self.iris)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .accessibilityHidden(true)
            Text("Welcome to Kannu")
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(notchForeground)
        }
        .opacity(shown || !fadesIn ? 1 : 0)
        .onAppear {
            guard fadesIn else { return }
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NotchWelcomeView()
        .frame(width: 420, height: 120)
        .background(Color.black)
}
