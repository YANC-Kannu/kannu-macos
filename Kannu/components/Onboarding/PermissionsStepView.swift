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

import Defaults
import SwiftUI

/// Onboarding step: the macOS permissions this setup needs, each explained, each asked only when
/// the user presses Allow, one dialog at a time. A tester used to meet four system dialogs at once,
/// over the welcome music; now nothing asks before this step, and the music waits for Finish.
struct PermissionsStepView: View {
    let rows: [LaunchPermission]
    let musicSource: MediaControllerType
    /// Whether the login item should be registered; the caller registers it.
    let onLaunchAtLoginChoice: (Bool) -> Void
    let onContinue: () -> Void

    @ObservedObject private var permissions = LaunchPermissionManager.shared
    @State private var launchAtLogin = true
    @State private var focusMode: FocusMonitoringMode = Defaults[.focusMonitoringMode]

    var body: some View {
        // The scroll view spans the window, so its bar sits at the window's edge; its cards keep the page's inset.
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text("A Few Permissions")
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text("macOS asks for each one only when you press Allow. Skip any: what it powers stays off until you allow it in Brain.")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, SettingsTheme.pageInset)

            ScrollView {
                VStack(spacing: SettingsTheme.listRowGap) {
                    ForEach(rows) { permission in
                        LaunchPermissionRow(permission: permission, musicSource: musicSource)
                    }
                    focusRow
                    Toggle(isOn: $launchAtLogin) {
                        PermissionRowLabel(
                            symbol: "power",
                            title: String(localized: "Open Kannu at login"),
                            reason: String(localized: "So the notch is there whenever your agents are.")
                        )
                    }
                    .permissionCard()
                }
                .padding(.horizontal, SettingsTheme.pageInset)
            }

            Text("Change these any time in Brain › Settings › General › Permissions, or System Settings › Privacy & Security.")
                .settingsDescriptionStyle()
                .padding(.horizontal, SettingsTheme.pageInset)

            Button("Continue") {
                // A row left unanswered is a Not now: its feature waits, and nothing asks later.
                for permission in rows where LaunchPermissionManager.answer(for: permission) == .notAsked {
                    permissions.postpone(permission)
                }
                Defaults[.focusMonitoringMode] = focusMode
                onLaunchAtLoginChoice(launchAtLogin)
                onContinue()
            }
            .buttonStyle(SettingsButtonStyle(.primary))
            .disabled(permissions.requestInFlight != nil)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, SettingsTheme.pageInset)
        }
        .padding(.vertical, SettingsTheme.sectionGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { permissions.refresh() }
    }

    /// The choice the onboarding window used to pop up over its Welcome screen.
    private var focusRow: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
            PermissionRowLabel(
                symbol: "moon",
                title: String(localized: "Focus detection"),
                reason: String(localized: "Developer Tools access reads Focus more reliably; without it, Kannu reads it as it can.")
            )
            SettingsSelect("Focus detection", selection: $focusMode, choices: [
                .withoutDevTools: String(localized: "Without DevTools"),
                .useDevTools: String(localized: "Use DevTools"),
            ], style: .segmented)
            if focusMode == .useDevTools {
                // A lone quiet button under the card's text, on its column, with its chevron, as Agents' "Open ›"
                // (docs/SETTINGS.md, "Which component for what"): bare at rest, the chevron says it goes somewhere.
                Button {
                    DeveloperToolsSettings.open()
                } label: {
                    HStack(spacing: SettingsMetrics.iconGap) {
                        Text("Open Developer Tools settings")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(SettingsButtonStyle(.quiet, flush: true))
            }
        }
        .permissionCard()
    }
}

/// One permission: why Kannu wants it, where it stands, and Allow / Not now. Shared by the
/// onboarding step, as a card of its own, and Brain › Settings › General › Permissions, as a row.
/// Allow is the answer the row asks for, so it is the primary and Not now the quiet one (the design review's finding 4):
/// our own styles, drawn alike in a window that is not key, where a native prominent button turns grey.
struct LaunchPermissionRow: View {
    let permission: LaunchPermission
    let musicSource: MediaControllerType
    /// Brain's Permissions section: a row of its card in Brain's type, the buttons trailing, never a
    /// card inside the card (docs/SETTINGS.md). Onboarding keeps its card.
    var asRow = false

