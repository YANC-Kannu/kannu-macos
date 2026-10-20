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

    /// Inherited names the child must not see when Kannu was started from inside an agent
    /// session: Claude Code's and Anthropic's own namespaces.
    ///
    /// Such a Kannu inherits that session's desktop-host proxy (`ANTHROPIC_BASE_URL`), its account
    /// and organization (`CLAUDE_CODE_ACCOUNT_UUID`, `CLAUDE_CODE_ORGANIZATION_UUID`) and its
    /// scopes. Measured 2026-10-18 from such a process: with them the probe fetched, without them
    /// it found no sign-in of its own. The inherited proxy substitutes the host session's
    /// credentials for Claude Code's, and the fetch writes that account into `~/.claude.json`.
    static let scrubbedEnvironmentPrefixes = ["CLAUDE", "ANTHROPIC"]

    /// Variables Claude Code exports into every process an agent session runs. Their presence is
    /// what marks the inherited environment as an agent session's rather than the user's own.
    static let agentSessionMarkers = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"]

    /// The child's environment. Nil — plain inheritance, what the working version always did —
    /// for every normal launch, including a user's own `launchctl setenv` configuration (an API
    /// key, a gateway, a cloud provider): that is what Claude Code should use, and the auth-status
    /// gate must see it to leave such a setup alone. Only an inherited agent session is scrubbed
    /// of `scrubbedEnvironmentPrefixes`. Removing only, never adding: an added variable is
    /// regression 2, so this deliberately offers no way to add one.
    static func environment(
        inheriting inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String]? {
        guard agentSessionMarkers.contains(where: { inherited[$0] != nil }) else { return nil }
        let kept = inherited.filter { name, _ in
            !scrubbedEnvironmentPrefixes.contains { name.hasPrefix($0) }
        }
        return kept.count == inherited.count ? nil : kept
    }
}

// MARK: - The print probe and sign-in

/// What a refresh needs the user to know, when anything. The card renders it.
enum ClaudeRefreshStatus: Equatable {
    /// Claude Code's own sign-in is open in the browser; Kannu fetches again once it finishes.
    case signingIn
    /// Claude Code is not signed in to claude.ai. A press of the card's Refresh starts its sign-in.
    case signInNeeded
    /// The sign-in a press started did not finish: it was cancelled, timed out, or no limits came
    /// back after it. A press starts it again; Terminal shows its prompt when the browser cannot.
    case signInDidNotFinish
    /// Claude Code is signed in to claude.ai and still returned no limits. Kannu does not start a
    /// browser sign-in over a working one — that can move Claude Code to another organization.
    case noLimitsReturned
    /// Claude Code's sign-in state could not be read, so nothing is started on a guess.
    case signInUnchecked
    /// Claude Code signs in some other way on this Mac (API key, key helper, cloud provider,
    /// gateway) and plan limits need claude.ai. Kannu never switches that by itself.
    case otherSignInMethod
    /// No Claude Code binary Kannu trusts was found.
    case notInstalled
    /// The fetch ran and failed: it timed out or exited with an error.
    case fetchFailed

    /// States after which the automatic refresh stands down until the user acts or the data
    /// changes some other way: running again would only find the same thing.
    var holdsAutomaticRefresh: Bool {
        switch self {
        case .signingIn, .signInNeeded, .signInDidNotFinish, .signInUnchecked, .otherSignInMethod: return true
        case .noLimitsReturned, .notInstalled, .fetchFailed: return false
        }
    }

    /// States that mean "a claude.ai sign-in is missing". Data turning fresh some other way — a
    /// sign-in in Terminal, Claude Code's own `/usage` — settles them.
    var awaitsSignIn: Bool {
        switch self {
        case .signInNeeded, .signInDidNotFinish, .signInUnchecked, .otherSignInMethod: return true
        case .signingIn, .noLimitsReturned, .notInstalled, .fetchFailed: return false
        }
    }
}

