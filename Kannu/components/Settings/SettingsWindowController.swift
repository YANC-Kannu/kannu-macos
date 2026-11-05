/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

import AppKit
import Combine
import Defaults
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    /// The Brain window's identifier: how a view tells it from a sheet over it, without building
    /// `shared` where it does not exist yet (a DEBUG snapshot).
    static let windowIdentifier = NSUserInterfaceItemIdentifier("KannuSettingsWindow")
    /// Brain's SwiftUI. It sits in the window only while the window is open, and outlives every
    /// close, so its page, scroll position and typing are still there on reopening.
    private var settingsContent: NSHostingView<SettingsView>?
    /// How the page was left when the content came out of the window, or how it stood before the first open.
    /// Nil once it is put back.
    private var leftState: LeftState?
    /// False until the first open, which has no close to remember and gets a `leftState` of its own.
    private var hasOpened = false
    /// A close asked for in full screen waits for the exit, so the window is never ordered out, and
    /// the app never turned `.accessory`, inside a full-screen Space.
    private var closeAfterFullScreen = false
    private var isChangingFullScreen = false
    private var brainAppearanceObserver: AnyCancellable?

    private struct LeftState {
        /// Nil when nothing on the page had focus.
        var focus: NSView?
        /// A text field's caret, since focusing the field again selects all its text.
        var selection: NSRange?
        var scrollPositions: [(clipView: NSClipView, origin: NSPoint)]
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsTheme.windowDefaultWidth, height: SettingsTheme.windowDefaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = window else { return }
        
        // Hidden, and kept: the Window menu and Mission Control read it.
        window.title = String(localized: "Kannu Brain")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // The title row is what drags it. A control dragged inside a page must not move the window.
        window.isMovableByWindowBackground = false
        window.backgroundColor = SettingsTheme.windowPaper
        window.minSize = NSSize(width: SettingsTheme.windowMinWidth, height: SettingsTheme.windowMinHeight)
        window.level = .normal

        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]

        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false

        // Nothing restores it at launch. A window that could come back full screen ahead of the terms
        // gate is a question this removes.
        window.isRestorable = false
        window.identifier = Self.windowIdentifier
        
        // Create the SwiftUI content
        let settingsView = SettingsView()
        settingsContent = NSHostingView(rootView: settingsView)
        restoreContent()
        
        // Handle window closing
        window.delegate = self
        
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panel)

        observeBrainAppearance()
    }

    /// Here, not in a view: a view does not react while Brain is closed (docs/REGRESSIONS.md, entry 22).
    /// The first apply is synchronous, so the first open cannot flash. `options: []`, because the
    /// publisher would otherwise fire that first value a second time.
    private func observeBrainAppearance() {
        applyBrainAppearance(Defaults[.brainAppearance])
        brainAppearanceObserver = Defaults.publisher(.brainAppearance, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in self?.applyBrainAppearance(change.newValue) }
    }

    /// This window only: the notch stays dark, every other window follows macOS, and nothing here may
    /// touch `NSApp.appearance`.
    private func applyBrainAppearance(_ choice: BrainAppearance) {
        switch choice {
        case .system: window?.appearance = nil
        case .light: window?.appearance = NSAppearance(named: .aqua)
        case .dark: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func showWindow() {
        // Ensure window exists
        _ = window
        restoreContent()
        closeAfterFullScreen = false

        // Utility windows (like NSColorPanel) are unreliable while accessory policy is active.
        NSApp.setActivationPolicy(.regular)

        // NSColorWell leaves the shared panel attached; dismiss any stale picker.
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)

        // Reassert regular window semantics in case any prior state mutated this window.
        window?.level = .normal
        window?.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]

        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Placed before it is ordered in, or a window this size visibly jumps.
        centerWindowOnActiveScreen()
        seedLeftStateForFirstOpen()

        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)

        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            guard !NSColorPanel.shared.isVisible else { return }
            self?.window?.makeKeyAndOrderFront(nil)
            self?.restoreLeftState()
        }
    }
    
    /// Opens (or fronts) the window and navigates to the Agent Status tab, scrolling to and
    /// pulsing the given row. The coordinator's subscribers are guaranteed to exist by the
    /// time this runs: SettingsView is built once in init, long before any caller can reach
    /// this method, so the request is never dropped.
    func showWindow(navigatingToAgentStatusHighlight highlightID: String) {
        showWindow()
        SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: highlightID)
    }

    private func restoreContent() {
        guard let window, let settingsContent, window.contentView !== settingsContent else { return }
        window.contentView = settingsContent
    }

    /// Closing only orders the window out, and SwiftUI in an ordered-out window goes on animating at
    /// the display's rate with nothing on screen (docs/REGRESSIONS.md, entry 22). Out of the window
    /// it stops, whatever the page animates. Its state stays; its `onDisappear`s and `.task`
    /// cancellations run now, and its `onAppear`s and `.task`s again on reopening.
    private func removeContentFromClosedWindow() {
        guard let window, !window.isVisible, let settingsContent, window.contentView === settingsContent else { return }
        let editor = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
        leftState = LeftState(
            focus: editor?.delegate as? NSView ?? window.firstResponder as? NSView,
            selection: editor?.selectedRange(),
            scrollPositions: Self.scrollers(in: settingsContent).map { ($0.contentView, $0.contentView.bounds.origin) }
        )
        window.contentView = NSView()
    }

    /// The first open has no `leftState`, since nothing has closed, yet ordering the window in still gives the
    /// page's first text field focus, selects its text and scrolls to it. A page builds every row, so that field can
    /// be a deep one that writes straight through, such as Agents' ntfy topic or a Pushover key, and the next key
    /// typed would replace what is stored. So the first open is put back like a reopening, to how it stood: nothing
    /// focused, every scroller where it starts. Laid out first, since until then the page has no scroll views.
    private func seedLeftStateForFirstOpen() {
        guard !hasOpened, let settingsContent else { return }
        hasOpened = true
        settingsContent.layoutSubtreeIfNeeded()
        leftState = LeftState(
            focus: nil,
            selection: nil,
            scrollPositions: Self.scrollers(in: settingsContent).map { ($0.contentView, $0.contentView.bounds.origin) }
        )
    }

    /// Ordering the content back in gives the page's first text field focus with its text selected,
    /// so the next key typed would replace it, and scrolls the page to that field. Whatever had focus
    /// gets it back, or nothing does; the scroll goes back last, since focusing a field also moves it.
    private func restoreLeftState() {
        guard let window, let leftState else { return }
        self.leftState = nil
        let focus = leftState.focus?.window === window ? leftState.focus : nil
        window.makeFirstResponder(focus)
        if let selection = leftState.selection, let field = focus as? NSTextField {
            field.currentEditor()?.selectedRange = selection
        }
        for (clipView, origin) in leftState.scrollPositions where clipView.bounds.origin != origin {
            clipView.setBoundsOrigin(origin)
            (clipView.superview as? NSScrollView)?.reflectScrolledClipView(clipView)
        }
    }

    private static func scrollers(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview -> [NSScrollView] in
            let inside = scrollers(in: subview)
            return (subview as? NSScrollView).map { [$0] + inside } ?? inside
        }
    }

    private func centerWindowOnActiveScreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen else {
            window.center()
            return
        }

        // Clamped: a window sized on a big display and reopened on a laptop would otherwise get a
        // negative origin.
        let visible = targetScreen.visibleFrame
        var frame = window.frame
        frame.size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        window.setFrame(frame, display: true)
    }

    override func close() {
        if let window, deferCloseUntilWindowed(window) { return }
        super.close()
        relinquishFocus()
    }

    /// True when the close must wait. Toggles only when no transition is running: whether AppKit
    /// honours a toggle during one, or inside its own callback, is a question this never asks. If one
    /// were ignored, the close would be lost and a later exit would close Brain by surprise.
    private func deferCloseUntilWindowed(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.fullScreen) || isChangingFullScreen else { return false }
        closeAfterFullScreen = true
        if !isChangingFullScreen { window.toggleFullScreen(nil) }
        return true
    }

    private func finishPendingClose() {
        guard closeAfterFullScreen else { return }
        // A turn later: this runs inside AppKit's transition callback. `NSWindow.close()` does not
        // ask `windowShouldClose` again, and `windowWillClose` then does all the usual work.
        DispatchQueue.main.async { [weak self] in
            // The flag stays set until here, so `showWindow` can still cancel.
            guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }
            self.closeAfterFullScreen = false
            // `NSWindow.close()` does not look at a sheet, and `ModalPresenter` counts one until it
            // ends. A sheet that arrived during the transition keeps Brain open.
            guard self.window?.attachedSheet == nil else { return }
            self.window?.close()
        }
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
    
    deinit {
        if let window = window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // A second Command-W can beat the turn `finishPendingClose` waits for.
        closeAfterFullScreen = false
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        relinquishFocus()
        // A turn later: `TaskDetailPage` saves on this same notification, and this is the only hook
        // the close button and Command-W share with `close()`.
        DispatchQueue.main.async { [weak self] in
            self?.removeContentFromClosedWindow()
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !deferCloseUntilWindowed(sender)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isChangingFullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isChangingFullScreen = false
        guard closeAfterFullScreen else { return }
        // A turn later, as in `finishPendingClose`. `showWindow` may clear the flag first.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.closeAfterFullScreen, !self.isChangingFullScreen else { return }
            // A sheet arrived during the entry. AppKit could ignore a toggle under it, and a flag
            // left set would close Brain at some later exit.
            guard self.window?.attachedSheet == nil else { self.closeAfterFullScreen = false; return }
            self.window?.toggleFullScreen(nil)
        }
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        isChangingFullScreen = false
        finishPendingClose()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isChangingFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isChangingFullScreen = false
        finishPendingClose()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        isChangingFullScreen = false
        finishPendingClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }

    /// Closed, minimised, hidden with the app, fully covered or left in another Space: AppKit says so here, and a
    /// page's live views stop until any of the window is on screen again (docs/SETTINGS.md, "Live data"). A full-screen
    /// Brain parked in another Space keeps `isVisible` true, so this, not the close, is what stops it there.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        BrainVisibility.shared.update(for: window)
    }
}
