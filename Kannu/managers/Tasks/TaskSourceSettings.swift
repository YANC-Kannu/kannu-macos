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

import Combine
import Defaults
import Foundation
import SwiftUI

/// The settings each source keeps on this Mac, all in `Constants.swift`: its Sync switch, what it is
/// connected to (a display copy — the token and where it may be sent live in the Keychain), its
/// account's name, its colour, and Show in notch. One switch per setting, so a view or the manager
/// reads any source's without naming it. What a source *is* lives in `TaskSourceFacts`.
extension TaskSource {
    /// "Sync X": whether its items are fetched. Nil for local tasks, which are never fetched.
    var enabledKey: Defaults.Key<Bool>? {
        switch self {
        case .local: return nil
        case .jira: return .jiraEnabled
        case .gitlab: return .gitlabEnabled
        case .github: return .githubEnabled
        case .linear: return .linearEnabled
        case .todoist: return .todoistEnabled
        case .appleReminders: return .appleRemindersEnabled
        }
    }

    /// What it is connected to, as shown: Jira's site, GitLab's or GitHub's server, Linear's
    /// workspace, the Todoist account, or "reminders". Empty when not connected; nil for local.
    var scopeKey: Defaults.Key<String>? {
        switch self {
        case .local: return nil
        case .jira: return .jiraSiteHost
        case .gitlab: return .gitlabHost
        case .github: return .githubHost
        case .linear: return .linearWorkspace
        case .todoist: return .todoistAccount
        case .appleReminders: return .appleRemindersScope
        }
    }

    /// The connected account's display name, for its status line; nil where there is none.
    var accountNameKey: Defaults.Key<String>? {
        switch self {
        case .local, .appleReminders: return nil
        case .jira: return .jiraAccountDisplayName
        case .gitlab: return .gitlabAccountDisplayName
        case .github: return .githubAccountDisplayName
        case .linear: return .linearAccountDisplayName
        case .todoist: return .todoistAccountDisplayName
        }
    }

    /// Every connected account's display name, and GitLab's and GitHub's usernames, for
    /// `TaskDetailSummary(selfNames:)`: the user's own name never takes a fact. GitHub's assignee is
    /// the user's own login, since its sync lists the issues assigned to them.
    static var selfNames: Set<String> {
        let names = allCases.compactMap { $0.accountNameKey.map { Defaults[$0] } }
            + [Defaults[.gitlabUsername], Defaults[.githubUsername]]
        return Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    /// The colour its tasks show when they have no tags (`TaskColoring`).
    var colorKey: Defaults.Key<TaskColor> {
        switch self {
        case .local: return .tasksLocalColor
        case .jira: return .jiraTaskColor
        case .gitlab: return .gitlabTaskColor
        case .github: return .githubTaskColor
        case .linear: return .linearTaskColor
        case .todoist: return .todoistTaskColor
        case .appleReminders: return .appleRemindersTaskColor
        }
    }

    /// The notch's Show in notch for it (`TaskSourceMenu`): what the notch lists, nothing else.
    var showInNotchKey: Defaults.Key<Bool> {
        switch self {
        case .local: return .tasksPopoverShowLocal
        case .jira: return .tasksPopoverShowJira
        case .gitlab: return .tasksPopoverShowGitLab
        case .github: return .tasksPopoverShowGitHub
        case .linear: return .tasksPopoverShowLinear
        case .todoist: return .tasksPopoverShowTodoist
        case .appleReminders: return .tasksPopoverShowAppleReminders
        }
    }

    /// Connected, by its display copy. Local tasks always are.
    var isConnected: Bool {
        scopeKey.map { !Defaults[$0].isEmpty } ?? true
    }

    /// Connected and its Sync switch on.
    var isSyncOn: Bool {
        isConnected && (enabledKey.map { Defaults[$0] } ?? false)
    }
}

/// The notch's Show in notch for every source, and which sources are connected, kept current from
/// Defaults for the notch's views (`TaskSourceMenu`, `TasksPopover`, the timer tab's task list). A
/// view filter only: `TasksManager` never reads it, so it changes what the notch shows and never
/// what is fetched or what Brain lists. Reads Defaults only — never the Keychain.
@MainActor
final class TaskSourcePreferences: ObservableObject {
    static let shared = TaskSourcePreferences()

    /// The sources the notch hides: Show in notch off, for Local tasks or a connected source. A
    /// source that is not connected has no check item, so its kept tasks always show.
    @Published private(set) var hiddenInNotch: Set<TaskSource> = []
    /// The connected sources, in source order: the ones Show in notch offers beside Local.
    @Published private(set) var connected: [TaskSource] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        recompute()
        // `options: []`, so subscribing does not fire.
        Publishers.MergeMany(
            TaskSource.allCases.map { Defaults.publisher($0.showInNotchKey, options: []).map { _ in () }.eraseToAnyPublisher() }
                + TaskSource.allCases.compactMap(\.scopeKey).map { Defaults.publisher($0, options: []).map { _ in () }.eraseToAnyPublisher() }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            MainActor.assumeIsolated { self?.recompute() }
        }
        .store(in: &cancellables)
    }

    /// Whether Show in notch hides anything, so the notch says "Filtered".
    var isNarrowing: Bool { !hiddenInNotch.isEmpty }

    /// A source's check item.
    func shownBinding(for source: TaskSource) -> Binding<Bool> {
        Binding(get: { Defaults[source.showInNotchKey] }, set: { Defaults[source.showInNotchKey] = $0 })
    }

    /// Show all: every source back in the notch.
    func showAll() {
        for source in TaskSource.allCases where !Defaults[source.showInNotchKey] {
            Defaults[source.showInNotchKey] = true
        }
    }

    private func recompute() {
        let connected = TaskSource.remoteSources.filter(\.isConnected)
        let hidden = Set(TaskSource.allCases.filter { !Defaults[$0.showInNotchKey] && $0.isConnected })
        if connected != self.connected { self.connected = connected }
        if hidden != hiddenInNotch { hiddenInNotch = hidden }
    }
}
