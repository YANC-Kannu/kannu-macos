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

import Combine
import Defaults
import SwiftUI

/// Brain › Timer's product, above its settings: the running timer with Pause and Stop, then the presets as start tiles
/// (docs/SETTINGS.md, "Product pages"). The notch is the timer's main surface, so the page stays lean: one timer and
/// one list.
///
/// It starts, pauses and stops a timer only on a press, through the calls the notch's popover makes. Brain's content is
/// built once and kept for the app's life, and a running timer publishes three changes a second, so the page keeps the
/// live-data contract (docs/SETTINGS.md, "Live data"):
/// 1. **Throttled and scoped.** What the page shows is copied into one value, `TimerPageData`, from one subscription to
///    the manager's `objectWillChange`, at most twice a second, and assigned only when it changed. Nothing here
///    observes the manager whole.
/// 2. **Stopped while Brain is not on screen.** That subscription is a `.task(id:)` on `BrainVisibility.isOnScreen`, so
///    it ends when Brain is closed, minimised, hidden, covered or in another Space, and starts again on its return.
/// 3. **No clock of its own.** The time moves with the manager's own tick, once a second: each tick is a change the
///    throttle lets through, so the page shows what the notch shows, at most half a second later. The manager keeps no
///    deadline, it counts `remainingTime` down and a pause stops the count, so a clock here (a `TimelineView`, a
///    `Timer`, a counting `Text`) would be a second clock that could disagree with the notch, and would tick on while a
///    timer stood paused. Off screen the copy stays as it was, and it is read again the moment Brain is back.
struct TimerOverview: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableTimerFeature) private var timerOn
    @Default(.timerPresets) private var storedPresets
    @State private var data = TimerPageData()
    /// The preset being added or edited, in its sheet.
    @State private var editing: TimerPresetSheet.Target?
    @State private var confirmingRestore = false

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's timer, presets and switch, so none
    /// of them lands in a PNG. Set, the page never subscribes.
    static var snapshotFixture: TimerOverviewFixture?
    #endif

    private var isOn: Bool {
        #if DEBUG
        if let fixture = Self.snapshotFixture { return fixture.timerOn }
        #endif
        return timerOn
    }

    private var presets: [TimerPreset] {
        #if DEBUG
        if let fixture = Self.snapshotFixture { return fixture.presets }
        #endif
        return storedPresets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if !isOn {
                // The notch shows no timer while the feature is off, so a start here would show nowhere.
                TimerMessageCard(title: String(localized: "Timer is off"), message: nil) {
                    Button("Turn on") { timerOn = true }
                }
            } else {
                if data.isActive {
                    TimerRunningCard(data: data, refresh: { copyFromManager() })
                } else {
                    // Its one action is the tiles right under it.
                    TimerMessageCard(title: String(localized: "No timer running"),
                                     message: String(localized: "Click a preset below to start a timer.")) {
                        EmptyView()
                    }
                }
                presetTiles
            }
        }
        .onAppear {
            #if DEBUG
            if let fixture = Self.snapshotFixture {
                data = fixture.data
                return
            }
            #endif
            // One read, not a subscription: the page opens on what runs now, and the subscription below takes over once
            // Brain is on screen.
            copyFromManager()
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if Self.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            // Back on screen: what changed while Brain was not, which `objectWillChange` will not send again.
            copyFromManager()
            // `objectWillChange` comes before a change; read through the run loop, the copy comes after it.
            for await _ in TimerManager.shared.objectWillChange
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                copyFromManager()
            }
        }
        // An edit of the presets shows on the running timer at once (its colour, its tile's ring), even while it stands
        // paused and the manager publishes nothing. A read, not a subscription; it runs only while Brain is open.
        .onChange(of: storedPresets) { _, _ in copyFromManager() }
        .sheet(item: $editing) { target in
            TimerPresetSheet(target: target)
        }
        .confirmationDialog("Restore default timer presets?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { storedPresets = TimerPreset.defaultPresets }
        }
    }

    /// The one place the page reads the manager's state: a fresh copy, assigned only when it changed. Also called right
    /// after a press, so the card never shows the old state for the throttle's half second.
    private func copyFromManager() {
        #if DEBUG
        if Self.snapshotFixture != nil { return }
        #endif
        let latest = TimerPageData(TimerManager.shared)
        if latest != data { data = latest }
    }

    // MARK: - The presets

    /// The presets as start tiles, in their order, then Add Preset. Search's "Timer Presets", found by "accent colour"
    /// too, lands on the heading, which is built whenever the timer is on: a preset's colour is set in its sheet.
    private var presetTiles: some View {
        let shown = presets
        return VStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
            HStack(spacing: SettingsMetrics.rowContent) {
                SettingsSectionHeader("Presets")
                    .settingsHighlight(id: SettingsTab.timer.highlightID(for: "Timer Presets"))
                Spacer(minLength: SettingsMetrics.rowContent)
                // Named for what it belongs to, as each tile's is: VoiceOver would otherwise hear "More" alone.
                SettingsMoreMenu(accessibilityLabel: Text(verbatim: String(localized: "Presets") + ", " + String(localized: "More"))) {
                    Button("Restore defaults") { confirmingRestore = true }
                }
            }
            .padding(.leading, SettingsTheme.sectionPadding.leading)
            SettingsFlowLayout(spacing: SettingsMetrics.cardPadding) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, preset in
                    TimerPresetTile(preset: preset,
                                    isRunning: data.isActive && data.presetID == preset.id,
                                    isFirst: index == 0,
                                    isLast: index == shown.count - 1,
                                    refresh: { copyFromManager() },
                                    edit: { editing = .edit(preset) },
                                    move: { move(preset, by: $0) },
                                    delete: { storedPresets.removeAll { $0.id == preset.id } })
                }
                TimerAddTile { editing = .add }
            }
        }
    }

    /// One place up (-1) or down (1) in the list, as the notch's preset list orders them.
    private func move(_ preset: TimerPreset, by offset: Int) {
        guard let index = storedPresets.firstIndex(where: { $0.id == preset.id }),
              storedPresets.indices.contains(index + offset) else { return }
        storedPresets.swapAt(index, index + offset)
    }
}

