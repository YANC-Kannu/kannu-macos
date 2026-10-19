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
import Combine
import AppKit
import Defaults
import SwiftUI

@MainActor
class CapsLockManager: ObservableObject {
    static let shared = CapsLockManager()
    
    @Published var isCapsLockActive: Bool = false
    
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var timerObserver: AnyCancellable?
    private let coordinator = KannuViewCoordinator.shared
    private let capsLockAnimation = Animation.spring(response: 0.32, dampingFraction: 0.85)

    private init() {
        // Get initial state
        isCapsLockActive = NSEvent.modifierFlags.contains(.capsLock)

        // A timer that starts while Caps Lock is on takes the closed notch back: the indicator
        // that waits for Caps Lock to be released ends. Only the current value is read, so a
        // replace that coalesces into "no change" changes nothing here.
        timerObserver = TimerManager.shared.$isTimerActive
            .removeDuplicates()
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.endHeldIndicatorForTimer()
            }

        // Monitor flag changes when app is focused
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // Monitor flag changes globally (even when app is not focused)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        print("CapsLockManager: ✅ Initialized with Caps Lock \(isCapsLockActive ? "ON" : "OFF")")
    }
    
    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let newState = event.modifierFlags.contains(.capsLock)
        
        guard newState != isCapsLockActive else { return }
        
        withAnimation(capsLockAnimation) {
            isCapsLockActive = newState
        }
        
        print("CapsLockManager: Caps Lock \(newState ? "ACTIVATED" : "DEACTIVATED")")
        
        // Only show/hide if feature is enabled
        guard Defaults[.enableCapsLockIndicator] else { return }
        
        if newState {
            // Show inline indicator: until Caps Lock is released, or only for the usual HUD time
            // while a running timer holds the closed notch.
            coordinator.toggleSneakPeek(
                status: true,
                type: .capsLock,
                duration: timerHoldsClosedNotch ? Self.flashDuration : .infinity,
                value: 1.0,
                icon: ""
            )
        } else {
            // Hide indicator
            coordinator.toggleSneakPeek(
                status: false,
                type: .capsLock,
                duration: 0,
                value: 0,
                icon: ""
            )
        }
    }

    /// How long Caps Lock shows while a timer holds the notch: `toggleSneakPeek`'s HUD default.
    static let flashDuration: TimeInterval = 1.5

    /// A running timer holds the closed notch (`ContentView.timerOwnsClosedNotch`), so Caps Lock
    /// flashes instead of hiding the timer until it is released.
    private var timerHoldsClosedNotch: Bool {
        TimerManager.shared.isTimerActive && coordinator.timerLiveActivityEnabled
    }

    private func endHeldIndicatorForTimer() {
        guard isCapsLockActive, Defaults[.enableCapsLockIndicator], coordinator.timerLiveActivityEnabled,
              coordinator.sneakPeek.show, coordinator.sneakPeek.type == .capsLock else { return }
        coordinator.toggleSneakPeek(status: false, type: .capsLock, duration: 0, value: 0, icon: "")
    }
}
