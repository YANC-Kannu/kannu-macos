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

struct LockScreenSettings: View {
    @ObservedObject private var previewManager = LockScreenWidgetPreviewManager.shared
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.enableLockScreenWeatherWidget) private var enableLockScreenWeatherWidget
    @Default(.enableLockScreenFocusWidget) private var enableLockScreenFocusWidget
    @Default(.lockScreenWeatherWidgetStyle) private var lockScreenWeatherWidgetStyle
    @Default(.lockScreenWeatherProviderSource) private var lockScreenWeatherProviderSource
    @Default(.lockScreenWeatherTemperatureUnit) private var lockScreenWeatherTemperatureUnit
    @Default(.lockScreenBatteryShowsCharging) private var lockScreenWeatherShowsCharging
    @Default(.lockScreenBatteryShowsBatteryGauge) private var lockScreenWeatherShowsBatteryGauge
    @Default(.lockScreenWeatherShowsAQI) private var lockScreenWeatherShowsAQI
    @Default(.lockScreenWeatherShowsSunrise) private var lockScreenWeatherShowsSunrise
    @Default(.lockScreenWeatherAQIScale) private var lockScreenWeatherAQIScale
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.lockScreenMusicMergedAirPlayOutput) private var lockScreenMusicMergedAirPlayOutput
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.lockScreen.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var musicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
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
            Section {
                Defaults.Toggle(key: .enableLockScreenLiveActivity) {
                    Text("Enable lock screen live activity")
                }
                .settingsHighlight(id: highlightID("Enable lock screen live activity"))
            } header: {
                SettingsSectionHeader("Live Activity & Feedback")
            } footer: {
                SettingsFooter("Controls whether Kannu mirrors lock/unlock events with its own live activity.")
            }

            Section {
                SettingsActionRow {
                    Button(previewManager.isPreviewVisible ? "Hide lock screen preview" : "Preview lock screen widgets") {
                        previewManager.togglePreview()
                    }
                }
                .settingsHighlight(id: highlightID("Preview lock screen widgets"))
            } header: {
                SettingsSectionHeader("Preview")
            } footer: {
                SettingsFooter("Opens a transparent preview window with mock data that mirrors the current lock screen widget configuration.")
            }

            Section {
                if #available(macOS 26.0, *) {
                    SettingsRow("Material", description: lockScreenGlassStyle == .liquid
                                ? nil : Text("Custom Liquid settings require the Liquid Glass material.")) {
                        Picker("Material", selection: $lockScreenGlassStyle) {
                            ForEach(LockScreenGlassStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                } else {
                    SettingsRow("Material", description: Text("Liquid Glass requires macOS 26 or later.")) {
                        Picker("Material", selection: $lockScreenGlassStyle) {
                            ForEach(LockScreenGlassStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Material"))
                }

                if lockScreenGlassStyle == .liquid {
                    SettingsRow("Glass mode", description: lockScreenGlassCustomizationMode == .customLiquid
                                ? Text("Use the sliders below to pick unique Apple liquid-glass variants for each widget.") : nil) {
                        Picker("Glass mode", selection: $lockScreenGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .settingsHighlight(id: highlightID("Glass mode"))
                }
            } header: {
                SettingsSectionHeader("Lock Screen Glass")
            } footer: {
                SettingsFooter("Choose the global material mode for lock screen widgets. Custom Liquid unlocks per-widget variant sliders while Standard sticks to the classic frosted/liquid options.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Show lock screen media panel")
                }
                .settingsHighlight(id: highlightID("Show lock screen media panel"))
                Defaults.Toggle(key: .lockScreenShowAppIcon) {
                    Text("Show media app icon")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Show media app icon"))
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
                .settingsHighlight(id: highlightID("Show panel border"))
                if lockScreenGlassCustomizationMode == .customLiquid {
                    Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                        Text("Use enhanced liquid border")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Use enhanced liquid border"))
                }
                if lockScreenGlassCustomizationMode == .customLiquid {
                    variantSlider(
                        title: "Music panel variant",
                        value: musicVariantBinding,
                        currentValue: lockScreenMusicLiquidGlassVariant.rawValue,
                        isEnabled: enableLockScreenMediaWidget,
                        highlight: highlightID("Music panel variant")
                    )
                } else if lockScreenGlassStyle == .frosted {
                    Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                        Text("Enable media panel blur")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else {
                    blurSettingUnavailableRow
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
                SettingsSectionHeader("Media Panel")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !showStandardMediaControls {
                        SettingsFooter("Enable Dynamic Island media controls to manage the lock screen panel.")
                    }
                    SettingsFooter("Enable and style the media controls that appear above the system clock when the screen is locked.")
                }
            }
            .disabled(!showStandardMediaControls)

            Section {
                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text("Show lock screen timer")
                }
                .settingsHighlight(id: highlightID("Show lock screen timer"))
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
                            variantSlider(
                                title: "Timer widget variant",
                                value: timerVariantBinding,
                                currentValue: lockScreenTimerLiquidGlassVariant.rawValue,
                                isEnabled: enableLockScreenTimerWidget,
                                highlight: highlightID("Timer widget variant")
                            )
                        }
                    }
                }
            } header: {
                SettingsSectionHeader("Timer Widget")
            } footer: {
                SettingsFooter("Controls the optional timer widget that floats above the media panel, including its classic, frosted, or liquid glass surface independent of the global material setting.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                    Text("Show lock screen weather")
                }
                .settingsHighlight(id: highlightID("Show lock screen weather"))

                if enableLockScreenWeatherWidget {
                    Picker("Layout", selection: $lockScreenWeatherWidgetStyle) {
                        ForEach(LockScreenWeatherWidgetStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Layout"))

                    Picker("Weather data provider", selection: $lockScreenWeatherProviderSource) {
                        ForEach(LockScreenWeatherProviderSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Weather data provider"))

                    Picker("Temperature unit", selection: $lockScreenWeatherTemperatureUnit) {
                        ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Temperature unit"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsLocation) {
                        Text("Show location label")
                    }
                    .disabled(lockScreenWeatherWidgetStyle == .circular)
                    .settingsHighlight(id: highlightID("Show location label"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) {
                        Text("Show sunrise time")
                    }
                    .disabled(lockScreenWeatherWidgetStyle != .inline)
                    .settingsHighlight(id: highlightID("Show sunrise time"))

                    SettingsRow("Show AQI widget", description: lockScreenWeatherProviderSource.supportsAirQuality
                                ? nil : Text("Air quality requires the Open Meteo provider.")) {
                        Defaults.Toggle(key: .lockScreenWeatherShowsAQI) {
                            Text("Show AQI widget")
                        }
                    }
                    .disabled(!lockScreenWeatherProviderSource.supportsAirQuality)
                    .settingsHighlight(id: highlightID("Show AQI widget"))

                    if lockScreenWeatherShowsAQI && lockScreenWeatherProviderSource.supportsAirQuality {
                        Picker("Air quality scale", selection: $lockScreenWeatherAQIScale) {
                            ForEach(LockScreenWeatherAirQualityScale.allCases) { scale in
                                Text(scale.displayName).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Air quality scale"))
                    }

                    Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) {
                        Text("Use colored gauges")
                    }
                    .settingsHighlight(id: highlightID("Use colored gauges"))
                }
            } header: {
                SettingsSectionHeader("Weather Widget")
            } footer: {
                SettingsFooter("Enable the weather capsule and configure its layout, provider, units, and optional battery/AQI indicators.")
            }


            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))

                    if lockScreenWeatherShowsBatteryGauge {
                        Defaults.Toggle(key: .lockScreenBatteryUsesLaptopSymbol) {
                            Text("Use MacBook icon when on battery")
                        }
                        .settingsHighlight(id: highlightID("Use MacBook icon when on battery"))

                        Defaults.Toggle(key: .lockScreenBatteryShowsCharging) {
                            Text("Show charging status")
                        }
                        .settingsHighlight(id: highlightID("Show charging status"))

                        if lockScreenWeatherShowsCharging {
                            Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) {
                                Text("Show charging percentage")
                            }
                            .settingsHighlight(id: highlightID("Show charging percentage"))
                        }

                        Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) {
                            Text("Show Bluetooth battery")
                        }
                        .settingsHighlight(id: highlightID("Show Bluetooth battery"))
                    }
                } header: {
                    SettingsSectionHeader("Battery Widget")
                } footer: {
                    SettingsFooter("Enable the battery capsule and configure its layout.")
                }
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                    Text("Show focus widget")
                }
                .settingsHighlight(id: highlightID("Show focus widget"))
            } header: {
                SettingsSectionHeader("Focus Widget")
            } footer: {
                SettingsFooter("Displays the current Focus state above the weather capsule whenever Focus detection is enabled.")
            }


            LockScreenPositioningControls()
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .navigationTitle("Lock screen")
    }
}

extension LockScreenSettings {
    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }

    private var blurSettingUnavailableRow: some View {
        SettingsNoteRow("Enable media panel blur",
                        description: "Only available when Material is set to Frosted Glass.")
    }

    @ViewBuilder
    private func variantSlider(
        title: String,
        value: Binding<Double>,
        currentValue: Int,
        isEnabled: Bool,
        highlight: String,
        preview: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.footerStack) {
            variantSliderRow(value: value, current: currentValue, range: liquidVariantRange, title: title)

            if let preview {
                preview
            }
        }
        .settingsHighlight(id: highlight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct LockScreenGlassVariantPreviewCell: View {
    @Binding var variant: LiquidGlassVariant

    private let cornerRadius: CGFloat = 16
    private let previewCornerRadius: CGFloat = 14
    private let previewSize = CGSize(width: 190, height: 96)

    var body: some View {
        ZStack {
            Image("glassdesktop")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            liquidGlassPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 6)
        .allowsHitTesting(false)
        .onAppear {
            Logger.log("Lock screen glass preview appeared (variant v\(variant.rawValue))", category: .performance)
        }
        .onDisappear {
            Logger.log("Lock screen glass preview disappeared", category: .performance)
        }
        .onChange(of: variant) { _, newValue in
            Logger.log("Lock screen glass preview variant changed to v\(newValue.rawValue)", category: .performance)
        }
    }

    private var liquidGlassPreview: some View {
        LiquidGlassBackground(
            variant: variant,
            cornerRadius: previewCornerRadius
        ) {
            Color.white.opacity(0.04)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}

private struct LockScreenPositioningControls: View {
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenMusicVerticalOffset) private var musicOffset
    @Default(.lockScreenTimerVerticalOffset) private var timerOffset
    @Default(.lockScreenMusicPanelWidth) private var musicWidth
    @Default(.lockScreenTimerWidgetWidth) private var timerWidth
    private let offsetRange: ClosedRange<Double> = -160...160
    private let musicWidthRange: ClosedRange<Double> = 320...Double(LockScreenMusicPanel.defaultCollapsedWidth)
    private let timerWidthRange: ClosedRange<Double> = 320...LockScreenTimerWidget.defaultWidth

    var body: some View {
        Section {
            let weatherBinding = Binding<Double>(
                get: { weatherOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if weatherOffset != clampedValue {
                        weatherOffset = clampedValue
                    }
                    propagateWeatherOffsetChange(animated: false)
                }
            )

            let timerBinding = Binding<Double>(
                get: { timerOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if timerOffset != clampedValue {
                        timerOffset = clampedValue
                    }
                    propagateTimerOffsetChange(animated: false)
                }
            )

            let musicBinding = Binding<Double>(
                get: { musicOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if musicOffset != clampedValue {
                        musicOffset = clampedValue
                    }
                    propagateMusicOffsetChange(animated: false)
                }
            )

            LockScreenPositioningPreview(
                weatherOffset: weatherBinding,
                timerOffset: timerBinding,
                musicOffset: musicBinding,
                musicWidth: musicWidthBinding,
                timerWidth: timerWidthBinding
            )
            .frame(height: 260)
            .padding(.vertical, 8)

            offsetRow(
                title: String(localized: "Weather"),
                value: weatherOffset,
                resetTitle: String(localized: "Reset Weather"),
                resetAction: resetWeatherOffset
            )
            offsetRow(
                title: String(localized: "Timer"),
                value: timerOffset,
                resetTitle: String(localized: "Reset Timer"),
                resetAction: resetTimerOffset
            )
            offsetRow(
                title: String(localized: "Music"),
                value: musicOffset,
                resetTitle: String(localized: "Reset Music"),
                resetAction: resetMusicOffset
            )
        } header: {
            SettingsSectionHeader("Lock Screen Positioning")
        } footer: {
            SettingsFooter("Drag the previews to adjust vertical placement. Positive values lift the panel; negative values lower it. Use the width sliders below to narrow the media and timer widgets without exceeding their default size. Changes apply instantly while the widgets are visible.")
                .textCase(nil)
        }

        Section {
            widthRow(
                title: String(localized: "Media Panel Width"),
                value: musicWidthBinding,
                range: musicWidthRange,
                helpText: String(localized: "Shrinks the lock screen media panel while keeping the expanded view full width.")
            )
            widthRow(
                title: String(localized: "Timer Widget Width"),
                value: timerWidthBinding,
                range: timerWidthRange,
                helpText: String(localized: "Adjusts the lock screen timer widget width without affecting button sizing.")
            )
            SettingsActionRow {
                Button(String(localized: "Reset Media Width"), action: resetMusicWidth)
                    .disabled(musicWidth == Double(LockScreenMusicPanel.defaultCollapsedWidth))
                Button(String(localized: "Reset Timer Width"), action: resetTimerWidth)
                    .disabled(timerWidth == LockScreenTimerWidget.defaultWidth)
            }
        } header: {
            SettingsSectionHeader("Widget Width")
        }
    }

    private var musicWidthBinding: Binding<Double> {
        Binding(
            get: { musicWidth },
            set: { newValue in
                let clampedValue = clamp(newValue, within: musicWidthRange)
                if musicWidth != clampedValue {
                    musicWidth = clampedValue
                    propagateMusicWidthChange(animated: false)
                }
            }
        )
    }

    private var timerWidthBinding: Binding<Double> {
        Binding(
            get: { timerWidth },
            set: { newValue in
                let clampedValue = clamp(newValue, within: timerWidthRange)
                if timerWidth != clampedValue {
                    timerWidth = clampedValue
                    propagateTimerWidthChange(animated: false)
                }
            }
        )
    }

    private func clampOffset(_ value: Double) -> Double {
        min(max(value, offsetRange.lowerBound), offsetRange.upperBound)
    }

    private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func resetWeatherOffset() {
        weatherOffset = 0
        propagateWeatherOffsetChange(animated: true)
    }

    private func resetTimerOffset() {
        timerOffset = 0
        propagateTimerOffsetChange(animated: true)
    }

    private func resetMusicOffset() {
        musicOffset = 0
        propagateMusicOffsetChange(animated: true)
    }

    private func resetMusicWidth() {
        musicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
        propagateMusicWidthChange(animated: true)
    }

    private func resetTimerWidth() {
        timerWidth = LockScreenTimerWidget.defaultWidth
        propagateTimerWidthChange(animated: true)
    }

    private func propagateWeatherOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateTimerOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateMusicOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateMusicWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateTimerWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetPanelManager.shared.refreshPosition(animated: animated)
        }
    }

    /// One widget's vertical offset: its value and a Reset on the trailing side.
    private func offsetRow(title: String, value: Double, resetTitle: String, resetAction: @escaping () -> Void) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text("\(formattedPoints(value)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(resetTitle, action: resetAction)
                    .disabled(value == 0)
            }
        } label: {
            Text("\(title) Offset")
        }
    }

    /// One widget's width: title and what it changes on the leading side, slider and value trailing.
    private func widthRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, helpText: String) -> some View {
        SettingsSliderRow(verbatim: title, description: helpText, value: value, in: range,
                          valueText: Text(formattedWidth(value.wrappedValue)))
    }

    private func formattedPoints(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    private func formattedWidth(_ value: Double) -> String {
        String(format: "%.0f pt", value)
    }
}