/// Timer's header actions (docs/SETTINGS.md, "Product pages"): the gear, which goes to the page's settings, then Start
/// timer, the page's one primary verb. Start timer starts the custom timer at its stored length, on a press only, as the
/// popover's Start Custom Timer does. It is off while a timer runs, as the popover hides its own start then; off while
/// the timer is off; and off at a length of 0:00, which would ring a second after it started.
struct TimerHeaderActions: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableTimerFeature) private var timerOn
    /// The custom timer's length, which Timer settings › Custom Timer and the popover set.
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    /// Whether a timer runs, followed only while Brain is on screen.
    @State private var running = false

    private var isOn: Bool {
        #if DEBUG
        if let fixture = TimerOverview.snapshotFixture { return fixture.timerOn }
        #endif
        return timerOn
    }

    private var isRunning: Bool {
        #if DEBUG
        if let fixture = TimerOverview.snapshotFixture { return fixture.data.isActive }
        #endif
        return running
    }

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            Button {
                // The first settings row, which is always built.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.timerFeatureHighlightID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Timer settings"))
            .accessibilityLabel(String(localized: "Timer settings"))
            Button("Start timer") {
                // Read at the press: the popover's own start, with no typed name, and never over a running timer.
                let length = customTimerDuration
                guard length > 0, !Self.timerRunsNow() else { return }
                let name = String(localized: "Custom Timer")
                TimerManager.shared.startTimer(duration: length, name: name, fallbackName: name)
            }
            .buttonStyle(SettingsButtonStyle(.primary))
            .disabled(isRunning || !isOn || customTimerDuration <= 0)
        }
        // One value, passed on only when it changes; `$isTimerActive` sends the current one as it subscribes.
        .task(id: visibility.isOnScreen) {
            guard visibility.isOnScreen else { return }
            for await active in TimerManager.shared.$isTimerActive
                .removeDuplicates()
                .values {
                running = active
            }
        }
    }

    /// Whether a timer runs, read from the manager at Start timer's press, never from `running`: that stays false until
    /// the task above first reads the manager, and a start then would replace the running timer.
    private static func timerRunsNow() -> Bool {
        TimerManager.shared.isTimerActive
    }
}

// MARK: - The running timer

/// The running timer, in the hero's three bands. Top: its state as the title, red in overtime, with the session's colour
/// beside it. Middle: its name, with a timed task's key, or where a mirrored timer comes from. Bottom, pinned: the time
/// left, large, over its length, with Pause or Resume and Stop at the right, then how much has run. A timer mirrored from
/// the Clock app is paused and stopped there, so it has no buttons here, as in the notch.
private struct TimerRunningCard: View {
    let data: TimerPageData
    /// Reads the manager again right after a press, so Pause never stays on screen for the throttle's half second after
    /// a click, where a second click would act against what the card shows.
    let refresh: () -> Void

