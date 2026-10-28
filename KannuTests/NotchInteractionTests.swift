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

/// On a notched MacBook, hover may open the notch only from the hardware notch, and a click
/// meant for another app may never open it (docs/REGRESSIONS.md entry 18).
final class NotchInteractionTests: XCTestCase {
    /// A 14" MacBook Pro at default scaling: 1512 wide, menu-bar areas either side of a ~185 pt
    /// notch, 38 pt top inset.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left: CGFloat = 663.5, right: CGFloat = 663.5, top: CGFloat = 38

    private var notch: CGRect {
        NotchInteractionGeometry.physicalNotchRect(screenFrame: screen, leftAreaWidth: left, rightAreaWidth: right, topInset: top)!
    }

    func testTheRectIsTheNotchKannuDraws() {
        // getClosedNotchSize's width: screen minus the areas either side, plus 4.
        XCTAssertEqual(notch.width, 1512 - 663.5 - 663.5 + 4)
        XCTAssertEqual(notch.height, 38)
        XCTAssertEqual(notch.maxY, screen.maxY, "flush with the top edge")
        XCTAssertEqual(notch.midX, screen.midX, "centred, as the window is")
    }

    func testOnlyTheNotchItselfCounts() {
        let onNotch = CGPoint(x: screen.midX, y: screen.maxY - 10)
        XCTAssertTrue(NotchInteractionGeometry.isOnPhysicalNotch(onNotch, notch: notch))
        XCTAssertTrue(NotchInteractionGeometry.isOnPhysicalNotch(CGPoint(x: screen.midX, y: screen.maxY), notch: notch),
                      "the pointer pinned against the top edge is on the notch")
        // The +8 pt hover growth either side, and below.
        XCTAssertFalse(NotchInteractionGeometry.isOnPhysicalNotch(CGPoint(x: notch.maxX + 4, y: screen.maxY - 10), notch: notch))
        XCTAssertFalse(NotchInteractionGeometry.isOnPhysicalNotch(CGPoint(x: screen.midX, y: notch.minY - 4), notch: notch))
        // A music or agent wing, over the menu-bar items beside the notch.
        XCTAssertFalse(NotchInteractionGeometry.isOnPhysicalNotch(CGPoint(x: notch.minX - 60, y: screen.maxY - 10), notch: notch))
        // The agent band below the notch, over a window's tabs and toolbar.
        XCTAssertFalse(NotchInteractionGeometry.isOnPhysicalNotch(CGPoint(x: screen.midX, y: screen.maxY - 50), notch: notch))
    }

    func testAScreenWithoutANotchHasNone() {
        XCTAssertNil(NotchInteractionGeometry.physicalNotchRect(screenFrame: screen, leftAreaWidth: 0, rightAreaWidth: 0, topInset: 0))
    }

    func testASecondScreenIsMeasuredInItsOwnCoordinates() {
        let external = CGRect(x: 1512, y: 200, width: 1512, height: 982)
        let rect = NotchInteractionGeometry.physicalNotchRect(screenFrame: external, leftAreaWidth: left, rightAreaWidth: right, topInset: top)!
        XCTAssertEqual(rect.midX, external.midX)
        XCTAssertEqual(rect.maxY, external.maxY)
    }

    /// A global monitor cannot consume a click: one on leftMouseDown in the notch view let a click
    /// meant for a menu item or tab beside the notch land there *and* open the panel over it.
    func testNoGlobalMouseDownMonitorInTheNotchView() throws {
        let code = try Self.contentViewCode()
        XCTAssertFalse(code.contains("addGlobalMonitorForEvents(matching: [.leftMouseDown]"),
                       "a click in another app must never open the notch (docs/REGRESSIONS.md entry 18)")
        XCTAssertTrue(code.contains("addGlobalMonitorForEvents(matching: [.leftMouseUp]"),
                      "the open panel's click-elsewhere close should still be here")
    }

    // MARK: - The open notch (docs/REGRESSIONS.md entry 22)

    /// The open body as SwiftUI lays it out in its window: 640 × 230, flush with the window's top.
    private let body = CGRect(x: 120, y: 0, width: 640, height: 230)

    func testTheOpenRectIsTheBodyPinnedToTheTopAndCentred() {
        let rect = NotchInteractionGeometry.openNotchRect(screenFrame: screen, bodyInWindow: body)!
        XCTAssertEqual(rect.size, body.size)
        XCTAssertEqual(rect.maxY, screen.maxY, "flush with the top edge, as the window is")
        XCTAssertEqual(rect.midX, screen.midX, "centred, as the window is; the body's x in it does not matter")
    }

    func testABodyBelowTheWindowTopKeepsItsDistance() {
        // An island: the pill sits a few points below the top of its window.
        let island = CGRect(x: 20, y: 6, width: 400, height: 180)
        let rect = NotchInteractionGeometry.openNotchRect(screenFrame: screen, bodyInWindow: island)!
        XCTAssertEqual(rect.maxY, screen.maxY - 6)
        XCTAssertEqual(rect.minY, screen.maxY - 186)
    }

