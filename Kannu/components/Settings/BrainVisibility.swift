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
import Combine

/// Whether any part of Brain's window is on screen. A live view on a page reads this and stops while it is false:
/// Brain closed, minimised, hidden with the app, fully covered, or left behind in another Space (docs/SETTINGS.md,
/// "Live data"). Closing alone is not enough to go by, because a full-screen Brain parked in another Space stays
/// visible to AppKit (docs/REGRESSIONS.md, entry 22).
@MainActor
final class BrainVisibility: ObservableObject {
    static let shared = BrainVisibility()

    /// False until the window is first on screen, so nothing live starts at launch.
    @Published private(set) var isOnScreen = false

    private init() {}

    /// From the window's occlusion state, which AppKit changes in every one of the cases above.
    /// `SettingsWindowController` calls it whenever that state changes.
    func update(for window: NSWindow) {
        let onScreen = window.isVisible && window.occlusionState.contains(.visible)
        if onScreen != isOnScreen { isOnScreen = onScreen }
    }
}
