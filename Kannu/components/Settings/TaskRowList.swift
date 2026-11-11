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

/// The task rows of a list on a page below Brain › Tasks' first: a project, a source with one project or none, Local
/// tasks. It follows `TasksManager`, as those pages do, works the rows out once per render (`TaskListRows`) and draws
/// them as the first page's list does (`TaskRowCards`).
struct TaskRowList: View {
    @ObservedObject private var manager = TasksManager.shared
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableTimerFeature) private var enableTimerFeature
    private let filter: TaskFilter
    private let onProjectPage: Bool
    private let context: TasksPageContext

    init(filter: TaskFilter, onProjectPage: Bool = false, context: TasksPageContext) {
        self.filter = filter
        self.onProjectPage = onProjectPage
        self.context = context
    }

    var body: some View {
        TaskRowCards(
            rows: TaskListRows(
                manager.listedTasks(filter),
                tagColors: manager.tagColors,
                integrationColors: manager.integrationColors,
                topTaskID: manager.activeTasks.first?.id,
                timedTaskID: manager.timing?.taskID,
                timingIsPaused: manager.timing?.isPaused ?? false
            ),
            tagColors: manager.tagColors, doneTicks: manager.doneTicks, isReady: manager.isReady,
            canStart: enableTimerFeature && manager.isReady, onProjectPage: onProjectPage,
            live: visibility.isOnScreen, context: context
        )
    }

    /// The caption's segments joined with " · ", an alert in orange; nil when it says nothing.
    static func text(of caption: TaskRowCaption) -> Text? {
        guard !caption.segments.isEmpty else { return nil }
        var text = Text(verbatim: "")
        for (index, segment) in caption.segments.enumerated() {
            if index > 0 { text = text + Text(verbatim: " · ") }
            let part = Text(verbatim: segment.text)
            text = text + (segment.isAlert ? part.foregroundStyle(.orange) : part)
        }
        return text
    }
}

/// A task list's rows, each a soft card: the task's colour dot, its title (two lines at most), one caption
/// (`TaskRowCaption`) with its tags as chips, then a local task's done tick (`TaskDoneTick`), ▶ or ■, and a › to the
/// task's page. Everything else a task can do is on its page and on the card's right-click menu.
///
/// Rows are not dragged, numbered or stepped up and down (David, 2026-10-23: "no drag and order tasks or numbering").
/// The menu's Move to Top is the one move — it picks what the notch's Up next shows first — and is a named
/// accessibility action too, the keyboard and VoiceOver path.
///
/// It observes nothing: its page passes what it draws, worked out once per render (`TaskListRows`: each task's colour,
/// whether it is first in the whole order, whether it is timed), so a row does O(1) work, and a press calls
/// `TasksManager`. The rows carry no highlight ids (docs/SETTINGS.md); each is `.id(task.id)`, so going back scrolls
/// to it. Lazy, unlike the page around it: a list can hold hundreds of tasks, and a plain stack builds every row as
/// the page opens. No search or deep link lands on a row here, and going back scrolls to a task by this `ForEach`'s
/// own id, which a lazy stack reaches before the row is built (docs/SETTINGS.md, "Pages and sections").
struct TaskRowCards: View {
    let rows: TaskListRows
    /// Each tag's colour, for its chip (`TaskColoring.key`).
    let tagColors: [String: TaskColor]
    let doneTicks: TaskDoneTicks
    let isReady: Bool
    let canStart: Bool
    /// Find's text: a tag it found is the chip shown (`TaskSearch.chipTags`).
    var query = ""
    var onProjectPage = false
    /// The task whose page shows beside the list (`ListDetailLayout`), drawn selected.
    var selected: UUID?
    /// Brain is on screen: only then does the row being timed keep its minute clock.
    let live: Bool
    let context: TasksPageContext

