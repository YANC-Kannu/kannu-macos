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

/// When a call pauses the music: once, as it starts (none or ringing to ongoing), with the switch
/// on, music playing, and the music not coming from the calling app itself.
final class CallMusicPolicyTests: XCTestCase {
    private let spotify = "com.spotify.client"
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func app(_ id: String) throws -> CallApp {
        try XCTUnwrap(CallAppCatalog.apps.first { $0.id == id })
    }

    private func ongoing(_ id: String = "whatsapp", since: Date? = nil) throws -> CallActivity {
        CallActivity(app: try app(id), phase: .ongoing(since: since ?? start))
    }

    private func decide(_ previous: CallActivity?, _ next: CallActivity?, isEnabled: Bool = true,
                        isPlaying: Bool = true, source: String? = "com.spotify.client") -> CallMusicPolicy.Decision {
        CallMusicPolicy.decide(previous: previous, next: next, isEnabled: isEnabled, isPlaying: isPlaying, sourceBundleID: source)
    }

    func testACallStartingWithMusicPlayingPauses() throws {
        XCTAssertEqual(decide(nil, try ongoing()), .pause)
    }

    func testARingThatConnectsPauses() throws {
        let ring = CallActivity(app: try app("whatsapp"), phase: .ringing)
        XCTAssertEqual(decide(ring, try ongoing()), .pause)
    }

    func testARingAloneDoesNothing() throws {
        XCTAssertEqual(decide(nil, CallActivity(app: try app("whatsapp"), phase: .ringing)), .none)
    }

    func testPausedMusicDoesNothing() throws {
        XCTAssertEqual(decide(nil, try ongoing(), isPlaying: false), .none)
    }

    func testTheSwitchOffDoesNothing() throws {
        XCTAssertEqual(decide(nil, try ongoing(), isEnabled: false), .none)
    }

    func testMusicFromTheCallingAppDoesNothing() throws {
        // A voice note in WhatsApp shows as WhatsApp's Now Playing.
        XCTAssertEqual(decide(nil, try ongoing(), source: "net.whatsapp.WhatsApp"), .none)
        // Its helper, and any case, are the same app.
        XCTAssertEqual(decide(nil, try ongoing(), source: "net.whatsapp.whatsapp.helper"), .none)
        // Another catalog app's audio is still music to this call.
        XCTAssertEqual(decide(nil, try ongoing(), source: "com.tinyspeck.slackmacgap"), .pause)
    }

    func testAnUnknownSourceStillPauses() throws {
        XCTAssertEqual(decide(nil, try ongoing(), source: nil), .pause)
    }

    func testAnOngoingUpdateDoesNothing() throws {
        let call = try ongoing()
        XCTAssertEqual(decide(call, call), .none)
    }

    func testTheEndOfACallDoesNothing() throws {
        XCTAssertEqual(decide(try ongoing(), nil), .none)
        XCTAssertEqual(decide(try ongoing(), nil, isPlaying: true, source: spotify), .none)
    }

    func testNoCallDoesNothing() {
        XCTAssertEqual(decide(nil, nil), .none)
    }

    func testANewCallThatReplacesTheLastOnePauses() throws {
        // The last call ended and another connected in the same reading: that is a start.
        XCTAssertEqual(decide(try ongoing("whatsapp"), try ongoing("slack", since: start.addingTimeInterval(60))), .pause)
    }
}
