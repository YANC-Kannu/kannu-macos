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
import Defaults
import SwiftUI

/// A source's page in Brain › Tasks (‹ Tasks): its connection, then its projects, each a › to its
/// own page — or, with one project or none, its tasks right there. Local tasks has its colour, Add a
/// task, then its tasks.
///
/// Every source's connection is the same section (`SourceConnectionSection`): Disconnect…, what
/// needs fixing, Sync, the colour a task from it shows with no tags (`TaskColoring`), Refresh, and
/// that source's own options — Jira's issue filter, GitLab's merge requests, GitHub's pull requests,
/// Todoist's filter. Connection only: Sync decides what is fetched, never what is listed, and a
/// paused source's tasks stay listed. Each source has its own rows, status and Refresh, so one
/// failing never shows on another.
///
/// Like every row below the overview, nothing here carries a highlight id: their search entries
/// land on the source's row on the overview (docs/SETTINGS.md). Status comes from the Defaults
/// display copies and the manager's sync state, never from the Keychain.
struct TaskSourcePage: View {
    @ObservedObject private var manager = TasksManager.shared
    @Default(.tasksLocalColor) private var localColor
    let source: TaskSource
    let context: TasksPageContext

    var body: some View {
        if source == .local {
            Section {
                TaskColorRow(
                    "Local tasks colour",
                    description: "For your own tasks that have no tags.",
                    accessibilityLabel: String(localized: "Local tasks colour: \(localColor.localizedName)"),
                    selection: $localColor
                )
            } header: {
                SettingsSectionHeader("Local tasks")
            }
            Section {
                TaskAddRow(context: context)
                TaskRowList(filter: TaskFilter(source: .local), context: context)
            } header: {
                SettingsSectionHeader("Tasks")
            }
        } else {
            SourceConnectionSection(source: source, context: context)
            projectsOrTasks
        }
    }

    /// Several projects: one row each, "ds-vendors · 40 open ›", the group path telling two "app"
    /// projects apart. One project or none: the tasks themselves, a level saved.
    @ViewBuilder
    private var projectsOrTasks: some View {
        let tasks = manager.activeTasks.filter { $0.source == source }
        let projects = TaskFacets.projectCounts(in: tasks)
        if projects.count > 1 {
            Section {
                ForEach(projects, id: \.key) { project in
                    let page = TasksPage.project(source, project.key)
                    LabeledContent {
                        TasksOpenButton(
                            text: String(localized: "\(project.count) open"),
                            accessibilityLabel: String(localized: "Open \(TasksSettings.title(of: page))")
                        ) { context.open(page) }
                    } label: {
                        SettingsRowLabel(verbatim: TaskFacets.projectShortName(project.key),
                                         description: TaskFacets.projectGroup(project.key))
                    }
                    .id(page)
                }
            } header: {
                SettingsSectionHeader(source.keyStyle == .list ? String(localized: "Lists") : String(localized: "Projects"))
            }
        } else {
            Section {
                if tasks.isEmpty {
                    SettingsNoteRow("No tasks yet", description: "Open tasks appear here after a sync.")
                }
                TaskRowList(filter: TaskFilter(source: TaskSourceFilter(source)), context: context)
            } header: {
                SettingsSectionHeader("Tasks")
            }
        }
    }
}

/// A project's page (‹ its source): its tasks in the task order, each caption without the project
/// the page already names ("#4326").
struct TaskProjectPage: View {
    let source: TaskSource
    let project: String
    let context: TasksPageContext

    var body: some View {
        Section {
            TaskRowList(filter: TaskFilter(source: TaskSourceFilter(source), project: project),
                        onProjectPage: true, context: context)
        } header: {
            SettingsSectionHeader(TaskFacets.projectShortName(project))
        } footer: {
            if let group = TaskFacets.projectGroup(project) {
                SettingsFooter(group)
            }
        }
    }
}

/// A source's connection, the same for every source: who it is connected as and Disconnect…; what
/// needs fixing; Sync; its colour; Refresh with what the last sync found; and its own options.
struct SourceConnectionSection: View {
    @ObservedObject private var manager = TasksManager.shared
    let source: TaskSource
    let context: TasksPageContext

    private var state: SourceSyncState { manager.syncState(source) }
    private var problem: String? { TaskSourceStatus.problem(state, source: source) }
    private var rateLimitedUntil: Date? { state.rateLimitEnd }