    var body: some View {
        // Only with rows: an empty stack would still take a row's gap in its page.
        if !rows.rows.isEmpty {
            LazyVStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
                ForEach(rows.rows) { row in
                    taskRow(row)
                        .id(row.id)
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func taskRow(_ row: TaskListRows.Row) -> some View {
        let task = row.task
        let isTimed = row.timing != nil
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                // The tick by ▶ itself (David, 2026-10-29), left of it so ▶ keeps its place.
                if TaskDoneTicks.canTick(task) {
                    TaskDoneTick(title: task.title, isTicked: doneTicks.isTicked(task.id), isEnabled: isReady, size: 14) {
                        press { $0.toggleDone(task.id) }
                    }
                }
                TaskTimingButton(isTimed: isTimed, canStart: canStart,
                                 start: { press { $0.start(task.id) } }, stop: { press { $0.stopTiming() } })
                Button {
                    context.open(.task(task.id))
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(SettingsButtonStyle(.quiet))
                .accessibilityLabel("Show Details")
            }
        } label: {
            if isTimed && live {
                // Only the row being timed changes on its own, once a minute, and only while Brain is on screen.
                TimelineView(.everyMinute) { timeline in
                    taskLabel(row, now: timeline.date)
                }
            } else {
                taskLabel(row, now: Date())
            }
        }
        .taskCard(selected: selected == task.id, label: task.title)
        .contextMenu {
            Button("Show Details") { context.open(.task(task.id)) }
            Divider()
            moreItems(for: task, isFirst: row.isFirst, isTimed: isTimed)
        }
        // The keyboard and VoiceOver path to the one move, offered while the task is not first.
        .accessibilityActions {
            if !row.isFirst {
                Button("Move to Top") { press { $0.moveToTop(task.id) } }
            }
        }
    }

    @ViewBuilder
    private func moreItems(for task: TaskItem, isFirst: Bool, isTimed: Bool) -> some View {
        // No "…": each acts in place or opens a small sheet (docs/SETTINGS.md).
        Button("Set Estimate") {
            context.sheet.wrappedValue = .estimate(taskID: task.id, title: task.title, draft: TaskFormDraft(editing: task))
        }
        Button("Add Time") {
            context.sheet.wrappedValue = .addTime(taskID: task.id, title: task.title)
        }
        Button("Add Tags") {
            // The tags in use, read at the press.
            context.sheet.wrappedValue = .tags(taskID: task.id, title: task.title, current: task.tags,
                                               existing: TaskFacets.tags(in: TasksManager.shared.tasks))
        }
        if task.source == .local {
            Button("Schedule") {
                context.sheet.wrappedValue = .schedule(taskID: task.id, title: task.title, current: task.scheduledAt)
            }
            if task.scheduledAt != nil {
                Button("Clear Schedule") { press { $0.setSchedule(nil, for: task.id) } }
            }
        }
        Divider()
        // The one move: first in the whole order, the notch's Up next shows it first.
        Button("Move to Top") { press { $0.moveToTop(task.id) } }
            .disabled(isFirst)
        Divider()
        if task.source == .local {
            Button("Mark Done") { press { $0.markDone(task.id) } }
            Button("Archive") { press { $0.archive(task.id) } }
            Button("Delete", role: .destructive) { context.pendingDelete.wrappedValue = task }
                .disabled(isTimed)
        } else {
            // A remote task is finished in its source, and archived here: that is its delete,
            // since a deleted one would only come back on the next sync.
            if let link = taskOpenLink(for: task, manager: TasksManager.shared) {
                Button(link.title) { NSWorkspace.shared.open(link.url) }
            }
            // Whether the time recorded on it is offered in Time to log, where its source takes time.
            // Never asking keeps it here.
            if task.source.logsTime {
                if task.logPolicy == .ask {
                    Button("Never Ask to Log") { press { $0.setAsksToLogTime(false, for: task.id) } }
                } else {
                    Button("Ask to Log") { press { $0.setAsksToLogTime(true, for: task.id) } }
                }
            }
            Button("Archive") { press { $0.archive(task.id) } }
        }
    }

    /// A press calls the manager, then the page reads it again at once (`TasksPageContext.refresh`), so a second click
    /// never waits for the first page's copy.
    private func press(_ action: (TasksManager) -> Void) {
        action(TasksManager.shared)
        context.refresh()
    }

    /// The task's colour as a dot (worked out once, `TaskListRows`), then its title, and its caption with its tags. No
    /// dot column while every listed task is glass; in a mixed list a glass task's dot is empty, so the titles still
    /// line up.
    private func taskLabel(_ row: TaskListRows.Row, now: Date) -> some View {
        let task = row.task
        let caption = TaskRowCaption(task: task, tracked: TaskTimeMath.trackedSeconds(task.segments, now: now), timing: row.timing,
                                     now: now, onProjectPage: onProjectPage, showsTags: false)
        return HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.rowContent) {
            if rows.showsColorDots {
                TaskColorDot(color: row.color)
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: task.title)
                    .lineLimit(2)
                TaskRowCaptionLine(caption: TaskRowList.text(of: caption), tags: TaskSearch.chipTags(of: task, query: query),
                                   foundFirst: !TaskSearch.foundTags(of: task, query: query).isEmpty, tagColors: tagColors)
            }
            // Ticked done and waiting out the undo window.
            .opacity(doneTicks.isTicked(task.id) ? SettingsTheme.disabledOpacity : 1)
        }
    }
}

