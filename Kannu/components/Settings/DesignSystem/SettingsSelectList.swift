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
import SwiftUI

/// What a `SettingsSelect` opens: one row per option, a tick on the chosen one, the keyboard's row highlighted.
/// Past `SettingsSelectNavigation.searchThreshold` options a search field leads and the rows scroll; a shorter
/// list takes typed letters instead. A view of its own so a board can draw it open: a popover is a window of its
/// own, and no board can capture one.
struct SettingsSelectList<Value: Hashable, Icon: View>: View {
    private let title: Text
    @Binding private var selection: Value
    private let options: [Value]
    private let optionTitle: (Value) -> String
    private let icon: (Value) -> Icon
    private let close: () -> Void
    @State private var query: String
    @State private var highlighted: Value?
    @State private var typed = ""
    @State private var lastKey = Date.distantPast
    @FocusState private var fieldHasFocus: Bool
    @FocusState private var listHasFocus: Bool

    /// `query` seeds the field, for a board; the select passes none.
    init(title: Text, selection: Binding<Value>, options: [Value], optionTitle: @escaping (Value) -> String,
         query: String = "", @ViewBuilder icon: @escaping (Value) -> Icon, close: @escaping () -> Void) {
        self.title = title
        _selection = selection
        self.options = options
        self.optionTitle = optionTitle
        _query = State(initialValue: query)
        self.icon = icon
        self.close = close
    }

