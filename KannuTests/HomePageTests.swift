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

/// The open notch's media screen during a call: which pages exist, which one shows, and what a
/// two-finger swipe does. The swipe is `TimerSidePage`'s, so the same cases are asked of it.
final class HomePageTests: XCTestCase {
    // MARK: - Pages

    func testBothPagesExistOnlyWhileACallDoes() {
        XCTAssertEqual(HomePage.pages(hasCall: true), [.call, .media], "Call is the left-hand page")
        XCTAssertEqual(HomePage.pages(hasCall: false), [.media])
    }

    func testTheScreenOpensOnTheCall() {
        XCTAssertEqual(HomePage.initial(hasCall: true), .call)
        XCTAssertEqual(HomePage.initial(hasCall: false), .media)
    }

    /// A call that ended takes its page with it, whatever was chosen.
    func testWithNoCallTheShownPageIsMedia() {
        for selected in HomePage.allCases {
            XCTAssertEqual(HomePage.shown(selected: selected, hasCall: true), selected)
            XCTAssertEqual(HomePage.shown(selected: selected, hasCall: false), .media)
        }
    }

    /// The labels hang wholly below the screen's bottom line, so they never sit on the media
    /// buttons, and inside the open notch's 20 pt footer.
    func testTheLabelsHangInTheFooter() {
        XCTAssertLessThanOrEqual(HomePage.pagerHeight, HomePage.pagerFooterOffset)
        XCTAssertLessThanOrEqual(HomePage.pagerFooterOffset, 20)
    }

    // MARK: - Swipe

    func testFingersLeftBringInMediaAndFingersRightBringBackTheCall() {
        XCTAssertEqual(HomePage.swiped(from: .call, dx: -60, dy: 0), .media)
        XCTAssertEqual(HomePage.swiped(from: .media, dx: 60, dy: 0), .call)
    }

    func testASwipeTowardsTheShownPageDoesNothing() {
        XCTAssertNil(HomePage.swiped(from: .media, dx: -60, dy: 0))
        XCTAssertNil(HomePage.swiped(from: .call, dx: 60, dy: 0))
    }

    func testAShortOrSlantedGestureDoesNothing() {
        let threshold = HomePage.swipeThreshold
        XCTAssertNil(HomePage.swiped(from: .call, dx: -(threshold - 1), dy: 0))
        XCTAssertEqual(HomePage.swiped(from: .call, dx: -threshold, dy: 0), .media)
        // Not clearly sideways: a vertical scroll that drifts.
        XCTAssertNil(HomePage.swiped(from: .call, dx: -60, dy: 60))
        XCTAssertNil(HomePage.swiped(from: .call, dx: -60, dy: 60 / HomePage.swipeDominance))
        XCTAssertEqual(HomePage.swiped(from: .call, dx: -60, dy: 30), .media)
    }

    func testTheSwipeIsTheTimerTabs() {
        XCTAssertEqual(HomePage.swipeThreshold, TimerSidePage.swipeThreshold)
        XCTAssertEqual(HomePage.swipeDominance, TimerSidePage.swipeDominance)
    }

    func testAGestureAddsUpAcrossItsEvents() {
        var swipe = HomePageSwipe()
        XCTAssertNil(swipe.add(dx: -15, dy: 0, current: .call))
        XCTAssertNil(swipe.add(dx: -15, dy: 1, current: .call))
        XCTAssertEqual(swipe.add(dx: -15, dy: 0, current: .call), .media)
    }

    /// A long swipe that overshoots and comes back never flips the page twice.
    func testAGestureFlipsAtMostOnce() {
        var swipe = HomePageSwipe()
        XCTAssertEqual(swipe.add(dx: -80, dy: 0, current: .call), .media)
        XCTAssertNil(swipe.add(dx: 200, dy: 0, current: .media))
        XCTAssertTrue(swipe.hasFlipped)
    }

    func testResetStartsANewGesture() {
        var swipe = HomePageSwipe()
        _ = swipe.add(dx: -80, dy: 0, current: .call)
        swipe.reset()
        XCTAssertEqual(swipe, HomePageSwipe())
        XCTAssertEqual(swipe.add(dx: 80, dy: 0, current: .media), .call)
    }

    /// Vertical travel counts unsigned: a scroll down and back up never nets out to a swipe.
    func testVerticalTravelDoesNotCancelOut() {
        var swipe = HomePageSwipe()
        XCTAssertNil(swipe.add(dx: -20, dy: 40, current: .call))
        XCTAssertNil(swipe.add(dx: -30, dy: -40, current: .call))
        XCTAssertEqual(swipe.dy, 80)
    }
}