/// A row's caption, then its tags, on one line: the caption whole, then the first tag as a chip in its colour and "+N"
/// for the rest; with no room for that chip, one "+N" for every tag after the caption, so a chip never takes a word
/// from the caption, which carries the time and any overtime. The notch rail's rule (`TaskTagChips`), in Brain's look.
/// The tags come in the order `TaskSearch.chipTags(of:query:)` gives — own tags, then labels, those Find found first —
/// so while `#docs` is searched for, the chip shown is #docs; a lone "+N" hiding a found tag wears the accent. VoiceOver
/// reads every tag, whichever chips show.
private struct TaskRowCaptionLine: View {
    let caption: Text?
    let tags: [String]
    let foundFirst: Bool
    let tagColors: [String: TaskColor]

    var body: some View {
        if let first = tags.first {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SettingsMetrics.iconGap) {
                    caption?.settingsDescriptionStyle().fixedSize()
                    chips {
                        TaskRowTagChip("#\(first)", tint: tagColors[TaskColoring.key(for: first)]?.tint)
                        if tags.count > 1 {
                            TaskRowTagChip("+\(tags.count - 1)", tint: nil)
                        }
                    }
                }
                HStack(spacing: SettingsMetrics.iconGap) {
                    caption?.settingsDescriptionStyle().layoutPriority(1)
                    chips {
                        TaskRowTagChip("+\(tags.count)", tint: foundFirst ? SettingsTheme.accent : nil)
                    }
                }
            }
        } else if let caption {
            caption.settingsDescriptionStyle()
        }
    }

    private func chips(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: SettingsMetrics.iconGap) {
            content()
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tags.map { "#\($0)" }.joined(separator: ", ")))
    }
}

/// One chip on a row: a tag in its colour's wash, or "+N"; decorative, so it stays unselectable, as a badge does.
private struct TaskRowTagChip: View {
    let text: String
    let tint: Color?

    init(_ text: String, tint: Color?) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(verbatim: text)
            .font(SettingsTheme.caption)
            .foregroundStyle(SettingsTheme.ink)
            .lineLimit(1)
            .padding(SettingsTheme.badgeInset)
            .background(Capsule().fill(tint.map { $0.opacity(SettingsTagChip.tintOpacity) } ?? SettingsTheme.line))
    }
}

