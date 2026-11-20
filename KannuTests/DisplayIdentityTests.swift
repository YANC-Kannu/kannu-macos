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

/// Issue #24: the notch's screen was picked, stored and matched by `localizedName`, which two
/// identical monitors share. Every case here is a fixture, because the bug needs two monitors with
/// one name and the Mac this runs on may have one display.
final class DisplayIdentityTests: XCTestCase {

    private let builtIn = ScreenFacts(id: 1, name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true,
                                      frame: CGRect(x: 0, y: 0, width: 1512, height: 982), uuid: "UUID-BUILT-IN")
    /// Two identical monitors, side by side to the right of the laptop.
    private let left = ScreenFacts(id: 7, name: "DELL U2720Q", isBuiltIn: false,
                                   frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), uuid: "UUID-DELL-A")
    private let right = ScreenFacts(id: 8, name: "DELL U2720Q", isBuiltIn: false,
                                    frame: CGRect(x: 4072, y: 0, width: 2560, height: 1440), uuid: "UUID-DELL-B")
    private let studio = ScreenFacts(id: 3, name: "Studio Display", isBuiltIn: false,
                                     frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), uuid: "UUID-STUDIO")

    private func choose(_ screens: [ScreenFacts], uuid: String?, legacyName: String? = nil,
                        main: CGDirectDisplayID? = 1) -> [CGDirectDisplayID] {
        DisplayPlacementResolver.screensToShowOn(screens, mode: .chooseDisplay, chosenUUID: uuid,
                                                 chosenName: legacyName, mainScreen: main)
    }

    // MARK: - Two displays, one name

    func testTwoDisplaysWithOneNameResolveToTwoScreens() {
        let screens = [builtIn, left, right]
        XCTAssertEqual(DisplayPlacementResolver.screen(withID: 7, in: screens), left)
        XCTAssertEqual(DisplayPlacementResolver.screen(withID: 8, in: screens), right,
                       "the second monitor must not resolve to the first one with its name")
        XCTAssertNil(DisplayPlacementResolver.screen(withID: 99, in: screens), "a gone display is gone, not a namesake")
        XCTAssertNil(DisplayPlacementResolver.screen(withID: nil, in: screens))
    }

    func testEitherOfTwoIdenticalMonitorsCanBeChosen() {
        XCTAssertEqual(choose([builtIn, left, right], uuid: "UUID-DELL-A"), [7])
        XCTAssertEqual(choose([builtIn, left, right], uuid: "UUID-DELL-B"), [8])
    }

    func testThePickerListsIdenticalMonitorsAsTwoChoices() {
        XCTAssertEqual(DisplayPlacementResolver.pickerTitles([builtIn, left, right]),
                       ["Built-in Retina Display", "DELL U2720Q (1)", "DELL U2720Q (2)"])
        XCTAssertEqual(DisplayPlacementResolver.pickerTitles([builtIn, studio]),
                       ["Built-in Retina Display", "Studio Display"], "a unique name is not numbered")
    }

    // MARK: - The pointer check reads each display's own frame

    /// `isPointerOnOpenNotch` builds the open body's rectangle from its own display's frame, found
    /// by id. By name, the right monitor measured its notch on the left one: the pointer on its
    /// body was "off the notch", and the notch closed under it.
    func testThePointerCheckUsesEachDisplaysOwnFrame() throws {
        let screens = [builtIn, left, right]
        let body = CGRect(x: 0, y: 0, width: 640, height: 200)

        let rightNotch = try XCTUnwrap(NotchInteractionGeometry.openNotchRect(
            screenFrame: try XCTUnwrap(DisplayPlacementResolver.screen(withID: 8, in: screens)).frame, bodyInWindow: body))
        let leftNotch = try XCTUnwrap(NotchInteractionGeometry.openNotchRect(
            screenFrame: try XCTUnwrap(DisplayPlacementResolver.screen(withID: 7, in: screens)).frame, bodyInWindow: body))

        let onRightBody = CGPoint(x: right.frame.midX, y: right.frame.maxY - 100)
        let onLeftBody = CGPoint(x: left.frame.midX, y: left.frame.maxY - 100)

        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(onRightBody, notch: rightNotch))
        XCTAssertFalse(NotchInteractionGeometry.isOnOpenNotch(onLeftBody, notch: rightNotch),
                       "the pointer over the other monitor's notch is not on this one")
        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(onLeftBody, notch: leftNotch))
        XCTAssertFalse(NotchInteractionGeometry.isOnOpenNotch(onRightBody, notch: leftNotch))

        // The bug, planted: the right view resolving its screen by name gets the left frame.
        let byName = try XCTUnwrap(screens.first { $0.name == right.name })
        let wrongNotch = try XCTUnwrap(NotchInteractionGeometry.openNotchRect(screenFrame: byName.frame, bodyInWindow: body))
        XCTAssertFalse(NotchInteractionGeometry.isOnOpenNotch(onRightBody, notch: wrongNotch),
                       "the planted name lookup must reproduce the bug, or this test proves nothing")
    }

    // MARK: - The fullscreen verdict is per display

    func testAFullscreenAppOnOneOfTwoIdenticalMonitorsHidesOnlyThatNotch() {
        let status: [CGDirectDisplayID: Bool] = [1: false, 7: true, 8: false]
        XCTAssertTrue(ClosedNotchVisibility.shouldHideClosedNotch(detectionEnabled: true, screen: 7, fullscreenStatus: status))
        XCTAssertFalse(ClosedNotchVisibility.shouldHideClosedNotch(detectionEnabled: true, screen: 8, fullscreenStatus: status))
    }

    // MARK: - The old preference carries over

    func testAConnectedLegacyChoiceIsStoredByUUID() {
        XCTAssertEqual(DisplayPlacementResolver.chosenDisplayUUID(
            storedUUID: nil, legacyName: "Studio Display", screens: [builtIn, studio]), "UUID-STUDIO")
        XCTAssertEqual(choose([builtIn, studio], uuid: nil, legacyName: "Studio Display"), [3],
                       "until the UUID is stored, the name still finds the display")
    }

    /// The dock may wake after launch: storing nothing keeps the name for the next look, and the
    /// notch waits on the main display meanwhile.
    func testAnUnconnectedLegacyChoiceFallsBackToMainAndStoresNothing() {
        XCTAssertNil(DisplayPlacementResolver.chosenDisplayUUID(
            storedUUID: nil, legacyName: "Studio Display", screens: [builtIn]))
        XCTAssertEqual(choose([builtIn], uuid: nil, legacyName: "Studio Display"), [1])
        XCTAssertEqual(DisplayPlacementResolver.chosenDisplayUUID(
            storedUUID: nil, legacyName: "Studio Display", screens: [builtIn, studio]), "UUID-STUDIO",
                       "the monitor waking later is still honoured")
    }

    func testNoChoiceAtAllIsTheMainDisplay() {
        XCTAssertNil(DisplayPlacementResolver.chosenDisplayUUID(storedUUID: nil, legacyName: nil, screens: [builtIn, studio]))
        XCTAssertEqual(choose([builtIn, studio], uuid: nil, main: 3), [3])
    }

    /// A legacy name shared by two monitors can only pick one: the first, as the old lookup did.
    /// Once that UUID is stored, the other one can no longer take its place.
    func testALegacyNameSharedByTwoMonitorsPicksTheFirstOnce() {
        let stored = DisplayPlacementResolver.chosenDisplayUUID(storedUUID: nil, legacyName: "DELL U2720Q",
                                                                screens: [builtIn, left, right])
        XCTAssertEqual(stored, "UUID-DELL-A")
        XCTAssertEqual(choose([builtIn, right], uuid: stored, legacyName: "DELL U2720Q"), [1],
                       "with the chosen one unplugged, its namesake must not take over")
    }

    func testAStoredUUIDWinsOverTheLegacyName() {
        XCTAssertEqual(DisplayPlacementResolver.chosenDisplayUUID(
            storedUUID: "UUID-DELL-B", legacyName: "Studio Display", screens: [builtIn, studio, right]), "UUID-DELL-B")
        XCTAssertEqual(choose([builtIn, studio, right], uuid: "UUID-DELL-B", legacyName: "Studio Display"), [8])
    }

    // MARK: - Reconnects

    /// A `CGDirectDisplayID` is not promised across a reconnect. The stored UUID is, so the choice
    /// follows the monitor to its new id, and an unplugged choice falls back without being lost.
    func testTheChoiceFollowsAReconnectUnderANewID() {
        let uuid = "UUID-DELL-B"
        XCTAssertEqual(choose([builtIn, left, right], uuid: uuid), [8])

        // Unplugged: main display, and the stored choice is untouched.
        XCTAssertEqual(choose([builtIn, left], uuid: uuid), [1])
        XCTAssertEqual(DisplayPlacementResolver.chosenDisplayUUID(storedUUID: uuid, legacyName: "DELL U2720Q",
                                                                  screens: [builtIn, left]), uuid)

        // Back, through another port: same monitor, same UUID, new id.
        let replugged = ScreenFacts(id: 12, name: "DELL U2720Q", isBuiltIn: false, frame: right.frame, uuid: uuid)
        XCTAssertEqual(choose([builtIn, left, replugged], uuid: uuid), [12])
        XCTAssertNil(DisplayPlacementResolver.screen(withID: 8, in: [builtIn, left, replugged]),
                     "a view model still holding the old id finds nothing, not the left monitor")
    }

    // MARK: - PR #80 review: what follows the notch when it moves

    private struct Metrics: Equatable { let width: CGFloat }

    /// The timer and music controls skipped a refresh when the metrics matched, so a notch that
    /// moved to an equal-sized display left its control window behind.
    func testAControlWindowRefreshFollowsTheNotchToAnotherDisplay() {
        let same = Metrics(width: 200)
        XCTAssertTrue(DisplayPlacementResolver.canSkipRefresh(last: (same, 7), next: (same, 7)))
        XCTAssertFalse(DisplayPlacementResolver.canSkipRefresh(last: (same, 7), next: (same, 8)),
                       "equal metrics on another display must still move the window")
        XCTAssertFalse(DisplayPlacementResolver.canSkipRefresh(last: (same, 8), next: (same, 12)),
                       "the same monitor back under a new id is a move too")
        XCTAssertFalse(DisplayPlacementResolver.canSkipRefresh(last: (same, 7), next: (Metrics(width: 220), 7)))
        XCTAssertFalse(DisplayPlacementResolver.canSkipRefresh(last: nil, next: (same, 7)), "never placed: place it")
    }

    /// Two equal-sized displays that swap places keep the same id set and the same frame set; only
    /// the pairing changes.
    func testTwoEqualDisplaysSwappingPlacesIsALayoutChange() {
        let before = [builtIn, left, right]
        let swapped = [builtIn,
                       ScreenFacts(id: 7, name: left.name, isBuiltIn: false, frame: right.frame, uuid: left.uuid),
                       ScreenFacts(id: 8, name: right.name, isBuiltIn: false, frame: left.frame, uuid: right.uuid)]
        XCTAssertEqual(Set(before.map(\.id)), Set(swapped.map(\.id)))
        XCTAssertEqual(Set(before.map { NSValue(rect: $0.frame) }), Set(swapped.map { NSValue(rect: $0.frame) }),
                       "the planted swap must leave both sets alone, or this test proves nothing")
        XCTAssertTrue(DisplayPlacementResolver.layoutChanged(from: before, to: swapped))

        XCTAssertFalse(DisplayPlacementResolver.layoutChanged(from: before, to: before), "nothing moved")
        let replugged = [builtIn, left,
                         ScreenFacts(id: 12, name: right.name, isBuiltIn: false, frame: right.frame, uuid: right.uuid)]
        XCTAssertTrue(DisplayPlacementResolver.layoutChanged(from: before, to: replugged), "a new id is a change")
        XCTAssertTrue(DisplayPlacementResolver.layoutChanged(from: before, to: [builtIn, left]), "an unplug is a change")
        XCTAssertTrue(DisplayPlacementResolver.layoutChanged(from: nil, to: before), "no snapshot yet")
    }

    /// The battery HUD's target was set once, when it appeared. Asked again as the notch moves, it
    /// follows the notch; with one window per display it stays nil, so every window shows it.
    func testAnActiveHUDFollowsTheNotchToItsNewDisplay() {
        func target(_ notch: CGDirectDisplayID?, _ connected: [CGDirectDisplayID], perDisplay: Bool = false) -> CGDirectDisplayID? {
            DisplayPlacementResolver.hudTargetDisplay(oneWindowPerDisplay: perDisplay, notchDisplay: notch,
                                                      mainScreen: 1, connected: connected)
        }
        XCTAssertEqual(target(8, [1, 7, 8]), 8)
        XCTAssertEqual(target(12, [1, 7, 12]), 12, "the notch's monitor back under a new id")
        XCTAssertEqual(target(1, [1, 7]), 1, "the notch fell back to the main display after an unplug")
        XCTAssertEqual(target(8, [1, 7]), 1, "a notch display that is gone falls back to the main one")
        XCTAssertEqual(target(nil, [7, 8]), 7, "no notch display and no main: the first connected")
        XCTAssertNil(target(8, [1, 7, 8], perDisplay: true))
    }
}
