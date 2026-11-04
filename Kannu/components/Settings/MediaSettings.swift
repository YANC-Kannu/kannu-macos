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

import Defaults
import SwiftUI

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenMusicAlbumParallaxEnabled
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.visualizerBarCount) private var visualizerBarCount
    @Default(.enableWaveformScrubber) private var enableWaveformScrubber
    @Default(.colorExtractionMode) private var colorExtractionMode
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity


    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.media.highlightID(for: title)
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls
    }

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.localizedName).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music Source"))
            } header: {
                SettingsSectionHeader("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsFooter("YouTube Music requires this third-party app to be installed: ")
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .buttonStyle(.link)
                            .font(SettingsTheme.description)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsFooter(String(localized: "'Now Playing' was the only option on previous versions and works with all media apps."))
                        SettingsFooter(String(localized: "Uses macOS Now Playing when Amazon Music is the active source. Timeline scrubbing may be unavailable."))
                    }
                }
            }

            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
            }

            Section {
                Defaults.Toggle(key: .showStandardMediaControls) {
                    Text("Show media controls in Dynamic Island")
                }
                .settingsHighlight(id: highlightID("Show media controls in Dynamic Island"))

                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) {
                    Text("Auto-hide inactive notch media player")
                }
                .disabled(!showStandardMediaControls)
                .settingsHighlight(id: highlightID("Auto-hide inactive notch media player"))
            } header: {
                SettingsSectionHeader("Dynamic Island Visibility")
            } footer: {
                if standardControlsSuppressed {
                    SettingsFooter("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
                } else if !autoHideInactiveNotchMediaPlayer {
                    SettingsFooter("When off, the notch player stays visible with placeholder info while nothing plays.")
                }
            }
            Section {
                Defaults.Toggle(key: .showShuffleAndRepeat) {
                    HStack {
                        Text("Enable customizable controls")
                        customBadge(text: "Beta")
                    }
                }
                if showShuffleAndRepeat {
                    SettingsRow("Show \"Change Media Output\" control", description: "Adds the AirPlay/route picker button back to the customizable controls palette.") {
                        Defaults.Toggle(key: .showMediaOutputControl) {
                            Text("Show \"Change Media Output\" control")
                        }
                    }
                    .settingsHighlight(id: highlightID("Show Change Media Output control"))
                    MusicSlotConfigurationView()
                }
            } header: {
                SettingsSectionHeader("Media controls")
            } footer: {
                if !showShuffleAndRepeat {
                    SettingsFooter("Turn on customizable controls to rearrange media buttons.")
                }
            }

            Section(header: Text("Lock Screen Media")) {
                SettingsRow("Enable album art parallax", description: "Applies the notch-style parallax effect to the lock screen media widget album art.") {
                    Defaults.Toggle(key: .lockScreenMusicAlbumParallaxEnabled) {
                        Text("Enable album art parallax")
                    }
                }
                .settingsHighlight(id: highlightID("Enable album art parallax"))
            }
            if musicControlWindowEnabled {
                Section {
                    SettingsRow("Skip buttons", description: musicSkipBehavior.description) {
                        Picker("Skip buttons", selection: $musicSkipBehavior) {
                            ForEach(MusicSkipBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .settingsHighlight(id: highlightID("Skip buttons"))
                } header: {
                    SettingsSectionHeader("Floating window panel skip behaviour")
                }
            }
            Section {
                SettingsRow("Enable music live activity", description: standardControlsSuppressed
                            ? Text("Standard notch media controls are hidden while this toggle is off.") : nil) {
                    Toggle(
                        "Enable music live activity",
                        isOn: $coordinator.musicLiveActivityEnabled.animation()
                    )
                }
                .disabled(standardControlsSuppressed)
                SettingsRow("Show floating media controls", description: "Shows play/pause and skip buttons beside the notch while music is active.") {
                    Defaults.Toggle(key: .musicControlWindowEnabled) {
                        Text("Show floating media controls")
                    }
                }
                .disabled(!coordinator.musicLiveActivityEnabled || standardControlsSuppressed)
                Toggle("Enable sneak peek", isOn: $enableSneakPeek)
                Toggle("Show sneak peek on playback changes", isOn: $showSneakPeekOnTrackChange)
                    .disabled(!enableSneakPeek)
                Defaults.Toggle(key: .enableLyrics) {
                    Text("Enable lyrics")
                }
                .settingsHighlight(id: highlightID("Enable lyrics"))
                SettingsRow("Show live canvas in Dynamic Island", description: "Shows the app's live canvas in place of album art when one is available.") {
                    Defaults.Toggle(key: .showLiveCanvasInDynamicIsland) {
                        Text("Show live canvas in Dynamic Island")
                    }
                }
                .settingsHighlight(id: highlightID("Show live canvas in Dynamic Island"))

                // How much the album art moves with the pointer.
                SettingsSliderRow("Parallax Effect Intensity", value: $parallaxEffectIntensity, in: 0...12, step: 1.0,
                                  valueText: Text("\(parallaxEffectIntensity, specifier: "%0.1f")"))
                .settingsHighlight(id: highlightID("Enable album art parallax effect"))


                Picker("Sneak Peek Style", selection: $sneakPeekStyles){
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .disabled(!enableSneakPeek)
                .settingsHighlight(id: highlightID("Sneak Peek Style"))

                SettingsStepperRow("Media inactivity timeout", value: $waitInterval, in: 0...10, step: 1,
                                   valueText: Text("\(waitInterval, specifier: "%.0f") seconds"))


                Defaults.Toggle(key: .showSongMetadataInClosedNotch) {
                    Text("Show song title and artist on non-notch displays")
                }
                .settingsHighlight(id: highlightID("Show song title and artist in closed notch"))
            } header: {
                SettingsSectionHeader("Media playback live activity")
            }

            Section {
                Defaults.Toggle(key: .enableRealTimeWaveform) {
                    HStack {
                        Text("Enable real-time waveform")
                        customBadge(text: "Beta")
                    }
                }
                .settingsHighlight(id: highlightID("Enable real-time waveform"))
                
                Picker("Visualizer candles", selection: $visualizerBarCount) {
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                
                Picker("Color extraction", selection: $colorExtractionMode) {
                    Text("Legacy").tag(ColorExtractionMode.legacy)
                    Text("Vibrant").tag(ColorExtractionMode.vibrant)
                }
                
                Toggle("Scrubbable real-time waveform", isOn: $enableWaveformScrubber)
            } header: {
                SettingsSectionHeader("Music Visualizer")
            } footer: {
                SettingsFooter("Shows a real-time audio spectrum synced to your music. Requires macOS 14.2 or later.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Show lock screen media panel")
                }
                Defaults.Toggle(key: .lockScreenShowAppIcon) {
                    Text("Show media app icon")
                }
                .disabled(!enableLockScreenMediaWidget)
                if isAppleMusicActive {
                    Defaults.Toggle(key: .lockScreenMusicMergedAirPlayOutput) {
                        Text("Show merged AirPlay and output devices")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Show merged AirPlay and output devices"))
                }
                Defaults.Toggle(key: .lockScreenPanelShowsBorder) {
                    Text("Show panel border")
                }
                .disabled(!enableLockScreenMediaWidget)
                if lockScreenGlassCustomizationMode == .customLiquid {
                    Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                        Text("Use enhanced liquid border")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                }
                if lockScreenGlassCustomizationMode == .customLiquid {
                    customLiquidBlurRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else if lockScreenGlassStyle == .frosted {
                    Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                        Text("Enable media panel blur")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else {
                    unavailableBlurRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                }
                SettingsRow("Fullscreen artwork on right-click", description: "Right-click the lock screen album art to use it as the wallpaper; right-click again to restore.") {
                    Defaults.Toggle(key: .lockScreenMusicFullscreenArtworkEnabled) {
                        Text("Fullscreen artwork on right-click")
                    }
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Fullscreen artwork on right-click"))
                Defaults.Toggle(key: .lockScreenUseArtworkLayoutOverFullscreenCanvas) {
                    Text("Use album art layout over fullscreen canvas")
                }
                .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
                .settingsHighlight(id: highlightID("Use album art layout over fullscreen canvas"))
                Defaults.Toggle(key: .lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork) {
                    Text("Keep album art visible during fullscreen artwork")
                }
                .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
                .settingsHighlight(id: highlightID("Keep album art visible during fullscreen artwork"))
            } header: {
                SettingsSectionHeader("Lock Screen Integration")
            } footer: {
                SettingsFooter("These controls mirror the Lock screen tab.")
            }
            .disabled(!showStandardMediaControls)

            // A radio group: the options are too long for a menu at this width.
            Section {
                Picker(selection: $hideNotchOption) {
                    Text("Always hide in fullscreen").tag(HideNotchOption.always)
                    Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                } label: {
                    Text("Hide DynamicIsland Options")
                }
                .pickerStyle(.radioGroup)
                .labeledContentStyle(.automatic)
                .labelsHidden()
                .settingsHighlight(id: highlightID("Hide DynamicIsland Options"))
                .onChange(of: hideNotchOption) {
                    Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
                }

                // Shown only while hiding is on and the grant is missing: without Accessibility
                // the detector cannot read `AXFullScreen` and falls back to the menu-bar probe
                // (`FullscreenFallbackVerdict`), which is close but not exact.
                if hideNotchOption != .never, !accessibilityPermission.isAuthorized {
                    SettingsActionRow(
                        "Accessibility access",
                        description: "Fullscreen is detected exactly with Accessibility. Without it, Kannu goes by whether the menu bar is hidden."
                    ) {
                        Button("Open System Settings") {
                            AccessibilityPermissionStore.shared.openSystemSettings()
                        }
                    }
                    .settingsHighlight(id: highlightID("Accessibility access"))
                }
            } header: {
                HStack {
                    SettingsSectionHeader("Hide DynamicIsland Options")
                    customBadge(text: "Beta")
                }
            }
        }
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }

    private var unavailableBlurRow: some View {
        SettingsNoteRow("Enable media panel blur",
                        description: "Only applies when Material is set to Frosted Glass.")
    }

    private var customLiquidBlurRow: some View {
        SettingsNoteRow("Enable media panel blur",
                        description: "Custom liquid glass already renders with Apple's liquid material, so this option is managed automatically.")
    }
}
