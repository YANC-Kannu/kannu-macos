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

/// Brain's choice of one value among several. `.popover` is a button showing the current value that opens our
/// own list (`SettingsSelectList`); `.segmented` draws two or three short options in place.
///
/// SwiftUI on macOS 14 has no custom picker style, and a custom view cannot read `.tag()`s, so the options are
/// data. It draws no title of its own: the row beside it does (`SettingsRow`), and VoiceOver reads the title as
/// the label.
struct SettingsSelect<Value: Hashable, Icon: View>: View {
    enum Style {
        case popover
        case segmented
    }

    private let title: Text
    @Binding private var selection: Value
    private let options: [Value]
    private let optionTitle: (Value) -> String
    private let icon: (Value) -> Icon
    private let style: Style
    @State private var isOpen = false
    @FocusState private var focusedOption: Value?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [Value],
         optionTitle: @escaping (Value) -> String, style: Style = .popover,
         @ViewBuilder icon: @escaping (Value) -> Icon) {
        self.title = Text(title)
        _selection = selection
        // Once each: `ForEach` needs it, and two screens with one name are one choice.
        var seen = Set<Value>()
        self.options = options.filter { seen.insert($0).inserted }
        self.optionTitle = optionTitle
        self.icon = icon
        self.style = style
    }

    var body: some View {
        switch style {
        case .popover: trigger
        case .segmented: segments
        }
    }

    /// The selection's own title, even when it is not among the options (a choice saved before its option went
    /// away, a list still loading), so the button is never blank.
    private var currentTitle: String {
        let current = optionTitle(selection)
        return current.isEmpty ? "—" : current
    }

    private var trigger: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: SettingsMetrics.iconGap) {
                icon(selection)
                ZStack(alignment: .leading) {
                    // A short list keeps its widest title's width, as a native pop-up does, so the row does
                    // not move when the choice changes. A long one would build every title for nothing.
                    if options.count <= SettingsSelectNavigation.searchThreshold {
                        ForEach(options, id: \.self) { Text(verbatim: optionTitle($0)).hidden() }
                    }
                    Text(verbatim: currentTitle)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(SettingsTheme.description)
                    .foregroundStyle(SettingsTheme.inkSecondary)
            }
            .font(SettingsTheme.body)
            .lineLimit(1)
        }
        // Its own, not the root's: a sheet or a card may hold a select.
        .buttonStyle(SettingsButtonStyle())
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            SettingsSelectList(title: title, selection: $selection, options: options,
                               optionTitle: optionTitle, icon: icon) { isOpen = false }
        }
        // Closing Brain takes its content out of the window and runs this (docs/REGRESSIONS.md, entry 22), while
        // `isOpen` survives the close: a list left open must not come back on reopening.
        .onDisappear { isOpen = false }
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: currentTitle))
        .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: SettingsMetrics.iconGap) {
                        icon(option).accessibilityHidden(true)
                        Text(verbatim: optionTitle(option))
                    }
                    .foregroundStyle(option == selection ? SettingsTheme.ink : SettingsTheme.inkSecondary)
                    .padding(SettingsTheme.segmentInset)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: SettingsTheme.segmentRadius, style: .continuous)
                                .fill(SettingsTheme.raised)
                                .overlay {
                                    RoundedRectangle(cornerRadius: SettingsTheme.segmentRadius, style: .continuous)
                                        .strokeBorder(SettingsTheme.line)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SegmentButtonStyle())
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                .focused($focusedOption, equals: option)
            }
        }
        .font(SettingsTheme.bodyStrong)
        .lineLimit(1)
        .padding(SettingsTheme.segmentTrackInset)
        .background(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous).fill(SettingsTheme.card))
        .overlay(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous).strokeBorder(SettingsTheme.line))
        .fixedSize()
        .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
        .animation(reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // With Full Keyboard Access a segment has focus, and the arrows move the choice, as a native one's do.
        // Focus goes with the choice, so Space on the focused segment keeps it. Right to left the segments are
        // drawn mirrored, so → steps back.
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            step((press.key == .rightArrow) == (layoutDirection == .leftToRight) ? 1 : -1)
            focusedOption = selection
            return .handled
        }
    }

    /// Arrows and VoiceOver's adjust land here; a disabled select ignores them, as its button does a click.
    private func step(_ offset: Int) {
        guard isEnabled else { return }
        let index = options.firstIndex(of: selection)
        guard let next = SettingsSelectNavigation.moved(from: index, by: offset, count: options.count) else { return }
        selection = options[next]
    }

    /// A press only. `.plain` would dim a disabled segment a second time (`SettingsToggleStyle`'s track has the
    /// same style for the same reason).
    private struct SegmentButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? SettingsTheme.pressedOpacity : 1)
        }
    }
}

extension SettingsSelect where Icon == EmptyView {
    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [Value],
         optionTitle: @escaping (Value) -> String, style: Style = .popover) {
        self.init(title, selection: selection, options: options, optionTitle: optionTitle, style: style) { _ in EmptyView() }
    }

    /// Literal options, in the order written: `choices: [3: String(localized: "3 seconds"), …]`.
    init(_ title: LocalizedStringKey, selection: Binding<Value>, choices: KeyValuePairs<Value, String>,
         style: Style = .popover) {
        self.init(title, selection: selection, options: choices.map { $0.key },
                  optionTitle: { value in choices.first { $0.key == value }?.value ?? "" }, style: style)
    }
}
