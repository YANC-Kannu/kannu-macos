//
//  SettingsAnimationRulesTests.swift
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

/// SwiftUI in an ordered-out window goes on ticking at the display's rate with nothing on screen, so
/// closing Brain takes its content out of the window, and what that does not stop is stopped by hand.
/// A repeating animation under Settings must still end by itself: one stuck there costs CPU for as
/// long as Brain is open, and again on every reopening (docs/REGRESSIONS.md, entry 22). None of this
/// can be run in this logic-only target, so the rules are pinned in the source, as the other rules
/// tests do, and measured off screen in the harness the ledger describes.
final class SettingsAnimationRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func settingsSources() throws -> [String: String] {
        let files = try swiftFiles(under: repoRoot.appendingPathComponent("Kannu/components/Settings"))
        XCTAssertEqual(repeatedNames(in: files), [], "two files under Settings share a name, so a rule reads only one of them")
        var sources: [String: String] = [:]
        for file in files {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        return sources
    }

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            files.append(file)
        }
        return files
    }

    private static func repeatedNames(in files: [URL]) -> [String] {
        Dictionary(grouping: files, by: \.lastPathComponent).filter { $0.value.count > 1 }.keys.sorted()
    }

    /// The `.repeatForever` ban reaches a subfolder only as far as this walk does.
    func testTheWalkReachesSubfoldersAndReportsARepeatedName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("DesignSystem/Inner")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        for path in ["Top.swift", "DesignSystem/Theme.swift", "DesignSystem/Inner/Top.swift", "DesignSystem/Notes.md"] {
            try Data().write(to: root.appendingPathComponent(path))
        }
        let files = try Self.swiftFiles(under: root)
        XCTAssertEqual(files.map(\.lastPathComponent).sorted(), ["Theme.swift", "Top.swift", "Top.swift"])
        XCTAssertEqual(Self.repeatedNames(in: files), ["Top.swift"])
    }

    /// Lines that start an animation with no end. Comments may name it; code may not.
    private static func offenders(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let code = line.components(separatedBy: "//")[0]
            return code.range(of: #"\.repeatForever\s*\("#, options: .regularExpression) != nil
        }
    }

    func testNothingUnderSettingsRepeatsForever() throws {
        let sources = try Self.settingsSources()
        XCTAssertFalse(sources.isEmpty, "the scan read nothing: the path moved")
        XCTAssertNotNil(sources["SettingsTheme.swift"], "the scan no longer reaches DesignSystem/")
        for (name, source) in sources {
            XCTAssertEqual(Self.offenders(in: source), [], "\(name) animates forever while its page is open")
        }
    }

    func testTheHighlightPulseIsBounded() throws {
        let view = try XCTUnwrap(Self.settingsSources()["SettingsView.swift"])
        XCTAssertTrue(view.contains(".repeatCount(3, autoreverses: true)"))
    }

    /// Guards the detector, not the tree: a pattern that matched nothing would pass forever.
    func testTheScannerCatchesEveryShapeOfOffender() {
        let planted = """
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
        .animation(active ? .easeInOut.repeatForever() : .default, value: pulse)
        let pulse = Animation.easeIn.repeatForever (autoreverses: true)
        // A comment may name .repeatForever(autoreverses: true).
        .animation(.easeInOut.repeatCount(3), value: pulse)
        """
        XCTAssertEqual(Self.offenders(in: planted).count, 3)
    }

    // MARK: - Closing takes the content out of the window

    private static func code(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "//")[0] }
            .joined(separator: "\n")
    }

    /// One function's code, found by matching its braces.
    private static func body(of signature: String, in code: String) -> String? {
        guard let start = code.range(of: signature) else { return nil }
        var depth = 0
        for index in code[start.upperBound...].indices {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return String(code[start.upperBound...index]) }
            }
        }
        return nil
    }

    private static func isBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let a = text.range(of: first), let b = text.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }

    /// Everything about the close that the CPU number depends on, and that keeps a reopened Brain
    /// where it was left.
    private static func closingViolations(in controller: String) -> [String] {
        let code = code(controller)
        guard let close = body(of: "func windowWillClose(", in: code),
              let remove = body(of: "func removeContentFromClosedWindow(", in: code),
              let restore = body(of: "func restoreLeftState(", in: code),
              let show = body(of: "func showWindow()", in: code) else {
            return ["windowWillClose, removeContentFromClosedWindow, restoreLeftState or showWindow is gone"]
        }
        var violations: [String] = []
        if !isBefore("DispatchQueue.main.async", "removeContentFromClosedWindow()", in: close) {
            // In the notification itself it would beat TaskDetailPage's save, and the window would
            // still be on screen.
            violations.append("the close does not take the content out a turn later")
        }
        if !remove.contains("!window.isVisible") {
            violations.append("a window reopened in the same turn would be emptied")
        }
        if !remove.contains("window.contentView = NSView()") {
            violations.append("the content stays in the closed window")
        }
        if !remove.contains("leftState = LeftState(") {
            violations.append("nothing remembers how the page was left")
        }
        // The field editor goes when the content does; the field it was editing stays.
        if !remove.contains("editor?.delegate") {
            violations.append("focus is remembered as a field editor that will not come back")
        }
        if !isBefore("restoreContent()", "orderFront", in: show) {
            violations.append("the window can come back empty")
        }
        // Focus lands on the page's first field, and scrolls to it, by the time the second makeKey
        // has run. Nothing may leave between that and putting them back.
        if let last = show.range(of: "makeKeyAndOrderFront", options: .backwards),
           let putBack = show.range(of: "restoreLeftState()", range: last.upperBound..<show.endIndex) {
            let gap = show[last.upperBound..<putBack.lowerBound]
            if gap.contains("return") || gap.contains("guard") {
                violations.append("an early exit can skip putting the page back")
            }
        } else {
            violations.append("the page is put back before focus moves it")
        }
        // Left to AppKit, the first field takes focus with its text selected, and one key replaces it.
        if !restore.contains("window.makeFirstResponder(focus)") {
            violations.append("focus is not put back")
        }
        if !restore.contains("selectedRange = selection") {
            violations.append("the caret is not put back")
        }
        if !restore.contains("?.window === window") {
            violations.append("focus can go to a view no longer in the window")
        }
        // Focusing a field scrolls it into view, so the scroll goes back after it.
        if !isBefore("makeFirstResponder(focus)", "setBoundsOrigin", in: restore) {
            violations.append("the scroll goes back before focus moves it again")
        }
        return violations + fullScreenCloseViolations(in: code, show: show)
    }

    /// A close asked for in full screen waits for the exit, so the window is never ordered out, and the
    /// app never turned `.accessory`, inside a full-screen Space. This proves the wiring. It cannot
    /// prove AppKit's timing, which takes a real window (docs/REGRESSIONS.md, entry 22).
    private static func fullScreenCloseViolations(in code: String, show: String) -> [String] {
        guard let shouldClose = body(of: "func windowShouldClose(", in: code),
              let close = body(of: "override func close(", in: code),
              let willClose = body(of: "func windowWillClose(", in: code),
              let deferClose = body(of: "func deferCloseUntilWindowed(", in: code),
              let finish = body(of: "func finishPendingClose(", in: code),
              let willEnter = body(of: "func windowWillEnterFullScreen(", in: code),
              let didEnter = body(of: "func windowDidEnterFullScreen(", in: code),
              let failedEntry = body(of: "func windowDidFailToEnterFullScreen(", in: code),
              let willExit = body(of: "func windowWillExitFullScreen(", in: code),
              let didExit = body(of: "func windowDidExitFullScreen(", in: code),
              let failedExit = body(of: "func windowDidFailToExitFullScreen(", in: code) else {
            return ["the deferred close or a full-screen delegate method is gone"]
        }
        var violations: [String] = []
        // The answer is what decides, and nothing is ordered out or turned `.accessory` ahead of it.
        if shouldClose.range(of: #"\{\s*!deferCloseUntilWindowed\(sender\)\s*\}"#, options: .regularExpression) == nil {
            violations.append("the close button and Command-W close inside the full-screen Space")
        }
        if !close.contains("deferCloseUntilWindowed(window) { return }")
            || !isBefore("deferCloseUntilWindowed(", "super.close()", in: close)
            || !isBefore("deferCloseUntilWindowed(", "relinquishFocus()", in: close) {
            violations.append("close() does not wait for the exit")
        }
        if !deferClose.contains("styleMask.contains(.fullScreen)") {
            violations.append("the wait does not look at full screen")
        }
        if !deferClose.contains("|| isChangingFullScreen") {
            violations.append("a close during a transition does not wait")
        }
        if !deferClose.contains("closeAfterFullScreen = true") {
            violations.append("nothing remembers the close it put off")
        }
        if !deferClose.contains("toggleFullScreen") {
            violations.append("the wait never starts the exit")
        }
        // A toggle AppKit ignored would lose the close, and a later exit would close Brain by surprise.
        if !deferClose.contains("if !isChangingFullScreen") {
            violations.append("the exit can start during a transition")
        }
        if !isBefore("DispatchQueue.main.async", "toggleFullScreen", in: didEnter) {
            violations.append("a close during the entry never starts the exit, or starts it inside AppKit's callback")
        }
        if !didEnter.contains("guard let self, self.closeAfterFullScreen") {
            violations.append("the exit after an entry does not ask whether a reopening cancelled it")
        }
        if !didEnter.contains("!self.isChangingFullScreen") {
            violations.append("the exit after an entry can start during a transition")
        }
        // Leaving the flag set would close Brain at some later exit.
        if !isBefore("self.window?.attachedSheet == nil else { self.closeAfterFullScreen = false", "toggleFullScreen", in: didEnter) {
            violations.append("the exit after an entry toggles under a sheet, or leaves the close pending")
        }
        for (name, method) in [("exit", didExit), ("failed entry", failedEntry), ("failed exit", failedExit)] where !method.contains("finishPendingClose()") {
            violations.append("the close is forgotten after a \(name)")
        }
        for (name, method) in [("entry", willEnter), ("exit", willExit)] where !method.contains("isChangingFullScreen = true") {
            violations.append("an \(name) is not marked as a transition")
        }
        for (name, method) in [("entry", didEnter), ("exit", didExit), ("failed entry", failedEntry), ("failed exit", failedExit)]
        where !method.contains("isChangingFullScreen = false") {
            violations.append("the transition never ends after a \(name)")
        }
        if !isBefore("guard closeAfterFullScreen", "DispatchQueue.main.async", in: finish) {
            violations.append("every exit queues a close, asked for or not")
        }
        if !isBefore("DispatchQueue.main.async", "window?.close()", in: finish) {
            violations.append("the close runs inside AppKit's callback, or not at all")
        }
        if !isBefore("guard let self, self.closeAfterFullScreen", "window?.close()", in: finish) {
            violations.append("a reopening in the turn before the close still closes Brain")
        }
        // As the entry's queued exit does: a transition that began in the turn between keeps the flag, and
        // its own end closes Brain.
        if !finish.contains("guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen") {
            violations.append("the queued close runs during a transition that began after it")
        }
        // In this order: the flag must not outlive a close that a sheet called off.
        if !isBefore("self.closeAfterFullScreen = false", "self.window?.attachedSheet == nil", in: finish) {
            violations.append("the close stays pending after it ran")
        }
        // Closing under a sheet can leave `ModalPresenter`'s count up, and the notch refusing to open.
        if !isBefore("self.window?.attachedSheet == nil", "window?.close()", in: finish) {
            violations.append("the close runs under a sheet")
        }
        if !willClose.contains("closeAfterFullScreen = false") {
            violations.append("a close that got there first leaves the other pending")
        }
        // During the exit the window is visible, and `showWindow` returns early there.
        if !isBefore("closeAfterFullScreen = false", "window?.isVisible == true", in: show) {
            violations.append("reopening during the exit still closes Brain")
        }
        return violations
    }

    func testClosingTakesTheContentOutAndOpeningPutsItBack() throws {
        let controller = try XCTUnwrap(Self.settingsSources()["SettingsWindowController.swift"])
        XCTAssertEqual(Self.closingViolations(in: controller), [])
    }

    /// Guards the detector: each of these is the real controller with one thing broken.
    func testTheCloseDetectorCatchesEachWayToBreakIt() throws {
        let real = try XCTUnwrap(Self.settingsSources()["SettingsWindowController.swift"])
        let later = """
                DispatchQueue.main.async { [weak self] in
                    self?.removeContentFromClosedWindow()
                }
        """
        let exitAfterEntry = """
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }
                    // A sheet arrived during the entry. AppKit could ignore a toggle under it, and a flag
                    // left set would close Brain at some later exit.
                    guard self.window?.attachedSheet == nil else { self.closeAfterFullScreen = false; return }
                    self.window?.toggleFullScreen(nil)
                }
        """
        let closeLater = """
                DispatchQueue.main.async { [weak self] in
                    // The flag stays set until here, so `showWindow` can still cancel.
                    guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }
                    self.closeAfterFullScreen = false
                    // `NSWindow.close()` does not look at a sheet, and `ModalPresenter` counts one until it
                    // ends. A sheet that arrived during the transition keeps Brain open.
                    guard self.window?.attachedSheet == nil else { return }
                    self.window?.close()
                }
        """
        let outerGuard = "guard closeAfterFullScreen else { return }\n        // A turn later: this runs"
        // Anchored: the entry's queued exit has the same guard, and a mutation replaces every occurrence.
        let closeGuard = "guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }\n            self.closeAfterFullScreen = false"
        let clearAndSheetGuard = "self.closeAfterFullScreen = false\n            // `NSWindow.close()` does not look at a sheet, and `ModalPresenter` counts one until it\n            // ends. A sheet that arrived during the transition keeps Brain open.\n            guard self.window?.attachedSheet == nil else { return }"
        let mutations: [(name: String, edits: [(from: String, to: String)])] = [
            ("never taken out", [(later, "")]),
            ("taken out during the notification", [(later, "removeContentFromClosedWindow()")]),
            ("reopened in the same turn, then emptied", [("!window.isVisible, ", "")]),
            ("left in the window", [("window.contentView = NSView()", "")]),
            ("state not remembered", [("leftState = LeftState(", "_ = LeftState(")]),
            ("the field editor remembered, not its field", [
                ("editor?.delegate as? NSView ?? window.firstResponder as? NSView", "window.firstResponder as? NSView"),
            ]),
            ("never put back", [("_ = window\n        restoreContent()", "_ = window")]),
            ("put back after ordering in", [
                ("_ = window\n        restoreContent()", "_ = window"),
                ("// Activate the app and ensure window gets focus", "restoreContent()"),
            ]),
            ("page put back before focus lands", [
                ("self?.window?.makeKeyAndOrderFront(nil)\n            self?.restoreLeftState()",
                 "self?.restoreLeftState()\n            self?.window?.makeKeyAndOrderFront(nil)"),
            ]),
            ("an early exit before the page is put back", [
                ("self?.window?.makeKeyAndOrderFront(nil)\n            self?.restoreLeftState()",
                 "self?.window?.makeKeyAndOrderFront(nil)\n            if self?.window?.isKeyWindow == false { return }\n            self?.restoreLeftState()"),
            ]),
            ("focus left to AppKit", [("window.makeFirstResponder(focus)", "")]),
            ("caret left selected", [("field.currentEditor()?.selectedRange = selection", "_ = field")]),
            ("focus on a view that has gone", [("leftState.focus?.window === window ? leftState.focus : nil", "leftState.focus")]),
            ("scroll put back before focus", [
                ("window.makeFirstResponder(focus)\n", "\n"),
                ("reflectScrolledClipView(clipView)\n        }", "reflectScrolledClipView(clipView)\n        }\n        window.makeFirstResponder(focus)"),
            ]),
            ("closed in full screen without leaving it", [("!deferCloseUntilWindowed(sender)", "true")]),
            ("windowShouldClose ignores the answer", [("!deferCloseUntilWindowed(sender)", "_ = deferCloseUntilWindowed(sender); return true")]),
            ("close() skips the wait", [("if let window, deferCloseUntilWindowed(window) { return }", "")]),
            ("close() ignores the answer", [("deferCloseUntilWindowed(window) { return }", "deferCloseUntilWindowed(window) { }")]),
            ("close() goes accessory before the wait", [
                ("if let window, deferCloseUntilWindowed(window) { return }\n        super.close()\n        relinquishFocus()",
                 "super.close()\n        relinquishFocus()\n        if let window, deferCloseUntilWindowed(window) { return }"),
            ]),
            ("the full-screen check is gone", [("window.styleMask.contains(.fullScreen) || ", "")]),
            ("a close during a transition does not wait", [(" || isChangingFullScreen", "")]),
            ("the close put off is not remembered", [("closeAfterFullScreen = true", "")]),
            ("toggles during a transition", [("if !isChangingFullScreen { window.toggleFullScreen(nil) }", "window.toggleFullScreen(nil)")]),
            ("never starts the exit", [("if !isChangingFullScreen { window.toggleFullScreen(nil) }", "")]),
            ("a close during the entry is swallowed", [("self.window?.toggleFullScreen(nil)", "")]),
            ("the exit starts inside AppKit's callback", [(exitAfterEntry, "window?.toggleFullScreen(nil)")]),
            ("the exit ignores a reopening", [("guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }", "guard let self, !self.isChangingFullScreen else { return }")]),
            ("the exit ignores a transition", [(", !self.isChangingFullScreen", "")]),
            ("the exit toggles under a sheet", [("guard self.window?.attachedSheet == nil else { self.closeAfterFullScreen = false; return }", "")]),
            ("a sheet at the entry leaves the close pending", [("else { self.closeAfterFullScreen = false; return }", "else { return }")]),
            ("the close is forgotten after the exit", [
                ("func windowDidExitFullScreen(_ notification: Notification) {\n        isChangingFullScreen = false\n        finishPendingClose()",
                 "func windowDidExitFullScreen(_ notification: Notification) {\n        isChangingFullScreen = false"),
            ]),
            ("the close is forgotten after a failed entry", [
                ("func windowDidFailToEnterFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false\n        finishPendingClose()",
                 "func windowDidFailToEnterFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false"),
            ]),
            ("the close is forgotten after a failed exit", [
                ("func windowDidFailToExitFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false\n        finishPendingClose()",
                 "func windowDidFailToExitFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false"),
            ]),
            ("an entry is not marked as a transition", [
                ("func windowWillEnterFullScreen(_ notification: Notification) {\n        isChangingFullScreen = true",
                 "func windowWillEnterFullScreen(_ notification: Notification) {"),
            ]),
            ("an exit is not marked as a transition", [
                ("func windowWillExitFullScreen(_ notification: Notification) {\n        isChangingFullScreen = true",
                 "func windowWillExitFullScreen(_ notification: Notification) {"),
            ]),
            ("the transition never ends after an entry", [
                ("func windowDidEnterFullScreen(_ notification: Notification) {\n        isChangingFullScreen = false",
                 "func windowDidEnterFullScreen(_ notification: Notification) {"),
            ]),
            ("the transition never ends after an exit", [
                ("func windowDidExitFullScreen(_ notification: Notification) {\n        isChangingFullScreen = false",
                 "func windowDidExitFullScreen(_ notification: Notification) {"),
            ]),
            ("the transition never ends after a failed entry", [
                ("func windowDidFailToEnterFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false",
                 "func windowDidFailToEnterFullScreen(_ window: NSWindow) {"),
            ]),
            ("the transition never ends after a failed exit", [
                ("func windowDidFailToExitFullScreen(_ window: NSWindow) {\n        isChangingFullScreen = false",
                 "func windowDidFailToExitFullScreen(_ window: NSWindow) {"),
            ]),
            ("the close runs inside AppKit's callback", [(closeLater, "window?.close()")]),
            ("every exit queues a close", [(outerGuard, "// A turn later: this runs")]),
            ("every exit closes Brain", [
                (outerGuard, "// A turn later: this runs"),
                (closeGuard, "guard let self else { return }\n            self.closeAfterFullScreen = false"),
            ]),
            ("a reopening in the turn before the close still closes", [(closeGuard, "guard let self else { return }\n            self.closeAfterFullScreen = false")]),
            ("the queued close runs during a new transition", [
                (closeGuard, "guard let self, self.closeAfterFullScreen else { return }\n            self.closeAfterFullScreen = false"),
            ]),
            ("the close stays pending", [(clearAndSheetGuard, "guard self.window?.attachedSheet == nil else { return }")]),
            ("a sheet at the exit leaves the close pending", [
                (clearAndSheetGuard, "guard self.window?.attachedSheet == nil else { return }\n            self.closeAfterFullScreen = false"),
            ]),
            ("the close runs under a sheet", [("guard self.window?.attachedSheet == nil else { return }", "")]),
            ("a close that got there first leaves the other pending", [
                ("func windowWillClose(_ notification: Notification) {\n        // A second Command-W can beat the turn `finishPendingClose` waits for.\n        closeAfterFullScreen = false",
                 "func windowWillClose(_ notification: Notification) {"),
            ]),
            // Anchored: the bare string occurs more than once, and a mutation replaces every occurrence.
            ("reopening during the exit still closes", [("restoreContent()\n        closeAfterFullScreen = false", "restoreContent()")]),
            ("the reopening clears the close too late", [
                ("restoreContent()\n        closeAfterFullScreen = false", "restoreContent()"),
                ("// Placed before it is ordered in", "closeAfterFullScreen = false\n        // Placed before it is ordered in"),
            ]),
        ]
        for mutation in mutations {
            var broken = real
            for edit in mutation.edits {
                XCTAssertTrue(broken.contains(edit.from), "\(mutation.name): the controller changed, this planted offender is stale")
                broken = broken.replacingOccurrences(of: edit.from, with: edit.to)
            }
            XCTAssertFalse(Self.closingViolations(in: broken).isEmpty, "\(mutation.name) was not caught")
        }
    }

    // MARK: - What closing does not stop by itself

    /// A player runs on at full cost with its view out of the window. A file that makes one must
    /// pause it, from `viewDidMoveToWindow` or `onDisappear`.
    private static func playerOffends(_ source: String) -> Bool {
        let code = code(source)
        guard code.range(of: #"\bAV(Queue)?Player\s*\("#, options: .regularExpression) != nil else { return false }
        return !code.contains(".pause()") || !(code.contains("viewDidMoveToWindow") || code.contains(".onDisappear"))
    }

    func testEveryPlayerUnderSettingsStopsWithItsWindow() throws {
        let sources = try Self.settingsSources()
        for (name, source) in sources {
            XCTAssertFalse(Self.playerOffends(source), "\(name) plays on behind a closed Brain")
        }
        let view = try XCTUnwrap(sources["DevicesSettings.swift"])
        XCTAssertTrue(view.contains("onWindowChange?(window != nil)"), "the looping icon no longer follows its window")
        XCTAssertTrue(view.contains("view.onWindowChange = { inWindow in coordinator.setPlaying(inWindow) }"), "the looping icon's window callback no longer reaches its player")
        // The pause in `setPlaying`'s else branch, not just anywhere in the file.
        XCTAssertTrue(view.contains("func setPlaying(_ playing: Bool) {\n            if playing {\n                controller?.play()\n            } else {\n                controller?.pause()\n            }"),
                      "the looping icon no longer pauses when its window goes")
    }

    func testThePlayerDetectorCatchesAnOffender() {
        XCTAssertTrue(Self.playerOffends("player = AVPlayer(playerItem: item); player?.play()"))
        XCTAssertTrue(Self.playerOffends("let looping = AVQueuePlayer(); looping.play()"))
        XCTAssertTrue(Self.playerOffends("player = AVPlayer(url: url)\n.onDisappear { player = nil }"))
        // A comment may name the cure; code has to have it.
        XCTAssertTrue(Self.playerOffends("player = AVPlayer(url: url) // .pause() from .onDisappear"))
        XCTAssertFalse(Self.playerOffends("player = AVPlayer(url: url)\n.onDisappear { player?.pause() }"))
        XCTAssertFalse(Self.playerOffends("let p = AVQueuePlayer()\noverride func viewDidMoveToWindow() { p.pause() }"))
        XCTAssertFalse(Self.playerOffends("VideoPlayer(player: player) // no AVPlayer made here"))
    }

    /// Lottie's Core Animation engine ends a loop when its view leaves the window and never starts
    /// it again. `AnimationEditorView` is a sheet: Brain cannot close under it.
    private static func lottieOffends(_ source: String) -> Bool {
        let code = code(source)
        guard code.range(of: #"\bLottieView\s*\("#, options: .regularExpression) != nil else { return false }
        return !(code.contains(".id(visit)") && code.contains(".onDisappear { visit += 1 }"))
    }

    func testAPageLottieStartsAgainOnReopening() throws {
        let sources = try Self.settingsSources()
        XCTAssertTrue(sources["AnimationEditorView.swift"]?.contains("LottieView(") == true, "the sheet exception is stale")
        for (name, source) in sources where name != "AnimationEditorView.swift" {
            XCTAssertFalse(Self.lottieOffends(source), "\(name): a Lottie here stays stopped once Brain reopens")
        }
        XCTAssertFalse(Self.lottieOffends("VideoPlayer(player: player)"))
        XCTAssertTrue(Self.lottieOffends("LottieView(state: state).frame(width: 60, height: 40)"))
    }

    // MARK: - What a reopened Brain must not lose

    /// `onDisappear` only runs a turn after the close, so the save stays on the notification.
    func testTheTaskPageStillSavesAtTheCloseItself() throws {
        let page = Self.code(try XCTUnwrap(Self.settingsSources()["TaskDetailPage.swift"]))
        XCTAssertEqual(page.components(separatedBy: "NSWindow.willCloseNotification").count - 1, 2, "the title and the estimate each save on it")
        XCTAssertEqual(page.components(separatedBy: "SettingsWindowController.windowIdentifier").count - 1, 2, "a sheet closing over the page must not save it")
    }

    /// `onAppear` runs again on reopening. A cookie typed but not yet validated is saved nowhere, so
    /// reading the stored one over it would lose it.
    func testReopeningKeepsAnUnsavedCookie() throws {
        let section = Self.code(try XCTUnwrap(Self.settingsSources()["SpotifyAuthSettingsSection.swift"]))
        let appear = try XCTUnwrap(section.range(of: ".onAppear"))
        let read = try XCTUnwrap(section.range(of: "SecureSecretsStore.value(for: .spotifySPDCCookie)", range: appear.upperBound..<section.endIndex))
        XCTAssertTrue(section[appear.upperBound..<read.lowerBound].contains("guard !loadedStoredCookie"))
    }
}
