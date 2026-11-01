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
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    /// The Brain window's identifier: how a view tells it from a sheet over it, without building
    /// `shared` where it does not exist yet (a DEBUG snapshot).
    static let windowIdentifier = NSUserInterfaceItemIdentifier("KannuSettingsWindow")
    /// Brain's SwiftUI. It sits in the window only while the window is open, and outlives every
    /// close, so its page, scroll position and typing are still there on reopening.
    private var settingsContent: NSHostingView<SettingsView>?
    /// How the page was left when the content came out of the window. Nil while it is in the window.
    private var leftState: LeftState?

    private struct LeftState {
        /// Nil when nothing on the page had focus.
        var focus: NSView?
        /// A text field's caret, since focusing the field again selects all its text.
        var selection: NSRange?
        var scrollPositions: [(clipView: NSClipView, origin: NSPoint)]
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
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
        
        window.title = String(localized: "Kannu Brain")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = Self.windowIdentifier
        
        // Create the SwiftUI content
        let settingsView = SettingsView()
        settingsContent = NSHostingView(rootView: settingsView)
        restoreContent()
        
        // Handle window closing
        window.delegate = self
        
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panel)
    }
    
    func showWindow() {
        // Ensure window exists
        _ = window
        restoreContent()

        // Utility windows (like NSColorPanel) are unreliable while accessory policy is active.
        NSApp.setActivationPolicy(.regular)

        // NSColorWell leaves the shared panel attached; dismiss any stale picker.
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)

        // Reassert regular window semantics in case any prior state mutated this window.
        window?.level = .normal
        window?.collectionBehavior = [.managed, .participatesInCycle]
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        centerWindowOnActiveScreen()
        
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
        guard let window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen else {
            window.center()
            return
        }

        var frame = window.frame
        frame.origin = NSPoint(
            x: targetScreen.visibleFrame.midX - frame.width / 2,
            y: targetScreen.visibleFrame.midY - frame.height / 2
        )
        window.setFrame(frame, display: true)
    }
    
    override func close() {
        super.close()
        relinquishFocus()
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
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
