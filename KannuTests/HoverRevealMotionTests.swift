//
//  HoverRevealMotionTests.swift
//  KannuTests
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest

/// When clipped text slides on hover, and how fast: only text clipped by more than a point, never
/// under Reduce Motion, at an even speed clamped so short text does not jump and long text does
/// not crawl.
final class HoverRevealMotionTests: XCTestCase {
    func testOnlyClippedTextSlidesAndNeverUnderReduceMotion() {
        XCTAssertTrue(HoverRevealMotion.shouldReveal(overflow: 40, reduceMotion: false))
        XCTAssertFalse(HoverRevealMotion.shouldReveal(overflow: 40, reduceMotion: true), "Reduce Motion: it stays still")
        XCTAssertFalse(HoverRevealMotion.shouldReveal(overflow: 0, reduceMotion: false), "nothing clipped, nothing to slide")
        XCTAssertFalse(HoverRevealMotion.shouldReveal(overflow: 0.5, reduceMotion: false), "half a point is rounding, not clipping")
        XCTAssertFalse(HoverRevealMotion.shouldReveal(overflow: -12, reduceMotion: false))
    }

    func testTravelIsEvenSpeedClampedAtBothEnds() {
        XCTAssertEqual(HoverRevealMotion.travelDuration(distance: 60, pointsPerSecond: 30), 2, accuracy: 0.001)
        XCTAssertEqual(HoverRevealMotion.travelDuration(distance: 5, pointsPerSecond: 30),
                       HoverRevealMotion.shortestTravel, "a few points never jumps")
        XCTAssertEqual(HoverRevealMotion.travelDuration(distance: 2_000, pointsPerSecond: 30),
                       HoverRevealMotion.longestTravel, "a very long text never crawls for minutes")
        XCTAssertEqual(HoverRevealMotion.travelDuration(distance: 60, pointsPerSecond: 0), HoverRevealMotion.shortestTravel)
    }

    func testTitlesSlideSlowerThanOneLine() {
        XCTAssertLessThan(HoverRevealMotion.verticalPointsPerSecond, HoverRevealMotion.horizontalPointsPerSecond,
                          "a line at a time, read whole")
        XCTAssertEqual(HoverRevealMotion.startDelay, 0.4, "the tooltip's own pause: brushing past starts nothing")
    }
}
