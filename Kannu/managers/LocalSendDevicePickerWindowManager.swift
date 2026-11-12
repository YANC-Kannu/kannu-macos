/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
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
import SwiftUI
import Defaults

private func applyLocalSendPanelCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

@MainActor
final class LocalSendDevicePickerWindowManager {
    static let shared = LocalSendDevicePickerWindowManager()
    
    private var window: NSWindow?
    private var onDeviceSelected: ((LocalSendDeviceInfo) -> Void)?
    private var onDismiss: (() -> Void)?
    
    private init() {}
    
    func show(
        onDeviceSelected: @escaping (LocalSendDeviceInfo) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let cornerRadius: CGFloat = 24
        self.onDeviceSelected = onDeviceSelected
        self.onDismiss = onDismiss
        
        let pickerView = LocalSendDevicePickerView(
            onDeviceSelected: { [weak self] device in
                self?.onDeviceSelected?(device)
                self?.hide()
            },
            onDismiss: { [weak self] in
                self?.onDismiss?()
                self?.hide()
            }
        )
        
        if let existingWindow = window {
            let hostingView = NSHostingView(rootView: pickerView)
            hostingView.sizingOptions = []
            applyLocalSendPanelCornerMask(hostingView, radius: cornerRadius)
            existingWindow.setHostedContent(hostingView)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        guard let screen = NSScreen.main else { return }
        
        let windowSize = CGSize(width: 480, height: 400)
        let windowOrigin = CGPoint(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.midY - windowSize.height / 2
        )
        
        let newWindow = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = true
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: 
            pickerView
                .background(Color.clear)
        )
        hostingView.sizingOptions = []
        applyLocalSendPanelCornerMask(hostingView, radius: cornerRadius)
        newWindow.setHostedContent(hostingView)
        newWindow.isMovableByWindowBackground = true
        
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        
        // Add click-outside-to-dismiss
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let locationInWindow = event.locationInWindow
            let windowFrame = window.frame
            let clickLocation = NSPoint(
                x: windowFrame.origin.x + locationInWindow.x,
                y: windowFrame.origin.y + locationInWindow.y
            )
            
            if !windowFrame.contains(clickLocation) && event.window != window {
                self.onDismiss?()
                self.hide()
            }
            return event
        }
    }
    
    func hide() {
        window?.orderOut(nil)
        window = nil
        onDeviceSelected = nil
        onDismiss = nil
    }
}

// MARK: - LocalSend Device Picker View

struct LocalSendDevicePickerView: View {
    @StateObject private var localSend = LocalSendService.shared
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant

    let onDeviceSelected: (LocalSendDeviceInfo) -> Void
    let onDismiss: () -> Void

    var body: some View {
        LocalSendDevicePickerContent(
            devices: localSend.devices,
            rejectedDeviceIDs: localSend.rejectedDeviceIDs,
            isRefreshing: localSend.isRefreshing,
            glassMode: glassMode,
            liquidGlassVariant: liquidGlassVariant,
            onRefresh: { localSend.refreshDeviceScan() },
            onDeviceSelected: { device in
                localSend.clearRejectedStatus(for: device.id)
                onDeviceSelected(device)
            },
            onDismiss: onDismiss
        )
        .onAppear {
            localSend.startDiscovery()
            localSend.refreshDeviceScan()
        }
    }
}

/// What the picker draws, from the values `LocalSendDevicePickerView` hands it. Nothing here holds the LocalSend service
/// or reads Defaults: a press calls back. So a DEBUG snapshot board draws this from made-up devices and never builds the
/// service, whose discovery opens multicast listeners.
struct LocalSendDevicePickerContent: View {
    let devices: [LocalSendDeviceInfo]
    let rejectedDeviceIDs: Set<String>
    let isRefreshing: Bool
    /// Shelf › Device Picker Style, the backdrop the user picked.
    let glassMode: LockScreenGlassCustomizationMode
    let liquidGlassVariant: LiquidGlassVariant
    let onRefresh: () -> Void
    let onDeviceSelected: (LocalSendDeviceInfo) -> Void
    let onDismiss: () -> Void

    @State private var hoveredDeviceID: String?

    /// The picker opens with nothing under the pointer; a board may put a device there.
    init(devices: [LocalSendDeviceInfo], rejectedDeviceIDs: Set<String>, isRefreshing: Bool,
         glassMode: LockScreenGlassCustomizationMode, liquidGlassVariant: LiquidGlassVariant,
         onRefresh: @escaping () -> Void, onDeviceSelected: @escaping (LocalSendDeviceInfo) -> Void,
         onDismiss: @escaping () -> Void, hoveredDeviceID: String? = nil) {
        self.devices = devices
        self.rejectedDeviceIDs = rejectedDeviceIDs
        self.isRefreshing = isRefreshing
        self.glassMode = glassMode
        self.liquidGlassVariant = liquidGlassVariant
        self.onRefresh = onRefresh
        self.onDeviceSelected = onDeviceSelected
        self.onDismiss = onDismiss
        _hoveredDeviceID = State(initialValue: hoveredDeviceID)
    }

