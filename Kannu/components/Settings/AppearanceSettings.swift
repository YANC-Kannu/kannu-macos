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
import UniformTypeIdentifiers

struct Appearance: View {
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @Default(.sliderColor) var sliderColor
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.customNotchSkins) private var customNotchSkins
    @Default(.selectedNotchSkinID) private var selectedNotchSkinID
    @Default(.notchSkinScrimOpacity) private var notchSkinScrimOpacity
    @Default(.notchFillColor) private var notchFillColor
    @ObservedObject private var notchSkinManager = NotchSkinManager.shared
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @Default(.brainAppearance) private var brainAppearance

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?
    @State private var isSkinImporterPresented = false
    @State private var isSkinDropTarget = false
    @State private var skinPromptCopied = false

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var appearanceMusicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var appearanceTimerVariantBinding: Binding<Double> {
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
                // The moon only picks the opposite of what is on screen, so this is the one way back
                // to Match macOS.
                SettingsRow("Brain appearance", description: brainAppearance.description) {
                    Picker("Brain appearance", selection: $brainAppearance) {
                        ForEach(BrainAppearance.allCases) { choice in
                            Text(choice.localizedName)
                                .tag(choice)
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Brain appearance"))
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Brain icon in notch")
                }
                .settingsHighlight(id: highlightID("Brain icon in notch"))
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
                .settingsHighlight(id: highlightID("Corner radius scaling"))
                Defaults.Toggle(key: .useModernCloseAnimation) {
                    Text("Use simpler close animation")
                }
                .settingsHighlight(id: highlightID("Use simpler close animation"))
            } header: {
                SettingsSectionHeader("General")
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    SettingsRow("Main screen style", description: externalDisplayStyle.description) {
                        Picker("Main screen style", selection: $externalDisplayStyle) {
                            ForEach(ExternalDisplayStyle.allCases) { style in
                                Text(style.localizedName)
                                    .tag(style)
                            }
                        }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                } header: {
                    SettingsSectionHeader("Display Style")
                }
            }

            notchWidthControls()

            Section {
                SettingsColorPickerRow(title: "Notch fill color",
                                       description: String(localized: "Fill color is used when no custom notch skin is selected."),
                                       selection: $notchFillColor)
                    .settingsHighlight(id: highlightID("Notch fill color"))
            } header: {
                SettingsSectionHeader("Notch appearance")
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
                    .settingsHighlight(id: highlightID("Lock screen material"))
                } else {
                    SettingsRow("Material", description: Text("Liquid Glass requires macOS 26 or later.")) {
                        Picker("Material", selection: $lockScreenGlassStyle) {
                            ForEach(LockScreenGlassStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Lock screen material"))
                }

                if lockScreenGlassStyle == .liquid {
                    SettingsRow("Lock screen glass mode", description: lockScreenGlassCustomizationMode == .customLiquid
                                ? Text("Pick per-widget liquid-glass variants below. Changes mirror the Lock screen tab.") : nil) {
                        Picker("Lock screen glass mode", selection: $lockScreenGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .settingsHighlight(id: highlightID("Lock screen glass mode"))

                    if lockScreenGlassCustomizationMode == .customLiquid {
                        VStack(alignment: .leading, spacing: SettingsMetrics.footerStack) {
                            variantSliderRow(value: appearanceMusicVariantBinding, current: lockScreenMusicLiquidGlassVariant.rawValue,
                                             range: liquidVariantRange, title: String(localized: "Music panel variant"))

                            LockScreenGlassVariantPreviewCell(variant: $lockScreenMusicLiquidGlassVariant)
                        }
                        .settingsHighlight(id: highlightID("Music panel variant (appearance)"))
                        .disabled(!enableLockScreenMediaWidget)
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.4)

                        variantSliderRow(value: appearanceTimerVariantBinding, current: lockScreenTimerLiquidGlassVariant.rawValue,
                                         range: liquidVariantRange, title: String(localized: "Timer widget variant"))
                        .settingsHighlight(id: highlightID("Timer widget variant (appearance)"))
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.4)
                    }
                }
            } header: {
                SettingsSectionHeader("Lock Screen Glass")
            } footer: {
                SettingsFooter("Configure lock screen materials from the Appearance tab. Custom Liquid unlocks variant sliders for both widgets whenever Liquid Glass is selected.")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Enable colored spectrograms")
                }
                .settingsHighlight(id: highlightID("Enable colored spectrograms"))
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Tint player controls with the album art color")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                .settingsHighlight(id: highlightID("Enable blur effect behind album art"))
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
                .settingsHighlight(id: highlightID("Slider color"))
            } header: {
                SettingsSectionHeader("Media")
            }

            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Idle Animation")
                }
                .settingsHighlight(id: highlightID("Idle Animation"))
            } header: {
                HStack {
                    SettingsSectionHeader("Additional features")
                }
            }

            // MARK: - Custom Idle Animations Section
            IdleAnimationsSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        notchSkinCard(
                            title: "Default",
                            image: nil,
                            isSelected: selectedNotchSkinID == nil
                        ) {
                            notchSkinManager.selectSkin(nil)
                        }

                        ForEach(BuiltInNotchSkin.all) { skin in
                            notchSkinCard(
                                title: skin.name,
                                image: NSImage(named: skin.assetName),
                                isSelected: selectedNotchSkinID == skin.id
                            ) {
                                notchSkinManager.selectBuiltInSkin(skin)
                            }
                        }

                        ForEach(customNotchSkins) { skin in
                            notchSkinCard(
                                title: skin.name,
                                image: NSImage(contentsOf: skin.fileURL),
                                isSelected: selectedNotchSkinID == skin.id.uuidString
                            ) {
                                notchSkinManager.selectSkin(skin)
                            }
                            .contextMenu {
                                Button("Remove") {
                                    notchSkinManager.removeSkin(skin)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isSkinDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isSkinDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isSkinDropTarget) { providers in
                        handleSkinDrop(providers)
                    }
                }
                .settingsHighlight(id: highlightID("Notch skin"))

                SettingsActionRow {
                    Button("Remove selected") {
                        if let id = selectedNotchSkinID,
                           let skin = customNotchSkins.first(where: { $0.id.uuidString == id }) {
                            notchSkinManager.removeSkin(skin)
                        }
                    }
                    .disabled(selectedNotchSkinID == nil || BuiltInNotchSkin.with(id: selectedNotchSkinID) != nil)

                    Button("Copy AI prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(NotchSkinPrompt.text, forType: .string)
                        notchSkinManager.importError = nil
                        skinPromptCopied = true
                    }
                    .help("Copies a prompt for ChatGPT or another image AI: it asks you a few questions, then designs a skin that fits the notch")

                    Button("Upload skin") {
                        notchSkinManager.importError = nil
                        isSkinImporterPresented = true
                    }
                    .buttonStyle(SettingsButtonStyle(.primary))
                }

                SettingsSliderRow("Scrim opacity", value: $notchSkinScrimOpacity, in: 0...0.6, step: 0.05,
                                  valueText: Text("\(Int(notchSkinScrimOpacity * 100))%"))
                .disabled(selectedNotchSkinID == nil)
                .settingsHighlight(id: highlightID("Skin scrim opacity"))
            } header: {
                SettingsSectionHeader("Notch skin")
            } footer: {
                if let importError = notchSkinManager.importError {
                    SettingsFooter(importError)
                } else if skinPromptCopied {
                    SettingsFooter("Prompt copied. Paste it into ChatGPT or another image AI, answer its questions, then upload the image here.")
                } else {
                    SettingsFooter("Upload a PNG, JPG, or WebP image to fill the notch background. Add a scrim if the traffic-light indicators are hard to read.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        appIconCard(
                            title: "Default",
                            image: defaultAppIconImage(),
                            isSelected: selectedAppIconID == nil
                        ) {
                            selectedAppIconID = nil
                            applySelectedAppIcon()
                        }

                        ForEach(customAppIcons) { icon in
                            appIconCard(
                                title: icon.name,
                                image: customIconImage(for: icon),
                                isSelected: selectedAppIconID == icon.id.uuidString
                            ) {
                                selectedAppIconID = icon.id.uuidString
                                applySelectedAppIcon()
                            }
                            .contextMenu {
                                Button("Remove") {
                                    removeCustomIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                        handleIconDrop(providers)
                    }
                }
                .settingsHighlight(id: highlightID("App icon"))

                SettingsActionRow {
                    Button("Remove selected") {
                        if let id = selectedAppIconID,
                           let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                            removeCustomIcon(icon)
                        }
                    }
                    .disabled(selectedAppIconID == nil)

                    Button("Add icon") {
                        iconImportError = nil
                        isIconImporterPresented = true
                    }
                    .buttonStyle(SettingsButtonStyle(.primary))
                }
            } header: {
                SettingsSectionHeader("App icon")
            } footer: {
                if let iconImportError {
                    SettingsFooter(iconImportError)
                } else {
                    SettingsFooter("Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                }
            }
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "Icon import was canceled or failed."
            }
        }
        .fileImporter(
            isPresented: $isSkinImporterPresented,
            allowedContentTypes: [.png, .jpeg, .image, .svg]
        ) { result in
            switch result {
            case .success(let url):
                notchSkinManager.importSkin(from: url)
            case .failure:
                notchSkinManager.importError = "Skin import was canceled or failed."
            }
        }
        .navigationTitle("Appearance")
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func notchSkinCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .frame(width: 120, height: 32)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleSkinDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in notchSkinManager.importSkin(from: url) }
        }
        return true
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            iconImportError = "That file could not be loaded as an image."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "Unable to save the icon file."
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        NSApp.applicationIconImage = image
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        Section {
            let recommendedMin = currentRecommendedMinimumNotchWidth()
            let tabCount = enabledStandardTabCount()
            let dynamicRange = Double(recommendedMin)...900
            
            let closedRange = Double(80)...400

            let widthBinding = Binding<Double>(
                get: { Double(openNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, dynamicRange.lowerBound), dynamicRange.upperBound)
                    let value = CGFloat(clamped)
                    if openNotchWidth != value {
                        openNotchWidth = value
                    }
                }
            )
            
            let closedWidthBinding = Binding<Double>(
                get: { Double(closedNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, closedRange.lowerBound), closedRange.upperBound)
                    let value = CGFloat(clamped)
                    if closedNotchWidth != value {
                        closedNotchWidth = value
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            )

            Defaults.Toggle(key: .customizePhysicalNotchWidth) {
                Text("Customize physical notch width")
            }
            .onChange(of: customizePhysicalNotchWidth) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .onAppear {
                enforceMinimumNotchWidth()
            }
            .settingsHighlight(id: highlightID("Customize physical notch width"))

            SettingsSliderRow("Closed notch / pill width", value: closedWidthBinding, in: closedRange, step: 5,
                              valueText: Text("\(Int(closedNotchWidth)) px"))
            .disabled(!customizePhysicalNotchWidth)
            .opacity(customizePhysicalNotchWidth ? 1 : 0.5)
            .settingsHighlight(id: highlightID("Closed notch / pill width"))

            SettingsSliderRow("Expanded notch width", value: widthBinding, in: dynamicRange, step: 10,
                              valueText: Text("\(Int(openNotchWidth)) px"))
            .disabled(!customizePhysicalNotchWidth)
            .opacity(customizePhysicalNotchWidth ? 1 : 0.5)
            .settingsHighlight(id: highlightID("Expanded notch width"))

            LabeledContent {
                Button("Reset Width") {
                    openNotchWidth = recommendedMin
                }
                .disabled(!customizePhysicalNotchWidth || abs(openNotchWidth - recommendedMin) < 0.5)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended width")
                    Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") enabled · min \(Int(recommendedMin)) px")
                        .settingsDescriptionStyle()
                }
            }
        } header: {
            HStack {
                SettingsSectionHeader("Notch Width")
                customBadge(text: "Beta")
            }
        } footer: {
            SettingsFooter(String(localized: "Recommended minimum width adjusts automatically based on the number of enabled tabs."))
        }
    }

    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }
}
