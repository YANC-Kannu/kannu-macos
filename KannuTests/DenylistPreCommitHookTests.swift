//
//  DenylistPreCommitHookTests.swift
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

import XCTest

/// `.githooks/pre-commit` refuses a commit whose staged added lines, author or committer match the local denylist
/// (`<git-common-dir>/info/kannu-denylist`). It must see the content that is committed, however git would render it:
/// a file an attribute marks `-diff`, a path git would quote, a symlink that became a file, and a conflict
/// resolution all count. The full hook runs here against a throwaway repository; none of its other checks apply
/// to these paths, so a clean change passes.
final class DenylistPreCommitHookTests: XCTestCase {
    private static let hook = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent(".githooks/pre-commit")
    /// A made-up name for the list, so this test never carries a real one.
    private static let refused = "zz-made-up-refused-name"
    /// The user's own git config (hooks, signing, templates) must not reach this repository.
    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_AUTHOR_NAME"] = "Dana Example"
        env["GIT_AUTHOR_EMAIL"] = "dana@example.com"
        env["GIT_COMMITTER_NAME"] = "Dana Example"
        env["GIT_COMMITTER_EMAIL"] = "dana@example.com"
        return env
    }()

    private var root: URL!
    private var work: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pre-commit-\(UUID().uuidString)")
        work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try write("README.md", "a clean start\n")
        try git(["add", "README.md"])
        try git(["commit", "-q", "-m", "start"])
        let common = try git(["rev-parse", "--git-common-dir"])
        try (["# made up for this test", Self.refused, ""].joined(separator: "\n"))
            .write(to: work.appendingPathComponent(common).appendingPathComponent("info/kannu-denylist"),
                   atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testScansAStagedFileMarkedNotForDiffing() throws {
        try write(".git/info/attributes", "*.json -diff\n")
        try stage("fixture.json", "{\"note\": \"\(Self.refused)\"}\n")
        XCTAssertEqual(try runHook(), 1, "an attribute that marks a text file -diff must not hide its added lines")
    }

    func testScansAPathGitWouldQuote() throws {
        try stage("zz café notes.md", "mentions \(Self.refused)\n")
        XCTAssertEqual(try runHook(), 1, "a non-ASCII path must reach the scan as the file it names")
    }

    func testScansASymlinkThatBecameAFile() throws {
        try FileManager.default.createSymbolicLink(atPath: work.appendingPathComponent("link.md").path,
                                                   withDestinationPath: "README.md")
        try git(["add", "link.md"])
        try git(["commit", "-q", "-m", "a link"])
        try FileManager.default.removeItem(at: work.appendingPathComponent("link.md"))
        try stage("link.md", "mentions \(Self.refused)\n")
        XCTAssertEqual(try runHook(), 1, "a type change (status T) adds content too")
    }

    func testChecksAConflictResolution() throws {
        let head = try git(["rev-parse", "HEAD"])
        try write(".git/MERGE_HEAD", head + "\n")
        try stage("resolved.md", "mentions \(Self.refused)\n")
        XCTAssertEqual(try runHook(), 1, "the merge exemption must not skip the denylist")
    }

    func testRefusesAMatchingIdentity() throws {
        try stage("more.md", "nothing to refuse here\n")
        XCTAssertEqual(try runHook(extra: ["GIT_AUTHOR_EMAIL": "someone@\(Self.refused).example"]), 1,
                       "the author's identity is published too")
    }

    func testAllowsACleanStagedFile() throws {
        try write(".git/info/attributes", "*.json -diff\n")
        try stage("fixture.json", "{\"note\": \"nothing to refuse here\"}\n")
        XCTAssertEqual(try runHook(), 0)
    }

    // MARK: - Helpers

    private enum HookTestError: Error { case git([String], Int32) }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = work
        process.environment = Self.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HookTestError.git(arguments, process.terminationStatus) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ path: String, _ text: String) throws {
        try text.write(to: work.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func stage(_ path: String, _ text: String) throws {
        try write(path, text)
        try git(["add", "--", path])
    }

    /// Runs the hook as git does before a commit: no arguments, in the work tree, the staged change in the index.
    private func runHook(extra: [String: String] = [:]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.hook.path]
        process.currentDirectoryURL = work
        process.environment = Self.environment.merging(extra) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
