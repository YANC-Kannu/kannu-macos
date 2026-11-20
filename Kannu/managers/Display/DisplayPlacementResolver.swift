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

import CoreGraphics
import Foundation

/// Which displays Kannu puts itself on.
///
/// This replaces three settings that together could not say the obvious thing. `showOnAllDisplays`
/// defaulted to true, so every display got a window; every non-notch display then hid its island
/// until the pointer rested at the top edge for a second; and neither row said which display it
/// meant. A user with a MacBook and a monitor saw Kannu in the notch, nothing on the monitor, and no
/// way to tell why.
public enum DisplayPlacement: String, CaseIterable, Identifiable, Equatable {
    /// The default: the external display when one is plugged in, the built-in when none is.
    case externalTakesOver
    /// One Kannu per display.
    case allDisplays
    /// The built-in display only, whatever else is connected.
    case builtInOnly
    /// One display the user picked, remembered by its UUID.
    case chooseDisplay

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .externalTakesOver: return String(localized: "External display takes over")
        case .allDisplays: return String(localized: "All displays")
        case .builtInOnly: return String(localized: "Built-in display only")
        case .chooseDisplay: return String(localized: "A display I choose")
        }
    }

    public var description: String {
        switch self {
        case .externalTakesOver:
            return String(localized: "Moves to the external display; follows the pointer with several.")
        case .allDisplays:
            return String(localized: "One Kannu on every display.")
        case .builtInOnly:
            return String(localized: "Stays on the built-in display, ignoring others.")
        case .chooseDisplay:
            return String(localized: "Stays on your pick; falls back to the main display.")
        }
    }
}

/// Everything the placement decision needs about one screen, so the decision can be tested without
/// an `NSScreen` — and without the two monitors this was written on a Mac that does not have.
public struct ScreenFacts: Equatable {
    /// The live identity: unique among the displays connected now, not promised across a reconnect.
    public let id: CGDirectDisplayID
    /// For people to read. Two identical monitors share it, so nothing is ever looked up by it.
    public let name: String
    public let isBuiltIn: Bool
    public let hasNotch: Bool
    public let frame: CGRect
    /// The stored identity (`CGDisplayCreateUUIDFromDisplayID`): the one a saved choice keeps, because
    /// it survives the reconnects and reboots that can hand the same monitor a new `id`.
    public let uuid: String?

    public init(id: CGDirectDisplayID, name: String, isBuiltIn: Bool, hasNotch: Bool = false, frame: CGRect = .zero,
                uuid: String? = nil) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.hasNotch = hasNotch
        self.frame = frame
        self.uuid = uuid
    }
}

/// The one place that answers "where does Kannu go".
///
/// Pure, and keyed on `CGDirectDisplayID` rather than `localizedName`, because two identical
/// monitors share a name and every override in the app used to collapse them into one.
public enum DisplayPlacementResolver {

    /// The displays Kannu should occupy, in the order given.
    ///
    /// - Parameters:
    ///   - pointerOn: the display the pointer is on, used only when the mode is
    ///     `externalTakesOver` and two or more externals are connected — the only case with a
    ///     running cost, which is why it is the only case that tracks the pointer.
    ///   - chosenUUID: the UUID of the display picked in Settings (`preferredScreenUUID`).
    ///   - chosenName: the pre-UUID choice (`preferred_screen_name`), read only while no UUID is
    ///     stored: a stored UUID that is not connected falls back, never to a namesake.
    ///   - mainScreen: the display to fall back to when a choice cannot be honoured.
    public static func screensToShowOn(
        _ screens: [ScreenFacts],
        mode: DisplayPlacement,
        chosenUUID: String? = nil,
        chosenName: String? = nil,
        pointerOn: CGDirectDisplayID? = nil,
        mainScreen: CGDirectDisplayID? = nil
    ) -> [CGDirectDisplayID] {
        guard !screens.isEmpty else { return [] }
        let fallback = mainScreen.flatMap { id in screens.first { $0.id == id }?.id } ?? screens[0].id

        switch mode {
        case .allDisplays:
            return screens.map(\.id)

        case .builtInOnly:
            // No built-in at all means clamshell, or a Mac mini. Showing nothing would make the app
            // vanish with no way to get it back, so it falls back like `chooseDisplay` does.
            return [screens.first(where: \.isBuiltIn)?.id ?? fallback]

        case .chooseDisplay:
            if let chosenUUID {
                return [screens.first { $0.uuid == chosenUUID }?.id ?? fallback]
            }
            guard let chosenName else { return [fallback] }
            return [screens.first { $0.name == chosenName }?.id ?? fallback]

        case .externalTakesOver:
            let externals = screens.filter { !$0.isBuiltIn }
            if externals.isEmpty {
                return [screens.first(where: \.isBuiltIn)?.id ?? fallback]
            }
            if externals.count == 1 {
                return [externals[0].id]
            }
            // Two or more externals: no way to guess which one the user is looking at, so follow the
            // pointer. A pointer on the built-in display still counts — that is where they are.
            if let pointerOn, screens.contains(where: { $0.id == pointerOn }) {
                return [pointerOn]
            }
            return [fallback]
        }
    }

