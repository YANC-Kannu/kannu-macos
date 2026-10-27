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

import Foundation
import os
import Security

/// Codex's rate limits from `codex app-server`, the interface OpenAI documents for clients
/// (https://learn.chatgpt.com/docs/app-server.md). Codex reads its own sign-in; Kannu never sees
/// a token. Only a foreground refresh uses this: it starts a process.
///
/// UNVERIFIED: Codex is not installed on the development Mac, so no real app-server has answered
/// this. The protocol is `CodexAppServerProtocol`; the binary is `CodexBinaryLocator`'s.
///
/// The process gets cwd `/`, the inherited environment, the three request lines on stdin and ten
/// seconds. Once the answer is in, stdin is closed and the server gets two seconds to exit on
/// that EOF before SIGTERM, then SIGKILL (`BoundedProcessRunner`). Its stdout is decoded and never
/// logged; its stderr is drained and dropped. Runs on its own serial queue, never on the main
/// thread or a Swift concurrency thread, one process at a time.
struct CodexAppServerClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "CodexAppServer")
    private static let queue = DispatchQueue(label: "com.kannu.app.codex-app-server", qos: .utility)
    static let timeout: TimeInterval = 10

    func fetch() async -> CodexAppServerProtocol.Outcome {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.fetchBlocking()) }
        }
    }

    private static func fetchBlocking() -> CodexAppServerProtocol.Outcome {
        guard let binary = CodexBinaryLocator.resolve(isTrusted: isSignedCodex) else {
            return .failed("no Developer ID-signed codex binary found")
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let process = Process()
        process.executableURL = binary
        process.arguments = CodexBinaryLocator.appServerArguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let started = Date()
        let run = BoundedProcessRunner.run(process, timeout: timeout, stdoutCap: 1_000_000, stderrCap: 0, killGrace: 2,
                                           input: CodexAppServerProtocol.requests(clientVersion: version),
                                           until: CodexAppServerProtocol.isComplete)
        let outcome = CodexAppServerProtocol.decode(run.stdout)
        let seconds = Date().timeIntervalSince(started)
        switch outcome {
        case .limits:
            log.notice("codex app-server answered account/rateLimits/read in \(seconds, format: .fixed(precision: 1))s")
        case .notSignedIn:
            log.notice("codex app-server: no ChatGPT sign-in to read limits with")
        case .failed(let reason):
            log.notice("codex app-server gave no limits: \(reason, privacy: .public) (exit \(run.status), timed out \(run.timedOut))")
        }
        return outcome
    }

    // MARK: Trust

    /// Verdicts by path, for as long as the file's `FileIdentity` (device, inode, size, change
    /// time) stands. Checking reads the whole binary, so it is done once per version, not once per
    /// refresh; any write to the file, or a file put in its place, gets it checked again.
    private static let trustVerdicts = OSAllocatedUnfairLock(
        initialState: [String: (identity: CodexBinaryLocator.FileIdentity, trusted: Bool)]())

    /// A child process inherits Kannu's privacy permissions, and every folder Codex is found in is
    /// writable by any process of the user's, so a binary that fails `signingRequirement` is never
    /// run. The check and the launch are separate moments: a process that swaps the file in that
    /// gap is not stopped by it, but the next refresh checks the new file again.
    static func isSignedCodex(_ url: URL) -> Bool {
        // Read before the check: a write during it moves the change time, so the verdict below is
        // filed under an identity the file no longer has and the next call checks again.
        guard let identity = CodexBinaryLocator.FileIdentity(path: url.path) else { return false }
        if let verdict = trustVerdicts.withLock({ $0[url.path] }), verdict.identity == identity {
            return verdict.trusted
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let trusted = SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && SecRequirementCreateWithString(CodexBinaryLocator.signingRequirement as CFString, [], &requirement) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, [], requirement) == errSecSuccess } == true
        trustVerdicts.withLock { $0[url.path] = (identity, trusted) }
        if !trusted { log.notice("skipped a codex binary without a Developer ID signature") }
        return trusted
    }
}
