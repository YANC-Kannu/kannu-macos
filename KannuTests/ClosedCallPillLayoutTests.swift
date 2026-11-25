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

/// The call pill's arithmetic: equal wings around the housing, the app's icon left, the phone glyph
/// and the elapsed time right.
final class ClosedCallPillLayoutTests: XCTestCase {
    typealias L = ClosedCallPillLayout

    private func pill(height: CGFloat = 32, housing: CGFloat = 185, time: Bool = true, camera: Bool = false) -> L {
        L(closedHeight: height, housingWidth: housing, showsTime: time, showsCamera: camera)
    }

    /// The agent pill's icon, so the two pills swap without the icon changing size.
    func testTheIconIsTheAgentPillsIcon() {
        for height: CGFloat in [0, 12, 24, 32, 38, 44] {
            XCTAssertEqual(pill(height: height).iconSize, ClosedAgentPillLayout.iconSize(closedHeight: height))
        }
        XCTAssertEqual(pill(height: 32).iconSize, 16)
        XCTAssertEqual(L.wingPadding, ClosedAgentPillLayout.wingPadding)
    }

    func testTheRightWingHoldsTheGlyphThenTheTimeThenTheCamera() {
        XCTAssertEqual(pill(time: false).rightContentWidth, L.glyphWidth, "ringing: the glyph alone")
        XCTAssertEqual(pill(time: true).rightContentWidth, L.glyphWidth + L.spacing + L.timeWidth)
        XCTAssertEqual(pill(time: true, camera: true).rightContentWidth,
                       L.glyphWidth + L.spacing + L.timeWidth + L.spacing + L.glyphWidth)
        XCTAssertEqual(pill(time: false, camera: true).rightContentWidth, L.glyphWidth + L.spacing + L.glyphWidth)
    }

    /// On a 32 pt notch: 62 | housing | 62 with the time, 28 | housing | 28 while it rings.
    func testEachWingFitsTheWiderSidePlusPadding() {
        XCTAssertEqual(pill(height: 32, time: true).wingWidth, 62)
        XCTAssertEqual(pill(height: 32, time: true).width, 185 + 124)
        XCTAssertEqual(pill(height: 32, time: true, camera: true).wingWidth, 78)
        XCTAssertEqual(pill(height: 32, time: false).wingWidth, 28, "the 16 pt icon is wider than the 12 pt glyph")
        XCTAssertEqual(pill(height: 20, time: false).wingWidth, 24, "the glyph is wider than a 4 pt icon")
    }

    /// The time's slot is fixed, so the pill is one width for the whole call.
    func testTheTimeSlotFitsAnHourOfMinutesAtElevenPoints() {
        // "59:59" in an 11 pt face with 7 pt digits: four digits and a colon.
        XCTAssertGreaterThanOrEqual(L.timeWidth, 4 * 7 + 3)
        XCTAssertLessThanOrEqual(L.timeWidth, 40, "a wider slot is the plan's cue to drop the time and keep the glyph")
    }

    func testThePillIsTheHousingAndTwoEqualWings() {
        for height: CGFloat in [0, 24, 32, 37, 38, 44] {
            for time in [false, true] {
                for camera in [false, true] {
                    let p = pill(height: height, housing: 185, time: time, camera: camera)
                    XCTAssertEqual(p.width, 185 + 2 * p.wingWidth, accuracy: 1e-9)
                    // The housing is centred on the pill, whatever the wings hold.
                    XCTAssertEqual(p.wingWidth + p.housingWidth / 2, p.width / 2, accuracy: 1e-9)
                    // Both sides sit inside their wings, centred.
                    XCTAssertEqual(p.iconRect.midX, p.wingWidth / 2, accuracy: 1e-9)
                    XCTAssertEqual(p.rightContentRect.midX, p.width - p.wingWidth / 2, accuracy: 1e-9)
                    XCTAssertGreaterThanOrEqual(p.iconRect.minX, 0)
                    XCTAssertLessThanOrEqual(p.rightContentRect.maxX, p.width + 1e-9)
                    XCTAssertEqual(p.iconRect.midY, p.closedHeight / 2, accuracy: 1e-9)
                }
            }
        }
    }

    func testNegativeInputsClampToZero() {
        let p = L(closedHeight: -4, housingWidth: -10, showsTime: false, showsCamera: false)
        XCTAssertEqual(p.closedHeight, 0)
        XCTAssertEqual(p.housingWidth, 0)
        XCTAssertEqual(p.iconSize, 0)
        XCTAssertEqual(p.width, 2 * p.wingWidth)
    }
}
