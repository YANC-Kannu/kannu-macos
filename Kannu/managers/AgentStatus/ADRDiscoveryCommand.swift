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

/// How Kannu invokes the user's `adr-discovery` — held as data so tests can pin it, the same
/// discipline `ClaudeUsageFetchCommand` earned the hard way (docs/REGRESSIONS.md entry 8):
/// every argument is verified against what the tool actually accepts (`cli.py` at
/// `ADRUpstream.commit`; the package still calls itself 0.2.0 there).
///
/// - `--json` so the snapshot is machine-readable.
/// - `--output-dir <snapshot folder>` so the file lands where the store already watches; the
///   tool names it `snapshot-<timestamp>.json` and writes it `0600` with `O_EXCL`.
/// - `--policy <file>` only when the user configured one (tenant domains, approved and forbidden
///   catalog ids, approved and forbidden indicators).
/// - Never `--dry-run` (nothing would be written), never `--root` (that scans a fixture tree,
///   not this Mac), never `--diff` (Kannu de-duplicates by finding id itself), never `--resolve`
///   (DNS lookups of provider hosts: Discovery sends nothing over the network without it), never
///   `--archive-skills` (zips of every skill, written where Kannu does not look).
///
/// Exit codes: 0 complete, 2 partial coverage (still a valid snapshot), 1 error.
enum ADRDiscoveryCommand {
    static let exitOK: Int32 = 0
    static let exitError: Int32 = 1
    static let exitPartial: Int32 = 2

    /// A scan on this Mac took 17 s; the sweep is budgeted upstream (200 k entries). Generous
    /// but bounded: a hung scan must not pin a worker forever.
    static let timeout: TimeInterval = 180

    /// Arguments that would make the run useless or scan the wrong thing.
    static let forbiddenArguments: Set<String> = ["--dry-run", "--root", "--diff", "--explain", "--resolve", "--archive-skills"]

    static func arguments(outputDirectory: URL, policyFile: URL?) -> [String] {
        var args = ["--json", "--output-dir", outputDirectory.path]
        if let policyFile {
            args += ["--policy", policyFile.path]
        }
        return args
    }

    /// True when the argument list writes a real snapshot of this machine.
    static func isValidScan(arguments: [String]) -> Bool {
        guard arguments.contains("--json"),
              let index = arguments.firstIndex(of: "--output-dir"), index + 1 < arguments.count else { return false }
        return !arguments.contains { forbiddenArguments.contains($0) }
    }

    /// Whether an exit status yielded a snapshot worth reading.
    static func producedSnapshot(exitStatus: Int32) -> Bool {
        exitStatus == exitOK || exitStatus == exitPartial
    }

    /// Where the drafting prompt asks the agent to write ADR's policy. Neither ADR nor Kannu has a
    /// default; this sits beside the snapshots' folder, not in it.
    static let suggestedPolicyPath = "~/.kannu/adr/policy.json"

    /// What "Copy a prompt that drafts a policy" on the ADR scan policy row puts on the
    /// pasteboard. Written from upstream's source at `ADRUpstream.commit` (`judge/sanction.py`,
    /// `judge/findings.py`): `tenant_domains` flags MCP servers that reach outside the listed
    /// domains. Since a3ab5f7 (2026-10-12) a forbidden match is a finding too — `forbidden` takes
    /// catalog ids of AI tools, `forbidden_indicators` names MCP servers, packages, skills and files,
    /// and either raises a high `forbidden_asset` — so the prompt describes them but keeps them
    /// opt-in. An `mcp_endpoint` url goes through `normalize_url` (`redact.strip_url`), which drops
    /// user info, query and fragment before comparing, so the prompt keeps those — where a URL's
    /// secrets live — out of the policy file. An indicator with an unknown kind or an extra field
    /// makes the file unreadable, and a file ADR cannot read fails every scan, hence the check at
    /// the end.
    static let policyDraftingPrompt = """
        Write \(suggestedPolicyPath) for ADR Discovery, the scanner Kannu runs to check the AI tools and MCP \
        servers on this Mac. Format: JSON, {"tenant_domains": ["example.com"]}. Any MCP server that connects by \
        URL to a host outside those domains is flagged; a subdomain of a listed domain counts as inside, and there \
        are no wildcards. Servers that run as a local command are not checked. First read my MCP configs \
        (~/.claude.json, ~/.cursor/mcp.json, any project .mcp.json) and list each URL-based server's name and \
        host only, never tokens, headers or environment values. Ask me which of those domains are mine, then \
        write the file with just those, create the folder if needed, and check it with python3 -m json.tool. \
        ADR also reads "forbidden", a list of ADR catalog ids of AI tools (such as claude-code), and \
        "forbidden_indicators", a list that can name an MCP server: {"kind": "mcp_endpoint", "url": "https://..."}, \
        {"kind": "package", "ecosystem": "npm", "name": "...", "all_versions": true} (or "versions": ["1.2.3"]), or \
        {"kind": "name", "asset_kind": "mcp_server", "name": "..."}. An mcp_endpoint url is scheme, host, port and \
        path only, never user info, a query string or a fragment (ADR drops them before comparing); if the path \
        itself carries a key, use a name indicator instead. Anything they match is a high-severity \
        finding; "approved" and "approved_indicators" are the allowed counterparts and raise none. Leave all four \
        out unless I ask, and use only those fields: ADR rejects an indicator with an unknown kind or an extra \
        field, and a policy it cannot read fails every scan. Finish by telling me to choose the file in Kannu: \
        Settings, Agent Security, ADR scans, Advanced, ADR scan policy, Choose.
        """
}

