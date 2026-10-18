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

/// What the timer tab's task form is for: a new task (the New task button beside the session name
/// field), or one task's edit (the pencil on its expanded card).
enum TimerTaskFormMode: Hashable {
    case add
    case edit(UUID)
}

/// The timer tab's task form, in place of the session name field and the composer, in their frame
/// (`TimerComposerMetrics.taskFormHeight`, under the composer's own height, so the notch never
/// grows): the title and a × where the New task button was; the estimate and tags; a local task's
/// reminder; then Add and Add & Start, or Save.
///
/// A Jira or GitLab task's title shows but is the server's (`TaskFormDraft`), and reminders are for
/// local tasks. Nothing is saved until Add or Save; the × and Escape leave without saving.
///
/// A view of its own, built only while shown, so `NotchTimerView` never touches `TasksManager`.
/// While a field has focus, or one of its menus tracks, it holds the notch open under tokens of its
/// own, released when the focus goes, the form goes, or the notch's window stops being key.
struct TimerTaskForm: View {
    private typealias M = TimerComposerMetrics

    @EnvironmentObject private var vm: KannuViewModel
    @ObservedObject private var manager = TasksManager.shared
    /// A new task is local: with Local hidden in the notch it would vanish as it is added.
    @Default(.tasksPopoverShowLocal) private var showLocal
    let mode: TimerTaskFormMode
    let close: () -> Void
    /// A task started from Add & Start: its name wins over a typed session name.
    let started: () -> Void

    @State private var draft: TaskFormDraft
    @FocusState private var focused: Field?
    /// `@State`, so the release names the token that was set.
    @State private var editingToken = UUID()
    @State private var menuTrackingToken = UUID()

    private enum Field: Hashable { case title, tags, reminder }

    init(mode: TimerTaskFormMode, close: @escaping () -> Void, started: @escaping () -> Void) {
        self.mode = mode
        self.close = close
        self.started = started
        switch mode {
        case .add:
            _draft = State(initialValue: TaskFormDraft())
        case .edit(let id):
            let task = TasksManager.shared.tasks.first { $0.id == id }
            _draft = State(initialValue: task.map(TaskFormDraft.init(editing:)) ?? TaskFormDraft())
        }
    }

