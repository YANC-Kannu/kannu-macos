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

/// Connect… on the Jira Cloud row. The token lives only in this sheet's state until Jira has
/// accepted it; the manager then stores it in the Keychain and the field is cleared. A sheet pads
/// its own content; a Form row never does.
struct JiraConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""
    /// Saved only when Connect succeeds; Cancel keeps the colour the key had.
    @State private var color = Defaults[.jiraTaskColor]
    @State private var problem: String?
    @State private var connecting: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
            Text("Connect Jira Cloud")
                .font(.headline)
            Text("Checked with your site, then kept in your Keychain.")
                .settingsDescriptionStyle()
            TextField("Site", text: $site, prompt: Text(verbatim: "acme.atlassian.net"))
            TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
            SecureField("API token", text: $token)
            Link("Create API token…", destination: JiraAPI.createTokenURL)
            LabeledContent {
                TaskColorPickerButton(
                    selection: $color,
                    accessibilityLabel: String(localized: "Jira colour: \(color.localizedName)")
                )
            } label: {
                SettingsRowLabel("Jira colour", description: "For Jira tasks that have no tags.")
            }
            if let problem {
                Text(verbatim: problem)
                    .settingsDescriptionStyle(tint: .red)
            }
            HStack(spacing: SettingsMetrics.rowContent) {
                if connecting != nil {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting != nil || !canConnect)
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(width: 420)
        .onDisappear {
            connecting?.cancel()
            token = ""
        }
    }

    private var canConnect: Bool {
        !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.isEmpty
    }

    private func connect() {
        problem = nil
        connecting = Task { @MainActor in
            let failure = await TasksManager.shared.connectJira(siteInput: site, email: email, token: token)
            guard !Task.isCancelled else { return }
            connecting = nil
            if let failure {
                problem = failure
            } else {
                token = ""
                Defaults[.jiraTaskColor] = color
                dismiss()
            }
        }
    }

    private func close() {
        connecting?.cancel()
        connecting = nil
        token = ""
        dismiss()
    }
}

/// Connect… on the GitLab row. The server field starts at gitlab.com; a self-managed server is any
/// HTTPS address, with a path if it has one. The token lives only in this sheet's state until GitLab
/// has accepted it; the manager then stores it in the Keychain and the field is cleared. A sheet
/// pads its own content; a Form row never does.
struct GitLabConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var server = GitLabHost.defaultServer
    @State private var token = ""
    /// Saved only when Connect succeeds; Cancel keeps the colour the key had.
    @State private var color = Defaults[.gitlabTaskColor]
    @State private var problem: String?
    @State private var connecting: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
            Text("Connect GitLab")
                .font(.headline)
            Text("Checked with your server, then kept in your Keychain.")
                .settingsDescriptionStyle()
            TextField("Server", text: $server, prompt: Text(verbatim: GitLabHost.defaultServer))
                .onChange(of: server) { _, _ in problem = nil }
            SecureField("Personal access token", text: $token)
            Text("`api` to log time; `read_api` lists only")
                .settingsDescriptionStyle()
            if let createTokenURL {
                Link("Create token…", destination: createTokenURL)
            }
            LabeledContent {
                TaskColorPickerButton(
                    selection: $color,
                    accessibilityLabel: String(localized: "GitLab colour: \(color.localizedName)")
                )
            } label: {
                SettingsRowLabel("GitLab colour", description: "For GitLab tasks that have no tags.")
            }
            if let problem {
                Text(verbatim: problem)
                    .settingsDescriptionStyle(tint: .red)
            }
            HStack(spacing: SettingsMetrics.rowContent) {
                if connecting != nil {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting != nil || !canConnect)
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(width: 420)
        .onDisappear {
            connecting?.cancel()
            token = ""
        }
    }

    /// The token page on the server typed so far, once it is an address Kannu would connect to.
    private var createTokenURL: URL? {
        guard case .success(let base) = GitLabHost.normalize(server) else { return nil }
        return GitLabHost.createTokenURL(base: base)
    }

    private var canConnect: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !token.isEmpty
    }

    private func connect() {
        problem = nil
        connecting = Task { @MainActor in
            let failure = await TasksManager.shared.connectGitLab(serverInput: server, token: token)
            guard !Task.isCancelled else { return }
            connecting = nil
            if let failure {
                problem = failure
            } else {
                token = ""
                Defaults[.gitlabTaskColor] = color
                dismiss()
            }
        }
    }

    private func close() {
        connecting?.cancel()
        connecting = nil
        token = ""
        dismiss()
    }
}

