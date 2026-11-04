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

struct Charge: View {
    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.chargingBatteryHUDDuration) private var chargingBatteryHUDDuration
    @Default(.lowBatteryHUDDuration) private var lowBatteryHUDDuration
    @Default(.fullBatteryHUDDuration) private var fullBatteryHUDDuration
    @Default(.lowBatteryHUDThreshold) private var lowBatteryHUDThreshold
    @Default(.fullBatteryHUDThreshold) private var fullBatteryHUDThreshold
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.battery.highlightID(for: title)
    }

    private var chargingDurationBinding: Binding<Double> {
        Binding(
            get: { Double(chargingBatteryHUDDuration) },
            set: { chargingBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDDuration) },
            set: { lowBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var fullBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDDuration) },
            set: { fullBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDThreshold) },
            set: { lowBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var fullBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDThreshold) },
            set: { fullBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private func sectionOpacity(_ isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.5
    }

    var body: some View {
        Form {
            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .showBatteryIndicator) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))
                    Defaults.Toggle(key: .showPowerStatusNotifications) {
                        Text("Show power status notifications")
                    }
                    .settingsHighlight(id: highlightID("Show power status notifications"))
                    Defaults.Toggle(key: .playLowBatteryAlertSound) {
                        Text("Play low battery alert sound")
                    }
                    .settingsHighlight(id: highlightID("Play low battery alert sound"))
                } header: {
                    SettingsSectionHeader("General")
                }
                Section {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                    .settingsHighlight(id: highlightID("Show battery percentage"))
                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Show power status icons")
                    }
                    .settingsHighlight(id: highlightID("Show power status icons"))
                } header: {
                    SettingsSectionHeader("Battery Information")
                }
                Section {
                    Defaults.Toggle(key: .showChargingBatteryHUD) {
                        Text("Charging HUD")
                    }
                    .settingsHighlight(id: highlightID("Charging HUD"))

                    Defaults.Toggle(key: .showLowBatteryHUD) {
                        Text("Low battery HUD")
                    }
                    .settingsHighlight(id: highlightID("Low battery HUD"))

                    Defaults.Toggle(key: .showFullBatteryHUD) {
                        Text("Fully charged HUD")
                    }
                    .settingsHighlight(id: highlightID("Fully charged HUD"))
                } header: {
                    SettingsSectionHeader("Battery HUDs")
                } footer: {
                    SettingsFooter("These temporary HUDs recreate the charging, low-battery, and full-battery notch alerts.")
                }
                Section {
                    SettingsSliderRow("Charging duration", value: chargingDurationBinding, in: 1...10, step: 1,
                                      valueText: Text("\(chargingBatteryHUDDuration)s"))
                    .settingsHighlight(id: highlightID("Charging duration"))
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showChargingBatteryHUD))

                    SettingsSliderRow("Low battery duration", value: lowBatteryDurationBinding, in: 1...10, step: 1,
                                      valueText: Text("\(lowBatteryHUDDuration)s"))
                    .settingsHighlight(id: highlightID("Low battery duration"))
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                    SettingsSliderRow("Full battery duration", value: fullBatteryDurationBinding, in: 1...10, step: 1,
                                      valueText: Text("\(fullBatteryHUDDuration)s"))
                    .settingsHighlight(id: highlightID("Full battery duration"))
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
                } header: {
                    SettingsSectionHeader("HUD Duration")
                }
                Section {
                    testHUDRow(Label("Charging HUD", systemImage: "bolt.fill"),
                               accessibilityLabel: Text("Test charging HUD"), kind: .charging)
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)
                    .settingsHighlight(id: highlightID("Test charging HUD"))

                    testHUDRow(Label("Low battery HUD", systemImage: "battery.25"),
                               accessibilityLabel: Text("Test low battery HUD"), kind: .lowBattery)
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                    .settingsHighlight(id: highlightID("Test low battery HUD"))

                    testHUDRow(Label("Fully charged HUD", systemImage: "battery.100"),
                               accessibilityLabel: Text("Test full battery HUD"), kind: .fullBattery)
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                    .settingsHighlight(id: highlightID("Test full battery HUD"))
                } header: {
                    SettingsSectionHeader("HUD Tests")
                } footer: {
                    SettingsFooter("Runs the real notch animation on the current target display. If an external screen is using Dynamic Island mode, the battery HUD is sent there first.")
                }
                Section {
                    SettingsRow("Low battery style", description: "Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.") {
                        SettingsSelect("Low battery style", selection: $lowBatteryHUDStyle,
                                       options: BatteryNotificationStyle.allCases, optionTitle: \.title,
                                       style: .segmented)
                    }
                    .settingsHighlight(id: highlightID("Low battery style"))

                    SettingsSliderRow("Low battery threshold", value: lowBatteryThresholdBinding, in: 5...30, step: 1,
                                      valueText: Text("\(lowBatteryHUDThreshold)%"))
                    .settingsHighlight(id: highlightID("Low battery threshold"))
                } header: {
                    SettingsSectionHeader("Low Battery")
                }
                .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                Section {
                    SettingsRow("Full battery style", description: "Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.") {
                        SettingsSelect("Full battery style", selection: $fullBatteryHUDStyle,
                                       options: BatteryNotificationStyle.allCases, optionTitle: \.title,
                                       style: .segmented)
                    }
                    .settingsHighlight(id: highlightID("Full battery style"))

                    SettingsSliderRow("Full charge threshold", value: fullBatteryThresholdBinding, in: 80...100, step: 1,
                                      valueText: Text("\(fullBatteryHUDThreshold)%"))
                    .settingsHighlight(id: highlightID("Full charge threshold"))
                } header: {
                    SettingsSectionHeader("Full Battery")
                }
                .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
            } else {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        Image(systemName: "battery.100percent.slash")
                            .font(.title)
                        Text("Battery settings and information are only available on MacBooks")
                            .font(.title3)
                    }
                }
            }
        }
        .navigationTitle("Battery")
    }

    /// A HUD's name with a Test button on the trailing side.
    private func testHUDRow(_ label: Label<Text, Image>, accessibilityLabel: Text,
                            kind: BatteryTemporaryHUDKind) -> some View {
        LabeledContent {
            Button("Test") {
                batteryStatusViewModel.triggerTestHUD(kind: kind)
            }
            .accessibilityLabel(accessibilityLabel)
        } label: {
            label
        }
    }
}
