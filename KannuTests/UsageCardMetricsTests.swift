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

import XCTest

/// The Usage tab's provider cards fit the open notch, whose height never changes for them, and
/// split in the golden ratio. Pinned here so a row that grows shows up as a number, not as a card
/// running into the notch's shadow band.
final class UsageCardMetricsTests: XCTestCase {
    private typealias M = UsageCardMetrics

    func testTheSlotArithmetic() {
        XCTAssertEqual(M.tabContentHeight(headerHeight: 38), 142)
        XCTAssertEqual(M.tabContentHeight(headerHeight: 32), 148)
        XCTAssertEqual(M.tabContentHeight(headerHeight: 24), 156)
        XCTAssertEqual(M.smallestTabContentHeight, 142)
        XCTAssertEqual(M.cardHeightLimit, 138)
    }

    func testTheClaudeCardFitsTheSmallestSlot() {
        // Every number of weekly bars the card draws, with and without a status row.
        for statusRow in [false, true] {
            let bars = M.maxWeeklyBars(statusRow: statusRow)
            XCTAssertGreaterThanOrEqual(bars, 3, "three weekly bars (all models, Fable, one more) must fit")
            for n in 1...bars {
                let height = M.cardHeight(body: M.splitBodyHeight(weeklyBars: n), statusRow: statusRow)
                XCTAssertLessThanOrEqual(height, M.cardHeightLimit, "\(n) weekly bars, status \(statusRow): \(height)")
            }
        }
        // The worst cases, pinned so a changed row size is a deliberate edit.
        XCTAssertEqual(M.cardHeight(body: M.splitBodyHeight(weeklyBars: 3), statusRow: true), 138)
        XCTAssertEqual(M.cardHeight(body: M.splitBodyHeight(weeklyBars: 4), statusRow: false), 136)
        XCTAssertEqual(M.maxWeeklyBars(statusRow: true), 3)
        XCTAssertEqual(M.maxWeeklyBars(statusRow: false), 4)
        // Two bars, the common case, with a status row.
        XCTAssertEqual(M.cardHeight(body: M.splitBodyHeight(weeklyBars: 2), statusRow: true), 130)
    }

    /// CodeRabbit on #113: Codex's and Cursor's weekly column also draws two token-total rows. Left
    /// out of the budget, Cursor's Auto and API bars with a status row made a 150 pt card.
    func testTheTokenTotalsCountInTheWeeklyBudget() {
        for statusRow in [false, true] {
            for n in 1...M.maxWeeklyBars(statusRow: statusRow, factRows: 2) {
                let height = M.cardHeight(body: M.splitBodyHeight(weeklyBars: n, factRows: 2), statusRow: statusRow)
                XCTAssertLessThanOrEqual(height, M.cardHeightLimit, "\(n) weekly bars and the totals, status \(statusRow)")
            }
        }
        XCTAssertEqual(M.maxWeeklyBars(statusRow: true, factRows: 2), 1)
        XCTAssertEqual(M.maxWeeklyBars(statusRow: false, factRows: 2), 2)
        XCTAssertEqual(M.cardHeight(body: M.splitBodyHeight(weeklyBars: 2, factRows: 2), statusRow: true), 150,
                       "the overflow the review found, now folded into the chip")
        XCTAssertEqual(M.maxWeeklyBars(statusRow: true), 3, "Claude's budget is unchanged")
    }

    func testTheFiveHourColumnSetsTheHeightUpToTwoWeeklyBars() {
        XCTAssertEqual(M.fiveHourColumnHeight, 66)
        XCTAssertEqual(M.weeklyColumnHeight(bars: 2), 54)
        XCTAssertEqual(M.weeklyColumnHeight(bars: 3), 74)
        XCTAssertEqual(M.splitBodyHeight(weeklyBars: 2), 66)
        XCTAssertEqual(M.splitBodyHeight(weeklyBars: 3), 74)
    }

    func testTheStackedFallbackFits() {
        let height = M.cardHeight(body: M.stackedBodyHeight(bars: M.maxStackedBars), statusRow: true)
        XCTAssertEqual(height, 138)
        XCTAssertLessThanOrEqual(height, M.cardHeightLimit)
    }