/// When Kannu runs its own Discovery scan: daily, or sooner after the MCP servers an agent's
/// settings declare changed — at most once per `debounce`. A change seen inside the window is
/// kept until the window has passed; it used to be dropped (the baseline moved on, the scan never
/// came). Compares server sets, not modification times: Claude Code rewrites `~/.claude.json` for
/// many reasons that are not MCP servers.
///
/// A scan that wrote no snapshot is retried after 1, 2, 4, 8, 16 hours (never later than the daily
/// scan) instead of a full day later; while scans keep failing, a config change waits for that
/// retry too, so a broken install is not re-run every five minutes.
struct ADRScanTrigger: Equatable {
    enum Reason: String, Equatable {
        case scheduled
        case configChanged = "config changed"
        case retry = "retry after a failed scan"
    }

    /// How long after the last Kannu-run scan the next one is due.
    static func retryDelay(consecutiveFailures: Int, interval: TimeInterval) -> TimeInterval {
        guard consecutiveFailures > 0 else { return interval }
        return min(3600 * pow(2, Double(min(consecutiveFailures, 10) - 1)), interval)
    }

    let interval: TimeInterval
    let debounce: TimeInterval
    private(set) var baseline: [String: [String]]?
    private(set) var pendingChange = false

    init(interval: TimeInterval, debounce: TimeInterval) {
        self.interval = interval
        self.debounce = debounce
    }

    /// `inventory` nil: the settings were not read this time — nothing learned, nothing lost.
    mutating func evaluate(now: Date, lastScan: Date?, consecutiveFailures: Int = 0,
                           inventory: [String: [String]]?) -> Reason? {
        if let inventory {
            if let baseline, baseline != inventory { pendingChange = true }
            baseline = inventory
        }
        let since = lastScan.map { now.timeIntervalSince($0) } ?? .infinity
        if since >= Self.retryDelay(consecutiveFailures: consecutiveFailures, interval: interval) {
            pendingChange = false
            return consecutiveFailures > 0 && since < interval ? .retry : .scheduled
        }
        if pendingChange, since >= changeDelay(consecutiveFailures: consecutiveFailures) {
            pendingChange = false
            return .configChanged
        }
        return nil
    }

    /// When the next automatic scan is due, for Settings; nil means at the next check (within a
    /// minute), because Kannu has not run one yet. Stable between checks, so publishing it does not
    /// redraw anything once a minute.
    func nextScan(lastScan: Date?, consecutiveFailures: Int) -> Date? {
        guard let lastScan else { return nil }
        let due = lastScan.addingTimeInterval(Self.retryDelay(consecutiveFailures: consecutiveFailures, interval: interval))
        guard pendingChange else { return due }
        return min(due, lastScan.addingTimeInterval(changeDelay(consecutiveFailures: consecutiveFailures)))
    }

    private func changeDelay(consecutiveFailures: Int) -> TimeInterval {
        consecutiveFailures > 0
            ? max(debounce, Self.retryDelay(consecutiveFailures: consecutiveFailures, interval: interval))
            : debounce
    }

