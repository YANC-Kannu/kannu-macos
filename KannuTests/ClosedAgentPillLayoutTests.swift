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

/// The sideways agent pill's arithmetic: equal wings around the housing, one dot left, one icon right.
final class ClosedAgentPillLayoutTests: XCTestCase {
    typealias L = ClosedAgentPillLayout

    private func pill(height: CGFloat = 32, housing: CGFloat = 185, shield: Bool = false) -> L {
        L(closedHeight: height, housingWidth: housing, showsShield: shield)
    }

    /// 2026-11-18, David: "reduce the logo size a bit". 16 pt on a 32 pt notch, down from 20.
    func testTheIconIsTheClosedHeightLessSixteen() {
        XCTAssertEqual(L.iconInset, 16)
        XCTAssertEqual(pill(height: 32).iconSize, 16)
        XCTAssertEqual(pill(height: 38).iconSize, 22)
        XCTAssertEqual(pill(height: 12).iconSize, 0, "never negative")
        XCTAssertEqual(L.iconSize(closedHeight: 32), 16, "the lock pill sizes its icon the same way")
    }

    /// The plan's figures: 28 | housing | 28 on a 32 pt notch.
    func testEachWingFitsTheWiderOfItsContentsPlusPadding() {
        XCTAssertEqual(pill(height: 32).wingWidth, 28, "the 16 pt icon is wider than the 10 pt dot")
        XCTAssertEqual(pill(height: 32).width, 185 + 56)
        XCTAssertEqual(pill(height: 38).wingWidth, 34)
        XCTAssertEqual(pill(height: 24).wingWidth, 22, "the dot is wider than an 8 pt icon")
    }

    func testTheShieldWidensBothWingsAndKeepsTheHousingCentred() {
        let plain = pill()
        let shielded = pill(shield: true)
        XCTAssertEqual(shielded.leftContentWidth, L.dotSize + L.shieldSpacing + L.shieldWidth)
        XCTAssertEqual(shielded.wingWidth, 38)
        XCTAssertGreaterThan(shielded.width, plain.width)
    }

    func testThePillIsTheHousingAndTwoEqualWings() {
        for height: CGFloat in [0, 24, 32, 37, 38, 44] {
            for shield in [false, true] {
                let p = pill(height: height, housing: 185, shield: shield)
                XCTAssertEqual(p.width, 185 + 2 * p.wingWidth, accuracy: 1e-9)
                // The housing is centred: the icon's wing mirrors the dot's wing.
                let housingMid = p.wingWidth + p.housingWidth / 2
                XCTAssertEqual(housingMid, p.width / 2, accuracy: 1e-9)
            }
        }
    }

    func testTheContentStaysInsideItsWing() {
        for height: CGFloat in [24, 32, 38] {
            for shield in [false, true] {
                let p = pill(height: height, shield: shield)
                XCTAssertGreaterThanOrEqual(p.leftContentRect.minX, L.wingPadding - 1e-9)
                XCTAssertLessThanOrEqual(p.leftContentRect.maxX, p.wingWidth - L.wingPadding + 1e-9)
                XCTAssertGreaterThanOrEqual(p.iconRect.minX, p.wingWidth + p.housingWidth + L.wingPadding - 1e-9)
                XCTAssertLessThanOrEqual(p.iconRect.maxX, p.width - L.wingPadding + 1e-9)
                XCTAssertEqual(p.iconRect.midY, height / 2, accuracy: 1e-9)
                XCTAssertEqual(p.leftContentRect.midY, height / 2, accuracy: 1e-9)
            }
        }
    }

    func testNegativeInputsClampToZero() {
        let p = L(closedHeight: -4, housingWidth: -10, showsShield: false)
        XCTAssertEqual(p.iconSize, 0)
        XCTAssertEqual(p.housingWidth, 0)
        XCTAssertEqual(p.width, 2 * (L.dotSize + 2 * L.wingPadding))
    }
}
