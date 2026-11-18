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

/// Onboarding's welcome (David, 2026-11-18: "I meant the final animation and welcoming to the app, that to
/// be cleaner"): Kannu's eye, "Welcome to Kannu", a soft chime. It plays once, fades only under Reduce
/// Motion, repeats nothing, chimes softly and only when it can be seen and heard, and lets the features
/// onboarding held back start after it rather than in the tick it begins. The sequence lives in
/// `AppDelegate`, which has no unit surface, so most rules read the source, each checked against a planted
/// offender.
final class WelcomeRulesTests: XCTestCase {
    private static let appPath = "Kannu/KannuApp.swift"

    // MARK: - The timeline

    func testTheTimelineIsShortAndSoft() {
        XCTAssertEqual(WelcomeTimeline.windowFade, 0.25)
        XCTAssertEqual(WelcomeTimeline.lineHold, 1.6)
        XCTAssertEqual(WelcomeTimeline.chimeVolume, 0.35)
        XCTAssertEqual(WelcomeTimeline.featureStartCap, 3)
        XCTAssertEqual(WelcomeTimeline.eyeDuration(fadesOnly: false), NotchEyeTimeline.showDuration)
        XCTAssertEqual(WelcomeTimeline.eyeDuration(fadesOnly: true), NotchEyeTimeline.fadeDuration)
        XCTAssertEqual(WelcomeTimeline.duration(fadesOnly: false), 2.9, accuracy: 1e-9)
        XCTAssertLessThan(WelcomeTimeline.duration(fadesOnly: true), WelcomeTimeline.duration(fadesOnly: false))
    }

    // MARK: - The source

    func testTheAppKeepsEveryWelcomeRule() throws {
        let app = try Self.read(Self.appPath)
        XCTAssertEqual(Self.problems(in: app), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("Kannu/animations/HelloAnimation.swift").path),
                       "boring.notch's hello is back")
    }

    func testThePlantedOffendersAreCaught() throws {
        let app = try Self.read(Self.appPath)
        func planted(_ old: String, _ new: String) -> String {
            XCTAssertTrue(app.contains(old), "the plant's anchor moved: \(old)")
            return app.replacingOccurrences(of: old, with: new)
        }
        XCTAssertEqual(Self.problems(in: planted("        guard welcomeTask == nil else { return }\n", "")),
                       ["the welcome can play twice"])
        XCTAssertEqual(Self.problems(in: planted("let fadesOnly = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion\n        welcomeTask",
                                                 "let fadesOnly = false\n        welcomeTask")),
                       ["the welcome ignores Reduce Motion"])
        XCTAssertEqual(Self.problems(in: planted("guard !notchWindows.isEmpty, paintsClosedNotch, Self.userInterfaceSoundsAreOn() else { return }\n", "")),
                       ["the chime plays with no notch on screen or with UI sounds off"])
        XCTAssertEqual(Self.problems(in: planted("volume: WelcomeTimeline.chimeVolume)", ")")),
                       ["the chime is not soft"])
        XCTAssertEqual(Self.problems(in: planted("        Defaults[.onboardingCompletedVersion] = OnboardingProgress.currentVersion\n",
                                                 "        Defaults[.onboardingCompletedVersion] = OnboardingProgress.currentVersion\n        NotificationCenter.default.post(name: .launchPermissionsChanged, object: nil)\n")),
                       ["the features start in the tick the welcome begins"])
        XCTAssertEqual(Self.problems(in: planted("        guard !onboardingFeaturesReleased else { return }\n", "")),
                       ["the features can be released twice"])
    }

    func testNothingInTheWelcomeRepeats() throws {
        for path in ["Kannu/components/Notch/NotchWelcomeView.swift", "Kannu/components/Onboarding/OnboardingFinishView.swift"] {
            let text = try Self.read(path)
            for clock in ["repeatForever", "TimelineView", "Timer.", "SparkleView", "phaseAnimator", "keyframeAnimator"] {
                XCTAssertFalse(text.contains(clock), "\(path) runs \(clock): the welcome plays once")
            }
        }
        let audio = try Self.read("Kannu/helpers/AudioPlayer.swift")
        XCTAssertFalse(audio.contains(")!"), "a missing sound file traps")
    }

    // MARK: - Rules

    static func problems(in app: String) -> [String] {
        var problems: [String] = []
        let start = ClosedNotchTimerRulesTests.body(after: "func startWelcome()", in: app) ?? ""
        if !start.contains("guard welcomeTask == nil else { return }") || app.contains("welcomeTask = nil") {
            problems.append("the welcome can play twice")
        }
        if !start.contains("let fadesOnly = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion")
            || !start.contains("WelcomeTimeline.eyeDuration(fadesOnly: fadesOnly)")
            || !app.contains("still.disablesAnimations = fadesOnly") {
            problems.append("the welcome ignores Reduce Motion")
        }
        let sound = ClosedNotchTimerRulesTests.body(after: "func playWelcomeSound()", in: app) ?? ""
        if !sound.contains("guard !notchWindows.isEmpty, paintsClosedNotch, Self.userInterfaceSoundsAreOn() else { return }")
            || !app.contains(#""com.apple.sound.uiaudio.enabled""#) {
            problems.append("the chime plays with no notch on screen or with UI sounds off")
        }
        if !sound.contains("volume: WelcomeTimeline.chimeVolume)") {
            problems.append("the chime is not soft")
        }
        let complete = ClosedNotchTimerRulesTests.body(after: "private func completeOnboarding()", in: app) ?? ""
        if complete.contains(".launchPermissionsChanged") || !complete.contains("WelcomeTimeline.featureStartCap")
            || !start.contains("self.releaseOnboardingFeatures()") {
            problems.append("the features start in the tick the welcome begins")
        }
        let release = ClosedNotchTimerRulesTests.body(after: "private func releaseOnboardingFeatures()", in: app) ?? ""
        if !release.contains("guard !onboardingFeaturesReleased else { return }") {
            problems.append("the features can be released twice")
        }
        return problems
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