    /// Any scan covers a pending change.
    mutating func scanStarted() {
        pendingChange = false
    }
}

/// The span of one Kannu-run scan. A snapshot modified inside it is the one that scan wrote — the
/// watcher may ingest it before the process exits, or the reload after exit may — and one modified
/// outside it was written by something else. `kannuScanStartedAt` used to be set and never
/// cleared, so after Kannu's first scan every later snapshot was labelled Kannu's.
struct ADRKannuScanWindow: Equatable {
    let startedAt: Date
    var finishedAt: Date?
    /// Whether this scan's success or failure has been counted (a file can be ingested twice).
    var settled = false

    func wrote(_ modified: Date) -> Bool {
        modified >= startedAt.addingTimeInterval(-1)
            && modified <= (finishedAt ?? .distantFuture).addingTimeInterval(2)
    }
}

/// The optional folder Kannu also searches for `adr-discovery`, `adr-sensor` and `uv`.
enum ADRToolFolder {
    /// macOS asks the user before an app reads these; Kannu checks the folder at every launch, so a
    /// tools folder inside one would raise that prompt again and again. Returns the folder's name.
    static func protectedFolderName(for path: String, home: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !home.isEmpty else { return nil }
        let expanded = trimmed.hasPrefix("~/") || trimmed == "~" ? home + trimmed.dropFirst() : trimmed
        let protected: [(folder: String, name: String)] = [
            ("Documents", "Documents"), ("Desktop", "Desktop"), ("Downloads", "Downloads"),
            ("Library/Mobile Documents", "iCloud Drive"),
        ]
        for entry in protected where expanded == home + "/" + entry.folder || expanded.hasPrefix(home + "/" + entry.folder + "/") {
            return entry.name
        }
        return nil
    }
}

/// The upstream ADR revision Kannu's integration was last checked against: github.com/uber/ADR
/// `main` at 6b33dff (2026-10-16). The install lines Kannu hands out pin it, because an unpinned
/// install runs whatever reached `main` last — the shape Kannu itself reports for an MCP server
/// (`unpinned_mcp_server`). Moving the pin is a deliberate change: re-read upstream at the new
/// commit first (the snapshot schema, the policy fields, the Detection API the adapter imports).
enum ADRUpstream {
    static let commit = "6b33dffecd719708c435f772c9e93f1210944e31"

    static let discoveryInstallCommand = "uv tool install \"adr-discovery @ git+https://github.com/uber/ADR@\(commit)#subdirectory=Discovery\""
    static let discoveryPipxCommand = "pipx install \"git+https://github.com/uber/ADR@\(commit)#subdirectory=Discovery\""
    static let detectionCloneCommand = "git clone https://github.com/uber/ADR && cd ADR && git checkout \(commit) && cd Detection && uv sync"
    /// Run inside an existing Detection folder; works from a branch or a detached checkout alike.
    static let detectionUpdateCommand = "git fetch && git checkout \(commit) && uv sync"

    /// Upstream's fix for Claude Code 2.1's list-shaped `--output-format json` (1c8ecd6, PR 134,
    /// 2026-09-22) added `if isinstance(claude_result, list):` after both
    /// `claude_result = json.loads(...)` lines in `guardrail/adr_agent/adr_baseline.py`. A checkout
    /// without it fails every analysis: `json.loads` returns a list and `.get` raises. Every
    /// revision of that file before the fix has the `json.loads` line and no `isinstance` check on
    /// it; every revision since, up to `commit`, has both.
    static let claudeCode21OutputFixMarker = "isinstance(claude_result"
    static let preClaudeCode21OutputShape = "claude_result = json.loads("

    /// Pure: whether a Detection checkout's `adr_baseline.py` predates that fix. Only the old code,
    /// recognisably there, counts: a file upstream later rewrites, or a fork that fixes it another
    /// way, need not have the `claude_result = json.loads(` line and is left to the run to judge —
    /// a stale verdict blocks analysis, and its update line would move a newer checkout back to
    /// the pin.
    static func predatesClaudeCode21OutputFix(baselineSource: String) -> Bool {
        baselineSource.contains(preClaudeCode21OutputShape) && !baselineSource.contains(claudeCode21OutputFixMarker)
    }
}