    var body: some View {
        Section {
            LabeledContent {
                if source.isConnected {
                    Button("Disconnect…") { context.confirmsDisconnect.wrappedValue = source }
                } else {
                    Button("Connect…") { context.connect(source) }
                }
            } label: {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(verbatim: source.title)
                    SettingsStatusText(TaskSourceStatus.text(for: source), isReady: source.isSyncOn && problem == nil)
                    Text(verbatim: source.isConnected ? TaskSourceStatus.detail(for: source) : TaskSourceStatus.pitch(for: source))
                        .settingsDescriptionStyle()
                }
            }

            if source.isConnected, let problem {
                SettingsErrorText(problem)
                if source == .appleReminders, state == .needsReconnect {
                    SettingsActionRow("Reminders access", description: "Allow Kannu in Privacy & Security › Reminders.") {
                        Button("Open Privacy & Security") { TaskSourceStatus.openRemindersPrivacySettings() }
                    }
                }
            }
            if source.isConnected, state == .needsKeychainApproval {
                SettingsActionRow("Keychain access", description: String(localized: "Let Kannu read the saved \(source.name) token.")) {
                    Button("Allow Keychain Access") { manager.refresh(source) }
                }
            }
            if !source.isConnected, manager.tokenRemovalFailed(source) {
                SettingsErrorText(String(localized: "Couldn't remove the \(source.name) token from your Keychain."))
                SettingsActionRow(
                    "Saved token",
                    description: String(localized: "Or delete com.kannu.app.secure-secrets (\(TaskSourceStatus.keychainItem(for: source))) in Keychain Access.")
                ) {
                    Button("Remove Token") { manager.retryRemovingToken(source) }
                }
            }

            if source.isConnected, let enabledKey = source.enabledKey {
                SettingsRow(
                    verbatim: String(localized: "Sync \(source.name)"),
                    description: Defaults[enabledKey]
                        ? String(localized: "Fetch your open \(source.name) \(source.itemNoun.many).")
                        : String(localized: "Sync paused. \(source.name) tasks stay listed.")
                ) {
                    Toggle(String(localized: "Sync \(source.name)"), isOn: Binding(
                        get: { Defaults[enabledKey] },
                        set: { Defaults[enabledKey] = $0 }
                    ))
                }
                // On the row that holds the switch, so it exists whenever the switch is clicked.
                .onChange(of: manager.syncOnSources.contains(source)) { _, isOn in
                    if isOn { manager.syncIfStale(source) }
                }

                TaskColorRow(
                    verbatim: String(localized: "\(source.name) colour"),
                    description: String(localized: "For \(source.name) tasks that have no tags."),
                    accessibilityLabel: String(localized: "\(source.name) colour: \(Defaults[source.colorKey].localizedName)"),
                    selection: Binding(get: { Defaults[source.colorKey] }, set: { Defaults[source.colorKey] = $0 })
                )

                SourceOptionRows(source: source)

                refreshRow
            }
        } header: {
            SettingsSectionHeader("Connection")
        }
    }

    /// Refresh, with what the last sync found. While the source asks Kannu to wait, the button is
    /// off until the time it gave; the timeline redraws once, then, with no polling.
    private var refreshRow: some View {
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                if manager.isSyncing(source) {
                    ProgressView()
                        .controlSize(.small)
                }
                TimelineView(.explicit(rateLimitedUntil.map { [$0] } ?? [])) { timeline in
                    Button("Refresh") { manager.refresh(source) }
                        .disabled(!canRefresh(at: timeline.date))
                }
            }
        } label: {
            TimelineView(.explicit(rateLimitedUntil.map { [$0] } ?? [])) { timeline in
                SettingsRowLabel(verbatim: String(localized: "\(source.name) \(source.itemNoun.many)"),
                                 description: TaskSourceStatus.syncCaption(state, enabled: source.isSyncOn, at: timeline.date, source: source))
            }
        }
    }

    private func canRefresh(at date: Date) -> Bool {
        guard source.isSyncOn, manager.isReady, !manager.isSyncing(source) else { return false }
        return rateLimitedUntil.map { $0 <= date } ?? true
    }
}

/// A source's own options on its page: what decides what is fetched, beyond Sync.
private struct SourceOptionRows: View {
    @ObservedObject private var manager = TasksManager.shared
    @Default(.jiraJQL) private var jiraJQL
    @Default(.gitlabIncludeMergeRequests) private var gitlabIncludeMergeRequests
    @Default(.githubIncludePullRequests) private var githubIncludePullRequests
    @State private var showsAdvanced = false
    let source: TaskSource

