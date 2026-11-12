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

/// Clipboard history's launch cleanup removes every image file its lists do not name. Two rules
/// follow, and both were broken: Pinned Items are one of those lists (pinning moves an item out of
/// History, so every pinned image lost its file at launch), and a Debug build, whose lists are its
/// own, must never clean the installed app's folder.
final class ClipboardDataCleanupTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-clipboard-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func place(_ names: String...) throws {
        for name in names {
            try Data("not an image".utf8).write(to: directory.appendingPathComponent(name))
        }
    }

    private func remaining() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    func testAPinnedImageKeepsItsFileAndOnlyUnnamedFilesGo() throws {
        try place("clipboard_image_history.png", "clipboard_image_pinned.png", "clipboard_image_dropped.png")

        let removed = ClipboardDataCleanup.removeUnreferencedFiles(
            in: directory, history: ["clipboard_image_history.png"], pinned: ["clipboard_image_pinned.png"])

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try remaining(), ["clipboard_image_history.png", "clipboard_image_pinned.png"])
        XCTAssertEqual(ClipboardDataCleanup.removeUnreferencedFiles(
            in: directory, history: ["clipboard_image_history.png"], pinned: ["clipboard_image_pinned.png"]), 0,
            "a second launch finds nothing")
    }

    func testAMissingFolderRemovesNothing() {
        XCTAssertEqual(ClipboardDataCleanup.removeUnreferencedFiles(
            in: directory.appendingPathComponent("absent", isDirectory: true), history: [], pinned: []), 0)
    }

    // MARK: - A Debug build's folder (`ClipboardManager` is AppKit, so its text is read)

    func testADebugBuildCleansOnlyAFolderOfItsOwn() throws {
        let file = Self.root.appendingPathComponent("Kannu/managers/ClipboardManager.swift")
        let code = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        XCTAssertTrue(code.contains("""
            #if DEBUG
            static let clipboardDataDirectory: URL = AppSupportPaths.child("ClipboardData-Debug")
            #else
            static let clipboardDataDirectory: URL = AppSupportPaths.child("ClipboardData")
            #endif
            """), "a Debug build's cleanup removes every file its own history does not name, "
                + "so it needs its own folder, beside the installed app's")

        let start = try XCTUnwrap(code.range(of: "static func migrateLegacyDataIfNeeded(isUpgrade: Bool) {\n#if DEBUG\n"),
                                  "the legacy move needs a Debug branch")
        let end = try XCTUnwrap(code.range(of: "\n#else\n", range: start.upperBound..<code.endIndex))
        let debugBranch = code[start.upperBound..<end.lowerBound].split(separator: "\n")
        XCTAssertFalse(debugBranch.isEmpty, "the Debug branch says why it does nothing")
        XCTAssertTrue(debugBranch.allSatisfy { $0.hasPrefix("//") },
                      "a Debug build must not move ~/Documents/ClipboardData: the installed app's images are there, "
                        + "and the Debug cleanup would delete them")
    }
}