    func testABodyNotLaidOutYetHasNoRect() {
        XCTAssertNil(NotchInteractionGeometry.openNotchRect(screenFrame: screen, bodyInWindow: .zero))
    }

    func testTheOpenNotchCountsItsMarginAndNothingPastIt() {
        let rect = NotchInteractionGeometry.openNotchRect(screenFrame: screen, bodyInWindow: body)!
        let margin = NotchInteractionGeometry.openNotchMargin
        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.midX, y: rect.midY), notch: rect))
        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.midX, y: screen.maxY), notch: rect),
                      "pinned against the top edge")
        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.maxX + margin - 1, y: rect.midY), notch: rect),
                      "resting on the edge never flaps it shut")
        XCTAssertTrue(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.midX, y: rect.minY - margin + 1), notch: rect))
        XCTAssertFalse(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.maxX + margin + 1, y: rect.midY), notch: rect))
        XCTAssertFalse(NotchInteractionGeometry.isOnOpenNotch(CGPoint(x: rect.midX, y: rect.minY - margin - 1), notch: rect))
    }

    func testTheOpenRectFollowsASecondScreen() {
        let external = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        let rect = NotchInteractionGeometry.openNotchRect(screenFrame: external, bodyInWindow: body)!
        XCTAssertEqual(rect.midX, external.midX)
        XCTAssertEqual(rect.maxY, external.maxY)
    }

    /// Every auto-close of the open notch decides on where the pointer is. A close read off the
    /// latched `isHovering` shut the notch under a still pointer once a popover, a menu or an
    /// alert had taken the hover away (David, 2026-10-28: "it randomly closes even when the
    /// mouse is in the notch area").
    func testEveryAutoCloseGoesThroughThePointerCheck() throws {
        XCTAssertEqual(Self.closeProblems(in: try Self.contentViewCode()), [])
    }

    func testTheCloseScannerCatchesPlantedOffenders() {
        let fixed = """
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                closeWhenPointerLeaves(.popoverClosed)
            }
            private func closeWhenPointerLeaves(_ reason: NotchCloseReason) {
                hoverTask = Task { @MainActor in
                    if shouldPreventAutoClose() || closeWatch.trackingMenus > 0 { continue }
                    if isPointerOnOpenNotch(NSEvent.mouseLocation) { continue }
                    vm.close()
                }
            }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak vm] _ in
                guard !self.isPointerOnOpenNotch(location) else { return }
                vm.close()
            }
            """
        XCTAssertEqual(Self.closeProblems(in: fixed), [])
        let stale = fixed.replacingOccurrences(of: "closeWhenPointerLeaves(.popoverClosed)",
                                               with: "runAfter(0.1) { if vm.notchState == .open && !isHovering { vm.close() } }")
        XCTAssertEqual(Self.closeProblems(in: stale), ["a close is decided by the latched isHovering"])
        XCTAssertEqual(Self.closeProblems(in: fixed.replacingOccurrences(of: "if isPointerOnOpenNotch(NSEvent.mouseLocation) { continue }", with: "")),
                       ["closeWhenPointerLeaves does not check where the pointer is"])
        XCTAssertEqual(Self.closeProblems(in: fixed.replacingOccurrences(of: " || closeWatch.trackingMenus > 0", with: "")),
                       ["closeWhenPointerLeaves closes while a menu tracks"])
        XCTAssertEqual(Self.closeProblems(in: fixed.replacingOccurrences(of: "guard !self.isPointerOnOpenNotch(location) else { return }", with: "")),
                       ["a click that falls through onto the notch closes it"])
    }

    // MARK: - Scanning

    private static func contentViewCode() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Kannu/ContentView.swift"), encoding: .utf8)
        return source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    private static func closeProblems(in code: String) -> [String] {
        var problems: [String] = []
        // Every `vm.close()` that reads `isHovering` in the few lines before it.
        let lines = code.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("vm.close()") {
            let window = lines[max(0, index - 3)...index].joined(separator: "\n")
            if window.contains("!isHovering") || window.contains("!self.isHovering") {
                problems.append("a close is decided by the latched isHovering")
            }
        }
        if let start = code.range(of: "func closeWhenPointerLeaves(") {
            let body = String(code[start.upperBound...].prefix(1200))
            // Where the pointer is now; the outside-click monitor's own check reads the click's place.
            if !body.contains("isPointerOnOpenNotch(NSEvent.mouseLocation)") {
                problems.append("closeWhenPointerLeaves does not check where the pointer is")
            }
            if !body.contains("closeWatch.trackingMenus > 0") {
                problems.append("closeWhenPointerLeaves closes while a menu tracks")
            }
        } else {
            problems.append("closeWhenPointerLeaves( not found")
        }
        if let monitor = code.range(of: "addGlobalMonitorForEvents(matching: [.leftMouseUp]") {
            let body = String(code[monitor.upperBound...].prefix(900))
            if !body.contains("isPointerOnOpenNotch(") {
                problems.append("a click that falls through onto the notch closes it")
            }
        }
        return problems
    }
}