    private var editedTask: TaskItem? {
        guard case .edit(let id) = mode else { return nil }
        return manager.activeTasks.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: M.taskFormRowSpacing) {
            titleRow
                .frame(height: M.nameFieldHeight)
                .zIndex(3)
            HStack(spacing: M.taskFormRowSpacing) {
                estimateMenu
                tagsField
            }
            .frame(height: M.taskFormRowHeight)
            .zIndex(2)
            reminderRow
                .frame(height: M.taskFormRowHeight)
                .zIndex(1)
            buttonRow
        }
        .frame(height: M.taskFormHeight, alignment: .top)
        .onAppear {
            if case .edit = mode, editedTask == nil {
                close()
                return
            }
            // After the field exists: focusing it in the same update finds nothing to focus.
            let first: Field = draft.canEditTitle ? .title : .tags
            DispatchQueue.main.async { focused = first }
        }
        .onChange(of: focused) { _, field in
            vm.setAutoCloseSuppression(field != nil, token: editingToken)
        }
        // The task left the list (done, deleted, archived, resynced away) while being edited.
        .onChange(of: manager.activeTasks.map(\.id)) { _, ids in
            if case .edit(let id) = mode, !ids.contains(id) { close() }
        }
        // A click into another app leaves a field focused in a window that is no longer key: drop
        // it, which lets the notch auto-close again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard note.object is KannuWindow else { return }
            focused = nil
        }
        // The estimate menu is a window of its own: the pointer leaves the notch to use it.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            vm.setAutoCloseSuppression(true, token: menuTrackingToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            vm.setAutoCloseSuppression(false, token: menuTrackingToken)
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: editingToken)
            vm.setAutoCloseSuppression(false, token: menuTrackingToken)
        }
    }

    // MARK: - Rows

    /// The session name field's place and look; the × where the New task button was.
    private var titleRow: some View {
        HStack(spacing: M.nameFieldSpacing) {
            Group {
                if draft.canEditTitle {
                    TextField(String(localized: "What needs doing?"), text: $draft.title)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .tint(.white)
                        .focused($focused, equals: .title)
                        .onSubmit(submit)
                        .onExitCommand(perform: close)
                        .accessibilityLabel(Text("Task title"))
                } else {
                    Text(verbatim: draft.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text(verbatim: String(localized: "Task title, \(draft.title)")))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: M.nameFieldHeight, height: M.nameFieldHeight)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: String(localized: "Close task form")))
            .hoverTooltip(String(localized: "Close without saving"), edge: .below)
        }
    }

    private var estimateMenu: some View {
        Menu {
            Button(String(localized: "No estimate")) { draft.estimateSeconds = nil }
            ForEach(draft.estimateMenuChoices, id: \.self) { seconds in
                Button(WorkDuration.format(seconds)) { draft.estimateSeconds = seconds }
            }
        } label: {
            Text(verbatim: draft.estimateLabel)
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(Text("Estimate"))
        .hoverTooltip(String(localized: "Estimate"), edge: .below)
    }

    private var tagsField: some View {
        TextField(String(localized: "Tags, comma separated"), text: $draft.tagsText)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .tint(.white)
            .focused($focused, equals: .tags)
            .onSubmit(submit)
            .onExitCommand(perform: close)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(Text("Tags"))
    }

    /// A local task's reminder: "Add a reminder", or the date and time and a ×. A field date
    /// picker, never the compact one: its calendar is a popover window, and the notch would close
    /// under it. While macOS blocks Kannu's notifications an orange bell says so.
    @ViewBuilder
    private var reminderRow: some View {
        if draft.canSchedule {
            HStack(spacing: 6) {
                if draft.reminder != nil {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    DatePicker(String(localized: "Reminder"), selection: reminderBinding, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.small)
                        .focused($focused, equals: .reminder)
                        .fixedSize()
                    Button {
                        draft.reminder = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: String(localized: "Remove reminder")))
                    .hoverTooltip(String(localized: "Remove reminder"), edge: .below)
                } else {
                    Button {
                        draft.reminder = TaskFormDraft.defaultReminder(now: Date(), calendar: .current)
                    } label: {
                        Label(String(localized: "Add a reminder"), systemImage: "bell")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if manager.remindersBlocked {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 20, height: 20)
                        .accessibilityLabel(Text(verbatim: String(localized: "Notifications are off for Kannu")))
                        .hoverTooltip(String(localized: "Notifications are off for Kannu"), edge: .below)
                }
            }
        } else {
            Text("Reminders are for local tasks.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: { draft.reminder ?? TaskFormDraft.defaultReminder(now: Date(), calendar: .current) },
            set: { draft.reminder = $0 }
        )
    }

    /// The composer's Start and Reset, in their look: Add & Start green, Add grey; Save green.
    private var buttonRow: some View {
        HStack(spacing: 10) {
            if draft.isNew {
                formButton(String(localized: "Add"), systemImage: "plus", prominent: false) { add(andStart: false) }
                formButton(String(localized: "Add & Start"), systemImage: "play.fill", prominent: true) { add(andStart: true) }
            } else {
                formButton(String(localized: "Save"), systemImage: "checkmark", prominent: true, action: save)
            }
        }
    }

    private func formButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let disabled = !manager.isReady || !draft.canSave
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: M.buttonFontSize, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: M.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prominent ? Self.startColor.opacity(disabled ? 0.5 : 1) : Color.white.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(prominent ? 0.15 : 0), lineWidth: 1)
        )
        .opacity(disabled ? 0.7 : 1)
        .disabled(disabled)
    }

    /// The composer's Start green (`NotchTimerView.startButtonColor`).
    private static let startColor = Color(red: 0.142, green: 0.633, blue: 0.265)

    // MARK: - Saving

    /// Return in a field: Add for a new task, Save for an edit.
    private func submit() {
        if draft.isNew {
            add(andStart: false)
        } else {
            save()
        }
    }

    /// A local task at the top of the order, then its tags and reminder. Add & Start starts it the
    /// way its ▶ would; when nothing starts, the form still closes on the added task.
    private func add(andStart: Bool) {
        guard draft.canSave, let id = manager.addTask(title: draft.title, estimateSeconds: draft.estimateSeconds) else { return }
        let tags = draft.tags
        if !tags.isEmpty { manager.setTags(tags, for: id) }
        if let reminder = draft.reminder { manager.setSchedule(reminder, for: id) }
        if !showLocal { showLocal = true }
        guard andStart, manager.start(id) else {
            close()
            return
        }
        started()
    }

    /// Only what changed (`TaskFormDraft.edits`), each through the manager's own edit.
    private func save() {
        guard draft.canSave, case .edit(let id) = mode, let task = editedTask else {
            close()
            return
        }
        for edit in draft.edits(to: task) {
            switch edit {
            case .title(let title): manager.renameTask(id, to: title)
            case .estimate(let seconds): manager.setEstimate(seconds, for: id)
            case .tags(let tags): manager.setTags(tags, for: id)
            case .schedule(let date): manager.setSchedule(date, for: id)
            }
        }
        close()
    }
}