    private var stateTitle: String {
        if data.isOvertime { return String(localized: "Overtime") }
        if data.isPaused { return String(localized: "Paused") }
        return String(localized: "Running")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardPadding) {
            HStack(spacing: SettingsMetrics.rowContent) {
                Text(verbatim: stateTitle)
                    .font(SettingsTheme.cardTitle)
                    .foregroundStyle(data.isOvertime ? SettingsTheme.destructive : SettingsTheme.ink)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Circle()
                    .fill(data.accent ?? SettingsTheme.accent)
                    .frame(width: SettingsMetrics.statusDot, height: SettingsMetrics.statusDot)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: data.name)
                    .font(SettingsTheme.sheetTitle)
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
                if let key = data.taskKey {
                    Text(verbatim: key)
                        .settingsDescriptionStyle()
                }
                if data.isMirrored {
                    Text("Mirrored from the Clock app")
                        .settingsDescriptionStyle()
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: SettingsMetrics.rowContent) {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                    Text(verbatim: data.time)
                        .font(SettingsTheme.pageTitle)
                        .monospacedDigit()
                        .foregroundStyle(data.isOvertime ? SettingsTheme.destructive : SettingsTheme.ink)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text(verbatim: TimerPageData.spoken(data.remaining)))
                    Text("of \(data.length)")
                        .settingsDescriptionStyle()
                        .accessibilityLabel(Text("of \(TimerPageData.spoken(data.total))"))
                }
                Spacer(minLength: SettingsMetrics.rowContent)
                if !data.isMirrored {
                    // Paused in overtime still needs Resume, as on every timer surface.
                    if data.offersPause {
                        Button {
                            Self.togglePause()
                            refresh()
                        } label: {
                            Text(verbatim: data.isPaused ? String(localized: "Resume") : String(localized: "Pause"))
                        }
                    }
                    Button {
                        Self.stop()
                        refresh()
                    } label: {
                        Text(verbatim: String(localized: "Stop"))
                    }
                }
            }
            TimerProgressBar(fraction: data.fraction,
                             tint: data.isOvertime ? SettingsTheme.destructive : (data.accent ?? SettingsTheme.accent))
        }
        .padding(SettingsTheme.heroPadding)
        .frame(maxWidth: .infinity, minHeight: SettingsTheme.heroMinHeight, alignment: .topLeading)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Timer"))
    }

    /// The notch's own toggle, read at the press, never from the copy, which can be half a second old.
    private static func togglePause() {
        let manager = TimerManager.shared
        guard manager.allowsManualInteraction else { return }
        manager.isPaused ? manager.resumeTimer() : manager.pauseTimer()
    }

    /// The notch's Stop: a timer started in Kannu ends, with the notch's smooth close.
    private static func stop() {
        let manager = TimerManager.shared
        guard manager.allowsManualInteraction else { return }
        manager.stopTimer()
    }
}

/// How much of the timer has run: the slider's track, filled up to that share, full in overtime. At nothing run it keeps
/// a dot, so the fill's start still shows.
private struct TimerProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(SettingsTheme.line)
            .frame(maxWidth: .infinity)
            .frame(height: SettingsTheme.sliderTrackHeight)
            .overlay(alignment: .leading) {
                TimerProgressFill(fraction: fraction)
                    .fill(tint)
            }
            .accessibilityHidden(true)
    }
}

/// The filled part of the bar: a capsule as wide as the share run, never narrower than it is tall.
private struct TimerProgressFill: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let width = max(rect.height, rect.width * min(max(fraction, 0), 1))
        return Capsule().path(in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
    }
}

// MARK: - The tiles

/// One preset as a start tile: its colour and name over its length. A click starts it, as the notch's preset list does,
/// replacing a timer that runs; the tile of the running preset wears the ring a chosen card does. A preset of 0:00, which
/// only an older version could save, does not start. Its less frequent actions sit in the ⋯ over its corner, never
/// inside its button, and in its right-click menu.
private struct TimerPresetTile: View {
    let preset: TimerPreset
    let isRunning: Bool
    let isFirst: Bool
    let isLast: Bool
    /// Reads the manager again right after the start, as the running card's buttons do.
    let refresh: () -> Void
    let edit: () -> Void
    let move: (Int) -> Void
    let delete: () -> Void