private struct LockScreenPositioningPreview: View {
    @Binding var weatherOffset: Double
    @Binding var timerOffset: Double
    @Binding var musicOffset: Double
    @Binding var musicWidth: Double
    @Binding var timerWidth: Double

    @State private var weatherStartOffset: Double = 0
    @State private var timerStartOffset: Double = 0
    @State private var musicStartOffset: Double = 0
    @State private var isWeatherDragging = false
    @State private var isTimerDragging = false
    @State private var isMusicDragging = false

    private let offsetRange: ClosedRange<Double> = -160...160

    var body: some View {
        GeometryReader { geometry in
            let screenPadding: CGFloat = 26
            let screenCornerRadius: CGFloat = 28
            let screenRect = CGRect(
                x: screenPadding,
                y: screenPadding,
                width: geometry.size.width - (screenPadding * 2),
                height: geometry.size.height - (screenPadding * 2)
            )
            let centerX = screenRect.midX
            let weatherBaseY = screenRect.minY + (screenRect.height * 0.28)
            let timerBaseY = screenRect.minY + (screenRect.height * 0.5)
            let musicBaseY = screenRect.minY + (screenRect.height * 0.78)
            let weatherSize = CGSize(width: screenRect.width * 0.42, height: screenRect.height * 0.22)
            let defaultMusicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
            let musicWidthScale = CGFloat(musicWidth / defaultMusicWidth)
            let timerWidthScale = CGFloat(timerWidth / LockScreenTimerWidget.defaultWidth)
            let timerSize = CGSize(
                width: (screenRect.width * 0.5) * timerWidthScale,
                height: screenRect.height * 0.2
            )
            let musicSize = CGSize(
                width: (screenRect.width * 0.56) * musicWidthScale,
                height: screenRect.height * 0.34
            )

            ZStack {
                RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .frame(width: screenRect.width, height: screenRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 18)
                    .position(x: screenRect.midX, y: screenRect.midY)

                weatherPanel(size: weatherSize)
                    .position(x: centerX, y: weatherBaseY - CGFloat(weatherOffset))
                    .gesture(weatherDragGesture(in: screenRect, baseY: weatherBaseY, panelSize: weatherSize))

                timerPanel(size: timerSize)
                    .position(x: centerX, y: timerBaseY - CGFloat(timerOffset))
                    .gesture(timerDragGesture(in: screenRect, baseY: timerBaseY, panelSize: timerSize))

                musicPanel(size: musicSize)
                    .position(x: centerX, y: musicBaseY - CGFloat(musicOffset))
                    .gesture(musicDragGesture(in: screenRect, baseY: musicBaseY, panelSize: musicSize))
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: weatherOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicWidth)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerWidth)
    }

