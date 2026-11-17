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

import XCTest

/// The attention alert's wiring, which is AppKit and SwiftUI, so its text is read: off by default,
/// started only by the bridge inside `continueLaunch()`, gated on the Terms and onboarding, drawn on
/// the notch and on the lock-screen pill, a shimmer that ends by itself, and Reduce Motion's glow.
/// `AttentionAlertTests` pins the rules themselves.
final class AttentionAlertRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The code without its comment lines, so a comment that names a banned API is no offender.
    private static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The body of `func name(`, by brace matching from its first `{`.
    private static func body(ofFunction name: String, in text: String) -> String? {
        guard let start = text.range(of: "func \(name)("),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[open...index]) }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func appSources() throws -> [String: String] {
        let base = root.appendingPathComponent("Kannu")
        var result: [String: String] = [:]
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result[String(url.path.dropFirst(root.path.count + 1))] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    // MARK: - Off by default

    func testTheAlertIsOffByDefault() throws {
        let constants = try Self.source("Kannu/models/Constants.swift")
        XCTAssertTrue(constants.contains(#"static let attentionAlertEnabled = Key<Bool>("attentionAlertEnabled", default: false)"#))
    }

    // MARK: - Nothing before the Terms and onboarding

    func testOnlyTheBridgeStartsTheAlertAndOnlyContinueLaunchStartsTheBridge() throws {
        let sources = try Self.appSources()
        XCTAssertGreaterThan(sources.count, 100, "the scan read too few files")
        let starters = sources.filter { Self.code($0.value).contains("AttentionAlertManager.shared.start()") }.keys
        XCTAssertEqual(Set(starters), ["Kannu/managers/AgentStatus/AgentStatusNotificationBridge.swift"])
        let feeders = sources.filter { Self.code($0.value).contains("AttentionAlertManager.shared.handle(") }.keys
        XCTAssertEqual(Set(feeders), ["Kannu/managers/AgentStatus/AgentStatusNotificationBridge.swift"])

        let app = try XCTUnwrap(sources["Kannu/KannuApp.swift"])
        let launch = try XCTUnwrap(Self.body(ofFunction: "continueLaunch", in: app))
        let all = Self.code(app).components(separatedBy: "AgentStatusNotificationBridge.shared.start()").count - 1
        let inLaunch = Self.code(launch).components(separatedBy: "AgentStatusNotificationBridge.shared.start()").count - 1
        XCTAssertGreaterThan(all, 0)
        XCTAssertEqual(all, inLaunch, "the bridge, and with it the alert, starts only inside continueLaunch()")
    }

    func testTheManagerAsksEveryGate() throws {
        let manager = Self.code(try Self.source("Kannu/managers/AgentStatus/AttentionAlertManager.swift"))
        let handle = try XCTUnwrap(Self.body(ofFunction: "handle", in: manager))
        for gate in ["Defaults[.attentionAlertEnabled]",
                     "TermsOfUse.isAccepted(acceptedVersion: Defaults[.termsAcceptedVersion])",
                     "LaunchPermissionManager.isOnboardingComplete",
                     "now < quietUntil"] {
            XCTAssertTrue(handle.contains(gate), "handle(_:) no longer checks \(gate)")
        }
        XCTAssertTrue(manager.contains("private var quietUntil: Date = .distantFuture"), "silent until start()")
    }

    // MARK: - Where it draws

    func testItDrawsOnTheNotchAndOnTheLockScreenPill() throws {
        let content = try Self.source("Kannu/ContentView.swift")
        let fill = try XCTUnwrap(content.range(of: "private var notchBodyFill: some View {"))
        let afterFill = content[fill.upperBound...]
        let end = try XCTUnwrap(afterFill.range(of: "private var mainLayoutBase"))
        XCTAssertTrue(afterFill[..<end.lowerBound].contains("AttentionAlertOverlay()"), "the notch's body fill draws the alert")

        let lock = Self.code(try Self.source("Kannu/components/LockScreen/LockScreenLiveActivityOverlay.swift"))
        let overlay = try XCTUnwrap(lock.range(of: ".overlay { AttentionAlertOverlay("))
        let clip = try XCTUnwrap(lock.range(of: ".clipShape("))
        XCTAssertLessThan(overlay.lowerBound, clip.lowerBound, "the pill clips the alert to its shape")
    }

    /// CodeRabbit on #70: a second session turning yellow while another already is alerts without
    /// changing the aggregate light, and the reveal re-arms only on a light change, so a hide-until-hover
    /// island kept the flash off screen. Each flash reveals it, without observing the manager or
    /// touching the activity latch (docs/REGRESSIONS.md entry 10).
    func testEachFlashRevealsAHiddenIsland() throws {
        let content = Self.code(try Self.source("Kannu/ContentView.swift"))
        XCTAssertTrue(content.contains(".onReceive(AttentionAlertManager.shared.$flash.compactMap { $0?.id }.removeDuplicates()) { _ in\n                revealForAttentionFlash()"))
        XCTAssertFalse(content.contains("@ObservedObject private var attention"), "a subscription, not an observation")
        let reveal = try XCTUnwrap(Self.body(ofFunction: "revealForAttentionFlash", in: content))
        for step in ["agentLightDeadline = deadline", "revealHoldDeadline = deadline", "armRevealCountdown()",
                     "AttentionAlertTracker.flashDuration"] {
            XCTAssertTrue(reveal.contains(step), step)
        }
        XCTAssertFalse(reveal.contains("lastRevealedLightState"), "independent of the light's transitions")
        XCTAssertFalse(reveal.contains("consumeActivityPulseWasHeartbeatOnly"), "the latch keeps its one consumer")
    }

    // MARK: - Ends by itself; Reduce Motion

    /// Every way a flash could keep ticking with nothing on screen (docs/REGRESSIONS.md entry 22).
    static func problems(in overlay: String) -> [String] {
        let code = Self.code(overlay)
        var found: [String] = []
        for banned in ["repeatForever", "TimelineView", "Timer.", "CADisplayLink"] where code.contains(banned) {
            found.append(banned)
        }
        if !code.contains(".repeatCount(Self.sweeps, autoreverses: false)") { found.append("no finite repeatCount") }
        return found
    }

    func testTheShimmerEndsByItself() throws {
        XCTAssertEqual(Self.problems(in: try Self.source("Kannu/components/AgentStatus/AttentionAlertOverlay.swift")), [])
        let manager = Self.code(try Self.source("Kannu/managers/AgentStatus/AttentionAlertManager.swift"))
        XCTAssertFalse(manager.contains("Timer."), "one sleep per alert, never a timer")
    }

    func testTheCheckCatchesPlantedOffenders() {
        let good = "withAnimation(.easeInOut(duration: 1).repeatCount(Self.sweeps, autoreverses: false)) { phase = 1 }"
        XCTAssertEqual(Self.problems(in: good), [])
        XCTAssertEqual(Self.problems(in: good + "\n.animation(.linear.repeatForever(), value: phase)"), ["repeatForever"])
        XCTAssertEqual(Self.problems(in: good + "\nTimelineView(.animation) { _ in }"), ["TimelineView"])
        XCTAssertEqual(Self.problems(in: "withAnimation(.linear) { phase = 1 }"), ["no finite repeatCount"])
        XCTAssertEqual(Self.problems(in: good + "\n// never repeatForever"), [], "a comment is no offender")
    }

    func testReduceMotionIsReadAtTheAlert() throws {
        let manager = Self.code(try Self.source("Kannu/managers/AgentStatus/AttentionAlertManager.swift"))
        XCTAssertTrue(manager.contains("AttentionAlertVisual.forReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)"))
        let overlay = Self.code(try Self.source("Kannu/components/AgentStatus/AttentionAlertOverlay.swift"))
        XCTAssertTrue(overlay.contains("case .glow: glow"))
    }

    // MARK: - The sound

    func testNonePlaysNothingAndKannuAlarmStopsWhenTheFlashEnds() throws {
        let manager = Self.code(try Self.source("Kannu/managers/AgentStatus/AttentionAlertManager.swift"))
        let play = try XCTUnwrap(Self.body(ofFunction: "playSound", in: manager))
        XCTAssertTrue(play.contains("case .silent:\n            return"), "None plays nothing")
        XCTAssertTrue(play.contains("playAlarm(name: name, fileExtension: fileExtension)"))

        // David: "Fade at ~2.4 s". Once, faded, stopped by the flash's end, restarted by the next play.
        let alarm = try XCTUnwrap(Self.body(ofFunction: "playAlarm", in: manager))
        XCTAssertTrue(alarm.hasPrefix("{\n        stopAlarm()"), "a new play cancels the pending fade first")
        XCTAssertTrue(alarm.contains("player.numberOfLoops = 0"), "never looped")
        XCTAssertTrue(alarm.contains("player.volume = 1"), "a restart is at full volume")
        XCTAssertTrue(alarm.contains("Task.sleep(for: .seconds(AttentionAlertTracker.alarmFadeStart))"))
        XCTAssertTrue(alarm.contains("player.setVolume(0, fadeDuration: AttentionAlertTracker.alarmFadeDuration)"))
        XCTAssertTrue(alarm.contains("player.stop()"))
        XCTAssertEqual(alarm.components(separatedBy: "Task {").count - 1, 1, "one task per play")
        for banned in ["Timer.", "repeatForever", "asyncAfter", "numberOfLoops = -1"] {
            XCTAssertFalse(alarm.contains(banned), banned)
        }
        let stop = try XCTUnwrap(Self.body(ofFunction: "stopAlarm", in: manager))
        XCTAssertTrue(stop.contains("alarmFadeTask?.cancel()") && stop.contains("alarmPlayer?.stop()"))
        let settings = try Self.source("Kannu/components/Settings/AgentStatusSettings.swift")
        XCTAssertTrue(settings.contains(".disabled(attentionAlertSound == .none)"), "Play sound is off for None")
    }

    // MARK: - The pill while locked with the live activity off

    func testThePillShowsForTheAlertOnlyWhileLockedAndGoesAfterOneSleep() throws {
        let window = Self.code(try Self.source("Kannu/managers/LockScreenLiveActivityWindowManager.swift"))
        let flash = try XCTUnwrap(Self.body(ofFunction: "flashForAttentionAlert", in: window))
        XCTAssertTrue(flash.contains("guard LockScreenManager.shared.isLocked, !Defaults[.enableLockScreenLiveActivity] else { return }"),
                      "only while locked, and only when the live activity has no pill up")
        XCTAssertTrue(flash.contains("present(notchSize: context.notchSize, on: context.screen, forAttentionAlert: true)"))
        XCTAssertEqual(flash.components(separatedBy: "Task.sleep").count - 1, 1, "one sleep")
        for banned in ["Timer.", "repeatForever", "asyncAfter"] {
            XCTAssertFalse(flash.contains(banned), banned)
        }
        // Nothing else lifts the live-activity guard.
        XCTAssertEqual(window.components(separatedBy: "forAttentionAlert: true").count - 1, 1)

        // Unlocking cancels the pending hide, on both unlock paths.
        let unlock = try XCTUnwrap(Self.body(ofFunction: "showUnlockAndScheduleHide", in: window))
        XCTAssertTrue(unlock.contains("cancelAttentionFlash()"))
        let hide = try XCTUnwrap(Self.body(ofFunction: "hideImmediately", in: window))
        XCTAssertTrue(hide.contains("cancelAttentionFlash()"))

        // A hide's delayed orderOut never removes a pill presented since.
        let hideWithAnimation = try XCTUnwrap(Self.body(ofFunction: "hideWithAnimation", in: window))
        XCTAssertTrue(hideWithAnimation.contains("guard self.presentGeneration == generation else { return }"))

        let manager = Self.code(try Self.source("Kannu/managers/AgentStatus/AttentionAlertManager.swift"))
        let alert = try XCTUnwrap(Self.body(ofFunction: "alert", in: manager))
        XCTAssertTrue(alert.contains("if LockScreenManager.shared.isLocked {"))
        XCTAssertTrue(alert.contains("flashForAttentionAlert(duration: AttentionAlertTracker.flashDuration)"))
    }

    // MARK: - The setting

    func testTheSettingRowsAndTheirSearchEntriesShareIDs() throws {
        let settings = try Self.source("Kannu/components/Settings/AgentStatusSettings.swift")
        let index = try Self.source("Kannu/components/Settings/SettingsView.swift")
        for title in ["Alert when an agent needs you", "Alert sound"] {
            XCTAssertTrue(settings.contains(".settingsHighlight(id: highlightID(\"\(title)\"))"), title)
            XCTAssertTrue(index.contains("highlightID: SettingsTab.agentStatus.highlightID(for: \"\(title)\")"), title)
        }
    }
}