    /// True when the placement needs the pointer tracked. Every other case costs nothing, and the
    /// monitor is installed and torn down on this answer alone.
    public static func needsPointerTracking(_ screens: [ScreenFacts], mode: DisplayPlacement) -> Bool {
        mode == .externalTakesOver && screens.filter { !$0.isBuiltIn }.count >= 2
    }

    // MARK: - Identity

    /// The screen with `id`, or nil when that display is gone. Never one that merely shares its
    /// name: two identical monitors are two screens, and a name lookup always found the first.
    public static func screen(withID id: CGDirectDisplayID?, in screens: [ScreenFacts]) -> ScreenFacts? {
        guard let id else { return nil }
        return screens.first { $0.id == id }
    }

    /// The UUID to store for the pre-UUID choice, or nil when there is nothing to store yet.
    ///
    /// A stored UUID is final, connected or not. Without one, a legacy name that a connected display
    /// carries picks the first such display, as the name lookup always did, and from then on an
    /// identical second monitor cannot take it. A name that matches nothing stays a name: the dock
    /// may wake after launch, and storing "main display" now would lose the choice for good.
    public static func chosenDisplayUUID(
        storedUUID: String?,
        legacyName: String?,
        screens: [ScreenFacts]
    ) -> String? {
        if let storedUUID { return storedUUID }
        guard let legacyName else { return nil }
        return screens.first { $0.name == legacyName }?.uuid
    }

    /// Whether the displays changed in a way that must re-place the notch: one came or went, one
    /// came back under a new id, or one moved. Compared as id-to-frame pairs, because two
    /// equal-sized displays that swap places leave both the id set and the frame set unchanged.
    public static func layoutChanged(from previous: [ScreenFacts]?, to current: [ScreenFacts]) -> Bool {
        guard let previous else { return true }
        func layout(_ screens: [ScreenFacts]) -> [CGDirectDisplayID: CGRect] {
            Dictionary(screens.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        }
        return previous.count != current.count || layout(previous) != layout(current)
    }

    /// A window that follows the notch (the timer and music controls) may skip a refresh only
    /// when neither its metrics nor its display changed. Metrics alone left it on the old display
    /// when the notch moved to another one of the same size.
    public static func canSkipRefresh<Metrics: Equatable>(
        last: (metrics: Metrics, display: CGDirectDisplayID?)?,
        next: (metrics: Metrics, display: CGDirectDisplayID?)
    ) -> Bool {
        guard let last else { return false }
        return last.metrics == next.metrics && last.display == next.display
    }

    /// The display a temporary HUD for the single notch window belongs on: the notch's display,
    /// else the main one, else the first connected. Nil with one window per display, where every
    /// window shows it. Asked again whenever the notch's display changes, so a HUD up while the
    /// notch moves (an unplug, a reconnect under a new id) follows it rather than staying hidden.
    public static func hudTargetDisplay(
        oneWindowPerDisplay: Bool,
        notchDisplay: CGDirectDisplayID?,
        mainScreen: CGDirectDisplayID?,
        connected: [CGDirectDisplayID]
    ) -> CGDirectDisplayID? {
        guard !oneWindowPerDisplay else { return nil }
        for candidate in [notchDisplay, mainScreen].compactMap({ $0 }) where connected.contains(candidate) {
            return candidate
        }
        return connected.first
    }

    /// The Display picker's titles, in the order given: the name, numbered from 1 when displays
    /// share it, so two identical monitors read as two choices.
    public static func pickerTitles(_ screens: [ScreenFacts]) -> [String] {
        var counts: [String: Int] = [:]
        for screen in screens { counts[screen.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return screens.map { screen in
            guard counts[screen.name, default: 0] > 1 else { return screen.name }
            seen[screen.name, default: 0] += 1
            return "\(screen.name) (\(seen[screen.name]!))"
        }
    }
}