    private func weatherPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.78), Color.blue.opacity(0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Inline snapshot preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
            }
            .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 8)
    }

    private func musicPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.68), Color.pink.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Media", systemImage: "play.square.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Lock screen panel preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
            }
            .shadow(color: Color.purple.opacity(0.24), radius: 12, x: 0, y: 9)
    }

    private func timerPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.orange.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay {
                VStack(spacing: 6) {
                    Text("Timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("00:05:00")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 8)
    }

    private func weatherDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isWeatherDragging {
                    isWeatherDragging = true
                    weatherStartOffset = weatherOffset
                }

                let proposed = weatherStartOffset - Double(value.translation.height)
                weatherOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isWeatherDragging = false
            }
    }

    private func musicDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isMusicDragging {
                    isMusicDragging = true
                    musicStartOffset = musicOffset
                }

                let proposed = musicStartOffset - Double(value.translation.height)
                musicOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isMusicDragging = false
            }
    }

    private func timerDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTimerDragging {
                    isTimerDragging = true
                    timerStartOffset = timerOffset
                }

                let proposed = timerStartOffset - Double(value.translation.height)
                timerOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isTimerDragging = false
            }
    }

    private func clampedOffset(
        _ proposed: Double,
        baseCenterY: CGFloat,
        panelHeight: CGFloat,
        screenRect: CGRect
    ) -> Double {
        let halfHeight = panelHeight / 2
        let minCenterY = screenRect.minY + halfHeight
        let maxCenterY = screenRect.maxY - halfHeight
        let proposedCenter = baseCenterY - CGFloat(proposed)
        let clampedCenter = min(max(proposedCenter, minCenterY), maxCenterY)
        let derivedOffset = Double(baseCenterY - clampedCenter)
        return min(max(derivedOffset, offsetRange.lowerBound), offsetRange.upperBound)
    }
}
