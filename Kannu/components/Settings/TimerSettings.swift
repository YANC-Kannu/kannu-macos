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
    @Default(.timerPresets) private var timerPresets
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
    @State private var showingResetConfirmation = false

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
        Form {
            timerFeatureSection

            if enableTimerFeature {
                timerConfigurationSections
            }
        }
        .navigationTitle("Timer")
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
        // On the Form, not the stepper rows: rows of a lazy Form may not exist when these change.
        .onChange(of: customHours) { _, _ in updateCustomDuration() }
        .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
        .onChange(of: customSeconds) { _, _ in updateCustomDuration() }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        Section {
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
                    Picker("Timer controls appear as", selection: $timerDisplayMode) {
                        ForEach(TimerDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
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
            timerPresetsSection
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
        Section {
            Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                Text("Show lock screen timer widget")
            }
            .settingsHighlight(id: highlightID("Show lock screen timer widget"))
            SettingsRow("Timer surface", description: timerGlassModeIsGlass
                        ? nil : Text("Classic mode keeps the original translucent black background.")) {
                Picker("Timer surface", selection: timerSurfaceBinding) {
                    ForEach(LockScreenTimerSurfaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .disabled(!enableLockScreenTimerWidget)
            .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
            .settingsHighlight(id: highlightID("Timer surface"))

            if timerGlassModeIsGlass {
                SettingsRow("Timer glass material", description: lockScreenTimerGlassStyle == .liquid
                            ? nil : Text("Uses the frosted blur treatment while glass mode is enabled.")) {
                    Picker("Timer glass material", selection: $lockScreenTimerGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
                .disabled(!enableLockScreenTimerWidget)
                .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                .settingsHighlight(id: highlightID("Timer glass material"))

                if lockScreenTimerGlassStyle == .liquid {
                    SettingsRow("Timer liquid mode") {
                        Picker("Timer liquid mode", selection: $lockScreenTimerGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
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
        Section {
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
        Section {
            Picker("Timer tint", selection: $colorMode) {
                ForEach(TimerIconColorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .settingsHighlight(id: highlightID("Timer tint"))

            if colorMode == .solid {
                SettingsColorPickerRow(title: "Solid colour", selection: $solidColor)
                    .settingsHighlight(id: highlightID("Solid colour"))
            }

            Picker("Custom timer style", selection: $timerInputStyle) {
                ForEach(TimerInputStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
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

            Picker("Progress style", selection: $progressStyle) {
                ForEach(TimerProgressStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!showsProgress)
            .settingsHighlight(id: highlightID("Progress style"))
        } header: {
            SettingsSectionHeader("Appearance")
        } footer: {
            SettingsFooter("Configure how the timer looks inside the closed notch. Progress can render as a ring around the icon or as horizontal bars.")
        }
    }

    @ViewBuilder
    private var timerPresetsSection: some View {
        Section {
            if timerPresets.isEmpty {
                Text("No presets configured. Add a preset to make it appear in the timer popover.")
                    .settingsDescriptionStyle()
            } else {
                TimerPresetListView(
                    presets: $timerPresets,
                    highlightProvider: highlightID,
                    moveUp: movePresetUp,
                    moveDown: movePresetDown,
                    remove: removePreset
                )
            }

            SettingsActionRow {
                Button(role: .destructive, action: { showingResetConfirmation = true }) {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                }
                .confirmationDialog("Restore default timer presets?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                    Button("Restore", role: .destructive, action: resetPresets)
                }

                Button(action: addPreset) {
                    Label("Add Preset", systemImage: "plus")
                }
            }
        } header: {
            SettingsSectionHeader("Timer Presets")
        } footer: {
            SettingsFooter("Presets show up inside the timer popover with the configured name, duration, and accent colour. Reorder them to change the display order.")
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        Section {
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

    private func addPreset() {
        let nextIndex = timerPresets.count + 1
        let defaultColor = Defaults[.accentColor]
        let newPreset = TimerPreset(name: "Preset \(nextIndex)", duration: 5 * 60, color: defaultColor)
        withAnimation(.smooth) {
            timerPresets.append(newPreset)
        }
    }

    private func movePresetUp(_ index: Int) {
        guard index > timerPresets.startIndex else { return }
        withAnimation(.smooth) {
            timerPresets.swapAt(index, index - 1)
        }
    }

    private func movePresetDown(_ index: Int) {
        guard index < timerPresets.index(before: timerPresets.endIndex) else { return }
        withAnimation(.smooth) {
            timerPresets.swapAt(index, index + 1)
        }
    }

    private func removePreset(_ index: Int) {
        guard timerPresets.indices.contains(index) else { return }
        withAnimation(.smooth) {
            _ = timerPresets.remove(at: index)
        }
    }

    private func resetPresets() {
        withAnimation(.smooth) {
            timerPresets = TimerPreset.defaultPresets
        }
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

private struct TimerPresetListView: View {
    @Binding var presets: [TimerPreset]
    let highlightProvider: (String) -> String
    let moveUp: (Int) -> Void
    let moveDown: (Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            presetRow(at: index)
        }
    }

    @ViewBuilder
    private func presetRow(at index: Int) -> some View {
        TimerPresetEditorRow(
            preset: $presets[index],
            isFirst: index == presets.startIndex,
            isLast: index == presets.index(before: presets.endIndex),
            highlightID: highlightID(for: index),
            moveUp: { moveUp(index) },
            moveDown: { moveDown(index) },
            remove: { remove(index) }
        )
    }

    private func highlightID(for index: Int) -> String? {
        index == presets.startIndex ? highlightProvider("Accent colour") : nil
    }
}

private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let highlightID: String?

    init(
        preset: Binding<TimerPreset>,
        isFirst: Bool,
        isLast: Bool,
        highlightID: String? = nil,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        _preset = preset
        self.isFirst = isFirst
        self.isLast = isLast
        self.highlightID = highlightID
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.remove = remove
    }

    private var components: TimerPreset.DurationComponents {
        TimerPreset.components(for: preset.duration)
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { components.hours },
            set: { updateDuration(hours: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { components.minutes },
            set: { updateDuration(minutes: $0) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { components.seconds },
            set: { updateDuration(seconds: $0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.updateColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(preset.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                TimerPresetComponentControl(title: String(localized: "Hours"), value: hoursBinding, range: 0...23)
                TimerPresetComponentControl(title: String(localized: "Minutes"), value: minutesBinding, range: 0...59)
                TimerPresetComponentControl(title: String(localized: "Seconds"), value: secondsBinding, range: 0...59)
            }

            SettingsColorPickerRow(title: "Accent colour", selection: colorBinding)
                .frame(maxWidth: 240, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(isFirst)

                Button(action: moveDown) {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(isLast)

                Spacer()

                Button(role: .destructive, action: remove) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 6)
        .settingsHighlightIfPresent(highlightID)
    }

    private func updateDuration(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var values = components
        if let hours { values.hours = hours }
        if let minutes { values.minutes = minutes }
        if let seconds { values.seconds = seconds }
        preset.duration = TimerPreset.duration(from: values)
    }
}

private struct TimerPresetComponentControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        // The texts sit beside the stepper, not inside its label, so they stay selectable —
        // a selectable Text inside a control label swallows the control's click.
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }
            Stepper(value: $value, in: range) {
                Text(title)
            }
            .labelsHidden()
        }
        .frame(width: 110, alignment: .leading)
    }
}