/// The non-interactive way to refresh usage, and how Kannu decides what a run meant.
///
/// `/usage` also exists as a non-interactive local command (`supportsNonInteractive`), so
/// `claude -p "/usage"` prints the plan rows without a model turn — no tokens are spent — and
/// takes the same path that writes `cachedUsageUtilization` to `~/.claude.json`. No pty and no
/// typed keystrokes, so none of the timing guesses the interactive spawn depends on.
///
/// The plan rows only appear when Claude Code is signed in with a claude.ai account whose
/// sign-in carries the `user:profile` scope. Signed in to claude.ai, the output always opens with
/// "You are currently using your subscription…"; signed out (or on an API key) it is only the
/// session cost summary.
extension ClaudeUsageFetchCommand {
    /// The probe, pinned exactly, in order. Read docs/REGRESSIONS.md entry 8 before adding
    /// anything: a flag or variable that looks harmless has silently stopped the fetch twice.
    ///
    /// The first turns off every hook for the run — measured 2026-10-18: it still fetched
    /// (`fetchedAtMs` advanced, three plan rows) and, unlike the bare run, left no SessionStart
    /// status file behind, and it keeps the user's own hooks from firing on every automatic
    /// refresh. The bare probe, also measured to fetch, runs only if the first fails outright.
    static let printProbeAttempts: [[String]] = [
        ["--settings", #"{"disableAllHooks":true}"#, "-p", "/usage"],
        ["-p", "/usage"]
    ]

    /// The oldest Claude Code read to carry the non-interactive `/usage` (2.1.263, from its
    /// bundle). On anything older `-p "/usage"` could reach the model as a prompt — a billed turn
    /// on every automatic refresh — so older binaries get the interactive spawn, on a press only.
    static let minimumPrintProbeVersion = "2.1.263"

    static func supportsPrintProbe(version: String) -> Bool {
        version.compare(minimumPrintProbeVersion, options: .numeric) != .orderedAscending
    }

    /// The probe was measured at 1-6 seconds; anything past this is stopped.
    static let printProbeTimeout: TimeInterval = 30

    /// Claude Code's own status command. It prints JSON by default and exits 1 when signed out,
    /// with the JSON still on stdout, so the exit status alone says nothing. Measured: it also
    /// printed `loggedIn: false` where the probe fetched, so it is asked only after a probe that
    /// shows no claude.ai sign-in, to tell an API-key or cloud setup from a missing one.
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

    /// The line that opens the output whenever Claude Code is signed in to claude.ai, with or
    /// without limits to show ("…your subscription…" or "…your overages…").
    static let claudeAISignInPrefix = "You are currently using your"

    static func outputHasPlanRows(_ output: String) -> Bool {
        lines(of: output).contains { line in planRowPrefixes.contains { line.hasPrefix($0) } }
    }

    static func outputShowsClaudeAISignIn(_ output: String) -> Bool {
        lines(of: output).contains { $0.hasPrefix(claudeAISignInPrefix) }
    }

    private static func lines(of output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    enum ProbeOutcome: Equatable {
        /// New numbers are on disk, or were just fetched inside Claude Code's write throttle.
        case fetched
        /// It ran cleanly and printed no plan rows. `signedInToClaudeAI` says whether the output
        /// still showed a claude.ai sign-in (the fetch itself came back empty) or none at all.
        case noPlanData(signedInToClaudeAI: Bool)
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
        if outputHasPlanRows(output) { return .fetched }
        return .noPlanData(signedInToClaudeAI: outputShowsClaudeAISignIn(output))
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
        /// No claude.ai sign-in to replace: the probe showed none, and the status names no other
        /// method. Claude Code's own sign-in is what fixes it.
        case startSignIn
        /// An API key, a key helper, a cloud provider or a gateway. Starting a claude.ai sign-in
        /// would change how Claude Code bills, so Kannu only explains and offers Terminal.
        case otherSignInMethod
        /// The status could not be read; nothing is started on a guess.
        case unknown
    }

    /// Asked only after a probe that showed no claude.ai sign-in. `claude.ai` here therefore means
    /// the status file disagrees with the probe; a sign-in is still the fix, as for `none`.
    static func signInDecision(for status: AuthStatus?) -> SignInDecision {
        guard let status else { return .unknown }
        guard status.apiProvider == "firstParty" else { return .otherSignInMethod }
        switch status.authMethod {
        case "none", "claude.ai": return .startSignIn
        default: return .otherSignInMethod
        }
    }

    // MARK: The refresh, as steps

    /// One refresh, step by step. `ClaudeUsageRefresh` runs the processes; these functions decide
    /// what runs next, so every path is pinned by tests rather than buried in process plumbing.
    enum RefreshStep: Equatable {
        case probe
        case interactiveFetch
        case authStatus
        case signIn
        case finish(ClaudeRefreshStatus?)
    }

    /// `manual` is a press of the card's Refresh; the automatic refresh is not.
    static func firstStep(binaryVersion: String, manual: Bool) -> RefreshStep {
        if supportsPrintProbe(version: binaryVersion) { return .probe }
        // Too old for the probe: the interactive spawn types keystrokes blind into a terminal
        // session, so it never runs unattended.
        return manual ? .interactiveFetch : .finish(nil)
    }

    static func step(afterProbe outcome: ProbeOutcome, manual: Bool, afterSignIn: Bool = false) -> RefreshStep {
        switch outcome {
        case .fetched:
            return .finish(nil)
        case .failed:
            if afterSignIn { return .finish(.signInDidNotFinish) }
            return manual ? .interactiveFetch : .finish(.fetchFailed)
        case .noPlanData(let signedIn):
            if afterSignIn { return .finish(.signInDidNotFinish) }
            // Signed in and no limits: never a browser sign-in over a working one.
            return signedIn ? .finish(.noLimitsReturned) : .authStatus
        }
    }

    static func step(afterInteractiveFetch fetched: Bool) -> RefreshStep {
        .finish(fetched ? nil : .fetchFailed)
    }

    static func step(afterAuth decision: SignInDecision, manual: Bool) -> RefreshStep {
        switch decision {
        // The browser only ever opens on a press.
        case .startSignIn: return manual ? .signIn : .finish(.signInNeeded)
        case .otherSignInMethod: return .finish(.otherSignInMethod)
        case .unknown: return .finish(.signInUnchecked)
        }
    }

    static func step(afterSignIn succeeded: Bool) -> RefreshStep {
        succeeded ? .probe : .finish(.signInDidNotFinish)
    }

    /// What the card shows after a refresh, and whether the automatic refresh stands down. The
    /// automatic refresh only ever surfaces the one thing a press can fix — a missing sign-in;
    /// everything else it finds is shown after a press, never as a permanent line nobody asked for.
    static func presentation(of status: ClaudeRefreshStatus?, manual: Bool)
        -> (shown: ClaudeRefreshStatus?, holdsAutomaticRefresh: Bool) {
        guard let status else { return (nil, false) }
        let shown = manual || status == .signInNeeded ? status : nil
        return (shown, status.holdsAutomaticRefresh)
    }

    /// A status about a missing sign-in is settled once Claude Code's cache is newer than the
    /// refresh that set it: something else — a sign-in in Terminal, Claude Code's own `/usage` —
    /// fetched in the meantime.
    static func freshCacheSettles(_ status: ClaudeRefreshStatus?, setAt: Date?, cacheObservedAt: Date?) -> Bool {
        guard let status, status.awaitsSignIn, let setAt, let cacheObservedAt else { return false }
        return cacheObservedAt > setAt
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

    /// The probe's own status file, if a hook still wrote one (the bare fallback, or an older
    /// Claude Code that ignores `disableAllHooks`). Measured: run from `/`, its SessionStart file
    /// carries no `cwd` — the hook strips a trailing slash, leaving nothing — and a transcript
    /// path under `~/.claude/projects/-/`, which is how Claude Code names the project `/`.
    static func isProbeHookFile(json: [String: Any]) -> Bool {
        (json["transcript_path"] as? String)?.contains("/.claude/projects/-/") == true
    }
}

// MARK: - Which Claude Code binary

/// Finds the Claude Code binary to run.
///
/// Claude Desktop keeps its own copy and updates it in the background; the terminal install in
/// `~/.local/bin` only updates when `claude` itself runs, so it can be months old on a Mac where
/// Claude is used only through the desktop app. A Homebrew cask's binary is linked from
/// `/opt/homebrew/bin` or `/usr/local/bin`. The newest version wins wherever it lives, among the
/// candidates the caller trusts — Kannu runs only a binary signed by Anthropic, because a child
/// process inherits Kannu's privacy permissions and these folders are writable by any process of
/// the user's. The npm shim at the same Homebrew path is a Node script and never qualifies.
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
        linkedCandidate(home.appendingPathComponent(".local/bin/claude"), fileManager: fileManager)
    }

    /// Where a Homebrew cask (or a manual install) links `claude`.
    static let linkedPaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// A link to a binary, resolved. The version is the last path component that reads as one
    /// (`…/versions/2.1.263`, `…/Caskroom/claude-code/2.1.300/claude`), else "0" — the lowest,
    /// which also keeps an unknown version off the print probe.
    static func linkedCandidate(_ link: URL, fileManager: FileManager = .default) -> Candidate? {
        let resolved = link.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: resolved.path) else { return nil }
        let version = resolved.pathComponents.last(where: isVersion) ?? "0"
        return Candidate(url: resolved, version: version)
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

    /// Every candidate in preference order for ties: Desktop's copies, the terminal install,
    /// then the linked paths. Duplicates (two links to one file) are listed once.
    static func candidates(home: URL, fileManager: FileManager = .default,
                           linkedPaths: [String] = linkedPaths) -> [Candidate] {
        var all = desktopCandidates(root: desktopRoot(home: home), fileManager: fileManager)
        all += [terminalCandidate(home: home, fileManager: fileManager)].compactMap { $0 }
        all += linkedPaths.compactMap { linkedCandidate(URL(fileURLWithPath: $0), fileManager: fileManager) }
        var seen: Set<String> = []
        return all.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    static func resolve(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        fileManager: FileManager = .default,
                        linkedPaths: [String] = linkedPaths,
                        isTrusted: (URL) -> Bool) -> Candidate? {
        newest(candidates(home: home, fileManager: fileManager, linkedPaths: linkedPaths)
            .filter { isTrusted($0.url) })
    }

    private static let appBinaryPath = "claude.app/Contents/MacOS/claude"

    private static func isVersion(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}
