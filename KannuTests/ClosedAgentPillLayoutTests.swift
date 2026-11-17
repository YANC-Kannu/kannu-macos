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

/// The sideways agent pill's arithmetic: equal wings around the housing, the dots left, one icon right.
final class ClosedAgentPillLayoutTests: XCTestCase {
    typealias L = ClosedAgentPillLayout

    private func pill(height: CGFloat = 32, housing: CGFloat = 185, dots: Int = 1, shield: Bool = false) -> L {
        L(closedHeight: height, housingWidth: housing, dotCount: dots, showsShield: shield)
    }

    func testTheIconIsTheClosedHeightLessTwelve() {
        XCTAssertEqual(pill(height: 32).iconSize, 20)
        XCTAssertEqual(pill(height: 38).iconSize, 26)
        XCTAssertEqual(pill(height: 8).iconSize, 0, "never negative")
    }

    func testTheDotsAreWhatTheBandDraws() {
        XCTAssertEqual(pill(dots: 1).dotsWidth, 10)
        XCTAssertEqual(pill(dots: 3).dotsWidth, 42, "three 10 pt dots, two 6 pt gaps")
        XCTAssertEqual(pill(dots: 0).dotsWidth, 0)
    }

    /// The plan's figures: about 32 pt a wing for Minimal, 54 pt for Classic, on a 32 pt notch.
    func testEachWingFitsTheWiderOfItsContentsPlusPadding() {
        XCTAssertEqual(pill(height: 32, dots: 1).wingWidth, 32, "the 20 pt icon is wider than one dot")
        XCTAssertEqual(pill(height: 32, dots: 3).wingWidth, 54, "three dots are wider than the icon")
        XCTAssertEqual(pill(height: 38, dots: 1).wingWidth, 38)
        XCTAssertEqual(pill(height: 38, dots: 3).wingWidth, 54)
    }

    func testTheShieldWidensBothWingsAndKeepsTheHousingCentred() {
        let plain = pill(dots: 1)
        let shielded = pill(dots: 1, shield: true)
        XCTAssertEqual(shielded.leftContentWidth, 10 + L.shieldSpacing + L.shieldWidth)
        XCTAssertEqual(shielded.wingWidth, 38)
        XCTAssertGreaterThan(shielded.width, plain.width)
        XCTAssertEqual(pill(dots: 0, shield: true).leftContentWidth, L.shieldWidth, "no gap before a shield alone")
    }

    func testThePillIsTheHousingAndTwoEqualWings() {
        for height: CGFloat in [0, 24, 32, 37, 38, 44] {
            for dots in [1, 3] {
                for shield in [false, true] {
                    let p = pill(height: height, housing: 185, dots: dots, shield: shield)
                    XCTAssertEqual(p.width, 185 + 2 * p.wingWidth, accuracy: 1e-9)
                    // The housing is centred: the icon's wing mirrors the dots' wing.
                    let housingMid = p.wingWidth + p.housingWidth / 2
                    XCTAssertEqual(housingMid, p.width / 2, accuracy: 1e-9)
                }
            }
        }
    }

    func testTheContentStaysInsideItsWing() {
        for height: CGFloat in [24, 32, 38] {
            for dots in [1, 3] {
                for shield in [false, true] {
                    let p = pill(height: height, dots: dots, shield: shield)
                    XCTAssertGreaterThanOrEqual(p.leftContentRect.minX, L.wingPadding - 1e-9)
                    XCTAssertLessThanOrEqual(p.leftContentRect.maxX, p.wingWidth - L.wingPadding + 1e-9)
                    XCTAssertGreaterThanOrEqual(p.iconRect.minX, p.wingWidth + p.housingWidth + L.wingPadding - 1e-9)
                    XCTAssertLessThanOrEqual(p.iconRect.maxX, p.width - L.wingPadding + 1e-9)
                    XCTAssertEqual(p.iconRect.midY, height / 2, accuracy: 1e-9)
                    XCTAssertEqual(p.leftContentRect.midY, height / 2, accuracy: 1e-9)
                }
            }
        }
    }

    func testNegativeInputsClampToZero() {
        let p = L(closedHeight: -4, housingWidth: -10, dotCount: -2, showsShield: false)
        XCTAssertEqual(p.iconSize, 0)
        XCTAssertEqual(p.dotsWidth, 0)
        XCTAssertEqual(p.width, 2 * L.wingPadding * 2)
    }
}
