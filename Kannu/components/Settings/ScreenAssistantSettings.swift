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

struct ScreenAssistantSettings: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @Default(.enableScreenAssistant) var enableScreenAssistant
    @Default(.screenAssistantDisplayMode) var screenAssistantDisplayMode
    @State private var geminiApiKey = ""
    @State private var apiKeyText = ""
    @State private var showingApiKey = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.screenAssistant.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenAssistant) {
                    Text("Enable Screen Assistant")
                }
                .settingsHighlight(id: highlightID("Enable Screen Assistant"))
            } header: {
                SettingsSectionHeader("AI Assistant")
            } footer: {
                SettingsFooter("AI-powered assistant that can analyze files, images, and provide conversational help. With global keyboard shortcuts on, \(shortcutDescription(for: .screenAssistantPanel)) opens the assistant.")
            }

            if enableScreenAssistant {
                Section {
                    LabeledContent {
                        HStack(spacing: 8) {
                            if geminiApiKey.isEmpty {
                                Text("Not Set")
                                    .foregroundColor(.red)
                            } else {
                                Text("••••••••")
                                    .foregroundColor(.green)
                            }

                            Button(showingApiKey ? "Hide" : (geminiApiKey.isEmpty ? "Set" : "Change")) {
                                if showingApiKey {
                                    showingApiKey = false
                                    if !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        SecureSecretsStore.set(apiKeyText, for: .geminiAPIKey)
                                        geminiApiKey = SecureSecretsStore.value(for: .geminiAPIKey)
                                    }
                                    apiKeyText = ""
                                } else {
                                    showingApiKey = true
                                    apiKeyText = geminiApiKey
                                }
                            }
                        }
                    } label: {
                        Text("Gemini API Key")
                    }

                    if showingApiKey {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Enter your Gemini API Key", text: $apiKeyText)
                                .textFieldStyle(.roundedBorder)

                            Text("Get your free API key from Google AI Studio")
                                .settingsDescriptionStyle()

                            HStack {
                                Spacer()

                                Button("Open Google AI Studio") {
                                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                                }

                                Button("Save") {
                                    SecureSecretsStore.set(apiKeyText, for: .geminiAPIKey)
                                    geminiApiKey = SecureSecretsStore.value(for: .geminiAPIKey)
                                    showingApiKey = false
                                    apiKeyText = ""
                                }
                                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    Picker("Display Mode", selection: $screenAssistantDisplayMode) {
                        ForEach(ScreenAssistantDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .settingsHighlight(id: highlightID("Display Mode"))

                    LabeledContent("Attached Files") {
                        Text("\(screenAssistantManager.attachedFiles.count)")
                    }

                    LabeledContent("Recording Status") {
                        Text(screenAssistantManager.isRecording ? "Recording" : "Ready")
                            .foregroundColor(screenAssistantManager.isRecording ? .red : .secondary)
                    }
                } header: {
                    SettingsSectionHeader("Configuration")
                } footer: {
                    switch screenAssistantDisplayMode {
                    case .popover:
                        SettingsFooter("Popover mode shows the assistant as a dropdown attached to the AI button. Panel mode shows the assistant in a floating window near the notch.")
                    case .panel:
                        SettingsFooter("Panel mode shows the assistant in a floating window near the notch. Popover mode shows the assistant as a dropdown attached to the AI button.")
                    }
                }

                Section {
                    SettingsActionRow {
                        Button("Clear All Files", role: .destructive) {
                            screenAssistantManager.clearAllFiles()
                        }
                        .foregroundColor(.red)
                        .disabled(screenAssistantManager.attachedFiles.isEmpty)
                    }
                } header: {
                    SettingsSectionHeader("Actions")
                } footer: {
                    SettingsFooter("Clear all files removes all attached files and audio recordings. This action is permanent.")
                }

                if !screenAssistantManager.attachedFiles.isEmpty {
                    Section {
                        ForEach(screenAssistantManager.attachedFiles) { file in
                            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                                HStack(spacing: SettingsMetrics.rowContent) {
                                    Image(systemName: file.type.iconName)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                        .accessibilityHidden(true)
                                    Text(file.type.displayName)
                                        .settingsDescriptionStyle()
                                    Spacer()
                                    Text(verbatim: timeAgoString(from: file.timestamp))
                                        .settingsDescriptionStyle()
                                }
                                Text(verbatim: file.name)
                                    .font(.body)
                                    .monospaced()
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        SettingsSectionHeader("Attached Files")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screen Assistant")
        .onAppear {
            geminiApiKey = SecureSecretsStore.value(for: .geminiAPIKey)
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
