//
//  PreCommitHookPipeTests.swift
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

/// `.githooks/pre-commit` runs under `set -euo pipefail`, so a pipe whose reader stops before the end
/// (awk with `exit`, `head`, `grep -q`) fails the whole hook whenever the writer is still writing: the
/// writer takes SIGPIPE, pipefail reports it, and errexit ends the hook. With `git show` of the ~175 KB
/// installer as the writer that was a race, and CI's "OpenSpec and hook" job failed now and then on an
/// unchanged tree with only `cat: ...: Broken pipe` (docs/REGRESSIONS.md entry 25).
///
/// This test takes the race out: a `git` shim on `PATH` makes every `git show` write slowly, in 4 KB
/// chunks, so any early reader closes the pipe while the writer still has data. SIGPIPE is ignored, as
/// it is on CI's runner, so the writer sees EPIPE and fails instead of dying quietly. The hook then runs
/// on a throwaway repository holding the real installer, mirrors and documents, with nothing staged:
/// the shape CI runs it in.
final class PreCommitHookPipeTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root
    private static let hook = repoRoot.appendingPathComponent(".githooks/pre-commit")
    /// Every file the hook reads through `git show`. Missing ones would skip checks and pass vacuously.
    private static let readFiles = [
        "Kannu/managers/AgentStatus/AgentHookInstaller.swift",
        "scripts/kannu-agent-status.sh",
        "scripts/kannu-usage-status.sh",
        "CONTRIBUTING.md",
        "AGENTS.md",
        ".agents/skills/kannu-senior-contributor/SKILL.md",
        ".cursor/rules/feature-changelog.mdc",
    ]
    /// `git show` through a slow pipe; every other subcommand is the real git.
    private static let shim = #"""
        #!/bin/bash
        if [ "$1" = show ]; then
          set -o pipefail
          /usr/bin/git "$@" | /usr/bin/perl -e '$|=1; while (read(STDIN, $b, 4096)) { print $b or exit 141; select(undef, undef, undef, 0.002) }'
          exit $?
        fi
        exec /usr/bin/git "$@"
        """#

    private var root: URL!
    private var work: URL!
    private var shimDirectory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/perl"),
                          "the slow-writer shim needs /usr/bin/perl")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pre-commit-pipe-\(UUID().uuidString)")
        work = root.appendingPathComponent("work")
        shimDirectory = root.appendingPathComponent("shim")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        let shimFile = shimDirectory.appendingPathComponent("git")
        try (Self.shim + "\n").write(to: shimFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimFile.path)

        _ = try run("/usr/bin/git", ["init", "-q", "-b", "main"])
        for path in Self.readFiles {
            let destination = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Self.repoRoot.appendingPathComponent(path), to: destination)
        }
        _ = try run("/usr/bin/git", ["add", "--"] + Self.readFiles)
        _ = try run("/usr/bin/git", ["commit", "-q", "--no-verify", "-m", "start"])
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// Anti-vacuous: the shim must really turn an early reader into a failed pipeline, or the next
    /// test proves nothing.
    func testTheShimMakesAnEarlyReaderFail() throws {
        let status = try run("/bin/bash", ["-c", """
            trap '' PIPE
            set -o pipefail
            git show :Kannu/managers/AgentStatus/AgentHookInstaller.swift | awk 'NR == 1 { exit }' > /dev/null
            """], slowGit: true)
        XCTAssertNotEqual(status, 0, "the slow git show should fail once awk stops reading")
    }

    func testTheHookNeverCutsOffAWriter() throws {
        let status = try run("/bin/bash", ["-c", "trap '' PIPE; exec /bin/bash \"$0\"", Self.hook.path],
                             slowGit: true)
        XCTAssertEqual(status, 0, """
            The hook failed on a clean tree while git show wrote slowly. A pipe in it has a reader that \
            stops early (awk exit, head, grep -q). Read the file into a variable first (docs/REGRESSIONS.md \
            entry 25).
            """)
    }

    // MARK: - Helpers

    private enum PipeTestError: Error { case failed([String], Int32) }

    /// Runs a command in the work tree with the user's git config shut out. Git setup steps throw on
    /// failure; the commands under test return their status.
    @discardableResult
    private func run(_ executable: String, _ arguments: [String], slowGit: Bool = false) throws -> Int32 {
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_AUTHOR_NAME"] = "Dana Example"
        env["GIT_AUTHOR_EMAIL"] = "dana@example.com"
        env["GIT_COMMITTER_NAME"] = "Dana Example"
        env["GIT_COMMITTER_EMAIL"] = "dana@example.com"
        if slowGit { env["PATH"] = shimDirectory.path + ":" + (env["PATH"] ?? "/usr/bin:/bin") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = work
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if executable == "/usr/bin/git" && process.terminationStatus != 0 {
            throw PipeTestError.failed(arguments, process.terminationStatus)
        }
        return process.terminationStatus
    }
}