/// Connect… for GitHub, Linear, Todoist and Apple Reminders. A token — GitHub's with its server — lives
/// only in this sheet's state until the source has accepted it; the manager then stores it in the
/// Keychain and the field is cleared. Apple Reminders has no token: Connect asks macOS, which shows
/// its own question once. A sheet pads its own content; a Form row never does.
struct SourceConnectSheet: View {
    let source: TaskSource
    @Environment(\.dismiss) private var dismiss
    @State private var server = "https://github.com"
    @State private var token = ""
    /// Saved only when Connect succeeds; Cancel keeps the colour the key had.
    @State private var color: TaskColor
    @State private var problem: String?
    @State private var connecting: Task<Void, Never>?

    init(source: TaskSource) {
        self.source = source
        _color = State(initialValue: Defaults[source.colorKey])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
            Text(verbatim: String(localized: "Connect \(source.title)"))
                .font(.headline)
            Text(verbatim: explanation)
                .settingsDescriptionStyle()
            if source == .github {
                TextField("Server", text: $server, prompt: Text(verbatim: "https://github.com"))
                    .onChange(of: server) { _, _ in problem = nil }
            }
            if source.usesToken {
                SecureField(tokenLabel, text: $token)
                if let createTokenURL = TaskSourceStatus.createTokenURL(for: source, server: server) {
                    Link("Create token…", destination: createTokenURL)
                }
            }
            LabeledContent {
                TaskColorPickerButton(
                    selection: $color,
                    accessibilityLabel: String(localized: "\(source.name) colour: \(color.localizedName)")
                )
            } label: {
                SettingsRowLabel(verbatim: String(localized: "\(source.name) colour"),
                                 description: String(localized: "For \(source.name) tasks that have no tags."))
            }
            if let problem {
                Text(verbatim: problem)
                    .settingsDescriptionStyle(tint: .red)
            }
            HStack(spacing: SettingsMetrics.rowContent) {
                if connecting != nil {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(source.usesToken ? String(localized: "Connect") : String(localized: "Allow Access")) { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting != nil || (source.usesToken && token.isEmpty))
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(width: 420)
        .onDisappear {
            connecting?.cancel()
            token = ""
        }
    }

    private var explanation: String {
        switch source {
        case .github:
            return String(localized: "Issues assigned to you. A fine-grained token with read access to issues is enough. Checked with your server, then kept in your Keychain.")
        case .linear:
            return String(localized: "Issues assigned to you. Create a personal API key in Linear, under Security & access. Checked with Linear, then kept in your Keychain.")
        case .todoist:
            return String(localized: "Your open tasks. Your API token is in Todoist, under Integrations › Developer. Checked with Todoist, then kept in your Keychain.")
        case .appleReminders:
            return String(localized: "Your incomplete reminders, from every list. macOS asks you once; Kannu reads them and never changes them.")
        case .local, .jira, .gitlab:
            return ""
        }
    }

    private var tokenLabel: String {
        switch source {
        case .linear: return String(localized: "API key")
        case .todoist: return String(localized: "API token")
        case .local, .jira, .gitlab, .github, .appleReminders: return String(localized: "Personal access token")
        }
    }

    private func connect() {
        problem = nil
        connecting = Task { @MainActor in
            let failure = await TasksManager.shared.connect(source, server: server, token: token)
            guard !Task.isCancelled else { return }
            connecting = nil
            if let failure {
                problem = failure
            } else {
                token = ""
                Defaults[source.colorKey] = color
                dismiss()
            }
        }
    }

    private func close() {
        connecting?.cancel()
        connecting = nil
        token = ""
        dismiss()
    }
}
