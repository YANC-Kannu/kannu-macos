/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

/// The onboarding window's steps, in order. Nothing in it plays a sound or raises a macOS dialog by
/// itself: `.permissions` asks for each permission only when the user presses Allow, and the
/// welcome music and the notch's hello wait for Finish. Each step is drawn as a sheet is, on a page's insets: its
/// title, a line under it, its cards, then its buttons trailing (docs/SETTINGS.md, "Onboarding").
enum OnboardingStep: CaseIterable {
    case welcome
    case musicSource
    case profileSelection
    case trafficLightStyle
    case caffeinateChoice
    case notes
    case permissions
    case finished
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    /// Applied when onboarding ends: switching to Spotify or Apple Music talks to the app at once,
    /// and that Automation dialog belongs to the Permissions step.
    @State private var musicSource: MediaControllerType = Defaults[.mediaController]
    /// Applied when onboarding ends, for the same reason: syncing with Apple Notes talks to Notes.
    @State private var notesChoice: OnboardingNotesChoice = .off
    let onLaunchAtLoginChoice: (Bool) -> Void
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    advance(to: .musicSource)
                }
                .transition(.opacity)

            case .musicSource:
                MusicControllerSelectionView(
                    onContinue: { source in
                        musicSource = source
                        advance(to: .profileSelection)
                    }
                )
                .transition(.opacity)

            case .profileSelection:
                ProfileSelectionView(
                    onContinue: { profiles in
                        applyProfileSettings(profiles)
                        advance(to: .trafficLightStyle)
                    }
                )
                .transition(.opacity)

            case .trafficLightStyle:
                TrafficLightStyleSelectionView(
                    onContinue: {
                        advance(to: .caffeinateChoice)
                    }
                )
                .transition(.opacity)

            case .caffeinateChoice:
                CaffeinateSelectionView(
                    onContinue: {
                        advance(to: .notes)
                    }
                )
                .transition(.opacity)

            case .notes:
                NotesSelectionView(
                    onContinue: { choice in
                        notesChoice = choice
                        advance(to: .permissions)
                    }
                )
                .transition(.opacity)

            case .permissions:
                // Rows read the settings the profile step just applied.
                PermissionsStepView(
                    rows: LaunchPermissionManager.rows(
                        musicSource: musicSource,
                        appleNotesSync: notesChoice.syncsWithAppleNotes
                    ),
                    musicSource: musicSource,
                    onLaunchAtLoginChoice: onLaunchAtLoginChoice,
                    onContinue: {
                        advance(to: .finished)
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(
                    onFinish: {
                        applyMusicSource()
                        applyNotesChoice()
                        onFinish()
                    },
                    onOpenSettings: {
                        applyMusicSource()
                        applyNotesChoice()
                        onOpenSettings()
                    }
                )
            }
        }
        .frame(width: 400, height: 600)
        // A window of its own, so it takes Brain's root itself, as a sheet does (docs/SETTINGS.md, "The design system"):
        // the panel under every step and the title bar, and Brain's type, buttons and switches.
        .background(SettingsTheme.panel.ignoresSafeArea())
        .settingsDesignSystem()
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.6)) {
            step = next
        }
    }

    /// The source chosen on the second step. After a Not now on its "Control …" row, Now Playing
    /// instead, which needs no Automation, so nothing asks later; the user can pick the app again
    /// in Brain › Settings › Media, where macOS asks in context.
    private func applyMusicSource() {
        var source = musicSource
        if LaunchPermissionManager.answer(for: .musicAutomation) == .deferred,
           !MusicManager.shared.isNowPlayingDeprecated {
            source = .nowPlaying
        }
        Defaults[.mediaController] = source
        NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
    }

    /// The Notes step's choice. After a Not now on "Control Notes", the notes stay in the notch with
    /// sync off, so nothing asks later.
    private func applyNotesChoice() {
        notesChoice.apply(notesAutomationDeferred: LaunchPermissionManager.answer(for: .notesAutomation) == .deferred)
    }
}

#if DEBUG
extension OnboardingView {
    /// Boards only (`--kannu-snapshots`): the window's view, opened at `step`, so a board draws what the window hosts.
    /// Spotify is the source, so the Permissions step names an app. Nothing on a board is pressed.
    init(snapshotStep: OnboardingStep) {
        self.init(onLaunchAtLoginChoice: { _ in }, onFinish: {}, onOpenSettings: {})
        _step = State(initialValue: snapshotStep)
        _musicSource = State(initialValue: .spotify)
    }
}
#endif
