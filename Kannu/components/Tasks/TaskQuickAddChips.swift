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

/// What the `#tag` and `@time` words typed in a new task's name will do (`TaskQuickAdd`), as small
/// chips at the end of the field: the tags, then a bell and the reminder ("12:00", "Tomorrow 17:00",
/// "Tue 9:00"). Nothing when no token is typed, or when no name is left to make a task of (the
/// words then do nothing: the field cannot add it, and the timer bar starts a plain session). It
/// takes no room the field did not already have, so the timer tab never grows for it.
struct TaskQuickAddChips: View {
    let text: String
    var fontSize: CGFloat = 10
    /// Room kept clear at the end, for a field whose border the chips sit inside.
    var trailingInset: CGFloat = 0
    /// False for words that go to a task named elsewhere (a task picked in the timer bar).
    var requiresName = true

    var body: some View {
        let now = Date()
        let parsed = TaskQuickAdd.parse(text, now: now, calendar: .current)
        if parsed.hasTokens, !requiresName || TaskItem.cleanedTitle(parsed.title) != nil {
            HStack(spacing: 4) {
                ForEach(parsed.tags, id: \.self) { tag in
                    chip(Text(verbatim: "#\(tag)"))
                }
                if let reminder = parsed.reminder {
                    chip(Text(Image(systemName: "bell.fill")) + Text(verbatim: " " + Self.when(reminder, now: now)))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, trailingInset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.spoken(parsed, now: now)))
        }
    }

    private func chip(_ label: Text) -> some View {
        label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    /// "12:00" today, "Tomorrow 17:00", or the weekday and time.
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        switch TaskReminderPlan.when(date, now: now, calendar: calendar) {
        case .today, .overdue:
            return time
        case .tomorrow:
            return String(localized: "Tomorrow \(time)")
        case .later:
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    private static func spoken(_ parsed: TaskQuickAdd.Parsed, now: Date) -> String {
        var parts: [String] = []
        if !parsed.tags.isEmpty {
            parts.append(String(localized: "Tags: \(parsed.tags.joined(separator: ", "))"))
        }
        if let reminder = parsed.reminder {
            parts.append(String(localized: "Reminder: \(when(reminder, now: now))"))
        }
        return parts.joined(separator: ". ")
    }
}
