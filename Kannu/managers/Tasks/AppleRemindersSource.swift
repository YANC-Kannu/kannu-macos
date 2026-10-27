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

import EventKit
import Foundation
import os

/// Kannu's one door to Reminders (EventKit). Read-only: it never saves or removes a reminder.
///
/// - **Asked once, on a click.** `access` only reads macOS's answer; `requestAccess()` — the one call
///   that can show macOS's question — runs only from Connect (`IntegrationSecretRulesTests`). Nothing
///   here runs at launch or before the Terms of Use gate: the store is built on first use.
/// - **Off the main thread.** The `EKEventStore` is built and read on its own serial queue: a first
///   touch of a protected resource can block the thread it runs on (docs/REGRESSIONS.md entry 11).
/// - **Told when Reminders changes.** While Reminders is connected and its sync is on, the store's
///   change notification asks for a quiet sync (`SourceSync.externalChange`); the observer is removed
///   on Disconnect, Sync off and Tasks off.
///
/// `@unchecked Sendable`: `store` is touched only on `queue`, and `observer` only on the main actor.
final class AppleRemindersStore: @unchecked Sendable {
    static let shared = AppleRemindersStore()

    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")
    private let queue = DispatchQueue(label: "com.kannu.app.tasks.reminders", qos: .userInitiated)
    /// Built on `queue`, on first use.
    private var store: EKEventStore?
    private var observer: NSObjectProtocol?

    private init() {}

    /// Whether Kannu may read reminders, as macOS says now. Never asks.
    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    private func onQueue<T>(_ work: @escaping (EKEventStore) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                let store = self.store ?? EKEventStore()
                self.store = store
                continuation.resume(returning: work(store))
            }
        }
    }

    /// Connect: macOS asks the user, once. True when Kannu may read reminders.
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        let store: EKEventStore = await onQueue { $0 }
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            Self.log.notice("Reminders access request failed")
            return false
        }
    }

    /// Every incomplete reminder in every list, as plain values; nil when Kannu may not read them.
    func incompleteReminders() async -> [ReminderSnapshot]? {
        guard hasAccess else { return nil }
        let store: EKEventStore = await onQueue { $0 }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map { reminder in
                    ReminderSnapshot(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        listTitle: reminder.calendar?.title ?? "",
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        priority: reminder.priority,
                        lastModified: reminder.lastModifiedDate,
                        isCompleted: reminder.isCompleted
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    /// Starts or stops asking for a sync when Reminders changes. Main actor: called by the manager.
    @MainActor
    func observeChanges(_ observe: Bool, onChange: @escaping @MainActor () -> Void) {
        if !observe {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            return
        }
        guard observer == nil, hasAccess else { return }
        Task { @MainActor in
            let store: EKEventStore = await self.onQueue { $0 }
            guard self.observer == nil else { return }
            self.observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { _ in
                MainActor.assumeIsolated { onChange() }
            }
        }
    }
}

/// Where Apple Reminders' "credential" lives: macOS's permission. Loading it never asks; there is
/// nothing to save or remove — Disconnect only stops Kannu reading, and the permission stays the
/// user's to change in System Settings.
struct AppleRemindersAccessKeeper: CredentialKeeping {
    func load(allowInteraction: Bool) async -> CredentialLoad<AppleRemindersAccess> {
        AppleRemindersStore.shared.hasAccess ? .found(AppleRemindersAccess()) : .missing
    }

    func save(_ credential: AppleRemindersAccess) async -> Bool { true }

    func remove() async -> Bool { true }
}

/// Apple Reminders as a task source (`SourceSync`): every incomplete reminder, by list.
struct AppleRemindersTaskSource: TaskSourceProvider {
    func scope(of credential: AppleRemindersAccess) -> String? { AppleReminders.scope }

    func fetch(_ credential: AppleRemindersAccess, options: Void) async -> SourceFetch {
        guard let snapshots = await AppleRemindersStore.shared.incompleteReminders() else {
            return .failed(.needsReconnect)
        }
        return .fetched(AppleReminders.fetch(snapshots))
    }
}
