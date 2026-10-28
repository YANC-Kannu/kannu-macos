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

import Foundation

/// Shorthand typed into a new local task's name, the quick-add pattern of Todoist and Things (David,
/// 2026-10-28: "# would create a tag and @noon would mean reminder at 12:00 pm").
///
/// A token is a whole word, separated by spaces:
/// - `#` and a letter, then letters, digits, `-` or `_`, is a tag: `#kannu`, `#deep-work`. `#123` (an
///   issue number) stays in the title.
/// - `@` and a word Kannu knows is the reminder:
///   - times of day: `noon` 12:00, `morning` 9:00, `evening` 18:00, `tonight` 20:00;
///   - days: `today` (the next whole hour, as "Add a reminder" picks), `tomorrow` (9:00), `mon` to
///     `sun` or the full names (9:00 on the next one);
///   - clock times: `5pm`, `5:30pm`, `9am`, `17:30`.
///
///   A day and a time combine: `@tomorrow @5pm`. A time with no day that has already passed today
///   rolls to tomorrow, and a weekday whose time has passed today means next week; `@today` with a
///   time is that time today, even when it has passed, because the day was said.
///
/// Anything else stays in the title as typed: `@5`, `@someone`, `a@b.com`. Pure, in the logic target.
enum TaskQuickAdd {
    struct Parsed: Equatable {
        /// The name with every token taken out, words one space apart; "" when only tokens were typed.
        let title: String
        /// In typed order, cleaned as the tag field cleans them (`TaskItem.cleanedTags`).
        let tags: [String]
        let reminder: Date?
        /// The words read as tokens, as typed and one space apart: what a field keeps after the
        /// name when the name is replaced (a task picked from the typed search).
        let tokenText: String

        var hasTokens: Bool { !tags.isEmpty || reminder != nil }
    }

    static let morningHour = 9
    static let eveningHour = 18
    static let tonightHour = 20
    /// A day with no time: 9:00, as a morning would be.
    static let dayHour = 9

    static func parse(_ text: String, now: Date, calendar: Calendar) -> Parsed {
        var titleWords: [Substring] = []
        var tokenWords: [Substring] = []
        var tags: [String] = []
        var day: Day?
        var time: (hour: Int, minute: Int)?
        for word in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            if let tag = tag(in: word) {
                tags.append(tag)
                tokenWords.append(word)
            } else if let when = when(in: word) {
                // A later word of the same kind wins: "@today @tomorrow" is tomorrow.
                if let whenDay = when.day { day = whenDay }
                if let whenTime = when.time { time = whenTime }
                tokenWords.append(word)
            } else {
                titleWords.append(word)
            }
        }
        return Parsed(
            title: titleWords.joined(separator: " "),
            tags: TaskItem.cleanedTags(tags),
            reminder: reminder(day: day, time: time, now: now, calendar: calendar),
            tokenText: tokenWords.joined(separator: " ")
        )
    }

    /// The title alone, for what needs no clock: search, and finding a task by name.
    static func title(of text: String) -> String {
        parse(text, now: Date(timeIntervalSinceReferenceDate: 0), calendar: Calendar(identifier: .gregorian)).title
    }

    // MARK: - Words

    private enum Day: Equatable {
        case today, tomorrow
        /// `Calendar`'s weekday: 1 is Sunday.
        case weekday(Int)
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    /// Punctuation that may follow a token in a sentence: "call Sam @noon," is still noon.
    private static let trailingPunctuation = CharacterSet(charactersIn: ",.;:!?")

    private static func tag(in word: Substring) -> String? {
        guard word.hasPrefix("#") else { return nil }
        let name = word.dropFirst().trimmingCharacters(in: trailingPunctuation)
        guard let first = name.first, first.isLetter,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return name
    }

    private static func when(in word: Substring) -> (day: Day?, time: (hour: Int, minute: Int)?)? {
        guard word.hasPrefix("@") else { return nil }
        let name = word.dropFirst().trimmingCharacters(in: trailingPunctuation).lowercased()
        switch name {
        case "noon": return (nil, (12, 0))
        case "morning": return (nil, (morningHour, 0))
        case "evening": return (nil, (eveningHour, 0))
        // A time of day like the others: after 20:00 it rolls to tomorrow's.
        case "tonight": return (nil, (tonightHour, 0))
        case "today": return (.today, nil)
        case "tomorrow", "tmrw": return (.tomorrow, nil)
        default: break
        }
        if let weekday = weekdays[name] { return (.weekday(weekday), nil) }
        if let clock = clockTime(name) { return (nil, clock) }
        return nil
    }

    /// `5pm`, `5:30pm`, `12am`, `9am`, `17:30`, `09:05`. A bare number (`@5`) is not a time: it
    /// could be anything.
    private static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        var body = Substring(text)
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body = body.dropLast(2)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts[0].count <= 2, let hour = Int(parts[0]) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let minutes = Int(parts[1]), minutes < 60 else { return nil }
            minute = minutes
        }
        switch meridiem {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            return (hour == 12 ? 0 : hour, minute)
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            return (hour == 12 ? 12 : hour + 12, minute)
        default:
            // 24-hour, and only with minutes: "@17:30", never "@17".
            guard parts.count == 2, (0...23).contains(hour) else { return nil }
            return (hour, minute)
        }
    }

    // MARK: - The reminder

    private static func reminder(day: Day?, time: (hour: Int, minute: Int)?, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        func at(_ dayStart: Date, _ hour: Int, _ minute: Int) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
        }
        func addingDays(_ days: Int, to date: Date) -> Date? {
            calendar.date(byAdding: .day, value: days, to: date)
        }
        switch (day, time) {
        case (nil, nil):
            return nil
        case (nil, let time?):
            // A time that has passed today rolls to tomorrow.
            guard let todayAt = at(today, time.hour, time.minute) else { return nil }
            if todayAt > now { return todayAt }
            return addingDays(1, to: today).flatMap { at($0, time.hour, time.minute) }
        case (.today?, let time?):
            // The day was said: today, even past, and the reminder shows overdue.
            return at(today, time.hour, time.minute)
        case (.today?, nil):
            return TaskFormDraft.defaultReminder(now: now, calendar: calendar)
        case (.tomorrow?, let time):
            return addingDays(1, to: today).flatMap { at($0, time?.hour ?? dayHour, time?.minute ?? 0) }
        case (.weekday(let weekday)?, let time):
            let hour = time?.hour ?? dayHour, minute = time?.minute ?? 0
            let ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7
            guard let dayStart = addingDays(ahead, to: today), let candidate = at(dayStart, hour, minute) else { return nil }
            if candidate > now { return candidate }
            return addingDays(7, to: dayStart).flatMap { at($0, hour, minute) }
        }
    }
}
