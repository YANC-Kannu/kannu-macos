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

import XCTest

/// Brain › Notes is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22). The page before this one observed the sync manager, the notch's coordinator and its
/// view model whole, so a sync, a sneak peek or a notch state change redrew it, Brain open or not. It keeps Agents'
/// live-data contract (docs/SETTINGS.md, "Live data"), starts no sync and no AppleScript of its own, and its boards
/// never read this Mac's notes or their image files. Each rule is read from the source and checked against planted
/// offenders, as `ClipboardPageLiveDataRulesTests` does for Clipboard.
final class NotesPageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/NotesOverview.swift"
    private static let pagePath = "Kannu/components/Settings/NotePage.swift"
    private static let settingsPath = "Kannu/components/Settings/NotesSettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"
    private static let boardsPath = "Kannu/helpers/DebugSnapshot.swift"

    /// The braces after a signature, matched by depth; the reader `ClosedNotchTimerRulesTests` already shares.
    private static func body(after signature: String, in code: String) -> String {
        ClosedNotchTimerRulesTests.body(after: signature, in: code) ?? ""
    }

    /// The braces after `signature`'s first occurrence past `anchor`, for a file with two of it.
    private static func body(after signature: String, following anchor: String, in code: String) -> String {
        guard let start = code.range(of: anchor) else { return "" }
        return body(after: signature, in: String(code[start.upperBound...]))
    }

    private static func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: the notes, the sync's switch, scope and date through Defaults, and the sync's own state
    /// through its `objectWillChange`, at most twice a second.
    private static let notesFeed = #"Defaults\.publisher\(keys: \.savedNotes, \.enableAppleNotesSync, \.appleNotesSyncScope, \.appleNotesLastSyncDate,\s*options: \[\]\)\s*\.merge\(with: AppleNotesSyncManager\.shared\.objectWillChange\)\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#

    /// All the page may name on `NotesManager.shared`, file by file: the calls a press makes. Anything else is either
    /// state, which only the copy reads, or work the page must not start.
    private static let allowedManagerNames: [String: Set<String>] = [
        "overview": ["togglePin", "openInNotes"],
        "page": ["togglePin", "openInNotes"],
        "settings": ["syncWithAppleNotes", "delete"],
    ]

    static func managerNames(in code: String) -> [String] {
        SettingsDesignSystemRulesTests.matches(of: #"\bNotesManager\.shared\.\w+"#, in: code)
            .map { String($0.dropFirst("NotesManager.shared.".count)) }
    }

    /// One subscription, in the settings view that holds the copy, and nothing else of the notes or the sync: no
    /// observer of the sync manager or of what the page used to observe whole, no `@Default` of the notes or of the last
    /// sync's date (each changes with every save or sync), no `onReceive` or sink, and their state read in one place, a
    /// copy assigned only when it changed. The copy's equality is the synthesized one, so it compares everything drawn.
    static func followProblems(settings: String, overview: String, page: String) -> [String] {
        let files = [("the settings", SettingsDesignSystemRulesTests.code(settings), "settings"),
                     ("the overview", SettingsDesignSystemRulesTests.code(overview), "overview"),
                     ("the note's page", SettingsDesignSystemRulesTests.code(page), "page")]
        let settingsCode = files[0].1, overviewCode = files[1].1
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: notesFeed, in: settingsCode).count != 1
            || files.dropFirst().contains(where: { !SettingsDesignSystemRulesTests.matches(of: notesFeed, in: $0.1).isEmpty }) {
            problems.append("the notes and the sync do not come through the page's one subscription throttled to 500 ms")
        }
        for (name, code, key) in files {
            if !SettingsDesignSystemRulesTests.matches(
                of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*\b(?:AppleNotesSyncManager|NotesManager|KannuViewModel|KannuViewCoordinator)\b"#,
                in: code).isEmpty {
                problems.append("\(name) observe a store whole")
            }
            if !SettingsDesignSystemRulesTests.matches(of: #"@Default\(\.(?:savedNotes|appleNotesLastSyncDate)\)"#, in: code).isEmpty {
                problems.append("\(name) observe the notes or the last sync through @Default")
            }
            if code.range(of: #"\.onReceive\([^\n]*(?:AppleNotesSyncManager|Defaults\.publisher)|(?:AppleNotesSyncManager|Defaults\.publisher)[^\n]*\.sink"#,
                          options: .regularExpression) != nil {
                problems.append("\(name) follow the notes or the sync outside the throttled task")
            }
            let pastTheCopy = managerNames(in: code).filter { !(allowedManagerNames[key] ?? []).contains($0) }
            if !pastTheCopy.isEmpty {
                problems.append("\(name) name the notes manager past its presses: \(pastTheCopy.joined(separator: ", "))")
            }
        }
        // The sync manager: the feed and the copy, both in the settings; nowhere else.
        if count("AppleNotesSyncManager.shared", in: settingsCode) != 2
            || files.dropFirst().contains(where: { $0.1.contains("AppleNotesSyncManager.shared") }) {
            problems.append("the sync manager is read past the copy")
        }
        // The notes: once in the copy, and once in the scope's press, which asks before narrowing.
        let copy = body(after: "init(_ sync: AppleNotesSyncManager)", in: overviewCode)
        if count("Defaults[.savedNotes]", in: overviewCode) != 1 || !copy.contains("Defaults[.savedNotes]")
            || count("Defaults[.savedNotes]", in: settingsCode) != 1
            || !body(after: "private var scopeSelection", in: settingsCode).contains("Defaults[.savedNotes]")
            || files[2].1.contains("Defaults[.savedNotes]") {
            problems.append("the notes are read past the copy")
        }
        for read in ["notes = Self.ordered(Defaults[.savedNotes])", "syncOn = Defaults[.enableAppleNotesSync]",
                     "scope = Defaults[.appleNotesSyncScope]", "lastSync = Defaults[.appleNotesLastSyncDate]",
                     "isSyncing = sync.isSyncing", "lastError = sync.lastError"] where !copy.contains(read) {
            problems.append("the copy does not read \(read)")
        }
        let reader = body(after: "private func copyFromStores()", in: settingsCode)
        if count("NotesPageData(AppleNotesSyncManager.shared)", in: settingsCode) != 1
            || !reader.contains("NotesPageData(AppleNotesSyncManager.shared)")
            || !reader.contains("if latest != data { data = latest }") {
            problems.append("the notes and the sync are not read in one place, into a copy assigned only when it changed")
        }
        if !overviewCode.contains("struct NotesPageData: Equatable {")
            || overviewCode.range(of: #"static func ==\s*\(lhs: NotesPageData"#, options: .regularExpression) != nil {
            problems.append("the copy's equality is not the synthesized one, so it can leave out what the page draws")
        }
        return problems
    }

    func testTheNotesComeThroughOneThrottledCopy() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let page = try Self.source(Self.pagePath)
        XCTAssertEqual(Self.followProblems(settings: settings, overview: overview, page: page), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("    @ObservedObject private var visibility = BrainVisibility.shared\n",
             "    @ObservedObject private var sync = AppleNotesSyncManager.shared\n    @ObservedObject private var visibility = BrainVisibility.shared\n"),
            // What the page before observed whole and never used.
            ("    @ObservedObject private var visibility = BrainVisibility.shared\n",
             "    @EnvironmentObject var vm: KannuViewModel\n    @ObservedObject private var visibility = BrainVisibility.shared\n"),
            ("    @Default(.appleNotesSyncScope) private var appleNotesSyncScope\n",
             "    @Default(.appleNotesSyncScope) private var appleNotesSyncScope\n    @Default(.savedNotes) private var savedNotes\n"),
            ("if latest != data { data = latest }", "data = latest"),
            ("        .navigationTitle(\"Notes\")",
             "        .onReceive(AppleNotesSyncManager.shared.objectWillChange) { _ in }\n        .navigationTitle(\"Notes\")"),
            (".disabled(data.isSyncing)", ".disabled(AppleNotesSyncManager.shared.isSyncing)"),
            ("NotesManager.shared.delete(note)", "NotesManager.shared.clearAll()"),
        ], in: settings) { Self.followProblems(settings: $0, overview: overview, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("ForEach(data.notes) { note in", "ForEach(NotesPageData.ordered(Defaults[.savedNotes])) { note in"),
            ("    @Default(.enableNotes) private var enabled\n",
             "    @Default(.enableNotes) private var enabled\n    @Default(.savedNotes) private var savedNotes\n"),
            ("        lastError = sync.lastError\n", ""),
            ("struct NotesPageData: Equatable {\n",
             "struct NotesPageData: Equatable {\n    static func == (lhs: NotesPageData, rhs: NotesPageData) -> Bool { lhs.notes.map(\\.id) == rhs.notes.map(\\.id) }\n"),
            ("Button(\"Copy\") { NotesOverview.copy(note) }", "Button(\"Copy\") { NotesManager.shared.clearAll() }"),
        ], in: overview) { Self.followProblems(settings: settings, overview: $0, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("    @Default(.enableNotePinning) private var pinning\n",
             "    @Default(.enableNotePinning) private var pinning\n    @ObservedObject private var sync = AppleNotesSyncManager.shared\n"),
            ("NotesManager.shared.openInNotes(note)", "NotesManager.shared.save(NotesManager.Draft(id: note.id, title: \"\", content: \"\", imageData: nil, colorIndex: 0))"),
        ], in: page) { Self.followProblems(settings: settings, overview: overview, page: $0) }
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// The subscription is the settings' one `.task`, keyed on Brain's visibility, returning at once while it is false,
    /// with no `Task` inside, reading once as Brain comes back (Defaults and `objectWillChange` will not send again what
    /// changed while it was away), and its loop taking a fresh copy. The list has no `.task`, and the note's page one,
    /// which reads its image once and follows nothing. `AgentsPageLiveDataRulesTests` holds the flag itself.
    static func offScreenProblems(settings: String, overview: String, page: String) -> [String] {
        var problems: [String] = []
        let opener = ".task(id: visibility.isOnScreen)"
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        if count(".task", in: settingsCode) != 1 || count(opener, in: settingsCode) != 1 {
            problems.append("the page does not follow Brain's visibility")
        } else {
            let task = body(after: opener, in: settingsCode)
            let guardRange = task.range(of: "guard visibility.isOnScreen else { return }")
            let feed = task.range(of: "Defaults.publisher(")
            if let guardRange, let feed, guardRange.lowerBound < feed.lowerBound {
                // The first read sits between the guard and the feed.
                let read = task.range(of: "copyFromStores()")
                if read == nil || read!.lowerBound < guardRange.upperBound || read!.upperBound > feed.lowerBound {
                    problems.append("the page does not read the notes as Brain comes back on screen")
                }
            } else {
                problems.append("the page subscribes while Brain is off screen")
            }
            if task.range(of: unstructuredTask, options: .regularExpression) != nil {
                problems.append("the page subscribes in a Task its .task cannot cancel")
            }
            if !body(after: ".values", in: task).contains("copyFromStores()") {
                problems.append("the page's loop does not take a fresh copy")
            }
        }
        if count(".task", in: SettingsDesignSystemRulesTests.code(overview)) != 0 {
            problems.append("the list has a .task of its own")
        }
        let pageCode = SettingsDesignSystemRulesTests.code(page)
        let imageTask = body(after: ".task(id: imageKey)", in: pageCode)
        if count(".task", in: pageCode) != 1 || imageTask.isEmpty || imageTask.contains("for await")
            || imageTask.contains("AppleNotesSyncManager") || imageTask.contains("Defaults")
            || !imageTask.contains("Task.detached(priority: .utility) { try? Data(contentsOf: url) }") {
            problems.append("the note's page does more than read its image once, off the main thread")
        }
        return problems
    }

    func testTheSubscriptionStopsWhileBrainIsOffScreen() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let page = try Self.source(Self.pagePath)
        XCTAssertEqual(Self.offScreenProblems(settings: settings, overview: overview, page: page), [])
        let loop = "            for await _ in Defaults.publisher(keys: .savedNotes, .enableAppleNotesSync, .appleNotesSyncScope, .appleNotesLastSyncDate,\n"
            + "                                              options: [])\n"
            + "                .merge(with: AppleNotesSyncManager.shared.objectWillChange)\n"
            + "                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n"
            + "                .values {\n                copyFromStores()\n            }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n", ""),
            ("            copyFromStores()\n            // The notes and the sync's switch", "            // The notes and the sync's switch"),
            (loop, "            Task {\n" + loop + "            }\n"),
            // A loop that follows and does nothing: the copy would never change after Brain comes back.
            ("                .values {\n                copyFromStores()\n            }", "                .values {\n            }"),
        ], in: settings) { Self.offScreenProblems(settings: $0, overview: overview, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if data.syncOn {\n", "            if data.syncOn {\n                EmptyView().task { }\n"),
        ], in: overview) { Self.offScreenProblems(settings: settings, overview: $0, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            guard let fileName = note.imageFileName else {\n",
             "            for await _ in AppleNotesSyncManager.shared.objectWillChange.values { image = nil }\n            guard let fileName = note.imageFileName else {\n"),
            // Read on the main thread, as the page draws.
            ("await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value", "try? Data(contentsOf: url)"),
        ], in: page) { Self.offScreenProblems(settings: settings, overview: overview, page: $0) }
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// The page keeps no clock and nothing that moves on its own: a note says when it was edited, and the sync when it
    /// last ran, by the time of day or the date, and off screen the copy simply stays as it was. A spinner, a relative
    /// date ("5 minutes ago") and a "Copied" that clears itself are clocks too.
    static func clockProblems(in source: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(source)
        return ["TimelineView", "Timer.", ".repeatForever", "ProgressView", "withAnimation", ".animation(", "asyncAfter",
                "style: .relative", ".relative(", "Task.sleep", ".sleep("]
            .filter { code.contains($0) }
            .map { "the page keeps a clock or a motion of its own: \($0)" }
    }

    func testThePageKeepsNoClock() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let page = try Self.source(Self.pagePath)
        for source in [settings, overview, page] {
            XCTAssertEqual(Self.clockProblems(in: source), [])
        }
        SettingsDesignSystemRulesTests.assertCaught([
            // The Last synced row as it was: a relative date and a spinner while a sync runs.
            (".disabled(data.isSyncing)", ".disabled(data.isSyncing)\n                        ProgressView()"),
            ("description: data.lastSync.map { NotesOverview.when($0, now: Date()) }",
             "description: data.lastSync.map { $0.formatted(.relative(presentation: .named)) }"),
        ], in: settings, by: Self.clockProblems)
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if data.syncOn {\n", "            TimelineView(.everyMinute) { _ in EmptyView() }\n            if data.syncOn {\n"),
        ], in: overview, by: Self.clockProblems)
        // A minute's sleep in the subscription's own task, to keep a "5 minutes ago" fresh: a clock all the same.
        SettingsDesignSystemRulesTests.assertCaught([
            ("            guard visibility.isOnScreen else { return }\n",
             "            guard visibility.isOnScreen else { return }\n            try? await Task.sleep(for: .seconds(60))\n"),
        ], in: settings, by: Self.clockProblems)
        SettingsDesignSystemRulesTests.assertCaught([
            ("                NotesOverview.copy(note)\n",
             "                NotesOverview.copy(note)\n                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {}\n"),
        ], in: page, by: Self.clockProblems)
    }

    // MARK: - No work of its own

    /// What a press, and only a press, may start: a sync, a pin, Open in Notes (AppleScript, behind its gate in the sync
    /// manager), a copy to the pasteboard and a delete.
    private static let presses = ["syncWithAppleNotes", "togglePin", "openInNotes", "NotesOverview.copy(", "delete(", "remove(",
                                  "NSPasteboard", "getImageData("]

    /// The page starts no sync and no AppleScript as it appears or follows: no press call in a hook. Each call is pinned
    /// to its count, so a new one anywhere fails here: the settings sync three times (the scope's choice, the narrowing
    /// question's Sync Kannu folder, Sync now), the list and the note's page pin and open in Notes from their buttons,
    /// and a note's image file is read only by Copy's press and by a note's page, once, off the main thread: never by a
    /// row or the settings, where it would be read as each one draws.
    static func workProblems(settings: String, overview: String, page: String) -> [String] {
        var problems: [String] = []
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        let pageCode = SettingsDesignSystemRulesTests.code(page)
        let hooks = [body(after: ".onAppear", following: ".onChange(of: enableNotes)", in: settingsCode),
                     body(after: ".task(id: visibility.isOnScreen)", in: settingsCode),
                     body(after: ".task(id: imageKey)", in: pageCode)]
        for hook in hooks {
            for call in presses where hook.contains(call) {
                problems.append("a hook starts work a press should: \(call)")
            }
        }
        if count(".onAppear", in: settingsCode) != 2 || count(".onAppear", in: overviewCode) != 0 || count(".onAppear", in: pageCode) != 0 {
            problems.append("the page has a hook beyond its visit's read and the list's scroll back")
        }
        let pinned: [(String, String, Int)] = [
            ("the settings", "syncWithAppleNotes", 3), ("the overview", "syncWithAppleNotes", 0), ("the note's page", "syncWithAppleNotes", 0),
            ("the overview", "togglePin", 2), ("the note's page", "togglePin", 1),
            ("the overview", "openInNotes", 1), ("the note's page", "openInNotes", 1), ("the settings", "openInNotes", 0),
            ("the settings", "NotesManager.shared.delete(", 1), ("the overview", "getImageData(", 1), ("the note's page", "getImageData(", 0),
            ("the settings", "getImageData(", 0),
            ("the note's page", "noteImageDataDirectory", 1), ("the overview", "noteImageDataDirectory", 0),
            ("the settings", "noteImageDataDirectory", 0),
            ("the note's page", "Data(contentsOf:", 1), ("the overview", "Data(contentsOf:", 0), ("the settings", "Data(contentsOf:", 0),
            ("the note's page", "NSImage(contentsOf", 0), ("the overview", "NSImage(contentsOf", 0), ("the settings", "NSImage(contentsOf", 0),
        ]
        let codes = ["the settings": settingsCode, "the overview": overviewCode, "the note's page": pageCode]
        for (name, call, expected) in pinned {
            let found = count(call, in: codes[name] ?? "")
            if found != expected { problems.append("\(name) call \(call) \(found) times, pinned at \(expected)") }
        }
        if !body(after: "static func copy(_ note: NoteItem)", in: overviewCode).contains("note.getImageData()") {
            problems.append("a note's image file is read other than on Copy's press")
        }
        return problems
    }

    func testThePageStartsNoWorkOfItsOwn() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let page = try Self.source(Self.pagePath)
        XCTAssertEqual(Self.workProblems(settings: settings, overview: overview, page: page), [])
        SettingsDesignSystemRulesTests.assertCaught([
            // As the notch's Notes tab does on appearing: a sync, and with it Notes' AppleScript.
            ("            copyFromStores()\n        }\n        .task", "            copyFromStores()\n            NotesManager.shared.syncWithAppleNotes()\n        }\n        .task"),
            ("            guard visibility.isOnScreen else { return }\n",
             "            guard visibility.isOnScreen else { return }\n            NotesManager.shared.syncWithAppleNotes()\n"),
            ("        .onChange(of: enableNotes) { _, _ in\n",
             "        .onAppear { NotesManager.shared.syncWithAppleNotes() }\n        .onChange(of: enableNotes) { _, _ in\n"),
        ], in: settings) { Self.workProblems(settings: $0, overview: overview, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if data.syncOn {\n", "            if data.syncOn {\n                EmptyView().onAppear { NotesManager.shared.syncWithAppleNotes() }\n"),
            ("Button(\"Open in Notes\") { NotesManager.shared.openInNotes(note) }",
             "Button(\"Open in Notes\") { NotesManager.shared.openInNotes(note); NotesManager.shared.openInNotes(note) }"),
            // A thumbnail on every row, read from its file as the row draws.
            ("                NoteColorDot(note: note)\n                SettingsRowLabel(",
             "                NoteColorDot(note: note)\n                Image(nsImage: NSImage(contentsOf: NoteItem.noteImageDataDirectory) ?? NSImage())\n                SettingsRowLabel("),
        ], in: overview) { Self.workProblems(settings: settings, overview: $0, page: page) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            guard let fileName = note.imageFileName else {\n",
             "            NotesManager.shared.togglePin(note)\n            guard let fileName = note.imageFileName else {\n"),
            ("                image = fixture.images[note.id]\n", "                image = note.getImageData().flatMap { NSImage(data: $0) }\n"),
        ], in: page) { Self.workProblems(settings: settings, overview: overview, page: $0) }
    }

    // MARK: - Boards draw fixtures, never this Mac's notes

    /// A board draws made-up notes and never reads the real ones: they can be anything, and a full-screen Brain can be on
    /// a shared screen (layout-proposal.md §2 C). So with a fixture set, the settings' `onAppear` takes the fixture and
    /// returns before anything reads the notes or the sync, the `.task` returns before it subscribes, the note's page
    /// takes the fixture's image before it reaches a file, and the boards build their notes in memory, with no read of
    /// the saved notes, no manager and no image file.
    static func boardProblems(settings: String, page: String, boards: String) -> [String] {
        var problems: [String] = []
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        let appear = body(after: ".onAppear", following: ".onChange(of: enableNotes)", in: settingsCode)
        let fixture = appear.range(of: "if let fixture = NotesOverview.snapshotFixture {\n                data = fixture.data\n                openNoteID = fixture.openNoteID\n                return\n            }")
        let firstTouch = ["copyFromStores()", "Defaults[", "AppleNotesSyncManager", "NotesManager"]
            .compactMap { appear.range(of: $0)?.lowerBound }.min()
        if fixture == nil || firstTouch == nil || fixture!.upperBound > firstTouch! {
            problems.append("a board's page reaches the notes as it appears")
        }
        let task = body(after: ".task(id: visibility.isOnScreen)", in: settingsCode)
        if let early = task.range(of: "if NotesOverview.snapshotFixture != nil { return }"),
           let touch = task.range(of: "copyFromStores()"), early.upperBound < touch.lowerBound {
        } else {
            problems.append("a board's page can follow the notes")
        }
        let imageTask = body(after: ".task(id: imageKey)", in: SettingsDesignSystemRulesTests.code(page))
        if let early = imageTask.range(of: "image = fixture.images[note.id]\n                return"),
           let file = imageTask.range(of: "noteImageDataDirectory"), early.upperBound < file.lowerBound {
        } else {
            problems.append("a board's note page can read an image file")
        }
        let boardsCode = SettingsDesignSystemRulesTests.code(boards)
        for touch in ["Defaults[.savedNotes]", "NotesManager", "AppleNotesSyncManager", "noteImageDataDirectory", "getImageData("]
            where boardsCode.contains(touch) {
            problems.append("the boards reach this Mac's notes through \(touch)")
        }
        if !boardsCode.contains("NotesOverview.snapshotFixture = notesPage\n        var boards = SettingsView.snapshotTabs(filter: request.tabs)") {
            problems.append("the notes tab's board can draw before the fixture is set")
        }
        return problems
    }

    func testTheBoardsNeverReadThisMacsNotes() throws {
        let settings = try Self.source(Self.settingsPath)
        let page = try Self.source(Self.pagePath)
        let boards = try Self.source(Self.boardsPath)
        XCTAssertEqual(Self.boardProblems(settings: settings, page: page, boards: boards), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("                openNoteID = fixture.openNoteID\n                return\n", "                openNoteID = fixture.openNoteID\n"),
            ("            returnTo = nil\n            #if DEBUG\n            if let fixture",
             "            returnTo = nil\n            copyFromStores()\n            #if DEBUG\n            if let fixture"),
            ("            if NotesOverview.snapshotFixture != nil { return }\n", ""),
        ], in: settings) { Self.boardProblems(settings: $0, page: page, boards: boards) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("                image = fixture.images[note.id]\n                return\n", "                image = fixture.images[note.id]\n"),
        ], in: page) { Self.boardProblems(settings: settings, page: $0, boards: boards) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("        NotesOverview.snapshotFixture = notesPage\n        var boards",
             "        NotesOverview.snapshotFixture = notesPage\n        _ = Defaults[.savedNotes]\n        var boards"),
            ("        NotesOverview.snapshotFixture = notesPage\n        var boards = SettingsView.snapshotTabs(filter: request.tabs)",
             "        var boards = SettingsView.snapshotTabs(filter: request.tabs)\n        NotesOverview.snapshotFixture = notesPage"),
        ], in: boards) { Self.boardProblems(settings: settings, page: page, boards: $0) }
    }

    // MARK: - The page, its header and its swap

    /// Notes leads with its overview and its settings follow; its header carries the gear, which lands on the first
    /// settings row; a note's › opens its page in the tab, which opens at its top; each visit opens on the list, and a
    /// Notes search or deep link takes the tab back to the list, where it lands. A board's fixture may open a note after
    /// the visit's reset.
    static func wiringProblems(settings: String, view: String, overview: String) -> [String] {
        var problems: [String] = []
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        if settingsCode.range(of: #"SettingsProductPage\(settingsTitle: String\(localized: "Notes settings"\)\) \{\s*NotesOverview\(data: data, open: \{ openNoteID = \$0\.id \}, delete: delete\)\s*\} settings: \{"#,
                              options: .regularExpression) == nil {
            problems.append("Notes does not lead with its overview")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .notes, actions: AnyView(NotesHeaderActions())) {") {
            problems.append("Notes' header has no actions")
        }
        if !SettingsDesignSystemRulesTests.code(overview).contains("highlightID: SettingsDeepLink.notesEnableHighlightID")
            || !settingsCode.contains(".settingsHighlight(id: highlightID(\"Enable Notes\"))") {
            problems.append("the gear does not land on the first settings row")
        }
        if !settingsCode.contains("NotePage(note: note, isReadOnly: data.isReadOnly(note), delete: delete)")
            || !settingsCode.contains("TasksBackRow(parent: SettingsTab.notes.title) {")
            || !settingsCode.contains("            .id(openNoteID)\n") {
            problems.append("a note's page is not the in-tab swap, under its back row and opening at its top")
        }
        let appear = body(after: ".onAppear", following: ".onChange(of: enableNotes)", in: settingsCode)
        let reset = appear.range(of: "openNoteID = nil")
        let fixture = appear.range(of: "#if DEBUG")
        if reset == nil || fixture == nil || reset!.lowerBound > fixture!.lowerBound {
            problems.append("a visit does not open on the list")
        }
        let link = body(after: ".onChange(of: highlights.activeHighlightID, initial: true)", in: settingsCode)
        if !link.contains("id.hasPrefix(highlightID(\"\"))") || !link.contains("openNoteID = nil") || !link.contains("returnTo = id") {
            problems.append("a Notes search or deep link does not take the tab back to the list")
        }
        return problems
    }

    func testNotesIsAProductPageWithItsSwap() throws {
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.wiringProblems(settings: settings, view: view, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("                        NotesOverview(data: data, open: { openNoteID = $0.id }, delete: delete)\n", ""),
            ("            .id(openNoteID)\n", ""),
            // A note left open would come back whole on a reopened Brain, on a screen that can be shared.
            ("            openNoteID = nil\n            returnTo = nil\n            #if DEBUG", "            returnTo = nil\n            #if DEBUG"),
            ("            guard let id, id.hasPrefix(highlightID(\"\")), openNoteID != nil else { return }\n            openNoteID = nil\n",
             "            guard let id, id.hasPrefix(highlightID(\"\")), openNoteID != nil else { return }\n"),
            (".settingsHighlight(id: highlightID(\"Enable Notes\"))", ""),
        ], in: settings) { Self.wiringProblems(settings: $0, view: view, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(NotesHeaderActions())", "")], in: view) {
            Self.wiringProblems(settings: settings, view: $0, overview: overview)
        }
    }

    // MARK: - New note's sheet

    private static let sheetPath = "Kannu/components/Settings/NewNoteSheet.swift"

    /// New note (layout-proposal.md §5 item 7) writes one thing, a new note, and only on Add (Return in the title, ⌘Return
    /// in the text, whose Return is its own): through `NotesManager.save`, the notes' one write path, never with no
    /// title and no text, and under one id for the sheet, so Return reaching both the title and Add saves it once. It observes nothing, keeps no clock, and its one
    /// hook focuses the title. The sheet opens only on a press of New note, the header's while Notes is on, or the empty
    /// state's.
    static func sheetProblems(sheet: String, overview: String) -> [String] {
        var problems: [String] = []
        let code = SettingsDesignSystemRulesTests.code(sheet)
        if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject|Default)\b"#, in: code).isEmpty {
            problems.append("the sheet observes a store or a setting")
        }
        let names = managerNames(in: code)
        let add = body(after: "private func add()", in: code)
        if names != ["save"] || !add.contains("NotesManager.shared.save(NotesManager.Draft(id: noteID,") {
            problems.append("the sheet writes other than one save, from Add")
        }
        if let guardRange = add.range(of: "guard !isEmpty else { return }"), let save = add.range(of: "NotesManager.shared.save("),
           guardRange.upperBound < save.lowerBound {
        } else {
            problems.append("the sheet can save a note with no title and no text")
        }
        if !code.contains("@State private var noteID = UUID()") {
            problems.append("the sheet saves under a new id each time, so one Return can save twice")
        }
        if count("add", in: code.replacingOccurrences(of: "private func add()", with: "")) != 2
            || !code.contains("Button(\"Add\", action: add)") || count(".onSubmit(add)", in: code) != 1
            || !code.contains(".focused($focused, equals: .title)\n                .onSubmit(add)") {
            problems.append("the sheet saves other than from Add and the title's Return")
        }
        // The text runs to several lines: a Return there must not save it half typed (the review's second pass, S1).
        if !code.contains(".keyboardShortcut(focused == .text ? KeyboardShortcut(.return, modifiers: .command) : .defaultAction)") {
            problems.append("Return in the text can save the note")
        }
        if count(".onAppear", in: code) != 1 || body(after: ".onAppear", in: code).trimmingCharacters(in: .whitespaces) != "focused = .title"
            || code.contains(".task") {
            problems.append("the sheet has a hook beyond focusing its title")
        }
        problems += clockProblems(in: sheet)
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        if count("showsNewNote = true", in: overviewCode) != 2 || count("Button(\"New note\") { showsNewNote = true }", in: overviewCode) != 2
            || count(".sheet(isPresented: $showsNewNote) { NewNoteSheet() }", in: overviewCode) != 2 {
            problems.append("New note's sheet opens other than on a press of New note")
        }
        if !overviewCode.contains("if enabled {\n                Button(\"New note\") { showsNewNote = true }") {
            problems.append("the header offers New note while Notes is off")
        }
        return problems
    }

    func testNewNoteSavesOnlyOnAdd() throws {
        let sheet = try Self.source(Self.sheetPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.sheetProblems(sheet: sheet, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("        guard !isEmpty else { return }\n", ""),
            ("Draft(id: noteID,", "Draft(id: UUID(),"),
            (".onAppear { focused = .title }", ".onAppear { focused = .title; add() }"),
            ("                .focused($focused, equals: .text)\n",
             "                .focused($focused, equals: .text)\n                .onChange(of: text) { _, _ in add() }\n"),
            // The text's Return saving the note again, through its submit or through Add's default action.
            ("                .focused($focused, equals: .text)\n", "                .focused($focused, equals: .text)\n                .onSubmit(add)\n"),
            (".keyboardShortcut(focused == .text ? KeyboardShortcut(.return, modifiers: .command) : .defaultAction)",
             ".keyboardShortcut(.defaultAction)"),
            ("    @State private var noteID = UUID()\n", "    @State private var noteID = UUID()\n    @ObservedObject private var sync = AppleNotesSyncManager.shared\n"),
            ("        dismiss()\n    }\n}", "        NotesManager.shared.syncWithAppleNotes()\n        dismiss()\n    }\n}"),
            (".lineLimit(4...12)", ".lineLimit(4...12)\n                .animation(.default, value: text)"),
        ], in: sheet) { Self.sheetProblems(sheet: $0, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([
            // Opened as the page appears, with no press.
            ("        .sheet(isPresented: $showsNewNote) { NewNoteSheet() }\n    }\n\n    /// One line above",
             "        .sheet(isPresented: $showsNewNote) { NewNoteSheet() }\n        .onAppear { showsNewNote = true }\n    }\n\n    /// One line above"),
            ("            if enabled {\n                Button(\"New note\") { showsNewNote = true }\n                    .buttonStyle(SettingsButtonStyle(.primary))\n            }\n",
             "            Button(\"New note\") { showsNewNote = true }\n                .buttonStyle(SettingsButtonStyle(.primary))\n"),
        ], in: overview) { Self.sheetProblems(sheet: sheet, overview: $0) }
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
