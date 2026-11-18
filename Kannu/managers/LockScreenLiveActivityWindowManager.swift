/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Defaults
import SkyLightWindow
import SwiftUI
import QuartzCore

@MainActor
class LockScreenLiveActivityWindowManager {
    static let shared = LockScreenLiveActivityWindowManager()

    private var window: NSWindow?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    /// The attention alert's one sleep while the pill shows only for it (live activity off). Cancelled on unlock.
    private var attentionFlashTask: Task<Void, Never>?
    /// Bumped by every `present`, so a hide's delayed `orderOut` never removes a pill shown again since.
    private var presentGeneration = 0
    private var hostingView: NSHostingView<LockScreenLiveActivityOverlay>?
    private let overlayModel = LockScreenLiveActivityOverlayModel()
    private let overlayAnimator = LockIconAnimator(initiallyLocked: LockScreenManager.shared.isLocked)
    private weak var viewModel: KannuViewModel?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var currentNotchSize: CGSize?

    /// Whether the target screen uses Dynamic Island (pill) mode.
    private var isDynamicIslandMode: Bool {
        isDynamicIslandModeForScreen(lockContext()?.screen)
    }

    private func isDynamicIslandModeForScreen(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return shouldUseDynamicIslandMode(for: screen.localizedName)
    }

