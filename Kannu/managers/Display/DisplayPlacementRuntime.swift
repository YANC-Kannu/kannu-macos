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
import Defaults

/// The thin layer between live `NSScreen`s and the pure `DisplayPlacementResolver`.
///
/// Nothing is stored: every answer is computed from the screens as they are right now. A cached set
/// of displays is exactly what goes stale when a dock wakes and fires four configuration changes in a
/// row, and `NSScreen` objects are not promised to survive a reconfiguration — so identity lives in
/// `CGDirectDisplayID`, which is stable, and the pointer is read when asked rather than tracked.
@MainActor
enum DisplayPlacementRuntime {

    /// The pre-UUID choice, read raw so that it is never registered as a default again.
    static let legacyPreferredScreenNameKey = "preferred_screen_name"

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.displayID
    }

    static func facts(for screens: [NSScreen] = NSScreen.screens) -> [ScreenFacts] {
        screens.compactMap { screen in
            guard let id = displayID(for: screen) else { return nil }
            return ScreenFacts(
                id: id,
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                hasNotch: screen.safeAreaInsets.top > 0,
                frame: screen.frame,
                uuid: NSScreen.displayUUID(for: id)
            )
        }
    }

    /// The chosen display's UUID, carrying an old name-based choice over the first time its
    /// display is connected (`DisplayPlacementResolver.chosenDisplayUUID` is the rule).
    static func chosenDisplayUUID(_ screens: [ScreenFacts]) -> String? {
        let stored = Defaults[.preferredScreenUUID]
        let legacy = UserDefaults.standard.string(forKey: legacyPreferredScreenNameKey)
        let chosen = DisplayPlacementResolver.chosenDisplayUUID(storedUUID: stored, legacyName: legacy, screens: screens)
        if stored == nil, let chosen {
            Defaults[.preferredScreenUUID] = chosen
        }
        return chosen
    }

    /// Stores a pick from Settings. The name goes along for a downgrade, whose builds read only it.
    /// Carries the name-keyed per-display overrides of the connected displays over to their UUIDs.
    ///
    /// Runs at launch and on every display change, outside any view, so no view writes Defaults
    /// while it renders. The name-keyed dictionaries are only read here from now on: a downgrade
    /// still finds the overrides set before this version, and nothing writes to them again.
    static func carryOverNameKeyedOverrides(screens given: [ScreenFacts]? = nil) {
        let screens = given ?? facts()
        let byNameStyle = Defaults[.displayStyleOverrides]
        let byNameAlwaysShow = Defaults[.alwaysShowOverrides]
        guard !byNameStyle.isEmpty || !byNameAlwaysShow.isEmpty else { return }

        let carried = Defaults[.displayOverridesCarriedUUIDs]
        let pending = DisplayPlacementResolver.displaysAwaitingOverrideCarryOver(screens, carried: Set(carried))
        guard !pending.isEmpty else { return }

        let style = DisplayPlacementResolver.carryOverOverrides(
            byNameStyle, into: Defaults[.displayStyleOverridesByUUID], for: pending)
        if style != Defaults[.displayStyleOverridesByUUID] {
            Defaults[.displayStyleOverridesByUUID] = style
        }
        let alwaysShow = DisplayPlacementResolver.carryOverOverrides(
            byNameAlwaysShow, into: Defaults[.alwaysShowOverridesByUUID], for: pending)
        if alwaysShow != Defaults[.alwaysShowOverridesByUUID] {
            Defaults[.alwaysShowOverridesByUUID] = alwaysShow
        }
        Defaults[.displayOverridesCarriedUUIDs] = carried + pending.compactMap(\.uuid)
    }

    /// The key of the per-display overrides for the display `id`, or nil when it has no UUID. Reads
    /// CoreGraphics only, so the sizing helpers can ask from any context.
    nonisolated static func overrideKey(for id: CGDirectDisplayID?) -> String? {
        id.flatMap(NSScreen.displayUUID(for:))
    }

    static func choose(_ screen: ScreenFacts) {
        guard let uuid = screen.uuid else { return }
        UserDefaults.standard.set(screen.name, forKey: legacyPreferredScreenNameKey)
        Defaults[.preferredScreenUUID] = uuid
    }

    /// The display the pointer is on, or nil when it cannot be placed.
    static func pointerDisplayID() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        // `NSMouseInRect`, not `CGRect.contains`: the latter is half-open and excludes the top and
        // right edges, and the top edge is exactly where a pointer goes to reach the notch.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }) else { return nil }
        return displayID(for: screen)
    }

    static func mainDisplayID() -> CGDirectDisplayID? {
        (NSScreen.main ?? NSScreen.screens.first).flatMap(displayID(for:))
    }

    /// The displays Kannu should occupy right now.
    static func activeDisplayIDs(mode: DisplayPlacement = Defaults[.displayPlacement]) -> [CGDirectDisplayID] {
        let screens = facts()
        let chosenUUID = mode == .chooseDisplay ? chosenDisplayUUID(screens) : nil
        return DisplayPlacementResolver.screensToShowOn(
            screens,
            mode: mode,
            chosenUUID: chosenUUID,
            chosenName: UserDefaults.standard.string(forKey: legacyPreferredScreenNameKey),
            pointerOn: pointerDisplayID(),
            mainScreen: mainDisplayID()
        )
    }

    /// The single screen Kannu belongs on, for the modes that use one window.
    static func activeScreen(mode: DisplayPlacement = Defaults[.displayPlacement]) -> NSScreen? {
        NSScreen.withDisplayID(activeDisplayIDs(mode: mode).first)
    }

    static func needsPointerTracking(mode: DisplayPlacement = Defaults[.displayPlacement]) -> Bool {
        DisplayPlacementResolver.needsPointerTracking(facts(), mode: mode)
    }
}

extension DisplayPlacement {
    /// Whether Kannu runs one window per display (the `windows`/`viewModels` dictionaries) or a
    /// single window on a resolved screen.
    ///
    /// Keyed on the *mode*, never on how many displays happen to be connected: if the count decided
    /// this, plugging a second monitor in would move Kannu between two different window lifecycles
    /// mid-flight, which is a worse bug than the one being fixed.
    var usesOneWindowPerDisplay: Bool { self == .allDisplays }
}

extension NSScreen {
    /// This screen's live identity, which every lookup matches on. `localizedName` is for people to
    /// read: two identical monitors share it, and a lookup by it always found the first of the pair.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The connected screen with `id`, or nil when that display is gone. Nil in, nil out: a caller
    /// that wants the main screen for "no screen yet" says so.
    static func withDisplayID(_ id: CGDirectDisplayID?) -> NSScreen? {
        guard let id else { return nil }
        return screens.first { $0.displayID == id }
    }

    /// The display's UUID, the identity a stored choice keeps across reconnects.
    static func displayUUID(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