    private let cornerRadius: CGFloat = 24
    
    private var usesCustomLiquidGlass: Bool {
        glassMode == .customLiquid
    }
    
    private var usesStandardLiquidGlass: Bool {
        guard glassMode == .standard else { return false }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    var body: some View {
        ZStack {
            // Explicitly clear background for proper transparency
            Color.clear
            
            // Background - clips to rounded rect
            panelBackground
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            
            // Content
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image("LocalSend")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    
                    Text("Select Device")
                        .font(SettingsTheme.sheetTitle)
                        .foregroundStyle(SettingsTheme.ink)
                    
                    Spacer()
                    
                    // Refresh button
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 0.85).repeatForever(autoreverses: false)
                                    : .easeOut(duration: 0.2),
                                value: isRefreshing
                            )
                            // The circle it replaced was 32 across; inside the quiet inset this is 38 by 28.
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(SettingsButtonStyle(.quiet))
                    .disabled(isRefreshing)
                    .help("Refresh devices")
                    // A name for VoiceOver, which read the symbol's. No `.hoverTooltip`: the style tracks hover itself,
                    // and a second hover source silences a tooltip (docs/TOOLTIPS.md, rule 3).
                    .accessibilityLabel(String(localized: "Refresh devices"))
                    
                    // Close button
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(SettingsButtonStyle(.quiet))
                    .accessibilityLabel(String(localized: "Close"))
                }
                .padding(.horizontal, SettingsTheme.sheetInset)
                .padding(.top, SettingsTheme.sheetInset)
                
                // Devices grid
                if devices.isEmpty {
                    emptyStateView
                } else {
                    devicesGridView
                }
            }
            // Brain's root, which a window of its own applies itself, as a sheet does; and dark whatever the Mac's
            // appearance, as the picker always was: it sits on the backdrop Shelf › Device Picker Style picks, glass made
            // for light text, which itself renders as it always did.
            .settingsDesignSystem()
            .environment(\.colorScheme, .dark)
        }
        .frame(width: 480, height: 400)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 15)
        .compositingGroup()
    }
    
    @ViewBuilder
    private var panelBackground: some View {
        if usesCustomLiquidGlass {
            LiquidGlassBackground(variant: liquidGlassVariant, cornerRadius: cornerRadius) {
                Color.black.opacity(0.3)
            }
        } else if usesStandardLiquidGlass {
            if #available(macOS 26.0, *) {
                LocalSendGlassBackdrop(cornerRadius: cornerRadius)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(0.4))
                )
        }
    }
    
    private var emptyStateView: some View {
        // Brain's empty state, as Clipboard's page draws its own: the glyph at the page title's size, the status, one
        // line, and one action in the standard button.
        VStack(spacing: SettingsMetrics.cardPadding) {
            Spacer()

            if isRefreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: SettingsTheme.ink))
                    .scaleEffect(1.2)

                Text("Scanning for devices...")
                    .font(SettingsTheme.bodyStrong)
                    .foregroundStyle(SettingsTheme.inkSecondary)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.inkSecondary)

                Text("No devices found")
                    .font(SettingsTheme.cardTitle)
                    .foregroundStyle(SettingsTheme.ink)

                Text("Make sure LocalSend is running on other devices")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .multilineTextAlignment(.center)

                Button("Scan Again") {
                    onRefresh()
                }
                .buttonStyle(SettingsButtonStyle())
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var devicesGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(devices) { device in
                    DeviceGridItem(
                        device: device,
                        isHovered: hoveredDeviceID == device.id,
                        isRejected: rejectedDeviceIDs.contains(device.id),
                        onSelect: {
                            onDeviceSelected(device)
                        }
                    )
                    .onHover { hovering in
                        hoveredDeviceID = hovering ? device.id : nil
                    }
                }
            }
            .padding(.horizontal, SettingsTheme.sheetInset)
            .padding(.bottom, SettingsTheme.sheetInset)
        }
    }
}

// MARK: - Device Grid Item

private struct DeviceGridItem: View {
    let device: LocalSendDeviceInfo
    let isHovered: Bool
    let isRejected: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                // Device icon
                ZStack {
                    Circle()
                        .fill(isHovered ? SettingsTheme.raised : SettingsTheme.selection)
                        .frame(width: 56, height: 56)

                    Image(systemName: deviceIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isRejected ? SettingsTheme.destructive
                                         : (isHovered ? SettingsTheme.accentStrong : SettingsTheme.ink))
                }
                
