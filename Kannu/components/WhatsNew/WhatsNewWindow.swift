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

import AppKit
import SwiftUI

/// The What's New window (openspec `whats-new`). `AppDelegate.showWhatsNewWindow()` opens it and holds it in
/// `whatsNewWindow`.
///
/// A titled, `.normal`-level window like onboarding's: never a borderless notch panel, which cannot be focused, and
/// never modal (docs/REGRESSIONS.md, entry 14). It is as tall as its content at `WhatsNewView.width`, measured once as
/// it is built, so a card grows with its text in every language; the content then goes in through `setHostedContent`,
/// so SwiftUI never resizes it (entry 17). Its title bar is transparent, with the panel under it, as Brain's and
/// onboarding's are.
///
/// Continue (Return), Escape, the close button and ⌘W all end in `close()`, which calls `onClose` once.
final class WhatsNewWindow: NSWindow {
    static let identifier = NSUserInterfaceItemIdentifier("WhatsNewWindow")

    /// Called once, when the window closes, however it was closed.
    var onClose: (() -> Void)?

    static func make(content: WhatsNewContent) -> WhatsNewWindow {
        let window = WhatsNewWindow(
            contentRect: NSRect(x: 0, y: 0, width: WhatsNewView.width, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Hidden, and kept for the Window menu and VoiceOver.
        window.title = String(localized: "What's New")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.identifier = identifier
        // Under Reduce Motion nothing animates, the window's own appearance included.
        window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .default
        // The band the transparent title bar takes from the top of the content.
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        let hostingView = NSHostingView(rootView: WhatsNewView(
            content: content,
            titleBarHeight: titleBarHeight,
            onContinue: { [weak window] in window?.close() }
        ))
        // Measured before `setHostedContent` turns the hosting view's own sizing off.
        window.setContentSize(hostingView.fittingSize)
        window.setHostedContent(hostingView)
        window.center()
        return window
    }

    /// Escape closes the window, as Continue does. AppKit offers every key-down to the key window's key equivalents
    /// before anything else, whatever has focus, and that is also how Return reaches Continue. `cancelOperation(_:)`
    /// would hear Escape only through a text field's key bindings, and this window has no field.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == Self.escapeKeyCode,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func close() {
        super.close()
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    /// `kVK_Escape`.
    private static let escapeKeyCode: UInt16 = 53
}
