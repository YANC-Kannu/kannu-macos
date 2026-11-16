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

/// Every release through 1.4.0-beta.3 bundled 131-byte Git LFS pointers in place of the Bluetooth HUD
/// clips. Nothing failed: `xcodebuild` copies a pointer like any other file, and `InlineHUD` and
/// `SettingsLoopingVideoIcon` only check that the bundle URL exists, so `AVPlayer` got a file it
/// cannot open and the icon slot stayed empty. These pin the tree, the absence of an LFS rule that
/// would undo it for a contributor who has git-lfs installed, and the check that stops a DMG being
/// made anyway.
final class BundledVideoTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root

    private static let pointer = """
        version https://git-lfs.github.com/spec/v1
        oid sha256:54332f65534c9af667a302e9c2df17e4420bffb94e93cecd0091b11a05e70efc
        size 351501

        """

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-bundled-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func check(_ path: URL) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.repoRoot.appendingPathComponent("scripts/check-no-lfs-pointers.sh").path,
            path.path,
        ]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// The whole of `Kannu/`, because the synchronized group copies whatever lands there into the app.
    func testEveryMovieUnderTheAppSourcesIsARealMovie() throws {
        let sources = Self.repoRoot.appendingPathComponent("Kannu")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let movies = walker.compactMap { $0 as? URL }.filter { ["mov", "mp4"].contains($0.pathExtension) }

        // A deleted directory must not pass by having nothing left to check.
        let names = Set(movies.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertTrue(names.isSuperset(of: [
            "airpods", "airpodsGen3", "airpodsGen4", "airpodsMax", "airpodsPro", "airpodsPro3",
            "beatssolo", "beatsstudio",
        ]), "found only \(names.sorted())")

        for movie in movies {
            let handle = try FileHandle(forReadingFrom: movie)
            defer { try? handle.close() }
            let head = try XCTUnwrap(handle.read(upToCount: 12))
            XCTAssertFalse(
                String(decoding: head, as: UTF8.self).hasPrefix("version http"),
                "\(movie.lastPathComponent) is a Git LFS pointer. Bundled media must be an ordinary blob."
            )
            XCTAssertEqual(
                String(decoding: head.dropFirst(4).prefix(4), as: UTF8.self), "ftyp",
                "\(movie.lastPathComponent) has no QuickTime file type box"
            )
        }
    }

    /// With git-lfs installed, `git add` turns a file an LFS rule matches back into a pointer, so the
    /// real files alone would not last. The repo has no such rule, and needs no `.gitattributes` at all.
    func testNoAttributeSendsAFileToLFS() throws {
        let attributes = Self.repoRoot.appendingPathComponent(".gitattributes")
        guard FileManager.default.fileExists(atPath: attributes.path) else { return }
        XCTAssertFalse(try read(".gitattributes").contains("filter=lfs"), ".gitattributes sends files to Git LFS")
    }

    func testTheCheckRefusesABundleHoldingAPointer() throws {
        let resources = directory.appendingPathComponent("Kannu.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Self.pointer.write(to: resources.appendingPathComponent("airpods.mov"), atomically: true, encoding: .utf8)

        let result = try check(directory.appendingPathComponent("Kannu.app"))

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stderr.contains("airpods.mov"), result.stderr)
    }

    func testTheCheckPassesABundleOfRealFiles() throws {
        let resources = directory.appendingPathComponent("Kannu.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.repoRoot.appendingPathComponent("Kannu/BluetoothHUDAnimations/airpods.mov"),
            to: resources.appendingPathComponent("airpods.mov")
        )
        try "not a pointer\n".write(to: resources.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(try check(directory.appendingPathComponent("Kannu.app")).status, 0)
    }

    /// A path it cannot read has not been shown to be clean.
    func testTheCheckFailsOnAMissingPath() throws {
        XCTAssertEqual(try check(directory.appendingPathComponent("Missing.app")).status, 2)
    }

    /// Every DMG path goes through `create-dmg.sh`: the release workflow, `manual-release.sh` and `build-dmg.sh`.
    func testCreatingADMGRunsTheCheck() throws {
        let script = try read("scripts/create-dmg.sh")
        let check = try XCTUnwrap(script.range(of: "check-no-lfs-pointers.sh"))
        let create = try XCTUnwrap(script.range(of: "dmg-settings.py"))
        XCTAssertLessThan(check.lowerBound, create.lowerBound)
    }
}
