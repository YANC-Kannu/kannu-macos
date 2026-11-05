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

/// The trailing column of a Recent chats row: this request's run time, and under it its tool calls
/// and tokens ("1h 53m 54s" / "212 tools · 83k in · 40k out · 458k context"; "Ran 2h 3m 12s" once it
/// ended).
///
/// Observes the token follower itself, so a token update re-renders this column only — never the
/// list (whose rows each resolve a click-through target). Only a running request ticks, once a
/// second, and nothing animates. No `.help` and no nested tooltip: the row's Button owns the hover
/// (docs/REGRESSIONS.md entry 9). Digits are never cut: each line falls back to a shorter form, or
/// to nothing, when it does not fit.
///
/// Brain's hero draws the same numbers as figures instead (`figures`): side by side, each over a label.
struct AgentTurnMetricsView: View {
    let session: AgentSessionStatus
    /// The primary card's larger type.
    var prominent = false
    /// Brain's type in place of the notch's (Brain › Agents); nil keeps the notch's.
    var font: Font? = nil
    /// Brain's hero (Brain › Agents): figures in `font`, from the leading edge. Nil keeps the trailing column, as the
    /// notch and Brain's rows draw it.
    var figures: Figures? = nil

    /// A figure's colour, its label under it, and the room between two figures: Brain's theme, which this view does not
    /// know.
    struct Figures {
        let numberColor: Color
        let labelFont: Font
        let labelColor: Color
        let spacing: CGFloat
    }

    @ObservedObject private var follower = ClaudeTurnTokenFollower.shared

    var body: some View {
        if let figures {
            if let display = AgentTurnMetricsView.display(for: session) {
                liveFigures(display, figures)
            }
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let display = AgentTurnMetricsView.display(for: session) {
                    column(display)
                        .layoutPriority(1)
                }
            }
        }
    }

    /// The figures, live: the run time ticks once a second while the request runs, and the tokens follow the follower.
    private func liveFigures(_ display: AgentTurnDisplay, _ figures: Figures) -> some View {
        let toolCalls = session.turn?.toolCalls ?? 0
        let tokens = self.tokens
        return Self.figureRow(runTime: runTime(display), toolCalls: toolCalls, tokens: tokens, font: font, figures: figures)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AgentTurnFormat.accessibilityText(display, now: Date(), toolCalls: toolCalls, tokens: tokens))
    }

    @ViewBuilder
    private func runTime(_ display: AgentTurnDisplay) -> some View {
        switch display {
        case let .live(since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentTurnFormat.duration(context.date.timeIntervalSince(since)))
            }
        case let .ended(interval):
            Text(AgentTurnFormat.duration(interval))
        }
    }

    /// The figures side by side: the run time, then the tool calls and the turn's tokens when there are any, each number
    /// over its label. Brain's static copy, drawn while Brain is not on screen, passes the run time as it froze and no
    /// tokens.
    static func figureRow(runTime: some View, toolCalls: Int, tokens: TurnTokens?, font: Font?, figures: Figures) -> some View {
        HStack(alignment: .top, spacing: figures.spacing) {
            figure(runTime, label: String(localized: "Run time"), font: font, figures: figures)
            if toolCalls > 0 {
                figure(Text(toolCalls.formatted()), label: String(localized: "Tools"), font: font, figures: figures)
            }
            if let tokens {
                figure(Text(verbatim: "\(AgentTurnFormat.compact(tokens.newInput)) · \(AgentTurnFormat.compact(tokens.output))"),
                       label: String(localized: "Tokens in · out"), font: font, figures: figures)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    private static func figure(_ number: some View, label: String, font: Font?, figures: Figures) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            number
                .font(font)
                .foregroundStyle(figures.numberColor)
            Text(label)
                .font(figures.labelFont)
                .foregroundStyle(figures.labelColor)
        }
    }

    static func display(for session: AgentSessionStatus) -> AgentTurnDisplay? {
        AgentTurnDisplay.duration(turn: session.turn, executionStartedAt: session.executionStartedAt,
                                  state: session.displayState, hookReportsWork: session.hasActiveRawState,
                                  updatedAt: session.updatedAt)
    }

    /// Tokens only when they belong to this card's current turn.
    private var tokens: TurnTokens? {
        guard let turn = session.turn, let tokens = follower.tokens[session.conversationID],
              tokens.startedAt == turn.startedAt, tokens.startOffset == turn.transcriptOffset else { return nil }
        return tokens
    }

    @ViewBuilder
    private func column(_ display: AgentTurnDisplay) -> some View {
        let toolCalls = session.turn?.toolCalls ?? 0
        let tokens = self.tokens
        let lines = AgentTurnFormat.metricsLines(toolCalls: toolCalls, tokens: tokens)
        VStack(alignment: .trailing, spacing: 2) {
            switch display {
            case let .live(since):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    durationLine(full: AgentTurnFormat.duration(context.date.timeIntervalSince(since)),
                                 short: AgentTurnFormat.shortDuration(context.date.timeIntervalSince(since)))
                }
            case let .ended(interval):
                durationLine(full: AgentTurnFormat.ran(AgentTurnFormat.duration(interval)),
                             short: AgentTurnFormat.ran(AgentTurnFormat.shortDuration(interval)))
            }
            // Widest first (`metricsLines` returns at most five); the first that fits is shown.
            ViewThatFits(in: .horizontal) {
                if lines.count > 0 { Text(lines[0]) }
                if lines.count > 1 { Text(lines[1]) }
                if lines.count > 2 { Text(lines[2]) }
                if lines.count > 3 { Text(lines[3]) }
                if lines.count > 4 { Text(lines[4]) }
                EmptyView()
            }
        }
        .font(font ?? (prominent ? .caption : .caption2))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentTurnFormat.accessibilityText(display, now: Date(), toolCalls: toolCalls, tokens: tokens))
    }

    private func durationLine(full: String, short: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(full)
            Text(short)
            EmptyView()
        }
    }
}
