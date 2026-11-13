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
    /// 4.5:1 on the line colour too, where a badge's text sits.
    static let inkSecondary = color(light: 0x66625A, dark: 0xA3A199)
    static let accent = color(light: 0x4DA3FF, dark: 0x4DA3FF)
    /// The accent where it must be read: text and thin marks. 2.54:1 on paper is too faint for that.
    static let accentStrong = color(light: 0x1D69C9, dark: 0x4DA3FF)
    static let controlOff = color(light: 0x8A877F, dark: 0x6F7076)
    static let knob = color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let onPrimary = color(light: 0xF4F1EA, dark: 0x101114)
    static let destructive = color(light: 0xBC3226, dark: 0xFF6B5E)
    /// A mark that means ready, such as a status line's dot. Drawn, never read, so 3:1 is its floor.
    static let success = color(light: 0x2E7D4F, dark: 0x5FD08A)

    // MARK: - Fonts: Geist when bundled, the system font at the same size and weight when not

    static let geistIsAvailable = NSFont(name: "Geist-Regular", size: 13) != nil
    static let geistMonoIsAvailable = NSFont(name: "GeistMono-Regular", size: 13) != nil

    /// One size on every page, so the title never changes size between tabs.
    static let pageTitle = sans(24, .semibold, "Geist-SemiBold")
    /// A card's title, the step between a page's title and a row: the hero's state, an empty state's status, and a
    /// status cell's headline figure.
    static let cardTitle = sans(17, .semibold, "Geist-SemiBold")
    /// A sheet's title: a sheet is smaller than a page.
    static let sheetTitle = sans(15, .semibold, "Geist-SemiBold")
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
    /// The notch's text: Geist at the size and weight the notch's own measures set (`UsageCardMetrics`,
    /// `TimerComposerMetrics`), sizes this scale has no name for. Geist ships Regular, Medium and SemiBold, so bold and
    /// heavier draw SemiBold, and lighter draws Regular. A symbol keeps `.system`, which sizes it, and so does monospaced
    /// text: Geist Mono ships Regular only. docs/SETTINGS.md, "The notch".
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        sans(size, weight, geistFace(weight))
    }

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
    /// Where a page starts, from the panel's leading edge. A page is held there, never centred.
    static let pageInset: CGFloat = 32
    /// The same on a panel at least `widePanelWidth` wide, such as a full-screen one.
    static let pageInsetWide: CGFloat = 48
    static let widePanelWidth: CGFloat = 1000
    /// From the panel's top to the title's frame, which puts the title's cap height 44 pt below it.
    static let pageHeaderTop: CGFloat = 37
    /// The search field and its suggestions.
    static let fieldRadius: CGFloat = 8
    /// The fade at the foot of the suggestions while more rows sit below, so a list of whole rows still says "more". The
    /// list ends on a row's bottom edge, and a row's tab line sits 7 to 20 pt above it, so the fade reaches that line.
    static let suggestionFade: CGFloat = 20

    // MARK: - Pages and sections

    /// Between two sections, and above the first and below the last.
    static let sectionGap: CGFloat = 24
    /// From the title's row to the page's scroll view, so a scrolled page is cut this far under the title, never against
    /// it. The page's own top padding gives up as much, so a page at rest starts where it did.
    static let pageScrollInset: CGFloat = 12
    /// A section's card around its rows. Twelve at the sides too: one inset for text inside and beside a card, so a row,
    /// a section's header and a card's title start on one edge.
    static let sectionPadding = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    /// Between two rows of a section: space, never a divider.
    static let sectionRowGap: CGFloat = 14
    /// From a section's header to its card, and from the card to its footer.
    static let sectionLabelGap: CGFloat = 8
    static let sectionRadius: CGFloat = 12
    /// A row's caption stops here, so a label column never runs past about 80 characters at the description's size, however
    /// long a caption still is.
    static let descriptionMaxWidth: CGFloat = 440

    // MARK: - Product pages: the product first, then its settings

    /// A product page's own content stops here. Past it the extra width is right margin, as with `pageMaxWidth`.
    static let productMaxWidth: CGFloat = 1200
    /// A line of prose, such as an empty state's or a section's footer: about 74 characters at the description's size, 63 at
    /// the body's.
    static let proseMaxWidth: CGFloat = 380
    /// The hero card, or the empty state in its place.
    static let heroMinHeight: CGFloat = 200
    /// The same inset as a section's card, so the hero's text starts where every card's does.
    static let heroPadding: CGFloat = 12
    static let heroIcon: CGFloat = 28
    /// A row of a product page's list, and the space between two.
    static let listRowHeight: CGFloat = 56
    static let listRowGap: CGFloat = 6
    static let listRowIcon: CGFloat = 20
    /// A row's trailing column, its state, metrics and light, so the eye travels a bounded distance.
    static let listTrailingWidth: CGFloat = 200
    /// A start tile, side by side with the others and wrapping: Timer's presets, four to a row at the window's first size.
    static let tileWidth: CGFloat = 180

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

    // MARK: - Choices and fields

    /// The selected segment, raised off its track.
    static let raised = color(light: 0xFFFFFF, dark: 0x2B2C31)
    static let segmentInset = EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10)
    static let segmentTrackInset: CGFloat = 2
    static let segmentRadius: CGFloat = 5
    /// Around a popover's content.
    static let popoverInset: CGFloat = 6
    static let selectMinWidth: CGFloat = 180
    static let selectRowHeight: CGFloat = 28
    static let selectRowInset: CGFloat = 8
    /// A long list's height: ten rows and half of the next, so it shows there is more to scroll to.
    static let selectListHeight: CGFloat = 294
    static let fieldInset = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    static let focusRingWidth: CGFloat = 2
    /// A choice card's one selected look: an accent ring this wide around its tile.
    static let choiceRingWidth: CGFloat = 2

    // MARK: - Badges

    /// A badge beside a title on a page ("Beta", "Alpha", "Built-in"): quiet, on the line colour.
    static let badgeInset = EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
    static let badgeRadius: CGFloat = 4

    // MARK: - Values

    static let sliderTrackHeight: CGFloat = 4
    /// The slider's knob, and so the slider's height.
    static let sliderKnob: CGFloat = 16
    /// How far an arrow key or VoiceOver's adjust moves a slider that has no step: this much of its range.
    static let sliderKeyboardFraction = 0.05
    static let stepperButtonWidth: CGFloat = 22
    static let stepperHeight: CGFloat = 22
    /// A divider's width.
    static let hairline: CGFloat = 1

    // MARK: - Sheets

    /// Around a sheet's content.
    static let sheetInset: CGFloat = 20
    /// Between a sheet's title, its fields and its buttons.
    static let sheetStack: CGFloat = 12
    /// Every sheet but the rules editor.
    static let sheetWidth: CGFloat = 420
    /// The rules editor: a kind, a command and a reason side by side.
    static let sheetWidthWide: CGFloat = 560

    private static func sans(_ size: CGFloat, _ weight: Font.Weight, _ name: String) -> Font {
        geistIsAvailable ? .custom(name, size: size) : .system(size: size, weight: weight)
    }

    private static func geistFace(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Geist-Medium"
        case .semibold, .bold, .heavy, .black: "Geist-SemiBold"
        default: "Geist-Regular"
        }
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
