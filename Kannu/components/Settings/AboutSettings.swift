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

struct About: View {
    @Default(.hangWatchdogEnabled) var hangWatchdogEnabled
    @Default(.termsAcceptedVersion) var termsAcceptedVersion
    @Default(.termsAcceptedAt) var termsAcceptedAt
    @State private var legalDocumentMissing = false
    @State private var copiedReport = false
    @State private var reportCopyFailed = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.about.highlightID(for: title)
    }

    /// "Accepted 28 Sep 2026 at 10:04 (version 1)." — what the gate recorded.
    private var termsAcceptanceText: String {
        guard let version = termsAcceptedVersion, let date = termsAcceptedAt else {
            return String(localized: "Kannu is provided as is, without warranty, under these terms.")
        }
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "You accepted version \(version) on \(when). Kannu is provided as is, without warranty, under these terms.")
    }

    /// "1.2.0 (2)" — the build used to hide behind a tap; it is what a bug report needs.
    private var versionText: String {
        let version = Bundle.main.releaseVersionNumber ?? String(localized: "unknown")
        guard let build = Bundle.main.buildVersionNumber, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Release name") {
                    Text(ReleaseInfo.codename)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Version") {
                    Text(versionText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if SparkleUpdaterController.shared.isEnabled {
                    SettingsActionRow {
                        Button("Check for Updates…") {
                            SparkleUpdaterController.shared.checkForUpdates(nil)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader("Version info")
            }

            Section {
                SettingsActionRow("Terms of Use", description: termsAcceptanceText) {
                    Button("View") { LegalDocuments.open(.terms) { legalDocumentMissing = !$0 } }
                }
                .settingsHighlight(id: highlightID("Terms of Use"))
                SettingsActionRow(
                    "License",
                    description: "Kannu is free software under the GNU General Public License v3, provided as is, without warranty of any kind."
                ) {
                    Button("View License") { LegalDocuments.open(.license) { legalDocumentMissing = !$0 } }
                    Button("Acknowledgements") { LegalDocuments.open(.notice) { legalDocumentMissing = !$0 } }
                }
                .settingsHighlight(id: highlightID("License"))
                if legalDocumentMissing {
                    SettingsErrorText("That document could not be opened. If it keeps failing, reinstall Kannu from kannu.app.")
                }
            } header: {
                SettingsSectionHeader("Legal")
            }

            Section {
                SettingsRow(
                    "Watch for freezes",
                    description: "If Kannu's interface stops responding for five seconds, it writes down what it was doing to ~/Library/Logs/Kannu and offers you the note next time it starts. Nothing is shown while it is stuck, and nothing is sent anywhere. On by default for the Developer profile."
                ) {
                    Toggle("Watch for freezes", isOn: $hangWatchdogEnabled)
                }
                .settingsHighlight(id: highlightID("Watch for freezes"))
                SettingsActionRow {
                    Button("Report a Problem…") {
                        CrashReporter.shared.reportAProblem()
                    }
                }
                .settingsHighlight(id: highlightID("Report a Problem"))

                SettingsActionRow {
                    Button(copiedReport ? "Copied" : "Copy Latest Report") {
                        copiedReport = false
                        reportCopyFailed = false
                        let copied = CrashReporter.shared.copyNewestReportToPasteboard()
                        copiedReport = copied
                        reportCopyFailed = !copied
                        guard copied else { return }
                        // Back to the normal label, the way every other copy button in Settings
                        // behaves; otherwise it reads "Copied" for the life of the window.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            copiedReport = false
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Copy Latest Report"))

                if reportCopyFailed {
                    SettingsErrorText("macOS has written no report about Kannu on this Mac.")
                }
            } header: {
                SettingsSectionHeader("Diagnostics")
            } footer: {
                SettingsFooter("A freeze leaves no crash report, so without this there is nothing to look at afterwards. The check costs one wake every two seconds. Reporting opens a GitHub issue with the details filled in — no name, nothing identifying your Mac — for you to read and submit; Kannu sends nothing itself.")
            }
        }
        .navigationTitle("About")
    }
}