    var body: some View {
        switch source {
        case .jira:
            DisclosureGroup(isExpanded: $showsAdvanced) {
                LabeledContent {
                    HStack(spacing: SettingsMetrics.rowContent) {
                        TextField("Issue filter (JQL)", text: $jiraJQL, prompt: Text(verbatim: JiraAPI.defaultJQL))
                            .labelsHidden()
                            .onSubmit { manager.refresh(.jira) }
                        Button("Reset") {
                            jiraJQL = JiraAPI.defaultJQL
                            manager.refresh(.jira)
                        }
                        .disabled(JiraAPI.effectiveJQL(jiraJQL) == JiraAPI.defaultJQL)
                    }
                } label: {
                    SettingsRowLabel("Issue filter (JQL)", description: "Which issues appear. Return applies it.")
                }
            } label: {
                SettingsRowLabel("Advanced")
            }
        case .gitlab:
            SettingsRow("Include merge requests", description: "Also show MRs assigned to you or awaiting your review.") {
                Defaults.Toggle(key: .gitlabIncludeMergeRequests) {
                    Text("Include merge requests")
                }
            }
            // On the row that holds the switch, so it exists whenever the switch is clicked. The
            // task order follows the switch on its own; this brings the fetch in line with it.
            .onChange(of: gitlabIncludeMergeRequests) { _, _ in
                manager.sourceOptionsChanged(.gitlab)
            }
        case .github:
            SettingsRow("Include pull requests", description: "Also show open pull requests assigned to you.") {
                Defaults.Toggle(key: .githubIncludePullRequests) {
                    Text("Include pull requests")
                }
            }
            // A sync in flight asked for the old set: it is dropped, and the new one fetched.
            .onChange(of: githubIncludePullRequests) { _, _ in
                manager.sourceOptionsChanged(.github)
            }
        case .local, .linear, .todoist, .appleReminders:
            EmptyView()
        }
    }
}

/// What a source's rows say about its connection, from the Defaults display copies and the
/// manager's sync state — never the Keychain. Shared by the overview's rows and the source pages.
enum TaskSourceStatus {
    /// "Connected as Dana", "Connected as @dana · gitlab.com (can log time)"; "Not connected".
    static func text(for source: TaskSource) -> String {
        guard source.isConnected else { return String(localized: "Not connected") }
        switch source {
        case .gitlab:
            let server = GitLabHost.displayName(Defaults[.gitlabHost])
            return Defaults[.gitlabCanLogTime]
                ? String(localized: "Connected as @\(Defaults[.gitlabUsername]) · \(server) (can log time)")
                : String(localized: "Connected as @\(Defaults[.gitlabUsername]) · \(server) (read-only)")
        case .appleReminders:
            return String(localized: "Allowed")
        case .github:
            return String(localized: "Connected as @\(Defaults[.githubUsername]) · \(GitHubHost.displayName(Defaults[.githubHost]))")
        case .local, .jira, .linear, .todoist:
            let name = source.accountNameKey.map { Defaults[$0] }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? String(localized: "Connected") : String(localized: "Connected as \(name)")
        }
    }

    /// The line under a connected source's status: where it reads from and what it lists.
    static func detail(for source: TaskSource) -> String {
        switch source {
        case .jira:
            return String(localized: "Site \(Defaults[.jiraSiteHost]) · Filter: \(JiraAPI.filterSummary(jql: Defaults[.jiraJQL]))")
        case .gitlab:
            let lists = Defaults[.gitlabIncludeMergeRequests]
                ? String(localized: "Lists your open issues and merge requests")
                : String(localized: "Lists your open issues")
            let name = Defaults[.gitlabAccountDisplayName].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? lists : "\(name) · \(lists)"
        case .github:
            return Defaults[.githubIncludePullRequests]
                ? String(localized: "Lists the open issues and pull requests assigned to you")
                : String(localized: "Lists the open issues assigned to you")
        case .linear, .todoist, .appleReminders, .local:
            return String(localized: "Lists your open \(source.name) \(source.itemNoun.many).")
        }
    }

    /// What a source not yet connected offers, and what connecting takes.
    static func pitch(for source: TaskSource) -> String {
        switch source {
        case .jira: return String(localized: "Your open issues. Needs your site, email and a token.")
        case .gitlab: return String(localized: "Your issues and MRs, from gitlab.com or your server.")
        case .github: return String(localized: "Issues assigned to you, from github.com or GitHub Enterprise. Needs a token.")
        case .linear: return String(localized: "Issues assigned to you. Needs a personal API key.")
        case .todoist: return String(localized: "Your open tasks. Needs your API token.")
        case .appleReminders: return String(localized: "Your incomplete reminders. macOS asks you first.")
        case .local: return ""
        }
    }