    private init() {
        registerScreenChangeObservers()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func windowSize(for notchSize: CGSize) -> CGSize {
        let indicatorWidth = max(0, notchSize.height - 12)
        let horizontalPadding = isDynamicIslandMode ? 8 : cornerRadiusInsets.closed.bottom
        let topOffset: CGFloat = isDynamicIslandMode ? dynamicIslandTopOffset : 0

        let totalWidth = notchSize.width + (indicatorWidth * 2) + (horizontalPadding * 2)

        return CGSize(width: totalWidth, height: notchSize.height + topOffset)
    }

    private func frame(for windowSize: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let originX = screenFrame.origin.x + (screenFrame.width / 2) - (windowSize.width / 2)
        let originY = screenFrame.origin.y + screenFrame.height - windowSize.height

        return NSRect(x: originX, y: originY, width: windowSize.width, height: windowSize.height)
    }

    private func ensureWindow(windowSize: CGSize, screen: NSScreen) -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: frame(for: windowSize, on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.alphaValue = 0
        window.animationBehavior = .none

        ScreenCaptureVisibilityManager.shared.register(window, scope: .notch)

        self.window = window
        self.hasDelegated = false
        return window
    }

    private func lockContext() -> (notchSize: CGSize, screen: NSScreen)? {
        // This pill is the notch on the lock screen, and it flashes at the notch on unlock: a
        // notch the user hid stays hidden there too.
        guard Defaults[.showNotch] else { return nil }
        guard let screen = LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main else {
            print("[\(timestamp())] LockScreenLiveActivityWindowManager: no main screen available")
            return nil
        }

        guard let viewModel else {
            print("[\(timestamp())] LockScreenLiveActivityWindowManager: no view model configured")
            return nil
        }

        var notchSize = viewModel.closedNotchSize
        if notchSize.width <= 0 || notchSize.height <= 0 {
            notchSize = getClosedNotchSize(screen: screen.localizedName)
        }

        return (notchSize, screen)
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenGeometryChange(reason: "screen-parameters")
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenGeometryChange(reason: "screens-did-wake")
            }
        }
        workspaceObservers = [wakeObserver]
    }

    private func handleScreenGeometryChange(reason: String) {
        guard let window else { return }
        guard window.isVisible || window.alphaValue > 0.01 else { return }
        guard let context = lockContext() else { return }

        let windowSize = windowSize(for: context.notchSize)
        let targetFrame = frame(for: windowSize, on: context.screen)
        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }

        if let hostingView {
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
            hostingView.rootView = LockScreenLiveActivityOverlay(model: overlayModel, animator: overlayAnimator, notchSize: context.notchSize, isDynamicIslandMode: isDynamicIslandMode)
        }

        currentNotchSize = context.notchSize

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: realigned window due to \(reason)")
    }

    /// `forAttentionAlert` lifts the live-activity guard for one call: `flashForAttentionAlert` only.
    private func present(notchSize: CGSize, on screen: NSScreen, forAttentionAlert: Bool = false) {
        guard Defaults[.enableLockScreenLiveActivity] || forAttentionAlert else {
            hideImmediately()
            return
        }
        presentGeneration += 1

        let windowSize = windowSize(for: notchSize)
        let window = ensureWindow(windowSize: windowSize, screen: screen)
        let targetFrame = frame(for: windowSize, on: screen)
        window.setFrame(targetFrame, display: true)

        let overlayView = LockScreenLiveActivityOverlay(model: overlayModel, animator: overlayAnimator, notchSize: notchSize, isDynamicIslandMode: isDynamicIslandMode)

        if let hostingView {
            hostingView.rootView = overlayView
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
        } else {
            let view = NSHostingView(rootView: overlayView)
            view.sizingOptions = []
            view.frame = CGRect(origin: .zero, size: targetFrame.size)
            hostingView = view
            window.setHostedContent(view)
        }

        if let hostingView, window.hostedContentView !== hostingView {
            window.setHostedContent(hostingView)
        }

        window.displayIfNeeded()

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        window.orderFrontRegardless()
        window.alphaValue = 1

        currentNotchSize = notchSize
    }

    func showLocked() {
        hideTask?.cancel()
        guard let context = lockContext() else { return }

        let collapsedScale = LockScreenLiveActivityOverlay.collapsedScale(for: context.notchSize, isDynamicIslandMode: isDynamicIslandMode)

        overlayAnimator.update(isLocked: true)
        overlayModel.showsAgentForAlert = false
        overlayModel.scale = collapsedScale
        overlayModel.opacity = 0

        present(notchSize: context.notchSize, on: context.screen)

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                self.overlayModel.scale = 1
            }
            withAnimation(.easeOut(duration: 0.18)) {
                self.overlayModel.opacity = 1
            }
        }

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: showing locked state")
    }

    /// The attention alert while the Mac is locked and the lock-screen live activity is off: no pill is on
    /// screen, so it shows for one flash and goes. One sleep, cancelled on unlock: no timer and no repeat.
    /// With the live activity on, the pill is already there and the alert's overlay shimmers it.
    func flashForAttentionAlert(duration: TimeInterval) {
        guard LockScreenManager.shared.isLocked, !Defaults[.enableLockScreenLiveActivity] else { return }
        guard let context = lockContext() else { return }
        hideTask?.cancel()
        attentionFlashTask?.cancel()

        overlayAnimator.update(isLocked: true, animated: false)
        // The flash carries the agent's dot and icon (the pill shows only for it).
        overlayModel.showsAgentForAlert = true
        overlayModel.scale = 1
        overlayModel.opacity = 1
        present(notchSize: context.notchSize, on: context.screen, forAttentionAlert: true)

        attentionFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.attentionFlashTask = nil
            self.hideWithAnimation()
        }
    }

    private func cancelAttentionFlash() {
        attentionFlashTask?.cancel()
        attentionFlashTask = nil
        overlayModel.showsAgentForAlert = false
    }

    func showUnlockAndScheduleHide() {
        hideTask?.cancel()
        cancelAttentionFlash()
        guard let context = lockContext() else { return }

        overlayModel.scale = 1
        overlayModel.opacity = 1

        present(notchSize: context.notchSize, on: context.screen)

        overlayAnimator.update(isLocked: false)

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LockScreenAnimationTimings.unlockCollapse))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.hideWithAnimation()
            }
        }
    }

    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil
        cancelAttentionFlash()

        hideWithAnimation()
    }

    private func hideWithAnimation() {
        guard let window else { return }

        let targetScale: CGFloat
        if let notchSize = currentNotchSize {
            targetScale = LockScreenLiveActivityOverlay.collapsedScale(for: notchSize, isDynamicIslandMode: isDynamicIslandMode)
        } else {
            targetScale = 0.7
        }

        withAnimation(.smooth(duration: LockScreenAnimationTimings.unlockCollapse)) {
            overlayModel.opacity = 0
            overlayModel.scale = targetScale
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LockScreenAnimationTimings.unlockCollapse
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }

        let generation = presentGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + LockScreenAnimationTimings.unlockCollapse + 0.02) {
            // A pill presented again since (the next alert's flash, a lock) stays.
            guard self.presentGeneration == generation else { return }
            window.orderOut(nil)
            self.currentNotchSize = nil
        }

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: HUD hidden")
    }

    func configure(viewModel: KannuViewModel) {
        self.viewModel = viewModel
    }
}
