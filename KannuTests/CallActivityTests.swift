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

/// Calls in other apps: which processes belong to which app, and how "who captures and plays"
/// becomes no call, a ring, or a call running since a moment.
final class CallActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let whatsApp = "net.whatsapp.WhatsApp"

    /// A process as the monitor hands it over. Unless said otherwise, one that captures and plays
    /// does so the way a call was measured to: capturing from the device it plays to.
    private func process(_ bundleID: String, capturing: Bool, playing: Bool, fromOutput: Bool? = nil) -> CallAudioProcess {
        CallAudioProcess(bundleID: bundleID, isCapturing: capturing, isPlaying: playing,
                         capturesFromOutputDevice: fromOutput ?? (capturing && playing))
    }

    private func app(_ id: String) throws -> CallApp {
        try XCTUnwrap(CallAppCatalog.apps.first { $0.id == id }, "\(id) left the catalog")
    }

    // MARK: - Catalog

    func testAnAppMatchesItsOwnBundleIDAndItsHelpers() throws {
        let app = CallApp(id: "orders", name: "Orders", bundleID: "com.example.orders",
                          processPrefixes: ["com.example.orders"], isVerified: false)
        XCTAssertTrue(app.matches(processBundleID: "com.example.orders"))
        XCTAssertTrue(app.matches(processBundleID: "com.example.orders.helper"))
        XCTAssertTrue(app.matches(processBundleID: "com.example.orders.helper.Renderer"))
        XCTAssertTrue(app.matches(processBundleID: "COM.EXAMPLE.Orders"), "bundle IDs compare without case")
    }

    /// A prefix ends at a dot: another app whose ID merely starts with the same letters is not a helper.
    func testALongerNameIsNotAHelper() {
        let app = CallApp(id: "orders", name: "Orders", bundleID: "com.example.orders",
                          processPrefixes: ["com.example.orders"], isVerified: false)
        XCTAssertFalse(app.matches(processBundleID: "com.example.ordersync"))
        XCTAssertFalse(app.matches(processBundleID: "com.example"))
        XCTAssertFalse(app.matches(processBundleID: ""))
    }

    func testTheCatalogFindsAnAppByAHelpersBundleID() throws {
        XCTAssertEqual(CallAppCatalog.app(forProcessBundleID: whatsApp)?.id, "whatsapp")
        // Measured on a Slack huddle: the audio runs in the helper, not in the app's own process.
        XCTAssertEqual(CallAppCatalog.app(forProcessBundleID: "com.tinyspeck.slackmacgap.helper")?.id, "slack")
        XCTAssertEqual(CallAppCatalog.app(forProcessBundleID: "com.hnc.Discord.helper")?.id, "discord")
        XCTAssertEqual(CallAppCatalog.app(forProcessBundleID: "com.microsoft.teams2.helper")?.id, "teams")
        XCTAssertNil(CallAppCatalog.app(forProcessBundleID: "com.example.orders"))
    }

    /// A browser holding the microphone is not necessarily a call, so none is listed.
    func testNoBrowserIsInTheCatalog() {
        for browser in ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
                        "com.microsoft.edgemac", "com.brave.Browser", "com.google.Chrome.helper"] {
            XCTAssertNil(CallAppCatalog.app(forProcessBundleID: browser), browser)
        }
    }

    func testTheCatalogIsWellFormed() {
        let apps = CallAppCatalog.apps
        XCTAssertEqual(Set(apps.map(\.id)).count, apps.count, "two apps share an id")
        for app in apps {
            XCTAssertFalse(app.name.isEmpty)
            XCTAssertFalse(app.processPrefixes.isEmpty, "\(app.id) matches no process")
            XCTAssertTrue(app.matches(processBundleID: app.bundleID), "\(app.id)'s own bundle ID is not one of its prefixes")
            // One process, one app: no prefix of one app may claim another's.
            for other in apps where other.id != app.id {
                XCTAssertFalse(other.matches(processBundleID: app.bundleID), "\(other.id) claims \(app.id)")
            }
        }
        XCTAssertEqual(apps.filter(\.callsCaptureFromOutput).map(\.id), ["whatsapp"],
                       "an app is held to the capture-from-output rule only once its call and its recording were both measured")
        XCTAssertEqual(apps.filter(\.isVerified).map(\.id), ["whatsapp", "slack"],
                       "an app is verified only once a real call was measured; docs/SETTINGS.md lists the rest as unverified")
    }

    // MARK: - Resolver: a call starts

    func testACapturingAndPlayingAppIsACallSinceThatReading() throws {
        var resolver = CallActivityResolver()
        let call = resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start)
        XCTAssertEqual(call, CallActivity(app: try app("whatsapp"), phase: .ongoing(since: start)))
        XCTAssertEqual(call?.startedAt, start)
        XCTAssertNil(resolver.dropDeadline)
    }

    /// A ringtone is output with no input (measured on a WhatsApp ring).
    func testARingtoneAloneIsNotACall() {
        var resolver = CallActivityResolver()
        XCTAssertNil(resolver.update(processes: [process(whatsApp, capturing: false, playing: true)], now: start))
    }

    /// Capture with no playback is not a call, for any app.
    func testCapturingAloneDoesNotStartACall() {
        var resolver = CallActivityResolver()
        XCTAssertNil(resolver.update(processes: [process(whatsApp, capturing: true, playing: false)], now: start))
        XCTAssertNil(resolver.update(processes: [process("com.hnc.Discord", capturing: true, playing: false)], now: start))
    }

    // MARK: - Resolver: a recording is not a call

    /// A WhatsApp voice note as measured (2026-11-25): it captures **and** plays from its first
    /// instant to its last, exactly as a call does, but it captures from the microphone alone.
    /// It showed as a call for its whole length until this rule.
    func testAWhatsAppVoiceNoteIsNotACall() {
        var resolver = CallActivityResolver()
        let recording = [process(whatsApp, capturing: true, playing: true, fromOutput: false)]
        for second in stride(from: 0.0, through: 13.0, by: 1.0) {
            XCTAssertNil(resolver.update(processes: recording, now: start.addingTimeInterval(second)), "at \(second) s")
        }
        // Deleted: the capture stops, the output lingers two seconds, then both are gone.
        let tail = [process(whatsApp, capturing: false, playing: true, fromOutput: false)]
        XCTAssertNil(resolver.update(processes: tail, now: start.addingTimeInterval(13.5)))
        XCTAssertNil(resolver.update(processes: [process(whatsApp, capturing: false, playing: false)], now: start.addingTimeInterval(15.5)))
        XCTAssertNil(resolver.dropDeadline)
    }

    /// A WhatsApp call as measured the same minute: it captures from the microphone and from the
    /// speakers it plays to, which is echo cancellation taking its reference.
    func testAWhatsAppCallIsACallUntilItsCaptureStops() throws {
        var resolver = CallActivityResolver()
        let calling = [process(whatsApp, capturing: true, playing: true, fromOutput: true)]
        XCTAssertEqual(resolver.update(processes: calling, now: start)?.phase, .ongoing(since: start))
        XCTAssertEqual(resolver.update(processes: calling, now: start.addingTimeInterval(40))?.startedAt, start)
        let hungUp = start.addingTimeInterval(41)
        let idle = [process(whatsApp, capturing: false, playing: false)]
        XCTAssertNotNil(resolver.update(processes: idle, now: hungUp))
        XCTAssertNil(resolver.update(processes: idle, now: hungUp.addingTimeInterval(CallActivityResolver.dropGrace)))
    }

    /// A voice note recorded straight after a call is not that call going on.
    func testAVoiceNoteAfterACallHasEndedIsNotACall() {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true, fromOutput: true)], now: start)
        let idle = [process(whatsApp, capturing: false, playing: false)]
        resolver.update(processes: idle, now: start.addingTimeInterval(30))
        XCTAssertNil(resolver.update(processes: idle, now: start.addingTimeInterval(30 + CallActivityResolver.dropGrace)))
        XCTAssertNil(resolver.update(processes: [process(whatsApp, capturing: true, playing: true, fromOutput: false)],
                                     now: start.addingTimeInterval(40)))
    }

    /// An app where the difference was not measured keeps the plain rule: capturing and playing
    /// is a call, wherever it captures from. Slack's huddle was measured only that far.
    func testAnAppWithoutTheMeasuredRuleNeedsOnlyCaptureAndPlayback() throws {
        var resolver = CallActivityResolver()
        let huddle = [process("com.tinyspeck.slackmacgap.helper", capturing: true, playing: true, fromOutput: false)]
        XCTAssertEqual(resolver.update(processes: huddle, now: start)?.app, try app("slack"))
    }

    /// One device that is microphone and speaker in one, a headset: a recording there captures
    /// from the device it plays to, as a call does, so it reads as a call. Known, and documented.
    func testOnASingleHeadsetARecordingStillReadsAsACall() {
        var resolver = CallActivityResolver()
        XCTAssertNotNil(resolver.update(processes: [process(whatsApp, capturing: true, playing: true, fromOutput: true)], now: start))
    }

    func testAnAppOutsideTheCatalogIsNotACall() {
        var resolver = CallActivityResolver()
        XCTAssertNil(resolver.update(processes: [process("com.example.orders", capturing: true, playing: true)], now: start))
    }

    /// An app's capture and its playback may sit in different helpers.
    func testAnAppsHelpersAreReadAsOne() throws {
        var resolver = CallActivityResolver()
        let call = resolver.update(processes: [
            process("com.hnc.Discord.helper", capturing: true, playing: false),
            process("com.hnc.Discord", capturing: false, playing: true),
        ], now: start)
        XCTAssertEqual(call?.app, try app("discord"))
    }

    /// The reading itself defaults the device fact to false: a monitor that did not ask is not a yes.
    func testAProcessDoesNotCaptureFromItsOutputUnlessTheMonitorSaysSo() {
        XCTAssertFalse(CallAudioProcess(bundleID: whatsApp, isCapturing: true, isPlaying: true).capturesFromOutputDevice)
    }

    /// A Slack huddle as measured: the helper captures and plays, the app's own process does neither.
    /// After leaving, the helper went on playing for 11 s with its capture stopped: the call ends on
    /// the capture, not on the output.
    func testASlackHuddleIsACallUntilItsHelperStopsCapturing() throws {
        var resolver = CallActivityResolver()
        let inHuddle = [process("com.tinyspeck.slackmacgap.helper", capturing: true, playing: true),
                        process("com.tinyspeck.slackmacgap", capturing: false, playing: false)]
        XCTAssertEqual(resolver.update(processes: inHuddle, now: start)?.app, try app("slack"))
        let left = start.addingTimeInterval(108)
        let afterLeaving = [process("com.tinyspeck.slackmacgap.helper", capturing: false, playing: true),
                            process("com.tinyspeck.slackmacgap", capturing: false, playing: false)]
        XCTAssertNotNil(resolver.update(processes: afterLeaving, now: left))
        XCTAssertNil(resolver.update(processes: afterLeaving, now: left.addingTimeInterval(CallActivityResolver.dropGrace)),
                     "the helper's lingering output kept the call up")
    }

    /// Two apps' halves do not add up to a call.
    func testOneAppCapturingAndAnotherPlayingIsNotACall() {
        var resolver = CallActivityResolver()
        XCTAssertNil(resolver.update(processes: [
            process(whatsApp, capturing: true, playing: false),
            process("com.hnc.Discord", capturing: false, playing: true),
        ], now: start))
    }

    // MARK: - Resolver: a call goes on, and ends

    func testACallKeepsItsStartWhileItsAppCaptures() throws {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start)
        // Its output may come and go: the other side is silent.
        let later = resolver.update(processes: [process(whatsApp, capturing: true, playing: false)],
                                    now: start.addingTimeInterval(600))
        XCTAssertEqual(later?.startedAt, start, "the clock restarted mid-call")
        XCTAssertNil(resolver.dropDeadline)
    }

    /// The grace runs from the first reading that shows the capture gone. Readings are up to 2 s
    /// apart while the microphone is in use, so counting from the last one that showed the capture
    /// would leave as little as a second of it.
    func testACallOutlivesItsCaptureByTheGrace() throws {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start)
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start.addingTimeInterval(60))

        let stopped = start.addingTimeInterval(62)
        XCTAssertNotNil(resolver.update(processes: [], now: stopped), "the call ended the moment capture stopped")
        XCTAssertEqual(resolver.dropDeadline, stopped.addingTimeInterval(CallActivityResolver.dropGrace))

        // A later reading inside the grace does not push the deadline out.
        let justBefore = stopped.addingTimeInterval(CallActivityResolver.dropGrace - 0.01)
        XCTAssertNotNil(resolver.update(processes: [], now: justBefore))
        XCTAssertEqual(resolver.dropDeadline, stopped.addingTimeInterval(CallActivityResolver.dropGrace))
        let atDeadline = stopped.addingTimeInterval(CallActivityResolver.dropGrace)
        XCTAssertNil(resolver.update(processes: [], now: atDeadline))
        XCTAssertNil(resolver.dropDeadline, "nothing is left to wake for")
    }

    /// A change of microphone stops and restarts the app's capture: one call, one clock.
    func testACaptureThatComesBackInsideTheGraceIsTheSameCall() {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start)
        resolver.update(processes: [], now: start.addingTimeInterval(10))
        let back = resolver.update(processes: [process(whatsApp, capturing: true, playing: true)],
                                   now: start.addingTimeInterval(11))
        XCTAssertEqual(back?.startedAt, start)
        XCTAssertNil(resolver.dropDeadline)
        // And a second drop gets a whole grace of its own.
        let again = start.addingTimeInterval(40)
        resolver.update(processes: [], now: again)
        XCTAssertEqual(resolver.dropDeadline, again.addingTimeInterval(CallActivityResolver.dropGrace))
    }

    func testACallAfterTheGraceIsANewCall() {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: start)
        let stopped = start.addingTimeInterval(30)
        XCTAssertNotNil(resolver.update(processes: [], now: stopped))
        let later = stopped.addingTimeInterval(CallActivityResolver.dropGrace + 1)
        XCTAssertNil(resolver.update(processes: [], now: later))
        let next = later.addingTimeInterval(5)
        let call = resolver.update(processes: [process(whatsApp, capturing: true, playing: true)], now: next)
        XCTAssertEqual(call?.startedAt, next)
    }

    /// The call that is running stays the one shown when a second app connects.
    func testARunningCallIsNotReplacedByAnotherApps() throws {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process("com.hnc.Discord", capturing: true, playing: true)], now: start)
        let both = resolver.update(processes: [
            process("com.hnc.Discord", capturing: true, playing: true),
            process(whatsApp, capturing: true, playing: true),
        ], now: start.addingTimeInterval(5))
        XCTAssertEqual(both?.app, try app("discord"))
        XCTAssertEqual(both?.startedAt, start)
    }

    /// With two apps connecting in one reading, the catalog's order decides, so the answer never flickers.
    func testTwoAppsStartingTogetherResolveInTheCatalogsOrder() throws {
        var resolver = CallActivityResolver()
        let call = resolver.update(processes: [
            process("com.hnc.Discord", capturing: true, playing: true),
            process(whatsApp, capturing: true, playing: true),
        ], now: start)
        XCTAssertEqual(call?.app, try app("whatsapp"))
    }

    // MARK: - Resolver: a ring

    func testARingShowsUntilItIsWithdrawn() throws {
        var resolver = CallActivityResolver()
        let ring = resolver.update(processes: [process(whatsApp, capturing: false, playing: true)],
                                   ringing: try app("whatsapp"), now: start)
        XCTAssertEqual(ring, CallActivity(app: try app("whatsapp"), phase: .ringing))
        XCTAssertTrue(ring?.isRinging ?? false)
        XCTAssertNil(ring?.startedAt)
        XCTAssertNil(resolver.dropDeadline, "a ring has no grace")
        XCTAssertNil(resolver.update(processes: [], now: start.addingTimeInterval(4)), "a declined ring stayed")
    }

    func testARingThatConnectsBecomesACallFromThatMoment() throws {
        var resolver = CallActivityResolver()
        resolver.update(processes: [], ringing: try app("whatsapp"), now: start)
        let answered = start.addingTimeInterval(7)
        let call = resolver.update(processes: [process(whatsApp, capturing: true, playing: true)],
                                   ringing: try app("whatsapp"), now: answered)
        XCTAssertEqual(call?.phase, .ongoing(since: answered))
    }

    func testARunningCallOutranksARing() throws {
        var resolver = CallActivityResolver()
        resolver.update(processes: [process("com.hnc.Discord", capturing: true, playing: true)], now: start)
        let call = resolver.update(processes: [process("com.hnc.Discord", capturing: true, playing: true)],
                                   ringing: try app("whatsapp"), now: start.addingTimeInterval(3))
        XCTAssertEqual(call?.app, try app("discord"))
        XCTAssertFalse(call?.isRinging ?? true)
    }
}
