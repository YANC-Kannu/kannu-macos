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
import SwiftUI

struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.hasSeenOSDAlphaWarning) var hasSeenOSDAlphaWarning
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    /// The Custom OSD style's sections, drawn inside the Controls tab's Form (which also holds this
    /// style's Accessibility and hide-on-disable side effects, and the macOS 26 material fallback).
    var body: some View {
        if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
            SettingsSection {
                SettingsPermissionCallout(
                    message: "Accessibility permission is needed to intercept system controls for the Custom OSD.",
                    requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                    openSettingsAction: { accessibilityPermission.openSystemSettings() }
                )
            } header: {
                SettingsSectionHeader("Accessibility")
            }
        }

        if hasAccessibilityPermission || enableThirdPartyDDCIntegration {
            SettingsSection {
                Toggle("Volume OSD", isOn: $enableOSDVolume)
                    .settingsHighlight(id: highlightID("Volume OSD"))
                Toggle("Brightness OSD", isOn: $enableOSDBrightness)
                    .settingsHighlight(id: highlightID("Brightness OSD"))
                SettingsRow("Keyboard backlight OSD", description: enableThirdPartyDDCIntegration
                            ? Text("Disabled while an external display app handles brightness.") : nil) {
                    Toggle("Keyboard backlight OSD", isOn: $enableOSDKeyboardBacklight)
                }
                .settingsHighlight(id: highlightID("Keyboard Backlight OSD"))
                .disabled(enableThirdPartyDDCIntegration)
            } header: {
                SettingsSectionHeader("Controls")
            } footer: {
                SettingsFooter("Choose which system controls should display custom OSD windows.")
            }

            SettingsSection {
                SettingsRow("Material") {
                    SettingsSelect("Material", selection: $osdMaterial,
                                   options: availableOSDMaterials, optionTitle: \.rawValue)
                }
                .settingsHighlight(id: highlightID("Material"))
                .onChange(of: osdMaterial) { _, _ in
                    previewValue = previewValue == 0.65 ? 0.651 : 0.65
                }

                if osdMaterial == .liquid {
                    if #available(macOS 26.0, *) {
                        SettingsRow("Glass mode") {
                            SettingsSelect("Glass mode", selection: $osdLiquidGlassCustomizationMode,
                                           options: LockScreenGlassCustomizationMode.allCases, optionTitle: \.rawValue,
                                           style: .segmented)
                        }

                        if osdLiquidGlassCustomizationMode == .customLiquid {
                            variantSliderRow(value: osdLiquidVariantBinding, current: osdLiquidGlassVariant.rawValue,
                                             range: liquidVariantRange, title: String(localized: "Custom liquid variant"))
                        }
                    } else {
                        Text("Custom Liquid is available on macOS 26 or later.")
                            .settingsDescriptionStyle()
                    }
                }

                SettingsRow("Icon & progress color") {
                    SettingsSelect("Icon & progress color", selection: $osdIconColorStyle,
                                   options: OSDIconColorStyle.allCases, optionTitle: \.rawValue)
                }
                .settingsHighlight(id: highlightID("Icon & Progress Color"))
                .onChange(of: osdIconColorStyle) { _, _ in
                    previewValue = previewValue == 0.65 ? 0.651 : 0.65
                }
            } header: {
                SettingsSectionHeader("Appearance")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsFooter("• Frosted Glass: Translucent blur effect")
                    SettingsFooter("• Liquid Glass: Modern glass effect (macOS 26+)")
                    SettingsFooter("• Solid Dark/Light/Auto: Opaque backgrounds")
                    SettingsFooter("Color options control the icon and progress bar appearance. Auto adapts to system theme.")
                }
            }

            SettingsSection {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Text("Live preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        CustomOSDView(
                            type: .constant(previewType),
                            value: .constant(previewValue),
                            icon: .constant("")
                        )
                        .frame(width: 200, height: 200)

                        HStack(spacing: 8) {
                            Button("Volume") {
                                previewType = .volume
                            }

                            Button("Brightness") {
                                previewType = .brightness
                            }
                                
                            Button("Backlight") {
                                previewType = .backlight
                            }
                        }
                        .controlSize(.small)
                            
                        SettingsSlider(value: $previewValue, in: 0...1,
                                       valueDescription: Text(Double(previewValue), format: .percent.precision(.fractionLength(0)))) {
                            Text("Live preview")
                        }
                            .frame(width: 160)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } header: {
                SettingsSectionHeader("Preview")
            } footer: {
                SettingsFooter("Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.")
            }
        }
    }
}
