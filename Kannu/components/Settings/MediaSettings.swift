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
        SettingsPage {
            SettingsSection {
                SettingsRow("Music source") {
                    SettingsSelect("Music source", selection: $mediaController,
                                   options: availableMediaControllers, optionTitle: \.localizedName)
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music Source"))
            } header: {
                SettingsSectionHeader("Media source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsFooter("YouTube Music requires this third-party app to be installed.")
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

            SettingsSection {
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
                SettingsSectionHeader("Dynamic Island visibility")
            } footer: {
                if standardControlsSuppressed {
                    SettingsFooter("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
                } else if !autoHideInactiveNotchMediaPlayer {
                    SettingsFooter("When off, the notch player stays visible with placeholder info while nothing plays.")
                }
            }
            SettingsSection {
                Defaults.Toggle(key: .showShuffleAndRepeat) {
                    HStack {
                        Text("Enable customizable controls")
                        customBadge(text: "Beta")
                    }
                }
                if showShuffleAndRepeat {
                    SettingsRow("Show \"Change Media Output\" control", description: "Adds the AirPlay output picker to the control palette.") {
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

            SettingsSection {
                SettingsRow("Enable album art parallax", description: "Parallax effect on the lock screen album art.") {
                    Defaults.Toggle(key: .lockScreenMusicAlbumParallaxEnabled) {
                        Text("Enable album art parallax")
                    }
                }
                .settingsHighlight(id: highlightID("Enable album art parallax"))
            } header: {
                SettingsSectionHeader("Lock screen media")
            }
            if musicControlWindowEnabled {
                SettingsSection {
                    SettingsRow("Skip buttons", description: musicSkipBehavior.description) {
                        SettingsSelect("Skip buttons", selection: $musicSkipBehavior,
                                       options: MusicSkipBehavior.allCases, optionTitle: \.displayName,
                                       style: .segmented)
                    }
                    .settingsHighlight(id: highlightID("Skip buttons"))
                } header: {
                    SettingsSectionHeader("Floating window panel skip behaviour")
                }
            }
            SettingsSection {
                SettingsRow("Enable music live activity", description: standardControlsSuppressed
                            ? Text("Media controls stay hidden while this is off.") : nil) {
                    Toggle(
                        "Enable music live activity",
                        isOn: $coordinator.musicLiveActivityEnabled.animation()
                    )
                }
                .disabled(standardControlsSuppressed)
                SettingsRow("Show floating media controls", description: "Play, pause and skip buttons beside the notch.") {
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
                SettingsRow("Show live canvas in Dynamic Island", description: "Shows the live canvas instead of album art.") {
                    Defaults.Toggle(key: .showLiveCanvasInDynamicIsland) {
                        Text("Show live canvas in Dynamic Island")
                    }
                }
                .settingsHighlight(id: highlightID("Show live canvas in Dynamic Island"))

                // How much the album art moves with the pointer.
                SettingsSliderRow("Parallax effect intensity", value: $parallaxEffectIntensity, in: 0...12, step: 1.0,
                                  valueText: Text("\(parallaxEffectIntensity, specifier: "%0.1f")"))
                .settingsHighlight(id: highlightID("Enable album art parallax effect"))


                SettingsRow("Sneak peek style") {
                    SettingsSelect("Sneak peek style", selection: $sneakPeekStyles,
                                   options: SneakPeekStyle.allCases, optionTitle: \.rawValue)
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

            SettingsSection {
                Defaults.Toggle(key: .enableRealTimeWaveform) {
                    HStack {
                        Text("Enable real-time waveform")
                        customBadge(text: "Beta")
                    }
                }
                .settingsHighlight(id: highlightID("Enable real-time waveform"))
                
                SettingsRow("Visualizer candles") {
                    SettingsSelect("Visualizer candles", selection: $visualizerBarCount, choices: [
                        4: String(localized: "4"),
                        5: String(localized: "5"),
                        6: String(localized: "6"),
                    ])
                }
                
                SettingsRow("Color extraction") {
                    SettingsSelect("Color extraction", selection: $colorExtractionMode, choices: [
                        ColorExtractionMode.legacy: String(localized: "Legacy"),
                        ColorExtractionMode.vibrant: String(localized: "Vibrant"),
                    ])
                }
                
                Toggle("Scrubbable real-time waveform", isOn: $enableWaveformScrubber)
            } header: {
                SettingsSectionHeader("Music visualizer")
            } footer: {
                SettingsFooter("Shows a real-time audio spectrum synced to your music. Requires macOS 14.2 or later.")
            }

            SettingsSection {
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
                SettingsRow("Fullscreen artwork on right-click", description: "Right-click the album art to toggle it as wallpaper.") {
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
                SettingsSectionHeader("Lock screen integration")
            } footer: {
                SettingsFooter("These controls mirror the Lock screen tab.")
            }
            .disabled(!showStandardMediaControls)

            SettingsSection {
                SettingsRow("Hide DynamicIsland options") {
                    SettingsSelect("Hide DynamicIsland options", selection: $hideNotchOption, choices: [
                        .always: String(localized: "Always hide in fullscreen"),
                        .nowPlayingOnly: String(localized: "Hide only when NowPlaying app is in fullscreen"),
                        .never: String(localized: "Never hide"),
                    ])
                }
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
                        description: "Lets Kannu detect full screen exactly."
                    ) {
                        Button("Open System Settings") {
                            AccessibilityPermissionStore.shared.openSystemSettings()
                        }
                    }
                    .settingsHighlight(id: highlightID("Accessibility access"))
                }
            } header: {
                HStack {
                    SettingsSectionHeader("Hide DynamicIsland options")
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
                        description: "Custom liquid glass handles this automatically.")
    }
}
