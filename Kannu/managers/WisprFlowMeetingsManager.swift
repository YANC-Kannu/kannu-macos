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
import os

/// Wispr Flow's meeting summaries, shown in the notch's Notes as read-only notes.
///
/// A mirror, never a copy: the notes live only in `notes`, read again each time the Notes tab
/// appears, so nothing here reaches `savedNotes`, Apple Notes sync or Clear Notes, and a meeting
/// deleted in Wispr is gone on the next look. Nothing reads Wispr's files until the user turns the
/// setting on, and there is no timer or file watcher: Wispr's WAL changes on every dictation.
@MainActor
final class WisprFlowMeetingsManager: ObservableObject {
    static let shared = WisprFlowMeetingsManager()

    @Published private(set) var notes: [NoteItem] = []

    /// Counts and error cases only, never a meeting's title or summary.
    private let logger = os.Logger(subsystem: "com.kannu.app", category: "WisprFlowMeetings")
    private var refreshTask: Task<Void, Never>?

    private init() {}

    /// Whether Wispr Flow is installed, as Launch Services knows it.
    nonisolated static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: WisprFlowMeetingsStore.bundleIdentifier) != nil
    }

    /// Reads the summaries again, off the main actor. With the setting off it only empties the list.
    func refresh() {
        refreshTask?.cancel()
        guard Defaults[.enableWisprFlowMeetings] else {
            refreshTask = nil
            if !notes.isEmpty { notes = [] }
            return
        }
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { WisprFlowMeetingsStore.meetings() }.value
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    /// Opens Wispr Flow, where a meeting's summary is edited.
    func openWisprFlow() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WisprFlowMeetingsStore.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func apply(_ result: Result<[WisprMeeting], WisprStoreError>) {
        switch result {
        case .success(let meetings):
            let mapped = meetings.map(Self.note(from:))
            if mapped != notes { notes = mapped }
            logger.info("Read \(meetings.count, privacy: .public) Wispr Flow meeting summaries")
        case .failure(let error):
            if !notes.isEmpty { notes = [] }
            logger.notice("Wispr Flow meetings unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// A meeting as a note. Wispr's ids are UUIDs, so a meeting keeps its note's identity across reads.
    static func note(from meeting: WisprMeeting) -> NoteItem {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteItem(
            id: UUID(uuidString: meeting.id) ?? UUID(),
            title: title.isEmpty ? String(localized: "Wispr Flow meeting") : title,
            content: meeting.summary,
            creationDate: meeting.created,
            modificationDate: meeting.modified,
            colorIndex: 0,
            wisprMeetingId: meeting.id
        )
    }
}
