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

/// One of the window's cards: a pillar's name over what it brings. VoiceOver reads the two together.
struct WhatsNewCard: Identifiable, Equatable {
    let title: String
    let text: String

    var id: String { title }
}

/// What the What's New window says: its title, the line under it, one card per pillar and its one button. The window
/// and its snapshot board both draw `kannu2(bundle:)`, so a board shows exactly what the window shows.
struct WhatsNewContent: Equatable {
    let title: String
    let line: String
    let cards: [WhatsNewCard]
    let button: String

    /// Kannu 2.0's welcome, with a card each for Brain, Tasks and Tags (openspec `whats-new`). Read from `bundle`'s
    /// catalog: the app's own as the window opens, or one language's for a board.
    static func kannu2(bundle: Bundle = .main) -> WhatsNewContent {
        WhatsNewContent(
            title: String(localized: "Welcome to Kannu 2.0", bundle: bundle),
            line: String(localized: "The notch is the front door. Brain is the room behind it.", bundle: bundle),
            cards: [
                WhatsNewCard(
                    title: String(localized: "Brain", bundle: bundle, comment: "A name, never translated: Kannu's main window."),
                    text: String(localized: "Settings is now Brain: pages for your agents, tasks, notes and more, full screen, with a menu bar of its own.", bundle: bundle)
                ),
                // The sidebar's own key for the Tasks page (`SettingsTab.title`), so the card never names it differently.
                WhatsNewCard(
                    title: String(localized: "Tasks", bundle: bundle),
                    text: String(localized: "Jira, GitLab, GitHub, Linear, Todoist and Reminders, beside your own. Open a task beside the list, time it, and log the time.", bundle: bundle)
                ),
                WhatsNewCard(
                    title: String(localized: "Tags", bundle: bundle),
                    text: String(localized: "Type #launch or @3pm in a task's name for a tag or a reminder, shown as chips. Filter any list by tag.", bundle: bundle, comment: "#launch and @3pm are what the user types, so they stay tokens the parser reads. @3pm may become @15:00 where clocks are 24-hour.")
                ),
            ],
            button: String(localized: "Continue", bundle: bundle)
        )
    }
}

/// The What's New window's content, as `WhatsNewWindow` hosts it. Drawn as an onboarding step is (docs/SETTINGS.md,
/// "Onboarding"): the title and one line under it, the cards, then Continue trailing, which Return presses.
///
/// A window of its own, so it applies Brain's root itself and paints the panel under the title bar, in light and dark.
/// It runs under that bar whether or not the hosting view is told of it: the root ignores the safe area and starts its
/// text `titleBarHeight` down. Nothing in it animates, so Reduce Motion has nothing to stop.
struct WhatsNewView: View {
    /// Two lines of English per card, with room for the third that longer languages need. The height follows the
    /// content (`WhatsNewWindow`), so a card grows with its text and never cuts it short.
    static let width: CGFloat = 480

    let content: WhatsNewContent
    /// The window's title bar, which the content runs under. 0 on a board, which has none.
    var titleBarHeight: CGFloat = 0
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                Text(content.title)
                    .font(SettingsTheme.pageTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Text(content.line)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(spacing: SettingsTheme.listRowGap) {
                ForEach(content.cards) { card in
                    WhatsNewCardView(card: card)
                }
            }

            Button(content.button, action: onContinue)
                .buttonStyle(SettingsButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, SettingsTheme.pageInset)
        .padding(.vertical, SettingsTheme.sectionGap)
        .padding(.top, titleBarHeight)
        .frame(width: Self.width, alignment: .topLeading)
        .background(SettingsTheme.panel)
        .ignoresSafeArea()
        .settingsDesignSystem()
    }
}

/// A card as a status cell's is drawn (docs/SETTINGS.md, "The content standard"): its title in `cardTitle` over its
/// text in `body` on `inkSecondary`, on the card's colour. Not a button, so its text stays selectable.
private struct WhatsNewCardView: View {
    let card: WhatsNewCard

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
            Text(card.title)
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)

            Text(card.text)
                .font(SettingsTheme.body)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SettingsMetrics.cardPadding)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        // One element, so VoiceOver reads the card's title and its text together.
        .accessibilityElement(children: .combine)
    }
}
