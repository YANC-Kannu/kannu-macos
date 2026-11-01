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

import AppKit
import SwiftUI

/// Every colour, font and control measure Brain's own styles use. Flat statics, because a nested
/// `Color` namespace would shadow SwiftUI's. How to add a token: docs/SETTINGS.md, "The design system".
enum SettingsTheme {
    // MARK: - Colours: paper in light, ink in dark, the logo's eye blue as the one accent

    /// The window's own colour, for AppKit: behind the title bar and during a resize.
    static let windowPaper = nsColor(light: 0xF4F1EA, dark: 0x101114)
    static let paper = Color(nsColor: windowPaper)
    static let panel = color(light: 0xFCFBF8, dark: 0x17181C)
    static let card = color(light: 0xF3F1EC, dark: 0x202126)
    static let selection = color(light: 0xE9E5DB, dark: 0x27282D)
    static let hover = color(light: 0xEEEAE1, dark: 0x1E1F23)
    static let line = color(light: 0xE2DED4, dark: 0x2D2E34)
    static let ink = color(light: 0x1C1A16, dark: 0xECEAE4)
    static let inkSecondary = color(light: 0x6B675E, dark: 0xA3A199)
    static let accent = color(light: 0x4DA3FF, dark: 0x4DA3FF)
    /// The accent where it must be read: text and thin marks. 2.54:1 on paper is too faint for that.
    static let accentStrong = color(light: 0x1D69C9, dark: 0x4DA3FF)
    static let controlOff = color(light: 0x8A877F, dark: 0x6F7076)
    static let knob = color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let onPrimary = color(light: 0xF4F1EA, dark: 0x101114)
    static let destructive = color(light: 0xBC3226, dark: 0xFF6B5E)

    // MARK: - Fonts: Geist when bundled, the system font at the same size and weight when not

    static let geistIsAvailable = NSFont(name: "Geist-Regular", size: 13) != nil
    static let geistMonoIsAvailable = NSFont(name: "GeistMono-Regular", size: 13) != nil

    static let pageTitle = sans(20, .semibold, "Geist-SemiBold")
    static let body = sans(13, .regular, "Geist-Regular")
    static let bodyStrong = sans(13, .medium, "Geist-Medium")
    /// A section's name. The root's font replaces what a grouped `Form` gives its headers, so they say it.
    static let sectionTitle = sans(13, .semibold, "Geist-SemiBold")
    /// `.subheadline`'s size on macOS, so a description wraps where it did.
    static let description = sans(11, .regular, "Geist-Regular")
    static let caption = sans(10, .regular, "Geist-Regular")
    static let micro = sans(9, .semibold, "Geist-SemiBold")
    static let mono: Font = geistMonoIsAvailable
        ? .custom("GeistMono-Regular", size: 13)
        : .system(size: 13, weight: .regular, design: .monospaced)

    // MARK: - The window

    static let windowDefaultWidth: CGFloat = 1100
    static let windowDefaultHeight: CGFloat = 760
    static let windowMinWidth: CGFloat = 820
    static let windowMinHeight: CGFloat = 560
    /// A page's widest, or a row would stretch across a full-screen panel.
    static let pageMaxWidth: CGFloat = 720

    // MARK: - The shell

    /// The title bar's height with no toolbar, so the moon centres on the traffic lights.
    static let titleRowHeight: CGFloat = 28
    /// The search suggestions render inside this column, and their text needs the room.
    static let sidebarWidth: CGFloat = 200
    static let panelInset: CGFloat = 8
    static let panelRadius: CGFloat = 14
    static let sidebarStack: CGFloat = 8
    static let sidebarRowHeight: CGFloat = 32
    static let sidebarRowRadius: CGFloat = 8
    static let sidebarRowInset: CGFloat = 10
    static let sidebarRowGap: CGFloat = 2
    static let sidebarGlyph: CGFloat = 16
    static let sidebarRowContent: CGFloat = 10
    static let sidebarBadgeHorizontalInset: CGFloat = 6
    static let sidebarBadgeVerticalInset: CGFloat = 2
    /// The grouped `Form`'s side margin, so a page's title lines up with its section cards.
    static let pageInset: CGFloat = 20
    /// The search field and its suggestions.
    static let fieldRadius: CGFloat = 8

    // MARK: - Controls

    static let controlRadius: CGFloat = 7
    static let buttonInset = EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
    static let buttonInsetSmall = EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
    static let toggleWidth: CGFloat = 32
    static let toggleHeight: CGFloat = 18
    static let toggleKnobInset: CGFloat = 2
    static let disabledOpacity = 0.45
    static let pressedOpacity = 0.7
    /// Every bounded control animation. Never `.repeatForever` (docs/REGRESSIONS.md, entry 22).
    static let quickAnimation = 0.15

    private static func sans(_ size: CGFloat, _ weight: Font.Weight, _ name: String) -> Font {
        geistIsAvailable ? .custom(name, size: size) : .system(size: size, weight: weight)
    }

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nsColor(light: light, dark: dark))
    }

    private static func nsColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
