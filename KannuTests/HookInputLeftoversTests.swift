//
//  HookInputLeftoversTests.swift
//  KannuTests
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest

/// The launch sweep for the payload files hook scripts v41 to v46 could leave behind. The age filter
/// is what keeps it off a file an older script, still installed at launch, is about to read.
final class HookInputLeftoversTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-hook-leftovers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func place(_ name: String, age: TimeInterval, now: Date, isDirectory: Bool = false) throws {
        let url = directory.appendingPathComponent(name)
        if isDirectory {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            try Data("{}".utf8).write(to: url)
        }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    func testOnlyAPayloadFileOlderThanTenMinutesIsStale() {
        let now = Date()
        let old = now.addingTimeInterval(-(HookInputLeftovers.maxAge + 1))
        XCTAssertEqual(HookInputLeftovers.maxAge, 600)
        XCTAssertTrue(HookInputLeftovers.isStale(name: ".kannu-input.Ab12Cd", modified: old, now: now))
        XCTAssertFalse(HookInputLeftovers.isStale(name: ".kannu-input.Ab12Cd", modified: now.addingTimeInterval(-600), now: now),
                       "exactly ten minutes is not past it")
        XCTAssertFalse(HookInputLeftovers.isStale(name: ".kannu-input.Ab12Cd", modified: now.addingTimeInterval(-5), now: now),
                       "a hook still running")
        XCTAssertFalse(HookInputLeftovers.isStale(name: ".kannu-input.Ab12Cd", modified: now.addingTimeInterval(60), now: now),
                       "a clock that moved back")
        for name in ["claude-s1.json", ".claude-s1.lock", ".kannu-status.lock", ".kannu-Ab12Cd.tmp", "kannu-input.Ab12Cd", ".kannu-input"] {
            XCTAssertFalse(HookInputLeftovers.isStale(name: name, modified: old, now: now), name)
        }
    }

    func testTheSweepRemovesOnlyStalePayloadFiles() throws {
        let now = Date()
        try place(".kannu-input.Old001", age: 20 * 60, now: now)
        try place(".kannu-input.Old002", age: 42 * 24 * 3600, now: now)
        try place(".kannu-input.New001", age: 30, now: now)
        try place("claude-s1.json", age: 20 * 60, now: now)
        try place(".claude-s1.lock", age: 20 * 60, now: now)
        try place(".kannu-status.lock", age: 20 * 60, now: now)
        // Only the hook makes these names, and only as files: a directory is not the sweep's to remove.
        try place(".kannu-input.Dir001", age: 20 * 60, now: now, isDirectory: true)

        XCTAssertEqual(HookInputLeftovers.removeStale(in: directory, now: now), 2)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                       [".kannu-input.New001", "claude-s1.json", ".claude-s1.lock", ".kannu-status.lock", ".kannu-input.Dir001"])
        XCTAssertEqual(HookInputLeftovers.removeStale(in: directory, now: now), 0, "a second launch finds nothing")
    }

    func testAMissingStatusDirectoryRemovesNothing() {
        XCTAssertEqual(HookInputLeftovers.removeStale(in: directory.appendingPathComponent("absent", isDirectory: true)), 0)
    }
}
