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

struct HUD: View {
    @EnvironmentObject var vm: KannuViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolumeDisplay
    @Default(.useColorCodedBatteryDisplay) var useColorCodedBatteryDisplay
    @Default(.useSmoothColorGradient) var useSmoothColorGradient
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    /// The Dynamic Island style's sections, drawn inside the Controls tab's Form (which also holds
    /// this style's Accessibility side effects).
    var body: some View {
        if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
            SettingsSection {
                SettingsPermissionCallout(
                    message: "Without Accessibility permission macOS handles the volume and brightness keys itself and shows its own HUD, so Kannu hides its own to avoid two HUDs stacking. Granting it lets Kannu replace them.",
                    requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                    openSettingsAction: { accessibilityPermission.openSystemSettings() }
                )
            } header: {
                SettingsSectionHeader("Accessibility")
            }
        }



        if enableSystemHUD && !Defaults[.enableCustomOSD] && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
            SettingsSection {
                Toggle("Volume HUD", isOn: $enableVolumeHUD)
                Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                SettingsRow("Keyboard backlight HUD", description: enableThirdPartyDDCIntegration
                            ? Text("Disabled while an external display app handles brightness.") : nil) {
                    Toggle("Keyboard backlight HUD", isOn: $enableKeyboardBacklightHUD)
                }
                .disabled(enableThirdPartyDDCIntegration)
            } header: {
                SettingsSectionHeader("Controls")
            } footer: {
                SettingsFooter("Choose which system controls should display HUD notifications.")
            }
        }

        SettingsSection {
            SettingsRow("Play feedback when volume is changed", description: "Plays a feedback sound on volume key presses.") {
                Defaults.Toggle(key: .playVolumeChangeFeedback) {
                    Text("Play feedback when volume is changed")
                }
            }
            .settingsHighlight(id: highlightID("Play feedback when volume is changed"))
        } header: {
            SettingsSectionHeader("Audio feedback")
        } footer: {
            SettingsFooter("Requires Accessibility permission so Dynamic Island can intercept the hardware volume keys.")
        }

        SettingsSection {
            Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                Text("Color-coded volume display")
            }
            .disabled(colorCodingDisabled)
            .settingsHighlight(id: highlightID("Color-coded volume display"))

            if !colorCodingDisabled && (useColorCodedBatteryDisplay || useColorCodedVolumeDisplay) {
                Defaults.Toggle(key: .useSmoothColorGradient) {
                    Text("Smooth color transitions")
                }
                .settingsHighlight(id: highlightID("Smooth color transitions"))
            }

            Defaults.Toggle(key: .showProgressPercentages) {
                Text("Show percentages beside progress bars")
            }
            .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
        } header: {
            SettingsSectionHeader("Dynamic Island progress bars")
        } footer: {
            if colorCodingDisabled {
                SettingsFooter("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
            } else if useSmoothColorGradient {
                SettingsFooter("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
            } else {
                SettingsFooter("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
            }
        }

        SettingsSection {
            SettingsRow("HUD style") {
                SettingsSelect("HUD style", selection: $inlineHUD, choices: [
                    false: String(localized: "Default"),
                    true: String(localized: "Inline"),
                ])
            }
            .settingsHighlight(id: highlightID("HUD style"))
            .onChange(of: Defaults[.inlineHUD]) {
                if Defaults[.inlineHUD] {
                    withAnimation {
                        Defaults[.systemEventIndicatorShadow] = false
                        Defaults[.progressBarStyle] = .hierarchical
                    }
                }
            }
            SettingsRow("Progressbar style") {
                SettingsSelect("Progressbar style", selection: $progressBarStyle, choices: [
                    ProgressBarStyle.hierarchical: String(localized: "Hierarchical"),
                    ProgressBarStyle.gradient: String(localized: "Gradient"),
                    ProgressBarStyle.segmented: String(localized: "Segmented"),
                ])
            }
            .settingsHighlight(id: highlightID("Progressbar style"))
            Defaults.Toggle(key: .systemEventIndicatorShadow) {
                Text("Enable glowing effect")
            }
            .settingsHighlight(id: highlightID("Enable glowing effect"))
            Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                Text("Use accent color")
            }
            .settingsHighlight(id: highlightID("Use accent color"))
        } header: {
            SettingsSectionHeader("Appearance")
        }
    }
}
