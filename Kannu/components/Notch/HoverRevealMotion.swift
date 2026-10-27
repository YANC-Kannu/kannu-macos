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

/// The timing of `HoverRevealText`'s slide, pure so it is tested: when a clipped text slides at
/// all, how long it waits, how fast it travels, how long it holds at the end, how fast it returns.
///
/// One slide per hover: wait `startDelay` (brushing past shows nothing), travel to the end at an
/// even reading speed, hold `holdAtEnd`, ease back in `returnDuration`. No loop and no timer, so a
/// card at rest costs nothing.
enum HoverRevealMotion {
    /// The same pause as a hover tooltip: brushing past a row never starts a slide.
    static let startDelay: TimeInterval = 0.4
    static let holdAtEnd: TimeInterval = 1.0
    static let returnDuration: TimeInterval = 0.35
    /// Sideways, for one line.
    static let horizontalPointsPerSecond: Double = 30
    /// Upwards, for a title over several lines: slower, a line at a time is read whole.
    static let verticalPointsPerSecond: Double = 18
    static let shortestTravel: TimeInterval = 0.6
    static let longestTravel: TimeInterval = 8

    /// Only text that is clipped by more than a point slides, and never under Reduce Motion.
    static func shouldReveal(overflow: Double, reduceMotion: Bool) -> Bool {
        !reduceMotion && overflow > 1
    }

    /// How long the travel to the end takes: the distance at an even speed, never so short it jumps
    /// nor so long a title takes forever.
    static func travelDuration(distance: Double, pointsPerSecond: Double) -> TimeInterval {
        guard pointsPerSecond > 0 else { return shortestTravel }
        return min(longestTravel, max(shortestTravel, distance / pointsPerSecond))
    }
}
