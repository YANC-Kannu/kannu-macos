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

import Foundation

/// The pages of the open notch's media screen (`NotchHomeView`) while a call exists: Call, the
/// call's page, on the left, and Media, the music player, on the right. With no call there is one
/// page, Media, no labels and no page swipe: a sideways swipe skips tracks, as it always has.
///
/// Pure, in the logic target: which pages exist, which one shows, and what a two-finger swipe does.
/// The swipe is `TimerSidePage`'s, copied: same threshold, same dominance, same one flip a gesture.
enum HomePage: String, CaseIterable, Identifiable, Equatable {
    case call
    case media

    var id: String { rawValue }

    /// The pages the media screen has: both while a call exists, Media alone otherwise.
    static func pages(hasCall: Bool) -> [HomePage] {
        hasCall ? [.call, .media] : [.media]
    }

    /// The page the media screen opens on, and turns to when a call begins: the call's.
    static func initial(hasCall: Bool) -> HomePage {
        hasCall ? .call : .media
    }

    /// The page to draw for the one the user last chose. A call that ended takes its page with
    /// it, whatever was chosen.
    static func shown(selected: HomePage, hasCall: Bool) -> HomePage {
        hasCall ? selected : .media
    }

    // MARK: - Labels

    /// The "Call · Media" labels are an overlay of the screen, so they take no layout room: they
    /// hang below its bottom line, in the open notch's footer (the timer tab's pattern,
    /// `TimerComposerMetrics.sidePagerFooterOffset`).
    static let pagerHeight: Double = 14
    /// How far below the screen's bottom line the labels' bottom edge sits. The footer under that
    /// line is 20 pt (the screen's 8 pt padding and the open notch's 12 pt), so 14 leaves 6.
    static let pagerFooterOffset: Double = 14

    // MARK: - Swipe

    /// How far one gesture must travel sideways, in points, before it changes the page.
    static let swipeThreshold: Double = 40
    /// How much more sideways than vertical a gesture must be.
    static let swipeDominance: Double = 1.5

    /// The page one gesture's accumulated deltas lead to, or nil when they lead nowhere new.
    ///
    /// `dx` and `dy` are in AppKit's natural-scrolling sense: fingers moving left give a negative
    /// `dx`, which brings in the right-hand page (Media); fingers moving right bring back Call.
    /// Only a clearly horizontal gesture of at least `threshold` points counts.
    static func swiped(
        from current: HomePage,
        dx: Double,
        dy: Double,
        threshold: Double = swipeThreshold
    ) -> HomePage? {
        guard abs(dx) >= threshold, abs(dx) > abs(dy) * swipeDominance else { return nil }
        let target: HomePage = dx < 0 ? .media : .call
        return target == current ? nil : target
    }
}

/// One two-finger gesture over the media screen, from its first event to its last: the deltas so
/// far, and whether it already changed the page. A gesture changes the page at most once.
struct HomePageSwipe: Equatable {
    /// Net sideways travel, signed.
    private(set) var dx: Double = 0
    /// Total vertical travel, unsigned.
    private(set) var dy: Double = 0
    private(set) var hasFlipped = false

    /// A new gesture began (or the last one ended): nothing counted yet.
    mutating func reset() {
        self = HomePageSwipe()
    }

    /// Adds one event's deltas (natural-scrolling sense). Returns the page to show, at most once
    /// per gesture.
    mutating func add(dx: Double, dy: Double, current: HomePage) -> HomePage? {
        self.dx += dx
        self.dy += abs(dy)
        guard !hasFlipped, let page = HomePage.swiped(from: current, dx: self.dx, dy: self.dy) else {
            return nil
        }
        hasFlipped = true
        return page
    }
}
