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

import SwiftUI
import Defaults

struct NotchNotesView: View {
    @Environment(\.notchForeground) private var notchForeground
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @FocusState private var isFocused: Bool
    @Default(.savedNotes) var savedNotes
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableAppleNotesSync) var enableAppleNotesSync
    @Default(.appleNotesSyncScope) var appleNotesSyncScope
    @Default(.enableWisprFlowMeetings) var enableWisprFlowMeetings
    @Default(.wisprMeetingTags) var wisprMeetingTags
    @Default(.enableNoteColorFiltering) var enableNoteColorFiltering
    @ObservedObject private var wisprMeetings = WisprFlowMeetingsManager.shared

    @State private var selectedNoteId: UUID?
    /// The open note is a Wispr Flow meeting's summary: shown, never saved (`NoteItem.wisprMeetingId`).
    /// Kept as state, not looked up, so a refresh that drops the meeting cannot make it savable.
    @State private var editorIsWisprMeeting = false
    @State private var isEditingNewNote = false
    
    // Editor State
    @State private var editorTitle: String = ""
    @State private var editorContent: String = ""
    @State private var editorImageData: Data? = nil
    @State private var editorColorIndex: Int = 0
    @State private var editorNoteId: UUID?
    /// Made from the clipboard and not saved yet: no autosave, and leaving drops it.
    @State private var editorIsDraft = false
    /// The open note's tags (`NoteTagsRow`), written as they are edited, never as a note opens.
    @State private var editorTags: [String] = []
    /// What is typed in "Add tag" and not added yet: Done, back and the notch closing add it.
    @State private var editorTagDraft = ""
    /// Where the open note's tags are kept, decided as it opens: a saved (or about to be saved) note,
    /// or a Wispr Flow meeting by its meeting id.
    @State private var editorTagTarget: TagTarget = .note(UUID())
    /// The title as the note opened: a `#word` already in it stays in the title (`takeTitleTags`).
    @State private var editorTitleAtOpen = ""
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var scrollSuppressionToken = UUID()
    @State private var isSuppressingScroll = false

    @Default(.enableNotes) var enableNotes
    
    var showSplitView: Bool {
        return enableClipboardManager && clipboardDisplayMode == .separateTab
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSplitView {
                NotchClipboardList()
                    .frame(maxWidth: .infinity)
                
                if enableNotes {
                    Divider()
                        .background(notchForeground.opacity(0.15))
                }
            }
            
            if enableNotes {
                ZStack {
                    if isEditingNewNote || selectedNoteId != nil {
                        NoteEditorView(
                            title: $editorTitle,
                            content: $editorContent,
                            imageData: $editorImageData,
                            colorIndex: $editorColorIndex,
                            onSave: saveNote,
                            onCancel: cancelEdit,
                            isNew: isEditingNewNote,
                            isReadOnly: editorIsReadOnly,
                            onOpenInNotes: openEditorNoteInNotes,
                            onDelete: editorStoredNote == nil ? nil : deleteEditorNote,
                            deletesInAppleNotes: editorIsReadOnly && !editorIsWisprMeeting,
                            opensInWisprFlow: editorIsWisprMeeting,
                            tags: editorTags,
                            tagDraft: $editorTagDraft,
                            onTagsEdited: tagsEdited,
                            onCommitTitle: takeTitleTags
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else {
                        NoteListView(
                            notes: listNotes,
                            // Beside the clipboard a card's title has no room to share with a chip.
                            showsCardTags: !showSplitView,
                            onSelect: selectNote,
                            onCreate: createNote,
                            onDeleteItem: { NotesManager.shared.delete($0) },
                            onClearAll: { NotesManager.shared.clearAll() },
                            onTogglePin: { NotesManager.shared.togglePin($0) },
                            onCreateFromClipboard: createNoteFromClipboard,
                            onSync: {
                                NotesManager.shared.syncWithAppleNotes()
                                WisprFlowMeetingsManager.shared.refresh()
                            }
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped() // Prevent overflow during transition
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditingNewNote)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedNoteId)
                .overlay {
                    // Hidden button for Cmd+V paste listener
                    Button("") {
                        handlePaste()
                    }
                    .keyboardShortcut("v", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
        // List, editor, split view and divider: a vertical scroll anywhere here is the notes', never
        // the notch's close gesture (docs/REGRESSIONS.md entry 21). The hover token is the second
        // guard, and the only one the editor had was none.
        .ownsVerticalScroll()
        .onHover { hovering in
            updateScrollSuppression(for: hovering)
        }
        .onAppear {
            updateLayoutState()
            NotesManager.shared.syncWithAppleNotes()
            WisprFlowMeetingsManager.shared.refresh()
        }
        .onChange(of: enableAppleNotesSync) { _, isEnabled in
            if isEnabled {
                NotesManager.shared.syncWithAppleNotes()
            }
        }
        .onChange(of: enableWisprFlowMeetings) { _, _ in
            // On: read the meetings. Off: empty the list.
            WisprFlowMeetingsManager.shared.refresh()
        }
        .onDisappear {
            updateScrollSuppression(for: false)
            // The notch closing keeps an edit and drops a draft, as "< Notes" does.
            if isEditing && !editorIsDraft {
                commitTagEdits()
                persistNote()
                keepNewNoteInView()
            }
            coordinator.notesLayoutState = .list
        }
        .onChange(of: isEditingNewNote) { _, _ in
            updateLayoutState()
        }
        .onChange(of: selectedNoteId) { _, _ in
            updateLayoutState()
        }
        .onChange(of: enableClipboardManager) { _, _ in
            updateLayoutState()
        }
        .onChange(of: clipboardDisplayMode) { _, _ in
            updateLayoutState()
        }
        .onChange(of: enableNotes) { _, _ in
            updateLayoutState()
        }
        .onChange(of: editorContent) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: editorTitle) { previous, title in
            // A `#word` leaves the title for the tags once a space typed at the end ends it. Only a space
            // just added at the end: a title that merely ends in one must not take a `#` typed elsewhere
            // in it, or the half-typed word after it.
            if title.count == previous.count + 1, title.hasPrefix(previous), let last = title.last, last.isWhitespace {
                takeTitleTags()
            }
            scheduleAutoSave()
        }
        .onChange(of: editorColorIndex) { _, _ in
            scheduleAutoSave()
        }
    }
    
    // MARK: - Actions

    private var isEditing: Bool { isEditingNewNote || selectedNoteId != nil }

    /// Kannu's notes, then Wispr Flow's meeting summaries while that setting is on, each with the tags
    /// Kannu keeps for it by meeting id. Only the list sees the meetings: every write below goes through
    /// `NotesManager`.
    private var listNotes: [NoteItem] {
        guard enableWisprFlowMeetings else { return savedNotes }
        return savedNotes + wisprMeetings.notes.map { meeting in
            var tagged = meeting
            tagged.tags = wisprMeetingTags[meeting.wisprMeetingId ?? ""] ?? []
            return tagged
        }
    }

    /// Where an open note's tags go.
    private enum TagTarget: Equatable {
        /// A note in `savedNotes`, or one about to be: `setTags` waits for its first save.
        case note(UUID)
        /// A Wispr Flow meeting, by its meeting id (`wisprMeetingTags`).
        case meeting(String)
    }

    /// The notch filter as it applies now, for what "+" starts a note with.
    private var effectiveFilter: NoteFilter {
        NoteFilter.stored.effective(offering: NoteFilter.sourceChoices(listNotes.map(\.filterFacets)),
                                    colorFiltering: enableNoteColorFiltering)
    }

    /// A tag added or removed in the editor, kept at once where the open note's tags live.
    private func tagsEdited(_ tags: [String]) {
        editorTags = tags
        switch editorTagTarget {
        case .note(let id): NotesManager.shared.setTags(tags, forNote: id)
        case .meeting(let meetingId): NotesManager.shared.setTags(tags, forWisprMeeting: meetingId)
        }
    }

    /// What "Add tag" still holds, added as Return would add it, so leaving the editor never loses it.
    private func commitPendingTag() {
        let typed = editorTagDraft
        editorTagDraft = ""
        guard TaskTagEditing.cleaned(typed) != nil else { return }
        let suggestions = TaskTagEditing.suggestions(for: typed, existing: SharedTags.inUse(), current: editorTags)
        guard let pick = TaskTagEditing.returnPick(for: typed, in: suggestions) else { return }
        tagsEdited(TaskTagEditing.adding(pick.tag, to: editorTags))
    }

    /// `#word`s typed into the title since the note opened become tags (`TaskQuickAdd.takingNewTags`):
    /// a space after one, Return, leaving the title, Done, back and the notch closing. Never from the
    /// autosave, which would take "#ac" half typed, and never on a read-only note, whose title is not
    /// a field. A word the title had when it opened stays: Apple Notes' own `#tag`s survive a sync.
    private func takeTitleTags() {
        guard isEditing, !editorIsReadOnly else { return }
        let taken = TaskQuickAdd.takingNewTags(from: editorTitle, openedWith: editorTitleAtOpen,
                                               room: TaskItem.maxTags - editorTags.count)
        guard !taken.tags.isEmpty else { return }
        editorTitle = taken.title
        tagsEdited(TaskItem.cleanedTags(editorTags + taken.tags))
    }

    /// Both before a save: the title's `#word`s, then a tag still being typed.
    private func commitTagEdits() {
        takeTitleTags()
        commitPendingTag()
    }

    /// A note just made never vanishes from the list it was made in: each part of the notch filter it
    /// fails is cleared (`NoteFilter.keeping`). Only for a new note that was saved; not on delete.
    private func keepNewNoteInView() {
        guard isEditingNewNote, let id = editorNoteId, Defaults[.savedNotes].contains(where: { $0.id == id }) else { return }
        let made = NoteFilter.Facets(source: .kannu, tags: editorTags, colorIndex: editorColorIndex)
        // Only parts that apply now: a colour kept while colour filtering is off, or a source not offered,
        // hides nothing, so it stays for when it does.
        NoteFilter.stored = NoteFilter.stored.keeping(made, activeAs: effectiveFilter)
    }

    /// The open note is a Wispr Flow meeting, or was made in Notes while sync reads the whole
    /// account: shown, not edited.
    private var editorIsReadOnly: Bool {
        if editorIsWisprMeeting { return true }
        guard let id = selectedNoteId, let note = savedNotes.first(where: { $0.id == id }) else { return false }
        return note.isReadOnlyMirror(syncEnabled: enableAppleNotesSync, scope: appleNotesSyncScope)
    }

    private func openEditorNoteInNotes() {
        if editorIsWisprMeeting {
            WisprFlowMeetingsManager.shared.openWisprFlow()
            return
        }
        guard let id = selectedNoteId, let note = savedNotes.first(where: { $0.id == id }) else { return }
        NotesManager.shared.openInNotes(note)
    }

    /// The open note as stored. Nil for a draft, or a new note not saved yet: nothing to delete.
    private var editorStoredNote: NoteItem? {
        guard !editorIsDraft, let id = editorNoteId else { return nil }
        return savedNotes.first(where: { $0.id == id })
    }

    /// The editor's trash: the note goes, here and in Notes, and the editor closes without saving
    /// it back.
    private func deleteEditorNote() {
        guard let note = editorStoredNote else { return }
        closeEditor()
        NotesManager.shared.delete(note)
    }

    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        // A read-only note's text and image are not edited here, but its tags are: text goes to the
        // field that has focus ("Add tag"), and nothing else is taken.
        if editorIsReadOnly {
            if pasteboard.string(forType: .string) != nil {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            return
        }
        
        // Check for file URLs first (higher quality source than icons)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
            if let firstImageURL = fileURLs.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
               let imageData = try? Data(contentsOf: firstImageURL) {
                updateImageData(imageData)
                return
            }
        }
        
        // Then direct image data
        if let tiffData = pasteboard.data(forType: .tiff) {
            updateImageData(tiffData)
            return
        } else if let pngData = pasteboard.data(forType: .png) {
            updateImageData(pngData)
            return
        }
        
        // Handle text paste
        if let text = pasteboard.string(forType: .string) {
            if isEditing {
                // The shortcut is intercepted here, so hand the paste to whichever field has focus:
                // it lands at the cursor, in the title or the text. Only with no field focused does
                // it go to the end of the text.
                if !NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                    editorContent.append(text)
                }
            } else {
                // Not in editor: a draft of a new note with the pasted text
                createDraft(content: text)
            }
        }
    }

    private func updateImageData(_ data: Data) {
        withAnimation {
            if isEditing {
                editorImageData = data
            } else {
                // If not editing, a draft of a new note with this image
                createDraft(content: "", imageData: data)
            }
        }
    }

    /// A note made from the clipboard (the button, or Cmd+V in the list) is a draft: nothing is saved
    /// until Done, and going back or closing the notch drops it.
    private func createDraft(content: String, imageData: Data? = nil) {
        editorTitle = ""
        editorContent = content
        editorImageData = imageData
        editorColorIndex = effectiveFilter.newNoteColorIndex ?? 0
        editorNoteId = UUID()
        editorIsDraft = true
        editorIsWisprMeeting = false
        openTags(of: nil)
        isEditingNewNote = true
    }
    
    private func createNote() {
        editorTitle = ""
        editorContent = ""
        editorImageData = nil
        editorColorIndex = effectiveFilter.newNoteColorIndex ?? 0 // Yellow, or the colour filtered on
        editorNoteId = UUID()
        editorIsDraft = false
        editorIsWisprMeeting = false
        openTags(of: nil)
        isEditingNewNote = true
    }
    
    private func selectNote(_ note: NoteItem) {
        editorTitle = note.title
        editorContent = note.content
        editorImageData = note.getImageData() // Load from disk
        editorColorIndex = note.colorIndex
        editorNoteId = note.id
        editorIsDraft = false
        editorIsWisprMeeting = note.isWisprMeeting
        openTags(of: note)
        selectedNoteId = note.id
        isEditingNewNote = false
    }

    /// The tag state for a note opening, `nil` for a new one: it starts with the tag filtered on, so it
    /// is listed. Writes nothing: only an edit does (`tagsEdited`).
    private func openTags(of note: NoteItem?) {
        editorTagDraft = ""
        editorTitleAtOpen = note?.title ?? ""
        if let note {
            editorTags = note.tags
            editorTagTarget = note.wisprMeetingId.map(TagTarget.meeting) ?? .note(note.id)
        } else {
            editorTags = effectiveFilter.newNoteTags
            editorTagTarget = .note(editorNoteId ?? UUID())
        }
    }

    /// Saves the editor's note. `NotesManager` writes nothing when nothing changed, so opening a note
    /// and going back no longer moves it to the top of the list. A Wispr Flow meeting is never saved:
    /// its id is not in `savedNotes`, so a save would store it as a new note of Kannu's.
    private func persistNote() {
        guard let id = editorNoteId, !editorIsWisprMeeting else { return }
        NotesManager.shared.save(NotesManager.Draft(
            id: id,
            title: editorTitle,
            content: editorContent,
            imageData: editorImageData,
            colorIndex: editorColorIndex
        ))
        // A new note's tags, once its first save has made it; no change for one already saved.
        NotesManager.shared.setTags(editorTags, forNote: id)
    }

    private func scheduleAutoSave() {
        guard isEditing, !editorIsDraft, !editorIsWisprMeeting else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistNote()
            }
        }
    }

    /// Done: the one way a draft is saved.
    private func saveNote() {
        commitTagEdits()
        persistNote()
        keepNewNoteInView()
        closeEditor()
    }

    /// "< Notes": an edit is kept, a draft is dropped.
    private func cancelEdit() {
        if !editorIsDraft {
            commitTagEdits()
            persistNote()
            keepNewNoteInView()
        }
        closeEditor()
    }
    
    private func createNoteFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Priority 1: Check for real image files (highest quality)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
            if let firstImageURL = fileURLs.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
               let imageData = try? Data(contentsOf: firstImageURL) {
                createDraft(content: "", imageData: imageData)
                return
            }
        }
        
        // Priority 2: Direct image data
        if let tiffData = pasteboard.data(forType: .tiff) {
            createDraft(content: "", imageData: tiffData)
            return
        } else if let pngData = pasteboard.data(forType: .png) {
            createDraft(content: "", imageData: pngData)
            return
        }
        
        if let text = pasteboard.string(forType: .string) {
            createDraft(content: text)
        }
    }
    
    private func closeEditor() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        isEditingNewNote = false
        selectedNoteId = nil
        editorIsDraft = false
        editorIsWisprMeeting = false
        // Tiny delay to clear state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            editorTitle = ""
            editorContent = ""
        }
        updateLayoutState()
    }

    private func updateScrollSuppression(for hovering: Bool) {
        guard hovering != isSuppressingScroll else { return }
        isSuppressingScroll = hovering
        vm.setScrollGestureSuppression(hovering, token: scrollSuppressionToken)
    }

    private func updateLayoutState() {
        let newState: NotesLayoutState
        if enableNotes && (isEditingNewNote || selectedNoteId != nil) {
            newState = .editor
        } else if showSplitView {
            newState = .split
        } else {
            newState = .list
        }

        if coordinator.notesLayoutState != newState {
            coordinator.notesLayoutState = newState
        }
    }
}

