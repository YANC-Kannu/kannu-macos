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
import Defaults
import LaunchAtLogin
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.displayPlacement) var displayPlacement
    @Default(.screenCaptureVisibility) var screenCaptureVisibility
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.alwaysShowOnNonNotchDisplays) var alwaysShowOnNonNotchDisplays
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) var musicGestureBehavior
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.externalDisplayStyle) var externalDisplayStyle

    /// `SMAppService.mainApp` registers whatever bundle is currently running, so a build
    /// launched from DerivedData or a build folder pins that path as the login item forever —
    /// the OS then keeps relaunching that stale copy even after a newer release is installed
    /// in /Applications. Only offer the toggle when we're running from a real install location.
    private var isRunningFromApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.general.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                SettingsRow("Menubar icon", description: "The eye in the menu bar. Click it to open the notch on the display you are on; right-click for Show Notch, Brain, updates, restart and quit. It stays while the notch is hidden.") {
                    Defaults.Toggle(key: .menubarIcon) {
                        Text("Menubar icon")
                    }
                }
                .settingsHighlight(id: highlightID("Menubar icon"))
                if isRunningFromApplicationsFolder {
                    LaunchAtLogin.Toggle {
                        Text("Launch at login")
                    }
                    .settingsHighlight(id: highlightID("Launch at login"))
                    // macOS can accept the registration but park it pending user approval; the
                    // toggle alone would just read off with no explanation and no way forward.
                    if SMAppService.mainApp.status == .requiresApproval {
                        LabeledContent {
                            Button("Open Login Items") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                        } label: {
                            Text("macOS needs you to approve Kannu in Login Items.")
                                .settingsDescriptionStyle()
                        }
                    }
                } else {
                    SettingsRow("Launch at login", description: "Move Kannu to your Applications folder to enable this.") {
                        Toggle(isOn: .constant(false)) {
                            Text("Launch at login")
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Launch at login"))
                }
                // A row, not the toolbar button it replaces: search can only land on rows inside
                // the form, and "quit" or "exit" found nothing when the only Quit sat in the toolbar.
                SettingsActionRow("Quit Kannu", description: "Stops Kannu and its notch until you open it again.") {
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }
                .settingsHighlight(id: highlightID("Quit Kannu"))
                SettingsRow("Where Kannu appears", description: displayPlacement.description) {
                    Picker("", selection: $displayPlacement) {
                        ForEach(DisplayPlacement.allCases) { placement in
                            Text(placement.localizedName).tag(placement)
                        }
                    }
                }
                .onChange(of: displayPlacement) {
                    NotificationCenter.default.post(name: Notification.Name.displayPlacementChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Where Kannu appears"))

                // Always mounted, disabled when it does not apply: a row that only exists in one
                // mode makes its own search entry land on nothing in every other mode, and the
                // inventory test reads source text so it cannot catch that.
                Picker("Display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap({ $0.localizedName })
                }
                .onChange(of: coordinator.preferredScreen) {
                    NotificationCenter.default.post(name: Notification.Name.displayPlacementChanged, object: nil)
                }
                .disabled(displayPlacement != .chooseDisplay)
                .settingsHighlight(id: highlightID("Display"))
                SettingsRow("Screenshots & recordings", description: screenCaptureVisibility.description) {
                    Picker("", selection: $screenCaptureVisibility) {
                        ForEach(ScreenCaptureVisibility.allCases) { option in
                            Text(option.localizedName).tag(option)
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Screenshots & recordings"))
            } header: {
                SettingsSectionHeader("System features")
            }

            Section {
                // Onboarding's Permissions rows: what a Not now there held back is allowed here,
                // one macOS dialog at a time.
                VStack(spacing: 10) {
                    // The current music source decides whether a "Control …" row shows.
                    ForEach(LaunchPermissionManager.rows(musicSource: Defaults[.mediaController])) { permission in
                        LaunchPermissionRow(permission: permission, musicSource: Defaults[.mediaController])
                    }
                }
                // Shared with onboarding, so Allow stays `.borderedProminent`, and its white label
                // cannot be read on the root's eye blue in dark.
                .tint(.accentColor)
                .settingsHighlight(id: highlightID("Permissions"))
            } header: {
                SettingsSectionHeader("Permissions")
            } footer: {
                SettingsFooter("Kannu asks macOS for a permission only when you press Allow. What you skip stays off until you allow it here.")
            }

            Section {
                Picker(selection: $notchHeightMode, label:
                        Text("Notch display height")) {
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                        .onChange(of: notchHeightMode) {
                            switch notchHeightMode {
                            case .matchRealNotchSize:
                                notchHeight = 38
                            case .matchMenuBar:
                                notchHeight = 44
                            case .custom:
                                notchHeight = 38
                            }
                            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        }
                        .settingsHighlight(id: highlightID("Notch display height"))
                if notchHeightMode == .custom {
                    SettingsSliderRow(title: Text("Custom notch size - \(notchHeight, specifier: "%.0f")"),
                                      value: $notchHeight, in: 15...45, step: 1, valueText: nil)
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    SettingsSliderRow(title: Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")"),
                                      value: $nonNotchHeight, in: 0...40, step: 1, valueText: nil)
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                SettingsSectionHeader("Notch Height")
            }

            NotchBehaviour()

            gestureControls()
        }
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            .settingsHighlight(id: highlightID("Enable gestures"))
            if enableGestures {
                Defaults.Toggle(key: .enableHorizontalMusicGestures) {
                    Text("Media change with horizontal gestures")
                }
                .settingsHighlight(id: highlightID("Horizontal media gestures"))

                if enableHorizontalMusicGestures {
                    SettingsRow("Gesture skip behavior", description: musicGestureBehavior.description) {
                        Picker("Gesture skip behavior", selection: $musicGestureBehavior) {
                            ForEach(MusicSkipBehavior.allCases) { behavior in
                                Text(behavior.displayName)
                                    .tag(behavior)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .settingsHighlight(id: highlightID("Gesture skip behavior"))

                    Defaults.Toggle(key: .reverseSwipeGestures) {
                        Text("Reverse swipe gestures")
                    }
                    .settingsHighlight(id: highlightID("Reverse swipe gestures"))
                }

                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .settingsHighlight(id: highlightID("Close gesture"))
                SettingsSliderRow("Gesture sensitivity", value: $gestureSensitivity, in: 100...300, step: 100,
                                  valueText: Text(gestureSensitivity == 100 ? "High" : gestureSensitivity == 200 ? "Medium" : "Low"))

                Defaults.Toggle(key: .reverseScrollGestures) {
                    Text("Reverse open/close scroll gestures")
                }
                .settingsHighlight(id: highlightID("Reverse scroll gestures"))
            }
        } header: {
            HStack {
                SettingsSectionHeader("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            SettingsFooter("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .extendHoverArea) {
                Text("Extend hover area")
            }
            .settingsHighlight(id: highlightID("Extend hover area"))
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable haptics")
            }
            .settingsHighlight(id: highlightID("Enable haptics"))
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            .settingsHighlight(id: highlightID("Open notch on hover"))
            // Also shown with hover-to-open off when a display hides until hovered: the same
            // value is the dwell before the hidden island slides in.
            if openNotchOnHover || !alwaysShowOnNonNotchDisplays {
                SettingsSliderRow("Minimum hover duration",
                                  description: "How long the pointer must rest on the notch before it opens. On displays where Kannu hides until hovered, this is also how long the pointer must rest at the top edge before the island slides in.",
                                  value: $minimumHoverDuration, in: 0...2, step: 0.1,
                                  valueText: Text("\(minimumHoverDuration, specifier: "%.1f")s"))
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Minimum hover duration"))
            }
            SettingsRow("External display style", description: externalDisplayStyle.description) {
                Picker("External display style", selection: $externalDisplayStyle) {
                    ForEach(ExternalDisplayStyle.allCases) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("External display style"))
            SettingsRow("Always show on non-notch displays", description: "By default the notch hides on external displays and appears when you hover near the top. Turn this on to keep it visible.") {
                Defaults.Toggle(key: .alwaysShowOnNonNotchDisplays) {
                    Text("Always show on non-notch displays")
                }
            }
            .settingsHighlight(id: highlightID("Always show on non-notch displays"))
        } header: {
            SettingsSectionHeader("Notch behavior")
        }

        perDisplayOverridesSection
    }

    /// Per-display overrides for the two settings above.
    ///
    /// Only screens without a physical notch are listed: a built-in notched display always
    /// renders the standard notch shape regardless of settings, so offering a choice there
    /// would be a control that does nothing.
    @ViewBuilder
    private var perDisplayOverridesSection: some View {
        perDisplayOverrideSections(overrideDisplays)
    }

    /// One entry per *name*: the override dictionaries are keyed by `localizedName`, so two
    /// identical monitors share one entry, and two rows with one identity made SwiftUI's `ForEach`
    /// undefined. One row for the pair is honest about what the setting can express; keying the
    /// overrides on `CGDirectDisplayID` is the real fix and is recorded as a follow-up.
    private var overrideDisplays: [(name: String, isBuiltIn: Bool)] {
        var seen = Set<String>()
        return NSScreen.screens
            .filter { $0.safeAreaInsets.top <= 0 }
            .map { (name: $0.localizedName, isBuiltIn: isBuiltInDisplay($0)) }
            .filter { seen.insert($0.name).inserted }
    }

    /// One group per display: its two overrides and Reset. The explanation sits under the last one.
    @ViewBuilder
    func perDisplayOverrideSections(_ displays: [(name: String, isBuiltIn: Bool)]) -> some View {
        ForEach(displays, id: \.name) { display in
            let name = display.name
            Section {
                Picker("Style", selection: displayStyleBinding(for: name)) {
                    Text("Follow default").tag(ExternalDisplayStyle?.none)
                    ForEach(ExternalDisplayStyle.allCases) { style in
                        Text(style.localizedName).tag(ExternalDisplayStyle?.some(style))
                    }
                }
                Picker("Always show", selection: alwaysShowBinding(for: name)) {
                    Text("Follow default").tag(Bool?.none)
                    Text("On").tag(Bool?.some(true))
                    Text("Off").tag(Bool?.some(false))
                }
                SettingsActionRow {
                    Button("Reset") {
                        Defaults[.displayStyleOverrides].removeValue(forKey: name)
                        Defaults[.alwaysShowOverrides].removeValue(forKey: name)
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .disabled(
                        Defaults[.displayStyleOverrides][name] == nil
                            && Defaults[.alwaysShowOverrides][name] == nil
                    )
                }
            } header: {
                HStack(spacing: 6) {
                    SettingsSectionHeader(name)
                    if display.isBuiltIn {
                        customBadge(text: String(localized: "Built-in"))
                    }
                }
            } footer: {
                if display.name == displays.last?.name {
                    SettingsFooter("Displays without their own setting follow the defaults above. Built-in displays with a notch always use the notch shape and aren't listed.")
                }
            }
        }
    }

    private func displayStyleBinding(for name: String) -> Binding<ExternalDisplayStyle?> {
        Binding(
            get: { Defaults[.displayStyleOverrides][name] },
            set: { newValue in
                if let newValue {
                    Defaults[.displayStyleOverrides][name] = newValue
                } else {
                    Defaults[.displayStyleOverrides].removeValue(forKey: name)
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
        )
    }

    private func alwaysShowBinding(for name: String) -> Binding<Bool?> {
        Binding(
            get: { Defaults[.alwaysShowOverrides][name] },
            set: { newValue in
                if let newValue {
                    Defaults[.alwaysShowOverrides][name] = newValue
                } else {
                    Defaults[.alwaysShowOverrides].removeValue(forKey: name)
                }
                // Changes the closed-notch offset, so the window geometry needs re-evaluating.
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
        )
    }
}

#if DEBUG
extension GeneralSettings {
    /// DEBUG snapshot harness: the per-display overrides, which list only displays without a
    /// notch (none on a lone MacBook), for two made-up displays.
    static func snapshotPerDisplayRows() -> AnyView {
        AnyView(Form {
            GeneralSettings().perDisplayOverrideSections([
                (name: "Studio Display (made up)", isBuiltIn: false),
                (name: "Built-in Display (made up)", isBuiltIn: true),
            ])
        })
    }
}
#endif