    private var searches: Bool { options.count > SettingsSelectNavigation.searchThreshold }
    private var shown: [Value] {
        SettingsSelectNavigation.matches(options.map(optionTitle), query: query).map { options[$0] }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: SettingsTheme.popoverInset) {
                if searches {
                    TextField(text: $query, prompt: Text("Search...")) { title }
                        .focused($fieldHasFocus)
                        .onSubmit { pick(highlighted ?? shown.first) }
                        .onExitCommand(perform: close)
                        .settingsField(isFocused: fieldHasFocus)
                }
                if shown.isEmpty {
                    Text("No results")
                        .settingsDescriptionStyle()
                } else {
                    rows
                }
            }
            .padding(SettingsTheme.popoverInset)
            .frame(minWidth: SettingsTheme.selectMinWidth, alignment: .leading)
            // The list's focus stop when it has no field, on a background as the sidebar's is (SettingsView),
            // painted the panel so the popover's material never shows through.
            .background {
                Rectangle()
                    .fill(SettingsTheme.panel)
                    .focusable(!searches)
                    .focused($listHasFocus)
                    .focusEffectDisabled()
            }
            .background(ArrowKeys { move(by: $0, scrolling: proxy) })
            .onKeyPress(.return) {
                pick(highlighted)
                return .handled
            }
            .onKeyPress(.escape) {
                close()
                return .handled
            }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                guard !searches else { return .ignored }     // letters belong to the field
                typeSelect(press.characters, scrolling: proxy)
                return .handled
            }
            // As the notch's suggestions do: a highlight the query moved is said, since VoiceOver's cursor is
            // not on it.
            .onChange(of: query) {
                let first = shown.first
                let moved = first != highlighted
                highlight(first, scrolling: proxy)
                if moved, let first { announce(first) }
            }
            .onAppear {
                highlighted = shown.contains(selection) ? selection : shown.first
                // A turn later: focusing in the same update finds nothing to focus (TimerSideColumn), and the
                // rows are laid out by then, so the scroll lands.
                DispatchQueue.main.async {
                    if searches { fieldHasFocus = true } else { listHasFocus = true }
                    if let highlighted { proxy.scrollTo(highlighted) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// Scrolls, at `selectListHeight`, only when the list searches; a short list shows every row.
    @ViewBuilder
    private var rows: some View {
        if searches {
            ScrollView { rowStack }
                .frame(height: SettingsTheme.selectListHeight)
        } else {
            rowStack
        }
    }

    private var rowStack: some View {
        VStack(spacing: 0) {
            ForEach(shown, id: \.self) { option in row(option) }
        }
    }

    private func row(_ option: Value) -> some View {
        Button { pick(option) } label: {
            HStack(spacing: SettingsMetrics.iconGap) {
                Image(systemName: "checkmark")
                    .font(SettingsTheme.description)
                    .opacity(option == selection ? 1 : 0)
                    .accessibilityHidden(true)
                icon(option).accessibilityHidden(true)
                Text(verbatim: optionTitle(option))
                Spacer(minLength: 0)
            }
            .font(SettingsTheme.body)
            .foregroundStyle(SettingsTheme.ink)
            .lineLimit(1)
            .padding(.horizontal, SettingsTheme.selectRowInset)
            .frame(height: SettingsTheme.selectRowHeight)
            .background {
                if option == highlighted {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .fill(SettingsTheme.selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        // Never takes the keyboard: the field or the list keeps it, as the notch's suggestion rows do.
        .focusable(false)
        // The pointer moves the highlight but never scrolls: a scroll under a still pointer would move it again.
        .onHover { hovering in
            if hovering { highlighted = option }
        }
        .accessibilityAddTraits(option == selection ? .isSelected : [])
        .id(option)
    }

    private func pick(_ option: Value?) {
        guard let option else { return }
        selection = option
        close()
    }

    /// The keyboard's highlight scrolls into view, with no animation.
    private func highlight(_ option: Value?, scrolling proxy: ScrollViewProxy) {
        highlighted = option
        if let option { proxy.scrollTo(option) }
    }

    /// ↑ and ↓. False when there is no row to land on, so the key goes on.
    private func move(by offset: Int, scrolling proxy: ScrollViewProxy) -> Bool {
        let rows = shown
        let index = highlighted.flatMap { rows.firstIndex(of: $0) }
        guard let next = SettingsSelectNavigation.moved(from: index, by: offset, count: rows.count) else { return false }
        highlight(rows[next], scrolling: proxy)
        announce(rows[next])
        return true
    }

    /// Letters in a list with no field: a prefix that a pause starts again, as in a macOS menu.
    private func typeSelect(_ characters: String, scrolling proxy: ScrollViewProxy) {
        let now = Date()
        typed = SettingsSelectNavigation.typed(characters, after: typed, pause: now.timeIntervalSince(lastKey))
        lastKey = now
        let rows = shown
        guard let index = SettingsSelectNavigation.typeSelect(typed, in: rows.map(optionTitle)) else { return }
        highlight(rows[index], scrolling: proxy)
        announce(rows[index])
    }

    /// The notch's idiom: the highlight moves where VoiceOver's cursor is not, so it is said.
    private func announce(_ option: Value) {
        AccessibilityNotification.Announcement(optionTitle(option)).post()
    }

    /// A press only, like the segment's: `.plain` would dim a disabled row a second time.
    private struct RowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? SettingsTheme.pressedOpacity : 1)
        }
    }

    /// ↑ and ↓ for the list, with or without a field. A focused field's editor takes these keys before SwiftUI
    /// sees them, so a local key monitor reads them, shaped like `HorizontalSwipeMonitor`'s.
    private struct ArrowKeys: NSViewRepresentable {
        let move: (Int) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.install(on: view)
            return view
        }

        func updateNSView(_ view: NSView, context: Context) { context.coordinator.move = move }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

        func makeCoordinator() -> Coordinator { Coordinator(move: move) }

        @MainActor
        final class Coordinator {
            var move: (Int) -> Bool
            private var monitor: Any?
            private weak var view: NSView?

            init(move: @escaping (Int) -> Bool) { self.move = move }

            /// ↑ and ↓, in this popover's own window only, while it is key, and never while an input method is
            /// composing: a focused field's editor takes these keys before SwiftUI sees them.
            func install(on view: NSView) {
                self.view = view
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let down: UInt16 = 125, up: UInt16 = 126
                    guard let self, let window = self.view?.window, event.window === window, window.isKeyWindow,
                          event.keyCode == down || event.keyCode == up,
                          event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
                    if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                    return self.move(event.keyCode == down ? 1 : -1) ? nil : event
                }
            }

            func remove() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
        }
    }
}
