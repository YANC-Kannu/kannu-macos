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

/// The gate that keeps a Keychain call able to show a dialog from overlapping a silent read, which has
/// the process-wide interaction switch off. Threads are held inside the gate with semaphores, so each
/// test shows who is let in while whom is inside.
final class KeychainInteractionGateTests: XCTestCase {
    /// A fake switch: what the gate turned off and put back, in order.
    private final class Switch: @unchecked Sendable {
        private let lock = NSLock()
        private var value = true
        private(set) var events: [String] = []
        func turnOff() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let was = value
            value = false
            events.append("off")
            return was
        }
        func restore(_ was: Bool) {
            lock.lock(); defer { lock.unlock() }
            value = was
            events.append("restore(\(was))")
        }
        var isOn: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func makeGate(_ fake: Switch) -> KeychainInteractionGate {
        KeychainInteractionGate(turnInteractionOff: fake.turnOff, restoreInteraction: fake.restore)
    }

    /// Runs `kind` on a background thread and holds it inside until `release` is signalled.
    private func hold(_ gate: KeychainInteractionGate, _ kind: KeychainInteractionGate.Kind,
                      entered: DispatchSemaphore, release: DispatchSemaphore, done: DispatchSemaphore,
                      onEnter: @escaping () -> Void = {}) {
        DispatchQueue.global().async {
            _ = gate.run(kind) {
                onEnter()
                entered.signal()
                release.wait()
            }
            done.signal()
        }
    }

    func testOverlappingSilentReadsShareOneSwitchOff() {
        let fake = Switch()
        let gate = makeGate(fake)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        hold(gate, .silent, entered: entered, release: release, done: done)
        hold(gate, .silent, entered: entered, release: release, done: done)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success, "a silent read never waits for another")
        XCTAssertFalse(fake.isOn)
        release.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(fake.isOn, "still off while the second silent read runs")
        release.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(fake.isOn)
        XCTAssertEqual(fake.events, ["off", "restore(true)"])
    }

    func testACallThatMayPromptWaitsForSilentReadsAndSeesTheSwitchOn() {
        let fake = Switch()
        let gate = makeGate(fake)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        hold(gate, .silent, entered: entered, release: release, done: done)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)

        let promptEntered = DispatchSemaphore(value: 0)
        var switchSeenByPrompt: Bool?
        DispatchQueue.global().async {
            _ = gate.run(.mayPrompt) { switchSeenByPrompt = fake.isOn }
            promptEntered.signal()
        }
        XCTAssertEqual(promptEntered.wait(timeout: .now() + 0.3), .timedOut, "must wait while the switch is off")
        release.signal()
        XCTAssertEqual(promptEntered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(switchSeenByPrompt, true)
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    func testSilentReadsWaitWhileACallMayPromptAndGiveUpWhenAskedNotToWait() {
        let fake = Switch()
        let gate = makeGate(fake)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        hold(gate, .mayPrompt, entered: entered, release: release, done: done)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)

        XCTAssertNil(gate.run(.silent, wait: false) { 1 }, "gives up at once while a dialog may be open")
        XCTAssertTrue(fake.events.isEmpty, "never turned the switch off")

        let silentDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = gate.run(.silent) { 1 }
            silentDone.signal()
        }
        XCTAssertEqual(silentDone.wait(timeout: .now() + 0.3), .timedOut, "a waiting silent read stays out")
        release.signal()
        XCTAssertEqual(silentDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(fake.events, ["off", "restore(true)"])
    }

    func testCallsThatMayPromptNeverWaitForEachOther() {
        let gate = makeGate(Switch())
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        hold(gate, .mayPrompt, entered: entered, release: release, done: done)
        hold(gate, .mayPrompt, entered: entered, release: release, done: done)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success, "two dialogs can be open at once")
        release.signal(); release.signal()
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
    }

    /// A call that may prompt, waiting for one silent read, holds back silent reads that arrive after
    /// it, so a stream of background reads cannot keep the dialog from ever opening.
    func testAWaitingCallThatMayPromptHoldsBackNewSilentReads() {
        let fake = Switch()
        let gate = makeGate(fake)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        hold(gate, .silent, entered: entered, release: release, done: done)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)

        let order = NSLock()
        var sequence: [String] = []
        let promptDone = DispatchSemaphore(value: 0), lateDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = gate.run(.mayPrompt) { order.lock(); sequence.append("prompt"); order.unlock() }
            promptDone.signal()
        }
        // Until the dialog call is waiting, a non-waiting silent read still gets in; once it waits, one is
        // refused. Polled with a deadline rather than a fixed sleep, so a slow runner cannot fail it. A
        // silent read that gets in first is harmless: the held one keeps the dialog call waiting.
        var refused = false
        let deadline = Date().addingTimeInterval(2)
        while !refused && Date() < deadline {
            refused = gate.run(.silent, wait: false) { 1 } == nil
            if !refused { Thread.sleep(forTimeInterval: 0.01) }
        }
        XCTAssertTrue(refused, "a waiting dialog call already blocks new silent reads")
        DispatchQueue.global().async {
            _ = gate.run(.silent) { order.lock(); sequence.append("late silent"); order.unlock() }
            lateDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.1)
        release.signal()
        XCTAssertEqual(promptDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(lateDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(sequence, ["prompt", "late silent"])
    }

    func testTheSwitchIsPutBackToWhatItWas() {
        let fake = Switch()
        _ = fake.turnOff()   // already off before Kannu's read
        let gate = makeGate(fake)
        XCTAssertEqual(gate.run(.silent) { 7 }, 7)
        XCTAssertFalse(fake.isOn, "restored to off, as it was")
        XCTAssertEqual(fake.events.last, "restore(false)")
    }
}