    /// The Keychain item's account, for the Remove Token hint.
    static func keychainItem(for source: TaskSource) -> String { "\(source.rawValue.lowercased())-credential" }

    /// A problem the user has to act on. Offline and rate limits are not: they read in the Refresh
    /// row's caption and clear on their own.
    static func problem(_ sync: SourceSyncState, source: TaskSource) -> String? {
        switch sync {
        case .authFailed(let status):
            return String(localized: "Token rejected (\(status)). Disconnect, then connect with a new token.")
        case .needsReconnect:
            switch source {
            case .appleReminders:
                return String(localized: "macOS no longer lets Kannu read your reminders.")
            case .jira:
                return String(localized: "Saved Jira sign-in missing or for another site. Disconnect, then connect again.")
            case .local, .gitlab, .github, .linear, .todoist:
                return String(localized: "Saved \(source.name) sign-in missing or for another server. Disconnect, then connect again.")
            }
        case .failed(let message):
            return message
        case .idle, .syncing, .synced, .offline, .rateLimited, .needsKeychainApproval:
            return nil
        }
    }

    /// The Refresh row's caption: what the last sync found, in the source's own nouns.
    static func syncCaption(_ sync: SourceSyncState, enabled: Bool, at date: Date, source: TaskSource) -> String {
        guard enabled else { return String(localized: "Sync paused.") }
        switch sync {
        case .idle:
            return String(localized: "Not synced yet.")
        case .syncing:
            return String(localized: "Syncing…")
        case .synced(let at, let count, let complete):
            let time = at.formatted(date: .omitted, time: .shortened)
            if !complete {
                return source == .jira
                    ? String(localized: "Synced \(time) · Showing the first \(count) — narrow the filter")
                    : String(localized: "Synced \(time) · Showing the first \(count)")
            }
            let noun = count == 1 ? source.itemNoun.one : source.itemNoun.many
            return String(localized: "Synced \(time) · \(count) \(noun)")
        case .offline:
            return String(localized: "Offline.")
        case .rateLimited(let until):
            guard until > date else { return String(localized: "You can refresh again.") }
            return String(localized: "Rate limited until \(until.formatted(date: .omitted, time: .shortened))")
        case .authFailed, .needsKeychainApproval, .needsReconnect, .failed:
            return String(localized: "Not synced.")
        }
    }

    /// Where a source's token is made, on the server typed so far; nil while it is not one Kannu
    /// would connect to.
    static func createTokenURL(for source: TaskSource, server: String) -> URL? {
        switch source {
        case .github:
            return TasksManager.githubCreateTokenURL(server: server)
        case .linear:
            return URL(string: "https://linear.app/settings/account/security")
        case .todoist:
            return URL(string: "https://app.todoist.com/app/settings/integrations/developer")
        case .local, .jira, .gitlab, .appleReminders:
            return nil
        }
    }

    /// System Settings › Privacy & Security › Reminders.
    static func openRemindersPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A colour row: the title and description, then the preset swatch. A raw `LabeledContent`, never a
/// `SettingsRow`: the swatch anchors a popover, and `SettingsRow`'s `.labelsHidden()` is for
/// controls whose label the row replaces (docs/SETTINGS.md). The swatch's own label replaces the
/// row's for VoiceOver, so `accessibilityLabel` names what it colours as well as the colour.
struct TaskColorRow: View {
    private let label: SettingsRowLabel
    private let accessibilityLabel: String
    @Binding private var selection: TaskColor

    init(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        accessibilityLabel: String,
        selection: Binding<TaskColor>
    ) {
        label = SettingsRowLabel(title, description: description)
        self.accessibilityLabel = accessibilityLabel
        _selection = selection
    }

    /// For a title built at run time (already localised): a source's "GitHub colour".
    init(verbatim title: String, description: String, accessibilityLabel: String, selection: Binding<TaskColor>) {
        label = SettingsRowLabel(verbatim: title, description: description)
        self.accessibilityLabel = accessibilityLabel
        _selection = selection
    }

    var body: some View {
        LabeledContent {
            TaskColorPickerButton(selection: $selection, accessibilityLabel: accessibilityLabel)
        } label: {
            label
        }
    }
}
