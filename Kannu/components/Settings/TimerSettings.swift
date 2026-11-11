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

struct TimerSettings: View {
    @ObservedObject private var coordinator = KannuViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.mirrorSystemTimer) private var mirrorSystemTimer
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.timerInputStyle) private var timerInputStyle
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    /// Observed, so the row updates after Choose File or Reset (a plain UserDefaults read did not).
    @AppStorage("customTimerSoundPath") private var customTimerSoundPath: String?
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0

    private func highlightID(_ title: String) -> String {
        SettingsTab.timer.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        // The product first, then its settings (docs/SETTINGS.md, "Product pages"). The presets moved up into its tiles.
        SettingsProductPage(settingsTitle: String(localized: "Timer settings")) {
            TimerOverview()
        } settings: {
            timerFeatureSection

            if enableTimerFeature {
                timerConfigurationSections
            }
        }
        .navigationTitle("Timer")
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
        // On the page, which owns the three values the stepper rows edit.
        .onChange(of: customHours) { _, _ in updateCustomDuration() }
        .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
        .onChange(of: customSeconds) { _, _ in updateCustomDuration() }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        SettingsSection {
            Defaults.Toggle(key: .enableTimerFeature) {
                Text("Enable timer feature")
            }
            .settingsHighlight(id: highlightID("Enable timer feature"))

            if enableTimerFeature {
                Toggle("Enable timer live activity", isOn: $coordinator.timerLiveActivityEnabled)
                    .animation(.easeInOut, value: coordinator.timerLiveActivityEnabled)
                LabeledContent {
                    Defaults.Toggle(key: .mirrorSystemTimer) {
                        Text("Mirror macOS Clock timers")
                    }
                    .labelsHidden()
                    .toggleStyle(SettingsToggleStyle(showsLabel: false))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Mirror macOS Clock timers")
                            alphaBadge()
                        }
                        Text("Shows the system Clock timer in the notch when available. Requires Accessibility permission to read the status item.")
                            .settingsDescriptionStyle()
                    }
                }
                .settingsHighlight(id: highlightID("Mirror macOS Clock timers"))

                SettingsRow("Timer controls appear as", description: timerDisplayMode.description) {
                    SettingsSelect("Timer controls appear as", selection: $timerDisplayMode,
                                   options: TimerDisplayMode.allCases, optionTitle: \.displayName, style: .segmented)
                }
                .settingsHighlight(id: highlightID("Timer controls appear as"))
            }
        } header: {
            SettingsSectionHeader("Timer Feature")
        } footer: {
            SettingsFooter("Control timer availability, live activity behaviour, and whether the app mirrors timers started from the macOS Clock app.")
        }
    }

    @ViewBuilder
    private var timerConfigurationSections: some View {
        Group {
            lockScreenIntegrationSection
            customTimerSection
            appearanceSection
            timerSoundSection
        }
        .onAppear {
            if showsLabel {
                controlWindowEnabled = false
            }
        }
        .onChange(of: showsLabel) { _, show in
            if show {
                controlWindowEnabled = false
            }
        }
    }

    @ViewBuilder
    private var lockScreenIntegrationSection: some View {
        SettingsSection {
            Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                Text("Show lock screen timer widget")
            }
            .settingsHighlight(id: highlightID("Show lock screen timer widget"))
            SettingsRow("Timer surface", description: timerGlassModeIsGlass
                        ? nil : Text("Classic mode keeps the original translucent black background.")) {
                SettingsSelect("Timer surface", selection: timerSurfaceBinding,
                               options: LockScreenTimerSurfaceMode.allCases, optionTitle: \.rawValue, style: .segmented)
            }
            .disabled(!enableLockScreenTimerWidget)
            .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
            .settingsHighlight(id: highlightID("Timer surface"))

            if timerGlassModeIsGlass {
                SettingsRow("Timer glass material", description: lockScreenTimerGlassStyle == .liquid
                            ? nil : Text("Uses the frosted blur treatment while glass mode is enabled.")) {
                    SettingsSelect("Timer glass material", selection: $lockScreenTimerGlassStyle,
                                   options: LockScreenGlassStyle.allCases, optionTitle: \.rawValue)
                }
                .disabled(!enableLockScreenTimerWidget)
                .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                .settingsHighlight(id: highlightID("Timer glass material"))

                if lockScreenTimerGlassStyle == .liquid {
                    SettingsRow("Timer liquid mode") {
                        SettingsSelect("Timer liquid mode", selection: $lockScreenTimerGlassCustomizationMode,
                                       options: LockScreenGlassCustomizationMode.allCases, optionTitle: \.rawValue,
                                       style: .segmented)
                    }
                    .disabled(!enableLockScreenTimerWidget)
                    .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                    .settingsHighlight(id: highlightID("Timer liquid mode"))

                    if lockScreenTimerGlassCustomizationMode == .customLiquid {
                        variantSliderRow(value: timerVariantBinding, current: lockScreenTimerLiquidGlassVariant.rawValue,
                                         range: liquidVariantRange, title: String(localized: "Timer widget variant"))
                        .settingsHighlight(id: highlightID("Timer widget variant"))
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.4)
                    }
                }
            }
        } header: {
            SettingsSectionHeader("Lock Screen Integration")
        } footer: {
            SettingsFooter("Mirrors the toggle found under Lock screen settings so timer-specific workflows can enable or disable the widget without switching tabs.")
        }
    }

    @ViewBuilder
    private var customTimerSection: some View {
        SettingsSection {
            LabeledContent("Default Custom Timer") {
                Text(customDurationDisplay)
                    .font(SettingsTheme.mono)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            TimerDurationStepperRow(title: String(localized: "Hours"), value: $customHours, range: 0...23)
            TimerDurationStepperRow(title: String(localized: "Minutes"), value: $customMinutes, range: 0...59)
            TimerDurationStepperRow(title: String(localized: "Seconds"), value: $customSeconds, range: 0...59)
        } header: {
            SettingsSectionHeader("Custom Timer")
        } footer: {
            SettingsFooter("This duration powers the \"Custom\" option inside the timer popover for quick access.")
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        SettingsSection {
            SettingsRow("Timer tint") {
                SettingsSelect("Timer tint", selection: $colorMode,
                               options: TimerIconColorMode.allCases, optionTitle: \.displayName, style: .segmented)
            }
            .settingsHighlight(id: highlightID("Timer tint"))

            if colorMode == .solid {
                SettingsColorPickerRow(title: "Solid colour", selection: $solidColor)
                    .settingsHighlight(id: highlightID("Solid colour"))
            }

            SettingsRow("Custom timer style") {
                SettingsSelect("Custom timer style", selection: $timerInputStyle,
                               options: TimerInputStyle.allCases, optionTitle: \.displayName, style: .segmented)
            }
            .settingsHighlight(id: highlightID("Custom timer style"))

            Toggle("Show timer name", isOn: $showsLabel)
            Toggle("Show countdown", isOn: $showsCountdown)
            Toggle("Show progress", isOn: $showsProgress)
            Toggle("Show preset list in timer tab", isOn: $showTimerPresetsInNotchTab)
                .settingsHighlight(id: highlightID("Show preset list in timer tab"))

            SettingsRow("Show floating pause/stop controls", description: "These controls sit beside the notch while a timer runs. They require the timer name to stay hidden for spacing.") {
                Toggle("Show floating pause/stop controls", isOn: $controlWindowEnabled)
            }
            .disabled(showsLabel)

            SettingsRow("Progress style") {
                SettingsSelect("Progress style", selection: $progressStyle,
                               options: TimerProgressStyle.allCases, optionTitle: \.rawValue, style: .segmented)
            }
            .disabled(!showsProgress)
            .settingsHighlight(id: highlightID("Progress style"))
        } header: {
            SettingsSectionHeader("Appearance")
        } footer: {
            SettingsFooter("Configure how the timer looks inside the closed notch. Progress can render as a ring around the icon or as horizontal bars.")
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        SettingsSection {
            LabeledContent {
                HStack(spacing: 8) {
                    Button("Reset to Default") {
                        customTimerSoundPath = nil
                    }
                    .disabled(customTimerSoundPath == nil)
                    Button("Choose File", action: selectCustomTimerSound)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer Sound")
                    Group {
                        if let customTimerSoundPath {
                            Text("Custom: \(URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)")
                        } else {
                            Text("Default: dynamic.m4a")
                        }
                    }
                    .settingsDescriptionStyle()
                }
            }
        } header: {
            SettingsSectionHeader("Timer Sound")
        } footer: {
            SettingsFooter("Select a custom sound to play when a timer ends. Supported formats include MP3, M4A, WAV, and AIFF.")
        }
    }

    private var customDurationDisplay: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = customTimerDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: customTimerDuration) ?? "0:00"
    }

    private func syncCustomDuration(_ value: Double? = nil) {
        let baseValue = value ?? customTimerDuration
        let components = TimerPreset.components(for: baseValue)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateCustomDuration() {
        let duration = TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        customTimerDuration = duration
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        ModalPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            customTimerSoundPath = url.path
        }
    }
}

private struct TimerDurationStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SettingsStepperRow(verbatim: title, value: $value, in: range, valueText: Text("\(value)"))
    }
}