// MARK: - Subviews

struct NotchClipboardList: View {
    @Environment(\.notchFill) private var notchFill
    @Environment(\.notchForeground) private var notchForeground
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var hoveredItemId: UUID?
    @State private var justCopiedId: UUID?
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    @State private var showClearHistoryAlert = false
    @State private var autoCloseToken = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Clipboard")
                    .font(SettingsTheme.font(size: 18, weight: .semibold))
                    .foregroundStyle(notchForeground)
                
                Spacer()
                
                if !clipboardManager.clipboardHistory.isEmpty {
                    Button(action: { showClearHistoryAlert = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .padding(6)
                            .background(notchForeground.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(String(localized: "Clear History"), edge: .below)
                    .accessibilityLabel(String(localized: "Clear History"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            
            if clipboardManager.clipboardHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("No copies yet")
                        .font(SettingsTheme.font(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Copy text to see it here")
                        .font(SettingsTheme.font(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30) // Add padding so it's not touching header
            } else {
                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 4) { // Tighter spacing
                            ForEach(clipboardManager.clipboardHistory) { item in
                                NotchClipboardItemRow(
                                    item: item,
                                    isHovered: hoveredItemId == item.id,
                                    justCopied: justCopiedId == item.id
                                )
                                .contentShape(Rectangle())
                                .onHover { isHovered in
                                    hoveredItemId = isHovered ? item.id : nil
                                }
                                .onTapGesture {
                                    clipboardManager.copyToClipboard(item)
                                    withAnimation {
                                        justCopiedId = item.id
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if justCopiedId == item.id {
                                            withAnimation {
                                                justCopiedId = nil
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }

                    LinearGradient(colors: [(notchFill ?? .black).opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .top)

                    LinearGradient(colors: [.clear, (notchFill ?? .black).opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Clear History", role: .destructive) {
                clipboardManager.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved clipboard item from the notch tab.")
        }
        .onChange(of: showClearHistoryAlert) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
        .onAppear {
            if !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

struct NotchClipboardItemRow: View {
    @Environment(\.notchForeground) private var notchForeground
    let item: ClipboardItem
    let isHovered: Bool
    let justCopied: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if item.type == .image, let data = item.getImageData(), let nsImage = NSImage(data: data) {
                 Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(notchForeground.opacity(0.1), lineWidth: 0.5))
            } else {
                Image(systemName: justCopied ? "checkmark.circle.fill" : item.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(justCopied ? .green : .blue)
                    .frame(width: 20)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(SettingsTheme.font(size: 13))
                    .foregroundStyle(notchForeground)
                    .lineLimit(1)
                
                HStack {
                    Text(item.type.displayName)
                        .font(SettingsTheme.font(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeAgoString(from: item.timestamp))
                        .font(SettingsTheme.font(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.3 : 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "Just now") }
        if interval < 3600 { return String(localized: "\(Int(interval/60))m") }
        return String(localized: "\(Int(interval/3600))h")
    }
}


struct NoteListView: View {
    @Environment(\.notchFill) private var notchFill
    @Environment(\.notchForeground) private var notchForeground
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    let notes: [NoteItem]
    /// Cards show "#first +N" after the title; not in split view, where a card is too narrow.
    var showsCardTags = true
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void
    let onDeleteItem: (NoteItem) -> Void
    let onClearAll: () -> Void
    let onTogglePin: (NoteItem) -> Void
    let onCreateFromClipboard: () -> Void
    let onSync: () -> Void

    @Default(.enableNoteSearch) var enableNoteSearch
    @Default(.enableNoteColorFiltering) var enableNoteColorFiltering
    @Default(.enableCreateFromClipboard) var enableCreateFromClipboard
    @Default(.enableAppleNotesSync) var enableAppleNotesSync
    @Default(.appleNotesSyncScope) var appleNotesSyncScope
    /// The filter, kept so the list comes back filtered after a note, a close or a relaunch (`NoteFilter`).
    @Default(.notesNotchSourceFilter) var sourceFilter
    @Default(.notesNotchTagFilter) var tagFilter
    @Default(.notesNotchColorFilter) var colorFilter
    
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    @State private var showClearNotesAlert = false
    @State private var autoCloseToken = UUID()

    /// What the filter reads from each listed note, once per redraw.
    private var facets: [NoteFilter.Facets] { notes.map(\.filterFacets) }

    /// The kept filter as it applies now: a source not offered is every source, and the colour sleeps
    /// while colour filtering is off (`NoteFilter.effective`).
    private func effective(offering sources: [NoteSource]) -> NoteFilter {
        NoteFilter(source: sourceFilter, tag: tagFilter, colorIndex: colorFilter)
            .effective(offering: sources, colorFiltering: enableNoteColorFiltering)
    }

    func sortedNotes(_ filter: NoteFilter) -> [NoteItem] {
        let searched = searchText.isEmpty ? notes : notes.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText) || 
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
        // A Wispr Flow meeting has no colour of its own, so no colour filter shows it.
        let filtered = filter.isNarrowing ? searched.filter { filter.matches($0.filterFacets) } : searched
        
        return filtered.sorted { 
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.modificationDate > $1.modificationDate
        }
    }

    /// The notes stored in Kannu: what Clear Notes reaches. Wispr Flow's meetings are only shown.
    private var storedNotes: [NoteItem] { notes.filter { !$0.isWisprMeeting } }

    /// The note's tags for its card, the one filtered on first, so the chip shown is that tag.
    private func chipTags(_ note: NoteItem, _ filter: NoteFilter) -> [String] {
        filter.tag == TaskFacets.anyTag ? note.tags : TaskTagEditing.movingToFront(filter.tag, in: note.tags)
    }

    /// Show all: every source, tag and colour.
    private func showAll() {
        NoteFilter.stored = .all
    }

    /// "Filtered · Show all", while the filter narrows the list, so nothing seems missing (the Tasks
    /// popover's line). On its own line: in split view the header has no room for it.
    private var filteredLine: some View {
        HStack(spacing: 4) {
            Text("Filtered")
                .foregroundStyle(.secondary)
            Text(verbatim: "·")
                .foregroundStyle(.secondary)
            Button(String(localized: "Show all"), action: showAll)
                .buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .font(SettingsTheme.font(size: 11, weight: .medium))
    }

    /// Why the list is empty: no notes at all, a search, or the filter.
    private func emptyState(_ filter: NoteFilter) -> (symbol: String, text: String) {
        if notes.isEmpty { return ("note.text", String(localized: "No notes yet")) }
        if !searchText.isEmpty { return ("magnifyingglass", String(localized: "No results found")) }
        if filter.isNarrowing { return ("line.3.horizontal.decrease", String(localized: "No notes match the filter")) }
        return ("note.text", String(localized: "No notes yet"))
    }

    var body: some View {
        let facets = facets
        let sources = NoteFilter.sourceChoices(facets)
        let filter = effective(offering: sources)
        let tagChoices = filter.tagChoices(facets)
        let sortedNotes = sortedNotes(filter)
        // Something to pick, or a filter to clear.
        let showsFilterMenu = !sources.isEmpty || !tagChoices.isEmpty
            || (enableNoteColorFiltering && !notes.isEmpty) || filter.isNarrowing
        return VStack(spacing: 0) {
            // Header. The "+" is the panel's one filled control and stands alone at the header's right end, the
            // top-right power point of the panel's golden triangle; the rest are plain glyphs grouped before it, and
            // nothing in the header is red or yellow, which in the notch mean an agent stopped or needs input.
            HStack {
                Text("Notes")
                    .font(SettingsTheme.font(size: 16, weight: .semibold))
                    .foregroundStyle(notchForeground)

                if enableAppleNotesSync {
                    // The sync's state and its button in one: the Apple logo, or the arrows turning while it runs.
                    Button(action: onSync) {
                        Image(systemName: appleNotesSync.isSyncing ? "arrow.triangle.2.circlepath" : "apple.logo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appleNotesSync.isSyncing ? SettingsTheme.accent : notchForeground.opacity(0.45))
                            .rotationEffect(.degrees(appleNotesSync.isSyncing ? 360 : 0))
                            .animation(
                                appleNotesSync.isSyncing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: appleNotesSync.isSyncing
                            )
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(appleNotesSync.isSyncing)
                    .hoverTooltip(String(localized: "Sync with Apple Notes"), edge: .below)
                    .accessibilityLabel(String(localized: "Sync with Apple Notes"))
                }
                
                Spacer()

                HStack(spacing: 2) {
                    // First: it comes and goes, and pushes nothing to its right.
                    if showsFilterMenu {
                        NoteFilterMenu(
                            sources: sources,
                            tags: tagChoices,
                            showsColors: enableNoteColorFiltering,
                            isNarrowing: filter.isNarrowing,
                            source: Binding(get: { filter.source }, set: { sourceFilter = $0 }),
                            tag: Binding(get: { filter.tag }, set: { tagFilter = $0 }),
                            colorIndex: Binding(get: { filter.colorIndex }, set: { colorFilter = $0 }),
                            showAll: showAll
                        )
                    }

                    if enableNoteSearch {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isSearchExpanded.toggle()
                            }
                        }) {
                            headerGlyph("magnifyingglass", weight: isSearchExpanded ? .bold : .medium,
                                        tint: isSearchExpanded ? SettingsTheme.accent : nil)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverTooltip(String(localized: "Search Notes"), edge: .below)
                        .accessibilityLabel(String(localized: "Search Notes"))
                    }

                    if enableCreateFromClipboard {
                        Button(action: onCreateFromClipboard) {
                            headerGlyph("doc.on.clipboard")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverTooltip(String(localized: "Create from Clipboard"), edge: .below)
                        .accessibilityLabel(String(localized: "Create from Clipboard"))
                    }

                    if !storedNotes.isEmpty {
                        // Neutral here: the alert it opens is where Delete is red.
                        Button(action: { showClearNotesAlert = true }) {
                            headerGlyph("trash")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverTooltip(String(localized: "Clear Notes"), edge: .below)
                        .accessibilityLabel(String(localized: "Clear Notes"))
                    }
                }
                .padding(.trailing, 10)

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(notchFill ?? .black)
                        .padding(5)
                        .background(notchForeground.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .hoverTooltip(String(localized: "New Note"), edge: .below)
                .accessibilityLabel(String(localized: "New Note"))
            }
            .padding(.horizontal, 16) // Reduced from 20
            .padding(.top, 8)
            .padding(.bottom, isSearchExpanded ? 4 : 2)

            if filter.isNarrowing {
                filteredLine
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            if isSearchExpanded {
                VStack(spacing: 6) {
                    if enableNoteSearch && !notes.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextField("Search notes...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(SettingsTheme.font(size: 12))
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .hoverTooltip(String(localized: "Clear Search"), edge: .below)
                                .accessibilityLabel(String(localized: "Clear Search"))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4) // Reduced from 6
                        .background(notchForeground.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.bottom, 10)
            }
            if sortedNotes.isEmpty {
                let empty = emptyState(filter)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: empty.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text(empty.text)
                            .font(SettingsTheme.font(size: 12, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .padding(.top, 10)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ScrollView {
                        let useGrid = sortedNotes.count > 3
                        let columns = useGrid ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] : [GridItem(.flexible())]
                        
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(sortedNotes) { note in
                                NoteRow(
                                    note: note, 
                                    onDelete: { onDeleteItem(note) },
                                    onTogglePin: { onTogglePin(note) },
                                    isCompact: useGrid,
                                    deletesInAppleNotes: note.isReadOnlyMirror(syncEnabled: enableAppleNotesSync, scope: appleNotesSyncScope),
                                    chipTags: showsCardTags ? chipTags(note, filter) : []
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(note)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }

                    LinearGradient(colors: [(notchFill ?? .black).opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .top)

                    LinearGradient(colors: [.clear, (notchFill ?? .black).opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .alert("Delete All Notes?", isPresented: $showClearNotesAlert) {
            Button("Delete", role: .destructive) {
                onClearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearNotesMessage)
        }
        .onChange(of: showClearNotesAlert) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
    }

    /// A secondary header control: a plain glyph, no circle, so only "+" reads as a button from across the panel.
    private func headerGlyph(_ systemName: String, weight: Font.Weight = .medium, tint: Color? = nil) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(tint ?? notchForeground.opacity(0.55))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }

    /// Says what Clear Notes reaches: synced notes go to Notes' Recently Deleted too, and notes made in
    /// Notes (shown read-only) stay.
    private var clearNotesMessage: String {
        let counts = NotesManager.shared.clearAllCounts()
        var message = String(localized: "This permanently removes \(counts.removed) notes and their attachments.")
        if counts.inAppleNotes > 0 {
            message += " " + String(localized: "\(counts.inAppleNotes) of them also move to Recently Deleted in Apple Notes.")
        }
        if counts.removed < storedNotes.count {
            message += " " + String(localized: "Notes made in Apple Notes stay.")
        }
        return message
    }
}

struct NoteRow: View {
    @EnvironmentObject var vm: KannuViewModel
    @Environment(\.notchFill) private var notchFill
    @Environment(\.notchForeground) private var notchForeground
    let note: NoteItem
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let isCompact: Bool
    /// A note made in Notes and shown read-only: deleting it here sends it to Recently Deleted in
    /// Notes as well, so the trash asks first.
    var deletesInAppleNotes = false
    /// The note's tags, in the order to show them (the one filtered on first): "#first +N" after the
    /// title, which wins when the card is narrow (`TaskTagChips`). Neutral chips: the bar is the card's
    /// one colour.
    var chipTags: [String] = []
    @State private var confirmDelete = false
    /// Holds the notch open while the delete confirmation shows.
    @State private var autoCloseToken = UUID()
    @State private var isHovered = false
    @State private var isCopied = false
    /// Read from disk once per image, off the main thread: reading it in `body` did it on every
    /// redraw, which a scroll or a hover causes many times a second.
    @State private var thumbnail: NSImage?
    @Default(.enableNotePinning) var enableNotePinning

    /// Changes when the note's image does (the file keeps its name when the image is replaced).
    private var thumbnailKey: String {
        "\(note.imageFileName ?? "")|\(note.modificationDate.timeIntervalSince1970)"
    }

    private var pinTooltip: String {
        note.isPinned ? String(localized: "Unpin Note") : String(localized: "Pin Note")
    }

    /// The title the card shows: a note left as "Untitled Note" shows its first line instead (`NoteDisplayText`).
    private var shownTitle: String {
        NoteDisplayText.title(title: note.title, content: note.content, untitled: String(localized: "Untitled Note"))
    }

    /// The text after that title on one line, without a first line that only says the title again.
    private var shownPreview: String {
        NoteDisplayText.preview(title: shownTitle, content: note.content)
    }

    /// The note's colour, or a neutral bar for a Wispr Flow meeting, which has none of its own.
    private var barColor: Color {
        note.isWisprMeeting ? notchForeground.opacity(0.3) : note.color
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: isCompact ? 8 : 12) {
                // Color Indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: isCompact ? 3 : 4)
                    .padding(.vertical, isCompact ? 4 : 2)

                VStack(alignment: .leading, spacing: isCompact ? 1 : 4) {
                    HStack(spacing: 4) {
                        if note.isWisprMeeting {
                            Image(systemName: "waveform")
                                .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                                .foregroundStyle(notchForeground.opacity(0.55))
                                .accessibilityLabel(String(localized: "From Wispr Flow"))
                        } else if note.isPinned {
                            // Neutral: the bar is the card's one colour.
                            Image(systemName: "pin.fill")
                                .font(.system(size: isCompact ? 7 : 8))
                                .foregroundStyle(notchForeground.opacity(0.55))
                        }
                        TaskTagChips(tags: chipTags) {
                            Text(shownTitle)
                                .font(SettingsTheme.font(size: isCompact ? 12 : 14, weight: .semibold))
                                .foregroundStyle(notchForeground)
                                .lineLimit(1)
                        }
                    }
                    
                    Text(shownPreview.isEmpty ? String(localized: "No content") : shownPreview)
                        .font(SettingsTheme.font(size: isCompact ? 10 : 12))
                        .foregroundStyle(notchForeground.opacity(0.7))
                        .lineLimit(isCompact ? 1 : 2)
                        .multilineTextAlignment(.leading)
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                Spacer(minLength: 0)
            }
            .padding(.trailing, isCompact ? 50 : 130) // Standardized padding for alignment
            .padding(isCompact ? 8 : 12)
                
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // A calm surface under the text whatever the skin: a textured skin's streaks ran under the
                // translucent card and took the preview's contrast. Over a plain fill this is that fill.
                RoundedRectangle(cornerRadius: 12)
                    .fill((notchFill ?? .black).opacity(0.45))
                RoundedRectangle(cornerRadius: 12)
                    .fill(notchForeground.opacity(isHovered ? 0.14 : (note.isPinned ? 0.11 : 0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(notchForeground.opacity(0.06), lineWidth: 1)
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Ensure everything stays inside the frame
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
                if isHovered {
                    HStack(spacing: isCompact ? 3 : 4) {
                        // A Wispr Flow meeting is only shown: Copy, no pin and no trash.
                        if enableNotePinning && !note.isWisprMeeting {
                            Button(action: onTogglePin) {
                                Image(systemName: note.isPinned ? "pin.slash.fill" : "pin.fill")
                                    .font(.system(size: isCompact ? 9 : 11))
                                    .foregroundStyle(.white)
                                    .padding(isCompact ? 5 : 6)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            // `.below`: rows sit in a ScrollView and the first rows are the most
                            // hovered; the grid's bottom padding leaves room under the last one.
                            .hoverTooltip(pinTooltip, edge: .below)
                            .accessibilityLabel(pinTooltip)
                        }

                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(note.content, forType: .string)
                            
                            // Also copy image data if present
                            if let imageData = note.getImageData(), let tiffData = NSImage(data: imageData)?.tiffRepresentation {
                                pasteboard.setData(tiffData, forType: .tiff)
                            }
                            
                            withAnimation {
                                isCopied = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    isCopied = false
                                }
                            }
                        }) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: isCompact ? 9 : 11))
                                .foregroundStyle(.white)
                                .padding(isCompact ? 5 : 6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverTooltip(String(localized: "Copy"), edge: .below)
                        .accessibilityLabel(String(localized: "Copy"))

                        if !note.isWisprMeeting {
                            Button(action: {
                                if deletesInAppleNotes { confirmDelete = true } else { onDelete() }
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: isCompact ? 9 : 11))
                                    .foregroundStyle(.red)
                                    .padding(isCompact ? 5 : 6)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .hoverTooltip(String(localized: "Delete Note"), edge: .below)
                            .accessibilityLabel(String(localized: "Delete Note"))
                        }
                    }
                    .padding(.horizontal, isCompact ? 6 : 8)
                    .padding(.vertical, isCompact ? 2 : 3)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.12)) // Softer dark gray, not solid black
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    )
                    .padding(.vertical, 4) // Ensure it stays within note borders
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                } else if !isCompact {
                    Text(timeAgoString(from: note.creationDate))
                        .font(SettingsTheme.font(size: 10))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                
                if let nsImage = thumbnail {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: isCompact ? 32 : 50, height: isCompact ? 32 : 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(notchForeground.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .padding(.trailing, isCompact ? 4 : 8)
                }
            }
            .padding(.trailing, isCompact ? 2 : 4)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .task(id: thumbnailKey) {
            guard let fileName = note.imageFileName else {
                thumbnail = nil
                return
            }
            let url = NoteItem.noteImageDataDirectory.appendingPathComponent(fileName)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            thumbnail = data.flatMap { NSImage(data: $0) }
        }
        // On the row, not on the hover-only trash button: the pointer leaving the row removed the
        // button, and its alert with it. The notch stays open while the alert asks.
        .alert("Delete This Note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It was made in Apple Notes, and it also moves to Recently Deleted there.")
        }
        .onChange(of: confirmDelete) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: autoCloseToken) }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "Just now") }
        if interval < 3600 { return String(localized: "\(Int(interval/60))m") }
        if interval < 86400 { return String(localized: "\(Int(interval/3600))h") }
        return date.formatted(.dateTime.day().month())
    }
}

struct NoteEditorView: View {
    @EnvironmentObject var vm: KannuViewModel
    @Environment(\.notchFill) private var notchFill
    @Environment(\.notchForeground) private var notchForeground
    @Environment(\.colorScheme) private var colorScheme

    /// Under a skin the editor paints its own black surface, so its text stays white there.
    private var editorForeground: Color { notchFill == nil ? .white : notchForeground }

    @Binding var title: String
    @Binding var content: String
    @Binding var imageData: Data?
    @Binding var colorIndex: Int
    let onSave: () -> Void
    let cancelAction: () -> Void
    let isNew: Bool
    /// A note made in Notes, shown while sync reads the whole account: its text is shown, not
    /// edited, and "Open in Notes" takes the user to where it is (`NoteItem.isReadOnlyMirror`).
    let isReadOnly: Bool
    let onOpenInNotes: () -> Void
    /// Nil hides the trash: a draft or an unsaved new note has nothing to delete.
    let onDelete: (() -> Void)?
    /// A note made in Notes: deleting it sends it to Recently Deleted there too, so the trash asks
    /// first, as the list row's does.
    let deletesInAppleNotes: Bool
    /// A Wispr Flow meeting's summary: read-only, and the open action goes to Wispr Flow instead of
    /// Notes. It has no colour of its own, so the colour picker is hidden.
    let opensInWisprFlow: Bool
    /// The note's tags, and the row that edits them (`NoteTagsRow`); no row when `onTagsEdited` is nil.
    let tags: [String]
    @Binding var tagDraft: String
    let onTagsEdited: (([String]) -> Void)?
    /// Return in the title, or the title losing focus: its new `#word`s become tags.
    let onCommitTitle: () -> Void
    @FocusState private var isTitleFocused: Bool
    @State private var confirmDelete = false
    /// Holds the notch open while the delete confirmation shows.
    @State private var autoCloseToken = UUID()

    init(title: Binding<String>, content: Binding<String>, imageData: Binding<Data?>, colorIndex: Binding<Int>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, isNew: Bool, isReadOnly: Bool = false, onOpenInNotes: @escaping () -> Void = {}, onDelete: (() -> Void)? = nil, deletesInAppleNotes: Bool = false, opensInWisprFlow: Bool = false, tags: [String] = [], tagDraft: Binding<String> = .constant(""), onTagsEdited: (([String]) -> Void)? = nil, onCommitTitle: @escaping () -> Void = {}) {
        self._title = title
        self._content = content
        self._imageData = imageData
        self._colorIndex = colorIndex
        self.onSave = onSave
        self.cancelAction = onCancel
        self.isNew = isNew
        self.isReadOnly = isReadOnly
        self.onOpenInNotes = onOpenInNotes
        self.onDelete = onDelete
        self.deletesInAppleNotes = deletesInAppleNotes
        self.opensInWisprFlow = opensInWisprFlow
        self.tags = tags
        self._tagDraft = tagDraft
        self.onTagsEdited = onTagsEdited
        self.onCommitTitle = onCommitTitle
    }

    @FocusState private var isContentFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: cancelAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                        Text("Notes")
                    }
                    .font(SettingsTheme.font(size: 15, weight: .medium))
                    .foregroundStyle(editorForeground)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()

                if isReadOnly {
                    Button(action: onOpenInNotes) {
                        Label {
                            Text(opensInWisprFlow ? String(localized: "Open in Wispr Flow") : String(localized: "Open in Notes"))
                        } icon: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .font(SettingsTheme.font(size: 12, weight: .medium))
                            .foregroundStyle(editorForeground.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(opensInWisprFlow ? String(localized: "Edit this summary in Wispr Flow")
                                                   : String(localized: "Edit this note in Notes"), edge: .below)
                    .padding(.trailing, 8)
                }

                if let onDelete {
                    Button(action: {
                        if deletesInAppleNotes { confirmDelete = true } else { onDelete() }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(String(localized: "Delete Note"), edge: .below)
                    .accessibilityLabel(String(localized: "Delete Note"))
                    .padding(.trailing, 12)
                }

                Button(action: onSave) {
                    Text("Done")
                        .font(SettingsTheme.font(size: 15, weight: .bold))
                        .foregroundStyle(NoteItem.color(at: colorIndex))
                }
                .buttonStyle(PlainButtonStyle())
            }
            // 12 pt above and below, not 16: back some of the tag row's line for the text.
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Title & Color Picker Row
            HStack(alignment: .center, spacing: 12) {
                if isReadOnly {
                    Text(title)
                        .font(SettingsTheme.font(size: 17, weight: .bold))
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else {
                    TextField("Title", text: $title)
                        .font(SettingsTheme.font(size: 17, weight: .bold))
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit(onCommitTitle)
                        .onChange(of: isTitleFocused) { _, focused in
                            if !focused { onCommitTitle() }
                        }
                }
                
                Spacer()
                
                // Color picker: none for a Wispr Flow meeting, which has no colour of its own.
                if !opensInWisprFlow {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<NoteItem.colors.count, id: \.self) { index in
                                Circle()
                                    .fill(NoteItem.colors[index])
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(editorForeground, lineWidth: colorIndex == index ? 2 : 0)
                                            .padding(-2)
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            colorIndex = index
                                        }
                                    }
                                    // `.above`: the toolbar is an earlier VStack sibling and draws
                                    // underneath; the editor below would draw over a `.below` bubble.
                                    .hoverTooltip(NoteItem.colorNames[index], edge: .above)
                                    .accessibilityLabel(NoteItem.colorNames[index])
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }
                    // A ScrollView clips both axes; without this the bubble is swallowed.
                    // The row is ~144pt against its 160pt maximum, so nothing scrolls today.
                    .scrollClipDisabled()
                    .frame(maxWidth: 160)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.bottom, onTagsEdited == nil ? 8 : 4)

            // The note's tags, one line: Kannu's alone, so a read-only note takes them too.
            if let onTagsEdited {
                NoteTagsRow(tags: tags, typed: $tagDraft, onEdit: onTagsEdited)
                    .padding(.bottom, 6)
            }

            Divider()
                .background(editorForeground.opacity(0.1))


            
            // Content Input
            ZStack(alignment: .topLeading) {
                if isReadOnly {
                    ScrollView {
                        Text(content)
                            .font(SettingsTheme.font(size: 13))
                            .foregroundStyle(editorForeground)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .padding(.bottom, 20)
                    }
                    .frame(maxHeight: .infinity)
                    .background(editorForeground.opacity(0.05))
                } else {
                    if content.isEmpty { // Placeholder
                        Text("Start typing...")
                            .font(SettingsTheme.font(size: 13)) // Reduced from 14
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 10)
                            .padding(.leading, 12)
                            .allowsHitTesting(false)
                    }
                
                    TextEditor(text: $content)
                        .font(SettingsTheme.font(size: 13))
                        .foregroundStyle(editorForeground)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .padding(.bottom, 20)
                        .padding(.trailing, imageData != nil ? 75 : 0) // Reduced from 100
                        .focused($isContentFocused)
                        .frame(maxHeight: .infinity)
                        .background(editorForeground.opacity(0.05))
                }
                
                // Image Overlay in Bottom Right
                if let data = imageData, let nsImage = NSImage(data: data) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 55, height: 55) // Reduced from 80
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(editorForeground.opacity(0.2), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 2)
                                
                                if !isReadOnly {
                                    Button(action: {
                                        withAnimation {
                                            imageData = nil
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.9), .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4) // Move out slightly for better accessibility
                                    .hoverTooltip(String(localized: "Remove Image"), edge: .above)
                                    .accessibilityLabel(String(localized: "Remove Image"))
                                }
                            }
                            .padding(12)
                            .padding(.bottom, 20) // Moved higher as requested
                        }
                    }
                }
                
                if Defaults[.enableNoteCharCount] {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(content.count) chars")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(4)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack takes full space
        .background(notchFill ?? .black) // Solid, so the list never shows through mid-slide
        // Under a skin the editor paints black, so it keeps the dark scheme there.
        .environment(\.colorScheme, notchFill == nil ? .dark : colorScheme)
        .environment(\.notchForeground, editorForeground)
        .onAppear {
            if isNew && !isReadOnly {
                isContentFocused = true
            }
        }
        // On the editor, not on its trash button, and the notch stays open while it asks.
        .alert("Delete This Note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It was made in Apple Notes, and it also moves to Recently Deleted there.")
        }
        .onChange(of: confirmDelete) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: autoCloseToken) }
    }
}
