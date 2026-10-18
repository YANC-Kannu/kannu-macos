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

/// How Kannu invokes Claude Code to refresh usage — extracted so the decisions are testable.
///
/// Two shipped regressions came from "harmless" additions to this invocation, each of which broke
/// the fetch silently while everything still looked healthy:
///
/// 1. `--no-session-persistence` — rejected outside `--print` ("can only be used with --print
///    mode"), so the session exited before `/usage` was ever typed.
/// 2. `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` — suppresses nonessential network traffic, and
///    the usage fetch is a network call, so the session ran and fetched nothing.
///
/// Both were reasoned about rather than verified. The rules below are pinned by
/// `ClaudeUsageFetchCommandTests`; see docs/REGRESSIONS.md.
enum ClaudeUsageFetchCommand {
    /// Flags Claude Code accepts only alongside `--print`. Passing one to the interactive session
    /// this fetch needs makes the CLI exit immediately.
    static let printOnlyFlags: Set<String> = [
        "--no-session-persistence",
        "--input-format",
        "--output-format",
        "--replay-user-messages"
    ]

    /// Environment variables that break the fetch. `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
    /// silences exactly the request we are trying to make.
    static let forbiddenEnvironmentKeys: Set<String> = [
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
    ]

    /// Attempts in order. The first tries to suppress the remote-control device registration (the
    /// phantom chat); the last is bare, which is the invocation observed to actually fetch, so it
    /// must stay as the final fallback.
    static let attempts: [[String]] = [
        ["--settings", #"{"disableRemoteControl":true}"#],
        []
    ]

    /// The interactive `/usage` (declared `requires: {ink}`) needs a terminal session, so any
    /// print-only flag is invalid in `attempts`. The print probe below is a separate command.
    static func isValidForInteractiveSession(arguments: [String]) -> Bool {
        !arguments.contains { printOnlyFlags.contains($0) }
    }

    /// Inherited names the child must not see: Claude Code's and Anthropic's own namespaces.
    ///
    /// A Kannu launched normally has none, so for it nothing changes. A Kannu started from inside
    /// an agent session inherits that session's — the desktop host's proxy (`ANTHROPIC_BASE_URL`),
    /// its account and organization (`CLAUDE_CODE_ACCOUNT_UUID`, `CLAUDE_CODE_ORGANIZATION_UUID`),
    /// its scopes. Measured 2026-10-18 from such a process: with them the probe fetched, without
    /// them it found no sign-in of its own. The inherited proxy substitutes the host session's
    /// credentials for Claude Code's, and the fetch writes that account into `~/.claude.json`.
    static let scrubbedEnvironmentPrefixes = ["CLAUDE", "ANTHROPIC"]

    /// The child's environment: the inherited one, minus `scrubbedEnvironmentPrefixes`. Nil —
    /// plain inheritance, what the working version always did — whenever there is nothing to
    /// remove, which is every normal launch. Removing only, never adding: an added variable is
    /// regression 2, so this deliberately offers no way to add one.
    static func environment(
        inheriting inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String]? {
        let kept = inherited.filter { name, _ in
            !scrubbedEnvironmentPrefixes.contains { name.hasPrefix($0) }
        }
        return kept.count == inherited.count ? nil : kept
    }
}

// MARK: - The print probe and sign-in

/// The non-interactive way to refresh usage, and how Kannu decides what a run meant.
///
/// `/usage` also exists as a non-interactive local command (`supportsNonInteractive`), so
/// `claude -p "/usage"` prints the plan rows without a model turn — no tokens are spent — and
/// takes the same path that writes `cachedUsageUtilization` to `~/.claude.json`. No pty and no
/// typed keystrokes, so none of the timing guesses the interactive spawn depends on.
///
/// The plan rows only appear when Claude Code is signed in with a claude.ai account whose
/// sign-in carries the `user:profile` scope. Without one the command still exits 0 and prints
/// only the session cost summary, which is what `ProbeOutcome.noPlanData` stands for.
extension ClaudeUsageFetchCommand {
    /// The probe, pinned exactly. Read docs/REGRESSIONS.md entry 8 before adding anything to it:
    /// a flag or variable that looks harmless has silently stopped the fetch twice.
    static let printProbe: [String] = ["-p", "/usage"]

    /// The probe was measured at about 8 seconds; anything past this is stopped.
    static let printProbeTimeout: TimeInterval = 30

    /// Claude Code's own status command. It prints JSON by default and exits 1 when signed out,
    /// with the JSON still on stdout, so the exit status alone says nothing.
    static let authStatusArguments: [String] = ["auth", "status"]

    /// Claude Code's own sign-in: it opens claude.ai in the browser and finishes through Claude
    /// Code's localhost callback. `--claudeai` is the subscription sign-in, named explicitly so a
    /// change of default cannot switch an account to a different method.
    static let signInArguments: [String] = ["auth", "login", "--claudeai"]

    /// The browser half is the user's; this is how long Kannu waits for it.
    static let signInTimeout: TimeInterval = 300

    /// The rows Claude Code prints only when its usage fetch returned data, e.g.
    /// "Current session: 78% used · resets 2:40am" and "Current week (all models): 41% used".
    static let planRowPrefixes = ["Current session:", "Current week"]

    static func outputHasPlanRows(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return planRowPrefixes.contains { trimmed.hasPrefix($0) }
        }
    }

    enum ProbeOutcome: Equatable {
        /// New numbers are on disk, or were just fetched inside Claude Code's write throttle.
        case fetched
        /// It ran cleanly and printed no plan rows: not signed in to claude.ai, or the sign-in
        /// lacks the scope the usage fetch needs. Either way a sign-in is what fixes it.
        case noPlanData
        /// Timed out, exited non-zero, or never started.
        case failed
    }