    @ObservedObject private var permissions = LaunchPermissionManager.shared

    var body: some View {
        if asRow {
            HStack(spacing: 8) {
                PermissionRowLabel(symbol: symbol, title: title, reason: reason, asRow: true)
                controls
            }
        } else {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
                PermissionRowLabel(symbol: symbol, title: title, reason: reason)
                HStack(spacing: SettingsMetrics.rowContent) {
                    Spacer(minLength: 0)
                    controls
                }
            }
            .permissionCard()
        }
    }

    private var status: LaunchPermissionStatus { permissions.statuses[permission] ?? .notAsked }

    @ViewBuilder
    private var controls: some View {
        switch status {
        case .notAsked, .deferred:
            if status == .notAsked {
                Button("Not now") { permissions.postpone(permission) }
                    .buttonStyle(SettingsButtonStyle(.quiet))
            } else {
                Text("Not now").settingsDescriptionStyle()
            }
            Button("Allow") { permissions.request(permission, musicSource: musicSource) }
                .buttonStyle(SettingsButtonStyle(.primary))
                .disabled(permissions.requestInFlight != nil)
        case .waiting:
            ProgressView().controlSize(.small)
            Text("Waiting for macOS…").settingsDescriptionStyle()
        case .allowed:
            SettingsStatusText(String(localized: "Allowed"), isReady: true)
        case .notAllowed:
            Text("Not allowed").settingsDescriptionStyle()
            Button("Open System Settings") { permissions.openSystemSettings(for: permission) }
                .buttonStyle(SettingsButtonStyle())
        case .askedWhenAppOpens:
            Text("macOS asks when \(permission == .notesAutomation ? String(localized: "Notes") : musicSource.localizedName) opens")
                .settingsDescriptionStyle()
        }
    }

    private var symbol: String {
        switch permission {
        case .accessibility: return "accessibility"
        case .bluetooth: return "headphones"
        case .downloads: return "arrow.down.circle"
        case .location: return "location"
        case .musicAutomation: return "music.note"
        case .notesAutomation: return "note.text"
        case .warp: return "terminal"
        }
    }

    private var title: String {
        switch permission {
        case .accessibility: return String(localized: "Accessibility")
        case .bluetooth: return String(localized: "Bluetooth")
        case .downloads: return String(localized: "Downloads folder")
        case .location: return String(localized: "Location")
        case .musicAutomation: return String(localized: "Control \(musicSource.localizedName)")
        case .notesAutomation: return String(localized: "Control Notes")
        case .warp: return String(localized: "Warp's agent sessions")
        }
    }

    private var reason: String {
        switch permission {
        case .accessibility:
            return String(localized: "Shows volume, brightness and the media keys in the notch.")
        case .bluetooth:
            return String(localized: "Shows your headphones and their battery when they connect.")
        case .downloads:
            return String(localized: "Shows download progress in the notch.")
        case .location:
            return String(localized: "Shows your local weather on the lock screen.")
        case .musicAutomation:
            return String(localized: "Lets the notch play, pause and skip in \(musicSource.localizedName).")
        case .notesAutomation:
            return String(localized: "Keeps the notch's notes in sync with Apple Notes.")
        case .warp:
            return String(localized: "Lets the agent light follow agents running in Warp.")
        }
    }
}

private struct PermissionRowLabel: View {
    let symbol: String
    let title: String
    let reason: String
    /// Brain's row type, as every other row of its section; onboarding keeps its own.
    var asRow = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The theme's one accent, not the Mac's: the strong one for the glyph, which must be seen.
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsTheme.accentStrong)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SettingsTheme.accent.opacity(0.15)))
                .accessibilityHidden(true)
            if asRow {
                SettingsRowLabel(verbatim: title, description: reason)
            } else {
                // Unselectable: on onboarding's switch card this is the switch's label.
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(title)
                        .font(SettingsTheme.bodyStrong)
                        .foregroundStyle(SettingsTheme.ink)
                    Text(reason)
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private extension View {
    /// Onboarding's card for one permission or choice: a section's card, on the window's panel.
    func permissionCard() -> some View {
        padding(SettingsMetrics.cardPadding)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
    }
}