    func testTheColumnsSplitInTheGoldenRatio() {
        // One Claude card and two cards (Claude and Cursor) at the two standard notch widths.
        let cases: [(notch: CGFloat, cards: Int, minor: CGFloat, major: CGFloat)] = [
            (640, 1, 210, 340), (640, 2, 98, 161), (690, 1, 229, 371), (690, 2, 108, 176)
        ]
        for c in cases {
            let inner = M.cardInnerWidth(notchWidth: c.notch, cards: c.cards)
            let split = M.columns(innerWidth: inner)
            XCTAssertEqual(split?.minor, c.minor, "\(c.notch) × \(c.cards)")
            XCTAssertEqual(split?.major, c.major, "\(c.notch) × \(c.cards)")
            XCTAssertEqual((split?.minor ?? 0) + (split?.major ?? 0) + M.columnSpacing, inner)
            // Whole points, the minor part rounded down as the timer's split is (the major part
            // takes the fraction), so the ratio errs upward by less than one point's worth of the
            // minor column: (1 + φ) / minor, about 0.027 at 98 pt.
            let exactMinor = (inner - M.columnSpacing) / (1 + M.goldenRatio)
            XCTAssertEqual(split?.minor, exactMinor.rounded(.down), "\(c.notch) × \(c.cards)")
            let error = ((split?.major ?? 0) / (split?.minor ?? 1)) - M.goldenRatio
            XCTAssertGreaterThanOrEqual(error, 0, "\(c.notch) × \(c.cards)")
            XCTAssertLessThan(error, (1 + M.goldenRatio) / (split?.minor ?? 1), "\(c.notch) × \(c.cards)")
            XCTAssertEqual(split?.minor, split?.minor.rounded(), "whole points")
        }
    }

    func testThreeCardsStackAndTwoSplit() {
        XCTAssertNil(M.columns(innerWidth: M.cardInnerWidth(notchWidth: 640, cards: 3)))
        XCTAssertNil(M.columns(innerWidth: M.cardInnerWidth(notchWidth: 690, cards: 3)))
        XCTAssertNotNil(M.columns(innerWidth: M.cardInnerWidth(notchWidth: 640, cards: 2)))
        XCTAssertNotNil(M.columns(innerWidth: M.cardInnerWidth(notchWidth: 850, cards: 3)))
        XCTAssertEqual(M.cardInnerWidth(notchWidth: 640, cards: 1), 560)
        XCTAssertEqual(M.cardInnerWidth(notchWidth: 640, cards: 2), 269)
    }

    func testTheRowsStayReadable() {
        XCTAssertGreaterThanOrEqual(M.barRowHeight, 16)
        XCTAssertGreaterThanOrEqual(M.noteRowHeight, 14)
        XCTAssertGreaterThanOrEqual(M.headerRowHeight, 24)
        XCTAssertGreaterThanOrEqual(M.barLabelWidth, 58)
        XCTAssertEqual(M.cardPadding, 6, "the composer's padding")
        XCTAssertEqual(M.barHeight, 4, "the timer's bar")
        XCTAssertLessThan(M.glyphFontSize, M.textFontSize)
        XCTAssertLessThan(M.textFontSize, M.valueFontSize)
        XCTAssertLessThan(M.valueFontSize, M.titleFontSize)
    }

    func testGoldenSplitIsTheTimersSplit() {
        for (total, spacing) in [(CGFloat(570), CGFloat(41)), (269, 10), (560, 10), (5, 10)] {
            let usage = M.goldenSplit(total, spacing: spacing)
            let timer = TimerComposerMetrics.goldenSplit(total, spacing: spacing)
            XCTAssertEqual(usage.minor, timer.minor)
            XCTAssertEqual(usage.major, timer.major)
        }
        // The timer's own numbers: 529 pt of columns around a 41 pt gap give 202 : 327.
        let split = M.goldenSplit(570, spacing: 41)
        XCTAssertEqual(split.minor, 202)
        XCTAssertEqual(split.major, 327)
        XCTAssertEqual(M.goldenSplit(5, spacing: 10).minor, 0, "never negative")
    }
}
