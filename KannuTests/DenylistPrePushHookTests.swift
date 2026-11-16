//
//  DenylistPrePushHookTests.swift
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

/// `.githooks/pre-push` refuses to publish commits that match the local denylist
/// (`<git-common-dir>/info/kannu-denylist`). What it treats as already published must come from the server the
/// push goes to: never from local remote-tracking refs, which in a clone that missed a history rewrite still reach
/// the old commits, and never from a remote's fetch URL when its push URL names another server. Each test builds
/// throwaway repositories and runs the real hook with the arguments and input git gives it.
final class DenylistPrePushHookTests: XCTestCase {
    private static let hook = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent(".githooks/pre-push")
    private static let zero = String(repeating: "0", count: 40)
    /// A made-up name for the list, so this test never carries a real one.
    private static let refused = "zz-made-up-refused-name"
    /// The user's own git config (hooks, signing, templates) must not reach these repositories.
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
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pre-push-\(UUID().uuidString)")
        work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: work)
        try commit("README.md", "a clean start\n", message: "start")
        try (["# made up for this test", Self.refused, ""].joined(separator: "\n"))
            .write(to: denylist(), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testRefusesACommitReachableOnlyFromAStaleTrackingRef() throws {
        let server = try bareRepository("server")
        try git(["push", "-q", server.path, "main"], in: work)
        try git(["checkout", "-q", "-b", "old"], in: work)
        let old = try commit("notes.md", "mentions \(Self.refused)\n", message: "old work")
        // A clone that missed a rewrite still has a tracking ref that reaches the old commit.
        try git(["update-ref", "refs/remotes/origin/stale", old], in: work)
        XCTAssertEqual(try runHook(remote: "origin", url: server.path, pushing: old), 1,
                       "a tracking ref is this clone's memory, not the server's: the server never had this commit")
    }

    func testAsksThePushURLNotTheFetchURL() throws {
        let fetchServer = try bareRepository("fetch-server")
        let pushServer = try bareRepository("push-server")
        try git(["checkout", "-q", "-b", "old"], in: work)
        let old = try commit("notes.md", "mentions \(Self.refused)\n", message: "old work")
        try git(["push", "-q", fetchServer.path, "old"], in: work)   // only the fetch server has it
        try git(["remote", "add", "split", fetchServer.path], in: work)
        try git(["remote", "set-url", "--push", "split", pushServer.path], in: work)
        XCTAssertEqual(try runHook(remote: "split", url: pushServer.path, pushing: old), 1,
                       "what the fetch server has says nothing about the server this push goes to")
    }

    func testAllowsACleanPush() throws {
        let server = try bareRepository("server")
        try git(["push", "-q", server.path, "main"], in: work)
        let clean = try commit("more.md", "nothing to refuse here\n", message: "clean work")
        XCTAssertEqual(try runHook(remote: "origin", url: server.path, pushing: clean), 0)
    }

    func testWithoutAListThereIsNoCheck() throws {
        let server = try bareRepository("server")
        let old = try commit("notes.md", "mentions \(Self.refused)\n", message: "old work")
        try FileManager.default.removeItem(at: denylist())
        XCTAssertEqual(try runHook(remote: "origin", url: server.path, pushing: old), 0,
                       "no list, no check: other contributors' pushes are unaffected")
    }

    // MARK: - Helpers

    private enum HookTestError: Error { case git([String], Int32) }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
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

    /// Runs the hook as git does: the remote's name and the URL pushed to as arguments, one ref per input line.
    private func runHook(remote: String, url: String, pushing sha: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.hook.path, remote, url]
        process.currentDirectoryURL = work
        process.environment = Self.environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("refs/heads/old \(sha) refs/heads/old \(Self.zero)\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @discardableResult
    private func commit(_ file: String, _ text: String, message: String) throws -> String {
        try text.write(to: work.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try git(["add", file], in: work)
        try git(["commit", "-q", "-m", message], in: work)
        return try git(["rev-parse", "HEAD"], in: work)
    }

    private func bareRepository(_ name: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).git")
        try git(["init", "-q", "--bare", url.path], in: root)
        return url
    }

    private func denylist() throws -> URL {
        let commonDirectory = try git(["rev-parse", "--git-common-dir"], in: work)
        return work.appendingPathComponent(commonDirectory).appendingPathComponent("info/kannu-denylist")
    }
}
