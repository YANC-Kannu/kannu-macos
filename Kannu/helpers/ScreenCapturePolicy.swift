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

/// What a window is, for screen capture. Said once, when the window registers with
/// `ScreenCaptureVisibilityManager`.
enum ScreenCaptureScope: Int {
    /// The notch and everything drawn as part of it: the music and timer satellites, the
    /// lock-screen widgets, the fullscreen artwork.
    case notch
    /// A standalone window: Brain (the Settings window), onboarding, the clipboard, the Screen Assistant.
    case panel
}

/// Which Kannu windows stay out of screenshots, recordings and capture-based thumbnails
/// (`NSWindow.sharingType = .none`).
///
/// The default hides the notch. A capture of a notched display shows a continuous menu bar where
/// the hardware notch is, so Kannu's black shape in that spot reads as an empty blob, not a notch,
/// in every screenshot and in a window switcher's desktop preview. Brain and the other panels
/// stay capturable unless the user asks for everything hidden.
///
/// Foundation-only so the logic target can pin the rule; the app target adds
/// `Defaults.Serializable` next to its key.
enum ScreenCaptureVisibility: String, CaseIterable, Identifiable {
    case hideNotch
    case hideEverything
    case showEverything

    var id: String { rawValue }

    func hides(_ scope: ScreenCaptureScope) -> Bool {
        switch self {
        case .hideNotch: return scope == .notch
        case .hideEverything: return true
        case .showEverything: return false
        }
    }

    var localizedName: String {
        switch self {
        case .hideNotch: return String(localized: "Hide the notch")
        case .hideEverything: return String(localized: "Hide everything")
        case .showEverything: return String(localized: "Show everything")
        }
    }

    var description: String {
        switch self {
        case .hideNotch:
            return String(localized: "The notch, its music and timer controls and the lock-screen widgets stay out of screenshots and recordings. Brain and other windows are captured.")
        case .hideEverything:
            return String(localized: "Every Kannu window stays out of screenshots and recordings, Brain included.")
        case .showEverything:
            return String(localized: "Kannu appears in screenshots and recordings.")
        }
    }
}
