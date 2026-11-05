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

struct Shelf: View {
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection
    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    // Without the access Shelf needs, Enable shelf can still be turned off, just not on.
    @Default(.dynamicShelf) private var dynamicShelf
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.shelf.highlightID(for: title)
    }

    var body: some View {
        Form {
            if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                Section {
                    if !canEnableShelf {
                        SettingsPermissionCallout(
                            title: "Additional folder access required",
                            message: "Enable Full Disk Access, or grant access to both Documents and Downloads folders to use Shelf.",
                            icon: "folder.badge.questionmark",
                            iconColor: .orange,
                            requestButtonTitle: "Request Folder Access",
                            openSettingsButtonTitle: "Open Privacy & Security",
                            requestAction: { shelfFolderAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { shelfFolderAccessPermission.openSystemSettings() }
                        )
                    }

                    if !fullDiskAccessPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "Full Disk Access for global mode",
                            message: "Without Full Disk Access, Shelf can only read files from Documents and Downloads. Grant Full Disk Access to make Shelf work globally.",
                            icon: "externaldrive.fill",
                            iconColor: .purple,
                            requestButtonTitle: "Request Full Disk Access",
                            openSettingsButtonTitle: "Open Privacy & Security",
                            requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    SettingsSectionHeader("Permissions")
                }
            }

            Section {
                Defaults.Toggle(key: .dynamicShelf) {
                    Text("Enable shelf")
                }
                .disabled(!canEnableShelf && !dynamicShelf)
                .settingsHighlight(id: highlightID("Enable shelf"))

                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf tab by default if items added")
                }
                .settingsHighlight(id: highlightID("Open shelf tab by default if items added"))

                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .settingsHighlight(id: highlightID("Expanded drag detection area"))

                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                .settingsHighlight(id: highlightID("Copy items on drag"))

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                .settingsHighlight(id: highlightID("Remove from shelf after dragging"))
            } header: {
                HStack {
                    SettingsSectionHeader("General")
                }
            }

            Section {
                SettingsRow("Quick Share Service", description: selectedProvider == nil
                            ? nil : Text("Files dropped on the shelf will be shared via this service")) {
                    // The saved id shows before discovery ends: the select draws the selection's own title.
                    SettingsSelect("Quick Share Service", selection: $quickShareProvider,
                                   options: quickShareService.availableProviders.map(\.id), optionTitle: { $0 }) { id in
                        if let provider = quickShareService.availableProviders.first(where: { $0.id == id }) {
                            QuickShareProviderIconImage(provider: provider, size: 16)
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Quick Share Service"))
            } header: {
                SettingsSectionHeader("Quick Share")
            } footer: {
                SettingsFooter("Choose which service to use when sharing files from the shelf. Drag files onto the shelf or click the shelf button to pick files.")
            }
            
            if quickShareProvider == "LocalSend" {
                LocalSendSettingsSection(highlightID: highlightID)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

private struct LocalSendSettingsSection: View {
    let highlightID: (String) -> String
    
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    /// The variant's seven siblings are sliders, so this one is too, through the same clamp.
    private var liquidGlassVariantBinding: Binding<Double> {
        Binding(
            get: { Double(liquidGlassVariant.rawValue) },
            set: { newValue in liquidGlassVariant = LiquidGlassVariant.clamped(Int(newValue.rounded())) }
        )
    }

    var body: some View {
        Section {
            SettingsRow("Device Picker Style") {
                SettingsSelect("Device Picker Style", selection: $glassMode,
                               options: LockScreenGlassCustomizationMode.allCases, optionTitle: \.localizedName)
            }
            .settingsHighlight(id: highlightID("Device Picker Style"))

            if glassMode == .customLiquid {
                variantSliderRow(value: liquidGlassVariantBinding, current: liquidGlassVariant.rawValue,
                                 range: liquidVariantRange, title: String(localized: "Liquid Glass Variant"))
            }
        } header: {
            SettingsSectionHeader("LocalSend Device Picker")
        } footer: {
            SettingsFooter("Customize the appearance of the LocalSend device selection popup that appears when you drop files.")
        }
    }
}
