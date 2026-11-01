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
import Combine
import Defaults
import SwiftUI

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Deliberately starts nothing. This is a *preview*: it only needs the three change
        // notifications, which `SystemChangesObserver` already produces whenever the HUD feature is
        // on. Starting the shared controllers here turned the preview into a second owner of them —
        // and since it never stopped them, opening this pane with the HUD switched **off** left
        // `SystemBrightnessController`'s 6.7 Hz IOKit poll running for the rest of the process:
        // `stopObserving()` never runs again, because the feature was already off. That is the
        // reported "toggled a lot of settings, then disabling the features didn't help".
        //
        // With the feature on, nothing changes — the observer is running the controllers and the
        // notifications flow. With it off, the preview sits still, which is the honest thing for a
        // preview of something that is not running.

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        // One Form for the whole tab. The style cards used to sit above two stacked Forms (the
        // style's settings, then the display integrations), each scrolling on its own.
        Form {
            Section {
                HStack(spacing: 10) {
                    HUDSelectionCard(
                        title: String(localized: "Dynamic Island"),
                        isSelected: selectedTab == .hud,
                        action: {
                            selectedTab = .hud
                            enableSystemHUD = true
                            enableCustomOSD = false
                            enableVerticalHUD = false
                            enableCircularHUD = false
                        }
                    ) {
                        VStack {
                            Capsule()
                                .fill(Color.black)
                                .frame(width: 64, height: 20)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                .overlay {
                                    HStack(spacing: 6) {
                                        Image(systemName: previewModel.iconName)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 12)

                                        GeometryReader { geo in
                                            Capsule()
                                                .fill(Color.white.opacity(0.2))
                                                .overlay(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.white)
                                                        .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                        .animation(.spring(response: 0.3), value: previewModel.level)
                                                }
                                        }
                                        .frame(height: 4)
                                    }
                                    .padding(.horizontal, 8)
                                }
                        }
                    }

                    HUDSelectionCard(
                        title: String(localized: "Custom OSD"),
                        isSelected: selectedTab == .osd,
                        action: {
                            selectedTab = .osd
                            enableCustomOSD = true
                            enableSystemHUD = false
                            enableVerticalHUD = false
                            enableCircularHUD = false
                        }
                    ) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                        .symbolRenderingMode(.hierarchical)
                                        .contentTransition(.symbolEffect(.replace))

                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.2))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.primary)
                                                    .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                    .animation(.spring(response: 0.3), value: previewModel.level)
                                            }
                                    }
                                    .frame(width: 36, height: 4)
                                }
                            }
                            .frame(width: 44, height: 44)
                    }
                    // The "Enable Custom OSD" search entry lands on the card that enables it.
                    .settingsHighlight(id: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD"))

                    HUDSelectionCard(
                        title: String(localized: "Vertical Bar"),
                        isSelected: selectedTab == .vertical,
                        action: {
                            selectedTab = .vertical
                            enableVerticalHUD = true
                            enableSystemHUD = false
                            enableCustomOSD = false
                            enableCircularHUD = false
                        }
                    ) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                            .overlay {
                                VStack {
                                    GeometryReader { geo in
                                        VStack {
                                            Spacer()
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.white)
                                                .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                    }
                                    .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(.bottom, 2)

                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                        .symbolRenderingMode(.hierarchical)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(4)
                            }
                            .frame(width: 22, height: 54)
                    }

                    HUDSelectionCard(
                        title: String(localized: "Circular"),
                        isSelected: selectedTab == .circular,
                        action: {
                            selectedTab = .circular
                            enableCircularHUD = true
                            enableSystemHUD = false
                            enableCustomOSD = false
                            enableVerticalHUD = false
                        }
                    ) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: CGFloat(previewModel.level))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.3), value: previewModel.level)
                            Image(systemName: previewModel.iconName)
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: 44, height: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            switch selectedTab {
            case .hud:
                HUD()
            case .osd:
                if #available(macOS 15.0, *) {
                    CustomOSDSettings()
                } else {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                            Text("macOS 15 or later required")
                                .font(.headline)
                            Text("Custom OSD feature requires macOS 15 or later.")
                                .settingsDescriptionStyle()
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
            case .vertical:
                verticalHUDSections
            case .circular:
                circularHUDSections
            }

            // Third-party display integrations (shared across all HUD variants)
            ExternalDisplayIntegrationsSection()
        }
        .navigationTitle("HUD and OSD")
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
            if #unavailable(macOS 26.0), Defaults[.osdMaterial] == .liquid {
                Defaults[.osdMaterial] = .frosted
                Defaults[.osdLiquidGlassCustomizationMode] = .standard
            }
        }
        // These lived on the Dynamic Island and Custom OSD sub-views' own Forms, live only while that
        // style was selected. Rows of a lazy Form cannot host them reliably, so they sit here, keyed
        // by the selected style exactly as before.
        .onChange(of: selectedTab) { _, _ in
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            switch selectedTab {
            case .hud:
                if !granted {
                    enableSystemHUD = false
                } else {
                    // Without this the tap was created once at launch and never retried, so
                    // granting Accessibility only took effect after restarting Kannu.
                    MediaKeyInterceptor.shared.start()
                }
            case .osd:
                if !granted {
                    enableCustomOSD = false
                    CustomOSDWindowManager.shared.forceHideAll()
                }
            case .vertical, .circular:
                break
            }
        }
        .onChange(of: enableCustomOSD) { _, enabled in
            if !enabled {
                CustomOSDWindowManager.shared.forceHideAll()
            }
        }
    }

    /// Accessibility callout, or the three HUD switches once Kannu can intercept the keys.
    @ViewBuilder
    private func controlsSections(permissionMessage: String) -> some View {
        if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
            Section {
                SettingsPermissionCallout(
                    message: permissionMessage,
                    requestAction: {
                        accessibilityPermission.requestAuthorizationPrompt()
                    },
                    openSettingsAction: {
                        accessibilityPermission.openSystemSettings()
                    }
                )
            } header: {
                SettingsSectionHeader("Accessibility")
            }
        }

        if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
            Section {
                Toggle("Volume HUD", isOn: $enableVolumeHUD)
                Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                SettingsRow("Keyboard Backlight HUD", description: enableThirdPartyDDCIntegration
                            ? Text("Disabled while external display integration is active. Brightness keys are handled by the external app.") : nil) {
                    Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                }
                .disabled(enableThirdPartyDDCIntegration)
            } header: {
                SettingsSectionHeader("Controls")
            } footer: {
                SettingsFooter("Choose which system controls should display HUD notifications.")
            }
        }
    }

    @ViewBuilder
    var verticalHUDSections: some View {
        controlsSections(permissionMessage: "Accessibility permission is needed to intercept system controls for the Vertical HUD.")

        Section {
            Toggle("Show Percentage", isOn: $verticalHUDShowValue)
            Toggle("Use Accent Color", isOn: $verticalHUDUseAccentColor)
            Toggle("Interactive (Drag to Change)", isOn: $verticalHUDInteractive)
            Picker("Material", selection: $verticalHUDMaterial) {
                ForEach(availableVerticalMaterials, id: \.self) { material in
                    Text(material.rawValue).tag(material)
                }
            }

            if verticalHUDMaterial == .liquid {
                if #available(macOS 26.0, *) {
                    SettingsRow("Glass mode") {
                        Picker("Glass mode", selection: $verticalHUDLiquidGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                        variantSliderRow(value: verticalLiquidVariantBinding, current: verticalHUDLiquidGlassVariant.rawValue,
                                         range: liquidVariantRange, title: String(localized: "Custom liquid variant"))
                    }
                } else {
                    Text("Custom Liquid is available on macOS 26 or later.")
                        .settingsDescriptionStyle()
                }
            }
            Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                Text("Color-coded Volume")
            }
            if Defaults[.useColorCodedVolumeDisplay] {
                Defaults.Toggle(key: .useSmoothColorGradient) {
                    Text("Smooth color transitions")
                }
            }
        } header: {
            SettingsSectionHeader("Behavior & Style")
        }

        Section {
            Picker("HUD Position", selection: $verticalHUDPosition) {
                Text("Left").tag("left")
                Text("Right").tag("right")
            }
            .pickerStyle(.menu)

            dimensionSlider(Text("Screen Padding: \(Int(verticalHUDPadding))px"), value: $verticalHUDPadding, in: 0...100, step: 4)
        } header: {
            SettingsSectionHeader("Position")
        } footer: {
            SettingsFooter("Choose directly on which side of the screen the vertical bar appears.")
        }

        Section {
            dimensionSlider(Text("Width: \(Int(verticalHUDWidth))px"), value: $verticalHUDWidth, in: 24...80, step: 2)
            dimensionSlider(Text("Height: \(Int(verticalHUDHeight))px"), value: $verticalHUDHeight, in: 100...500, step: 10)
            SettingsActionRow {
                Button("Reset to Default") {
                    verticalHUDWidth = 36
                    verticalHUDHeight = 160
                    verticalHUDPadding = 24
                }
            }
        } header: {
            SettingsSectionHeader("Dimensions")
        }
    }

    @ViewBuilder
    var circularHUDSections: some View {
        controlsSections(permissionMessage: "Accessibility permission is needed to intercept system controls for the Circular HUD.")

        Section {
            Toggle("Show Percentage", isOn: $circularHUDShowValue)
            Toggle("Use Accent Color", isOn: $circularHUDUseAccentColor)
            Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                Text("Color-coded Volume")
            }
            if Defaults[.useColorCodedVolumeDisplay] {
                Defaults.Toggle(key: .useSmoothColorGradient) {
                    Text("Smooth color transitions")
                }
            }
        } header: {
            SettingsSectionHeader("Style")
        }

        Section {
            dimensionSlider(Text("Size: \(Int(circularHUDSize))px"), value: $circularHUDSize, in: 40...200, step: 5)
            dimensionSlider(Text("Line Width: \(Int(circularHUDStrokeWidth))px"), value: $circularHUDStrokeWidth, in: 2...16, step: 1)
            SettingsActionRow {
                Button("Reset to Default") {
                    circularHUDSize = 65
                    circularHUDStrokeWidth = 4
                }
            }
        } header: {
            SettingsSectionHeader("Dimensions")
        }
    }

    /// A size or position slider: the title (which carries the value, "Width: 36px") on the leading
    /// side, the slider trailing. The readout column stays reserved, so the bar is the same length
    /// as on a row whose value sits trailing.
    private func dimensionSlider<V: BinaryFloatingPoint>(_ title: Text, value: Binding<V>, in range: ClosedRange<V>,
                                                         step: V.Stride) -> some View where V.Stride: BinaryFloatingPoint {
        SettingsSliderRow(title: title.monospacedDigit(), value: value, in: range, step: step, valueText: nil)
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return "Running" }
            if betterDisplayManager.isDetected { return "Not running" }
            return "Not detected"
        case .lunar:
            if lunarManager.isConnected { return "Connected" }
            if lunarManager.isRunning { return "Running" }
            if lunarManager.isDetected { return "Not running" }
            return "Not detected"
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if lunarManager.isRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through Kannu's HUD."
            }
            if !betterDisplayManager.isRunning {
                return "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration."
            }
            return "BetterDisplay OSD events will be routed through Kannu's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through Kannu's HUD via DDC."
            }
            if !lunarManager.isRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through Kannu's HUD; volume follows when external volume control listener is enabled below."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    /// Step size and display-app integration sections, drawn inside the Controls tab's Form.
    var body: some View {
        Section {
            stepRow(Text("Volume step"), value: $volumeStepPercent)
                .settingsHighlight(id: highlightID("Volume step"))
                .disabled(enableExternalVolumeControlListener)
            stepRow(Text("Volume fine step"), value: $volumeFineStepPercent)
                .settingsHighlight(id: highlightID("Volume fine step"))
                .disabled(enableExternalVolumeControlListener)
            stepRow(Text("Brightness step"), value: $brightnessStepPercent)
                .settingsHighlight(id: highlightID("Brightness step"))
                .disabled(enableThirdPartyDDCIntegration)
            stepRow(Text("Brightness fine step"), value: $brightnessFineStepPercent)
                .settingsHighlight(id: highlightID("Brightness fine step"))
                .disabled(enableThirdPartyDDCIntegration)
        } header: {
            SettingsSectionHeader("Step size")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if enableExternalVolumeControlListener {
                    SettingsFooter("Disabled while external display volume integration is active.")
                }
                if enableThirdPartyDDCIntegration {
                    SettingsFooter("Disabled while external display brightness integration is active.")
                }
                SettingsFooter("Percent change per key press. Fine step applies when holding Shift+Option.")
            }
        }

        Section {
            SettingsRow("Enable third-party DDC app integration", description: enableThirdPartyDDCIntegration
                        ? nil : Text("Enable to route BetterDisplay or Lunar display adjustments through Kannu's active HUD style.")) {
                Toggle("Enable third-party DDC app integration", isOn: $enableThirdPartyDDCIntegration)
            }
            .settingsHighlight(id: highlightID("Third-party DDC app integration"))

            if enableThirdPartyDDCIntegration {
                Picker("Provider", selection: $thirdPartyDDCProvider) {
                    ForEach(ThirdPartyDDCProvider.allCases) { provider in
                        HStack {
                            AppIconImage(
                                bundleIdentifiers: provider.bundleIdentifiers,
                                symbolFallback: "display",
                                symbolColor: .secondary
                            )
                            Text(provider.displayName)
                        }
                        .tag(provider)
                    }
                }
                .settingsHighlight(id: highlightID("Third-party DDC provider"))

                SettingsRow("Enable external volume control listener", description: Text(
                    enableExternalVolumeControlListener
                    ? "Kannu's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                    : "Kannu keeps native volume key interception. External provider volume payloads are ignored while this is off."
                )) {
                    Toggle("Enable external volume control listener", isOn: $enableExternalVolumeControlListener)
                }
                .settingsHighlight(id: highlightID("Enable external volume control listener"))

                LabeledContent {
                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Status")
                            Text(providerStatusText)
                                .foregroundStyle(providerStatusColor)
                        }
                        // The descriptions carry Markdown links; a plain String would show the brackets.
                        Text(LocalizedStringKey(providerStatusDescription))
                            .settingsDescriptionStyle()
                    }
                }
            }
        } footer: {
            if enableThirdPartyDDCIntegration {
                SettingsFooter("Kannu always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
            }
        }
    }

    /// A percent step: the title on the leading side, the value and a stepper trailing.
    private func stepRow(_ title: Text, value: Binding<Int>) -> some View {
        SettingsStepperRow(title: title, value: value, in: 1...25,
                           valueText: Text("\(value.wrappedValue)%"))
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                // Four cards share one Form row, so they flex instead of taking a fixed 110 pt.
                .frame(minWidth: 72, maxWidth: 110)
                .frame(height: 76)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
