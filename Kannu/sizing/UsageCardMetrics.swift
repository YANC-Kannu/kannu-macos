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

import CoreGraphics

/// Every size of the Usage tab's provider cards, so a card's height is known and fits the open
/// notch without the notch growing, and its two columns split in the golden ratio.
///
/// The notch is a fixed 200 pt when open (`matters.swift`). After its 12 pt bottom padding, the
/// header and 8 pt of stack spacing, the Usage tab has 142 pt on a notched MacBook (header 38),
/// 156 on a display with no notch (header 24). The old card stacked its two sections and reached
/// 157 pt before any forecast caption or status line, so it ran into the shadow band and the
/// window clipped it. A card has two things: the 5-hour window (one gauge, now) and the weekly
/// stack (all models plus each per-model window, the trend) — a 1 : φ pair, laid side by side.
///
/// `goldenRatio`, `goldenSplit` and the row sizes are the timer tab's (`TimerComposerMetrics`,
/// `GoldenRow`), copied here while that file is not on `development`; whichever change lands
/// second delegates to the other.
enum UsageCardMetrics {
    // MARK: The slot

    /// `openNotchSize.height` in `matters.swift`.
    static let openNotchHeight: CGFloat = 200
    /// `ContentView`'s bottom padding inside the notch shape.
    static let openNotchBottomPadding: CGFloat = 12
    /// `NotchLayout`'s default `VStack` spacing between the header and the tab.
    static let notchLayoutSpacing: CGFloat = 8
    /// The header is `max(24, closed notch height)`: a 14" MacBook Pro's notch, the smallest slot.
    static let notchedHeaderHeight: CGFloat = 38
    /// Room kept free under the card inside the slot, as the timer keeps under its composer.
    static let bottomClearance: CGFloat = 4

    /// What the Usage tab gets under a header `headerHeight` tall: 142 / 148 / 156.
    static func tabContentHeight(headerHeight: CGFloat) -> CGFloat {
        openNotchHeight - openNotchBottomPadding - headerHeight - notchLayoutSpacing
    }

    /// The slot every card is designed for.
    static var smallestTabContentHeight: CGFloat { tabContentHeight(headerHeight: notchedHeaderHeight) }

    /// The tallest a card may be.
    static var cardHeightLimit: CGFloat { smallestTabContentHeight - bottomClearance }

    // MARK: The tab

    /// `ContentView`'s padding inside the notch shape, both sides.
    static let openNotchHorizontalPadding: CGFloat = 12
    /// `ContentView.notchHorizontalPadding` while open with `cornerRadiusScaling` on (the
    /// default): 19 − 5. The window is exactly `openNotchSize.width` wide, so this is what the
    /// content gets — 588 pt of a 640 pt notch, measured; `TimerComposerMetrics` assumes 19 and
    /// a wider root, which the window caps.
    static let openNotchSideInset: CGFloat = 14
    static let tabHorizontalPadding: CGFloat = 8
    /// Between provider cards.
    static let cardSpacing: CGFloat = 10

    // MARK: One card

    static let cardCornerRadius: CGFloat = 10
    static let cardFill: Double = 0.06
    /// The composer's padding.
    static let cardPadding: CGFloat = 6
    static let rowSpacing: CGFloat = 6
    /// Icon, name, tier chip and the refresh glyph; the name field's height.
    static let headerRowHeight: CGFloat = 24
    static let providerIconSize: CGFloat = 20
    static let sectionTitleHeight: CGFloat = 14
    static let sectionTitleSpacing: CGFloat = 4
    /// `[label] [bar] [percent]` on one line.
    static let barRowHeight: CGFloat = 16
    static let barRowSpacing: CGFloat = 4
    static let barHeight: CGFloat = 4
    static let barTrackOpacity: Double = 0.12
    static let barMinimumFill: CGFloat = 4
    /// "All models" at 11 pt.
    static let barLabelWidth: CGFloat = 58
    /// "100%" at 12 pt, monospaced digits.
    static let percentWidth: CGFloat = 32
    /// A reset, a forecast, a Today/Week fact.
    static let noteRowHeight: CGFloat = 14
    static let noteRowSpacing: CGFloat = 2
    static let statusRowHeight: CGFloat = 16
    /// Between the 5-hour and the weekly column.
    static let columnSpacing: CGFloat = 10
    /// Below this the minor column cannot hold "resets in 4h 15m": the card stacks instead.
    static let minimumMinorColumnWidth: CGFloat = 88