extension View {
    /// A list's row as a soft card, its rows `listRowGap` apart: the card's colour and radius, the hero's inset, at
    /// least `listRowHeight` tall. Selected, the one selected look, a 2-pt ring (docs/SETTINGS.md, "The design
    /// system"), told to VoiceOver. For VoiceOver the card is one group named for its task (`label`), so its ✓, ▶ and
    /// › say whose they are.
    func taskCard(selected: Bool, label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
        return padding(.horizontal, SettingsMetrics.cardPadding)
            .padding(.vertical, SettingsMetrics.rowContent)
            .frame(maxWidth: .infinity, minHeight: SettingsTheme.listRowHeight, alignment: .leading)
            .background(SettingsTheme.card, in: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(SettingsTheme.accentStrong, lineWidth: SettingsTheme.choiceRingWidth)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// ▶ starts timing the task, ■ stops it; off while it cannot start (the timer off, the task file
/// not ready). Values only — the list or the page passes them — so a row observes nothing.
struct TaskTimingButton: View {
    let isTimed: Bool
    let canStart: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        if isTimed {
            Button(action: stop) {
                Image(systemName: "stop.fill")
                    .imageScale(.large)
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .accessibilityLabel("Stop timing")
        } else {
            Button(action: start) {
                Image(systemName: "play.fill")
                    .imageScale(.large)
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .disabled(!canStart)
            .accessibilityLabel("Start timing")
        }
    }
}

/// A typed estimate, as the notch's task form takes it (`TaskFormDraft`): 45m, 1.5h or 2d 3h, with
/// the presets on a chevron. Text it cannot read turns orange and is never saved; while focused it
/// shows what it understood ("= 19h"); leaving it writes a readable length the standard way. A
/// Jira or GitLab task with none of Kannu's shows its source's ("2h from Jira") as the prompt.
/// Brain's New Task sheet, a task's Time row and the Set Estimate sheet share it.
struct TaskEstimateField: View {
    @Binding var draft: TaskFormDraft
    var onSubmit: () -> Void = {}
    /// The draft after leaving the field or picking a preset, so a caller saves the value it sees
    /// rather than reading state just written.
    var onSettle: (TaskFormDraft) -> Void = { _ in }
    /// Escape; nil leaves Escape to whatever holds the field (a sheet's Cancel).
    var onCancel: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.iconGap) {
            field
            if focused, let echo = draft.estimateEcho {
                Text(verbatim: echo)
                    .settingsDescriptionStyle()
                    .lineLimit(1)
                    .fixedSize()
            }
            Menu {
                Button(String(localized: "No estimate")) { choose(nil) }
                ForEach(draft.estimateMenuChoices, id: \.self) { seconds in
                    Button(WorkDuration.format(seconds)) { choose(seconds) }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.button)
            .buttonStyle(SettingsButtonStyle(.quiet))
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Estimate presets")
        }
        .onChange(of: focused) { _, isFocused in
            guard !isFocused else { return }
            var next = draft
            next.settleEstimateText()
            draft = next
            onSettle(next)
        }
    }

    @ViewBuilder
    private var field: some View {
        TextField("Estimate", text: Binding(get: { draft.estimateText }, set: { draft.typeEstimate($0) }),
                  prompt: Text(verbatim: draft.estimatePrompt))
            .foregroundStyle(draft.estimateReading == .unreadable ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            .focused($focused)
            .onSubmit(onSubmit)
            .help(Text("Type 45m, 1.5h or 2d 3h"))
            .accessibilityHint(Text(accessibilityHint))
            .modifier(CancelOnEscape(action: onCancel))
            .settingsField(isFocused: focused)
    }

    /// Why Add or Save waits, or what was understood: VoiceOver cannot see the orange.
    private var accessibilityHint: String {
        switch draft.estimateReading {
        case .unreadable: return String(localized: "Not a length. Type 45m, 1.5h or 2d 3h.")
        case .length: return draft.estimateEcho ?? String(localized: "Type 45m, 1.5h or 2d 3h")
        case .none: return String(localized: "Type 45m, 1.5h or 2d 3h")
        }
    }

    private func choose(_ seconds: Int?) {
        var next = draft
        next.chooseEstimate(seconds)
        draft = next
        onSettle(next)
    }
}

/// Escape runs the action only when there is one: with none, Escape goes to whatever holds the field (a sheet's
/// Cancel). A modifier, so the field's chrome still goes on last and Escape stays on the field (`SettingsField`).
private struct CancelOnEscape: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onExitCommand(perform: action)
        } else {
            content
        }
    }
}

/// "Open in Jira", "Open in GitHub": the item's page, built from or checked against the task's own
/// site or server (`TasksManager.browseURL`); nil for a task with no page Kannu would open.
@MainActor
func taskOpenLink(for task: TaskItem, manager: TasksManager) -> (title: String, url: URL)? {
    guard let title = task.source.browseLabel, let url = manager.browseURL(for: task) else { return nil }
    return (title, url)
}