                // Device name
                VStack(spacing: SettingsMetrics.labelStack) {
                    Text(device.alias)
                        .font(SettingsTheme.bodyStrong)
                        .foregroundStyle(isRejected ? SettingsTheme.destructive : SettingsTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if isRejected {
                        Text("Rejected")
                            .font(SettingsTheme.description)
                            .foregroundStyle(SettingsTheme.destructive)
                    } else if let model = device.model, !model.isEmpty {
                        Text(model)
                            .font(SettingsTheme.description)
                            .foregroundStyle(SettingsTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
                    .fill(isHovered ? SettingsTheme.selection : SettingsTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
                    .strokeBorder(isRejected ? SettingsTheme.destructive
                                  : (isHovered ? SettingsTheme.accentStrong : SettingsTheme.line),
                                  lineWidth: SettingsTheme.hairline)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1.0)
        // The theme's bounded ease, none under Reduce Motion, never a spring (docs/SETTINGS.md, "The design system").
        .animation(reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation), value: isHovered)
    }
    
    private var deviceIcon: String {
        let aliasLower = device.alias.lowercased()
        let modelLower = (device.model ?? "").lowercased()
        let combined = aliasLower + " " + modelLower
        
        // iPhone / iOS devices
        if combined.contains("iphone") {
            return "iphone"
        }
        if combined.contains("ipad") {
            return "ipad"
        }
        if combined.contains("ipod") {
            return "ipodtouch"
        }
        
        // Android phones by brand
        if combined.contains("pixel") || combined.contains("nexus") {
            return "smartphone"
        }
        if combined.contains("samsung") || combined.contains("galaxy") {
            return "smartphone"
        }
        if combined.contains("oneplus") || combined.contains("one plus") {
            return "smartphone"
        }
        if combined.contains("xiaomi") || combined.contains("redmi") || combined.contains("poco") || combined.contains("mi ") {
            return "smartphone"
        }
        if combined.contains("huawei") || combined.contains("honor") {
            return "smartphone"
        }
        if combined.contains("oppo") || combined.contains("realme") || combined.contains("vivo") {
            return "smartphone"
        }
        if combined.contains("motorola") || combined.contains("moto ") {
            return "smartphone"
        }
        if combined.contains("nokia") {
            return "smartphone"
        }
        if combined.contains("sony") || combined.contains("xperia") {
            return "smartphone"
        }
        if combined.contains("lg") {
            return "smartphone"
        }
        if combined.contains("asus") && (combined.contains("phone") || combined.contains("rog")) {
            return "smartphone"
        }
        if combined.contains("nothing") && combined.contains("phone") {
            return "smartphone"
        }
        
        // Android tablets
        if combined.contains("tab") || combined.contains("tablet") {
            return "tablet.portrait"
        }
        
        // Mac devices
        if combined.contains("macbook") {
            return "laptopcomputer"
        }
        if combined.contains("imac") {
            return "desktopcomputer"
        }
        if combined.contains("mac mini") || combined.contains("mini") && combined.contains("mac") {
            return "macmini"
        }
        if combined.contains("mac pro") {
            return "macpro.gen3"
        }
        if combined.contains("mac studio") {
            return "macstudio"
        }
        if combined.contains("mac") || combined.contains("macos") {
            return "desktopcomputer"
        }
        
        // Windows/Linux laptops and desktops
        if combined.contains("laptop") || combined.contains("notebook") {
            return "laptopcomputer"
        }
        if combined.contains("thinkpad") || combined.contains("lenovo") {
            return "laptopcomputer"
        }
        if combined.contains("dell") || combined.contains("xps") || combined.contains("inspiron") || combined.contains("latitude") {
            return "laptopcomputer"
        }
        if combined.contains("hp") || combined.contains("pavilion") || combined.contains("envy") || combined.contains("spectre") || combined.contains("elitebook") {
            return "laptopcomputer"
        }
        if combined.contains("asus") || combined.contains("zenbook") || combined.contains("vivobook") {
            return "laptopcomputer"
        }
        if combined.contains("acer") || combined.contains("aspire") || combined.contains("swift") {
            return "laptopcomputer"
        }
        if combined.contains("msi") {
            return "laptopcomputer"
        }
        if combined.contains("surface") {
            return "laptopcomputer"
        }
        if combined.contains("razer") {
            return "laptopcomputer"
        }
        if combined.contains("chromebook") {
            return "laptopcomputer"
        }
        
        // Desktop keywords
        if combined.contains("desktop") || combined.contains("pc") || combined.contains("workstation") {
            return "desktopcomputer"
        }
        if combined.contains("windows") || combined.contains("linux") || combined.contains("ubuntu") || combined.contains("fedora") {
            return "desktopcomputer"
        }
        
        // Android generic
        if combined.contains("android") {
            return "smartphone"
        }
        
        // Phone/Mobile generic
        if combined.contains("phone") || combined.contains("mobile") {
            return "smartphone"
        }
        
        // TV devices
        if combined.contains("tv") || combined.contains("shield") || combined.contains("fire") || combined.contains("roku") || combined.contains("chromecast") {
            return "appletv"
        }
        
        // Default: try to guess based on common patterns
        // If it looks like a computer name with a person's name, assume laptop
        if combined.contains("'s ") || combined.contains("-pc") || combined.contains("-laptop") {
            return "laptopcomputer"
        }
        
        // Default fallback
        return "smartphone"
    }
}

// MARK: - Glass Backdrop for LocalSend Picker

@available(macOS 26.0, *)
private struct LocalSendGlassBackdrop: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let dynamicFontSize = max(min(proxy.size.width, proxy.size.height) / 8, 42)

            Text("LocalSend Device Picker")
                .font(.system(size: dynamicFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.clear)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .glassEffect(
                    .clear.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