    /// The ⋯'s name for VoiceOver, with the preset's, so a row of tiles is not a row of "More"s.
    private var menuLabel: String {
        [preset.name, String(localized: "More")].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        Button {
            TimerManager.shared.startTimer(duration: preset.duration, name: preset.name, preset: preset,
                                           fallbackName: preset.name)
            refresh()
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                HStack(spacing: SettingsMetrics.rowContent) {
                    Circle()
                        .fill(preset.color)
                        .frame(width: SettingsMetrics.statusDot, height: SettingsMetrics.statusDot)
                    // A label inside the tile's button, so it stays unselectable: selectable text swallows the click.
                    Text(verbatim: preset.name)
                        .font(SettingsTheme.bodyStrong)
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
                Text(verbatim: preset.formattedDuration)
                    .font(SettingsTheme.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(SettingsTheme.ink)
            }
            .padding(SettingsMetrics.cardPadding)
            .frame(width: SettingsTheme.tileWidth, alignment: .leading)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
            .settingsChoiceRing(RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous), isSelected: isRunning)
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(preset.duration <= 0)
        .accessibilityLabel(Text(verbatim: preset.name))
        .accessibilityValue(Text(verbatim: TimerPageData.spoken(preset.duration)))
        .accessibilityAddTraits(isRunning ? .isSelected : [])
        .overlay(alignment: .bottomTrailing) {
            SettingsMoreMenu(accessibilityLabel: Text(verbatim: menuLabel)) {
                menuItems
            }
            .padding(SettingsMetrics.rowContent)
        }
        .contextMenu {
            menuItems
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Edit…", action: edit)
        Button("Move up") { move(-1) }
            .disabled(isFirst)
        Button("Move down") { move(1) }
            .disabled(isLast)
        Divider()
        Button("Delete", role: .destructive, action: delete)
    }
}

/// The last tile: Add Preset, which opens the sheet for a new one. As tall as a preset's tile, so a row lines up.
private struct TimerAddTile: View {
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text("Add preset")
                    .font(SettingsTheme.bodyStrong)
                Image(systemName: "plus")
                    .font(SettingsTheme.cardTitle)
            }
            .foregroundStyle(SettingsTheme.inkSecondary)
            .padding(SettingsMetrics.cardPadding)
            .frame(width: SettingsTheme.tileWidth, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.line, lineWidth: SettingsTheme.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The card in the timer's place

/// The running timer's place when none runs, or the page's while the timer is off: the page's glyph, the status, at most
/// one line that teaches, and at most one action (docs/SETTINGS.md, "Product pages"), as Agents' message card.
private struct TimerMessageCard<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.timer.systemImage)
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
            if let message {
                // The body's size on the secondary ink: an empty state's one line teaches, so it reads as text.
                Text(verbatim: message)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: SettingsTheme.proseMaxWidth)
            }
            action()
        }
        .padding(SettingsTheme.heroPadding)
        .frame(maxWidth: .infinity, minHeight: SettingsTheme.heroMinHeight)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The data

/// What Brain › Timer shows of the timer, copied in one value, so one throttled subscription carries it and the page
/// redraws only when it changed (docs/SETTINGS.md, "Live data"). Its `init` is the one place the page reads the manager's
/// state; the buttons read it again at the press.
struct TimerPageData: Equatable {
    var isActive = false
    var name = ""
    /// The time left as the notch writes it ("18:42", "-2:15" in overtime), and the whole length ("25:00").
    var time = ""
    var length = ""
    /// The seconds left, below zero in overtime, and the whole length's, for VoiceOver.
    var remaining: TimeInterval = 0
    var total: TimeInterval = 0
    /// How much of the length has run, 0 to 1: full in overtime.
    var fraction = 0.0
    var isPaused = false
    var isOvertime = false
    /// Pause or Resume shows, unless the timer runs in overtime: paused there, it still needs Resume.
    var offersPause = true
    /// A Clock-app timer the manager mirrors, which the Clock app pauses and stops.
    var isMirrored = false
    /// The session's colour: the timed task's, else its preset's.
    var accent: Color?
    /// The preset the timer started from, whose tile wears the ring.
    var presetID: UUID?
    /// A timed task's short key ("ds-vendors #4264").
    var taskKey: String?

    init() {}

    /// The manager as it is now. Nothing while no timer runs, so an idle copy never changes.
    @MainActor
    init(_ timerManager: TimerManager) {
        guard timerManager.isTimerActive else { return }
        isActive = true
        name = timerManager.timerName
        time = timerManager.formattedRemainingTime()
        length = timerManager.formattedTotalDuration()
        remaining = timerManager.remainingTime
        total = timerManager.totalDuration
        fraction = min(1, max(0, timerManager.progress))
        isPaused = timerManager.isPaused
        isOvertime = timerManager.isOvertime
        offersPause = !timerManager.isOvertime || timerManager.isPaused
        isMirrored = timerManager.isExternalTimerActive
        accent = timerManager.sessionAccent
        presetID = timerManager.activePresetId
        taskKey = timerManager.sessionTaskKey
    }

    /// A length or the time left in words, "18 minutes, 42 seconds": "18:42" read aloud is a clock time, not a length.
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(abs(seconds))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

#if DEBUG
/// DEBUG snapshot boards only: what `TimerOverview` and its header show in place of this Mac's timer, presets and switch.
struct TimerOverviewFixture {
    var data: TimerPageData
    var presets: [TimerPreset]
    /// The timer feature: off, the page shows its off state in place of the timer and the tiles.
    var timerOn = true
}
#endif