    /// `fetchStampAdvanced` is the `fetchedAtMs` check. Plan rows without an advance still mean
    /// a fetch: Claude Code skips the cache write when it wrote one moments ago (60 s on 2.1.295,
    /// 300 s on 2.1.263), and the cache it kept is that recent.
    static func classifyProbe(exitStatus: Int32?, timedOut: Bool, fetchStampAdvanced: Bool,
                              output: String) -> ProbeOutcome {
        if fetchStampAdvanced { return .fetched }
        guard !timedOut, exitStatus == 0 else { return .failed }
        return outputHasPlanRows(output) ? .fetched : .noPlanData
    }

    /// The three fields of `claude auth status` Kannu reads. The rest of that output names the
    /// account, so it is never kept, logged or shown.
    struct AuthStatus: Equatable {
        let loggedIn: Bool
        let authMethod: String
        let apiProvider: String
    }

    static func parseAuthStatus(_ output: String) -> AuthStatus? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
              start < end,
              let json = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8))
                as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool,
              let authMethod = json["authMethod"] as? String else { return nil }
        return AuthStatus(loggedIn: loggedIn, authMethod: authMethod,
                          apiProvider: json["apiProvider"] as? String ?? "firstParty")
    }

    enum SignInDecision: Equatable {
        /// Signed out, or signed in with claude.ai but without the scope: Claude Code's own
        /// sign-in fixes both, and replaces nothing the user chose.
        case startSignIn
        /// An API key, a key helper, a cloud provider or a gateway. Starting a claude.ai sign-in
        /// would change how Claude Code bills, so Kannu only explains and offers Terminal.
        case otherSignInMethod
        /// The status could not be read; nothing is started on a guess.
        case unknown
    }

    static func signInDecision(for status: AuthStatus?) -> SignInDecision {
        guard let status else { return .unknown }
        guard status.apiProvider == "firstParty" else { return .otherSignInMethod }
        switch status.authMethod {
        case "none", "claude.ai": return .startSignIn
        default: return .otherSignInMethod
        }
    }

    /// The Terminal fallback, for a sign-in that needs its prompt visible (the paste-a-code case,
    /// or a browser that never opened). Written to a `.command` file and opened with `open`, which
    /// needs no Automation permission. The binary path is single-quoted, so a space in
    /// "Application Support" cannot split it.
    static func terminalSignInScript(binary: URL) -> String {
        let quoted = "'" + binary.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return """
        #!/bin/zsh
        # Written by Kannu: signs Claude Code on this Mac in to your claude.ai account.
        # Kannu never reads or stores the sign-in; Claude Code keeps it in your keychain.
        \(quoted) \(signInArguments.joined(separator: " "))
        echo
        echo "You can close this window."

        """
    }
}

// MARK: - Which Claude Code binary

/// Finds the Claude Code binary to run.
///
/// Claude Desktop keeps its own copy and updates it in the background; the terminal install in
/// `~/.local/bin` only updates when `claude` itself runs, so it can be months old on a Mac where
/// Claude is used only through the desktop app. The newest version wins wherever it lives. The npm
/// shim under Homebrew is deliberately not a candidate: it is a Node script, not the binary.
enum ClaudeCodeBinary {
    struct Candidate: Equatable {
        let url: URL
        let version: String
    }

    static func desktopRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude-code")
    }

    /// Desktop installs `claude-code/<version>/<build>/claude.app/Contents/MacOS/claude`; builds
    /// before October 2026 used `claude-code/<version>/claude.app/...`. Both are read.
    static func desktopCandidates(root: URL, fileManager: FileManager = .default) -> [Candidate] {
        guard let versions = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: [Candidate] = []
        for versionDir in versions where isVersion(versionDir.lastPathComponent) {
            let version = versionDir.lastPathComponent
            let flat = versionDir.appendingPathComponent(appBinaryPath)
            if fileManager.isExecutableFile(atPath: flat.path) {
                found.append(Candidate(url: flat, version: version))
            }
            let builds = (try? fileManager.contentsOfDirectory(at: versionDir, includingPropertiesForKeys: nil)) ?? []
            for build in builds {
                let nested = build.appendingPathComponent(appBinaryPath)
                if fileManager.isExecutableFile(atPath: nested.path) {
                    found.append(Candidate(url: nested, version: version))
                }
            }
        }
        return found
    }

    /// `~/.local/bin/claude`, a symlink into `~/.local/share/claude/versions/<version>`.
    static func terminalCandidate(home: URL, fileManager: FileManager = .default) -> Candidate? {
        let link = home.appendingPathComponent(".local/bin/claude")
        let resolved = link.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: resolved.path) else { return nil }
        let version = resolved.lastPathComponent
        return Candidate(url: resolved, version: isVersion(version) ? version : "0")
    }

    /// Highest version first; a tie keeps the earlier candidate, so Desktop's copy wins.
    static func newest(_ candidates: [Candidate]) -> Candidate? {
        candidates.enumerated().max { lhs, rhs in
            switch lhs.element.version.compare(rhs.element.version, options: .numeric) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.offset > rhs.offset
            }
        }?.element
    }

    static func resolve(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        fileManager: FileManager = .default) -> Candidate? {
        newest(desktopCandidates(root: desktopRoot(home: home), fileManager: fileManager)
               + [terminalCandidate(home: home, fileManager: fileManager)].compactMap { $0 })
    }

    private static let appBinaryPath = "claude.app/Contents/MacOS/claude"

    private static func isVersion(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