    // MARK: Type and chips, the timer's scale

    static let titleFontSize: CGFloat = 13
    static let valueFontSize: CGFloat = 12
    static let textFontSize: CGFloat = 11
    static let glyphFontSize: CGFloat = 10
    static let chipPaddingHorizontal: CGFloat = 6
    static let chipPaddingVertical: CGFloat = 2
    static let chipFill: Double = 0.12
    /// A bar's dimming once its reading is stale.
    static let staleOpacity: Double = 0.55

    // MARK: Widths

    static let goldenRatio: CGFloat = 1.6180339887

    /// Two parts of `total` with `spacing` between them in the golden ratio, minor : major = 1 : φ,
    /// in whole points, rounded down so the major part takes the fraction.
    static func goldenSplit(_ total: CGFloat, spacing: CGFloat) -> (minor: CGFloat, major: CGFloat) {
        let parts = max(0, total - spacing)
        let minor = (parts / (1 + goldenRatio)).rounded(.down)
        return (minor, parts - minor)
    }

    /// The tab's width inside its padding, in an open notch `notchWidth` wide.
    static func tabWidth(notchWidth: CGFloat) -> CGFloat {
        notchWidth - openNotchHorizontalPadding * 2 - openNotchSideInset * 2 - tabHorizontalPadding * 2
    }

    /// One of `cards` cards sharing the tab, outside its padding.
    static func cardWidth(notchWidth: CGFloat, cards: Int) -> CGFloat {
        let count = CGFloat(max(1, cards))
        return ((tabWidth(notchWidth: notchWidth) - cardSpacing * (count - 1)) / count).rounded(.down)
    }

    /// The same card inside its padding: what its columns share.
    static func cardInnerWidth(notchWidth: CGFloat, cards: Int) -> CGFloat {
        cardWidth(notchWidth: notchWidth, cards: cards) - cardPadding * 2
    }

    /// The 5-hour and weekly columns across `innerWidth`, or nil when the minor one would be too
    /// narrow — then the card stacks its rows.
    static func columns(innerWidth: CGFloat) -> (minor: CGFloat, major: CGFloat)? {
        let split = goldenSplit(innerWidth, spacing: columnSpacing)
        return split.minor >= minimumMinorColumnWidth ? split : nil
    }

    // MARK: Heights

    /// A titled section of `bars` bar rows.
    static func sectionHeight(bars: Int) -> CGFloat {
        let rows = CGFloat(max(1, bars))
        return sectionTitleHeight + sectionTitleSpacing + barRowHeight * rows + barRowSpacing * (rows - 1)
    }

    /// The 5-hour column: title, bar, the reset, and room for one forecast line.
    static var fiveHourColumnHeight: CGFloat {
        sectionHeight(bars: 1) + (noteRowSpacing + noteRowHeight) * 2
    }

    /// The weekly column: title (with the reset beside it) and `bars` bars.
    static func weeklyColumnHeight(bars: Int) -> CGFloat {
        sectionHeight(bars: bars)
    }

    /// The split body is as tall as its taller column.
    static func splitBodyHeight(weeklyBars: Int) -> CGFloat {
        max(fiveHourColumnHeight, weeklyColumnHeight(bars: weeklyBars))
    }

    /// The stacked fallback: labelled bar rows with no title, then one reset line, all at the
    /// bar rows' spacing.
    static func stackedBodyHeight(bars: Int) -> CGFloat {
        let rows = CGFloat(max(1, bars))
        return barRowHeight * rows + barRowSpacing * rows + noteRowHeight
    }

    /// A card around `body`: padding, the header row, and the status row when there is one.
    static func cardHeight(body: CGFloat, statusRow: Bool) -> CGFloat {
        cardPadding * 2 + headerRowHeight + rowSpacing + body + (statusRow ? rowSpacing + statusRowHeight : 0)
    }

    /// The most weekly bars a split card draws and still fits; the rest fold into a "+n" chip.
    static func maxWeeklyBars(statusRow: Bool) -> Int {
        (1...8).last { cardHeight(body: splitBodyHeight(weeklyBars: $0), statusRow: statusRow) <= cardHeightLimit } ?? 1
    }

    /// The most bars a stacked card draws.
    static let maxStackedBars = 3
}
