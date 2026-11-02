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

/// The done tick before a local task, the checklist pattern of Reminders and Things: an empty
/// circle that shows a check under the pointer and fills when clicked. The task then leaves its
/// list after `TaskDoneTicks.undoSeconds`, and a second click before that takes the tick back
/// (`TasksManager.toggleDone`). Values only, like `TaskTimingButton`, so a row observes nothing.
/// It sits in the notch too, so the tooltip is `.hoverTooltip`, never a help tag (docs/TOOLTIPS.md).
struct TaskDoneTick: View {
    let title: String
    let isTicked: Bool
    var isEnabled = true
    var size: CGFloat = 13
    var tooltipEdge: HoverTooltipEdge = .above
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            if reduceMotion {
                toggle()
            } else {
                withAnimation(.snappy(duration: 0.18), toggle)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(isTicked ? Color.primary : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .hoverTooltip(isTicked ? String(localized: "Undo") : String(localized: "Mark done"),
                      edge: tooltipEdge, alignment: .leading, isHovering: isHovered)
        .accessibilityLabel(Text(verbatim: isTicked
            ? String(localized: "Mark \(title) not done")
            : String(localized: "Mark \(title) done")))
    }

    private var symbol: String {
        if isTicked { return "checkmark.circle.fill" }
        return isHovered && isEnabled ? "checkmark.circle" : "circle"
    }
}
