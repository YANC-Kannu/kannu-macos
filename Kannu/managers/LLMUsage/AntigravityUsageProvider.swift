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

/// Antigravity has no token or cost log Kannu can read. The card shows two things:
/// - the model quotas the Antigravity CLI reports for `agy -p "/usage" --output-format json`, when a
///   Google-signed `agy` is installed (`AntigravityQuotaReader`; unverified, see
///   `AntigravityUsageCommand`), and
/// - a session line from the hook-written status files `~/.kannu/agent-status/antigravity-*.json`,
///   shown alone without quotas and as the secondary line under them.
struct AntigravityUsageProvider: UsageProvider {
    let id: ProviderID = .antigravity
    let statusDir: URL
    let home: URL
    /// `/usage` asks Google's backend, so the provider takes the network floor (`LLMUsageManager`):
    /// at most every 3 minutes on the Usage tab's 30-second tick, 10 seconds for a Refresh.
    var isLocalFileProvider: Bool { !AntigravityUsageCommand.reachesNetwork }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        self.statusDir = home.appendingPathComponent(".kannu/agent-status")
    }

    func fetchSnapshot(now: Date, interactive: Bool = false) async throws -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now
        snapshot.logsUnavailable = true   // no token logs for Antigravity
        snapshot.billedCostOnly = true    // hide cost columns entirely

        let sessions = sessionLine(now: now)
        // `interactive` is not passed on: it marks a step that may show a prompt, and `agy` never
        // does. The failure backoff is lifted by the Refresh button instead (`clearBackoff`).
        let reading = await AntigravityQuotaReader.shared.read(now: now, home: home)
        let limits = AntigravityQuotaLimits(pools: reading?.pools ?? [])
        if limits.isEmpty {
            switch sessions {
            case .none:
                throw UsageError.notConfigured("No Antigravity sessions found. Start a chat in Antigravity IDE to see session info here.")
            case .noneRecent:
                throw UsageError.notConfigured("No recent Antigravity sessions in the last 24 hours.")
            case .line:
                break
            }
        }
        func usageLimit(_ window: AntigravityQuotaWindow) -> UsageLimit {
            UsageLimit(used: window.usedPercent, limit: 100, resetsAt: window.resetsAt)
        }
        snapshot.sessionLimit = limits.session.map(usageLimit)
        snapshot.weekLimit = limits.week.map(usageLimit)
        snapshot.limitsLabel = limits.label
        snapshot.extraLimits = limits.extras.map {
            NamedLimit(key: $0.key, limit: usageLimit($0.window), label: $0.label, isSessionWindow: $0.isSessionWindow)
        }
        // Bars kept from an earlier run carry that run's time, so the manager's own last-good bound
        // (a later throw keeps this result) counts from when `agy` said them, not from now.
        if !limits.isEmpty, let reading { snapshot.lastUpdated = reading.readAt }
        // Repurposed as the card's status line, alone or under the quota bars.
        if case .line(let line) = sessions { snapshot.quotaError = line }
        return snapshot
    }

    private enum Sessions {
        case none
        case noneRecent
        case line(String)
    }

    private func sessionLine(now: Date) -> Sessions {
        let files = antigravityStatusFiles()
        if files.isEmpty { return .none }

        var latestTs: Int64 = 0
        var sessionCount = 0
        var lastState = ""

        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let ts = (json["ts"] as? NSNumber)?.int64Value ?? 0
            let state = (json["state"] as? String) ?? ""
            // Skip simulation / test sessions
            let convID = file.deletingPathExtension().lastPathComponent
            guard !convID.lowercased().contains("default"),
                  !convID.lowercased().contains("kannu-test"),
                  !convID.lowercased().hasPrefix("test-")
            else { continue }
            // Only count sessions active within 24 hours
            let ageSeconds = (Int64(now.timeIntervalSince1970 * 1000) - ts) / 1000
            guard ageSeconds < 86_400 else { continue }

            sessionCount += 1
            if ts > latestTs {
                latestTs = ts
                lastState = state
            }
        }

        if sessionCount == 0 { return .noneRecent }

        let lastDate = Date(timeIntervalSince1970: TimeInterval(latestTs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relTime = formatter.localizedString(for: lastDate, relativeTo: now)
        let stateLabel = lastState.isEmpty ? "" : " · \(lastState.replacingOccurrences(of: "_", with: " "))"
        return .line("\(sessionCount) session\(sessionCount == 1 ? "" : "s") · last active \(relTime)\(stateLabel)")
    }

    private func antigravityStatusFiles() -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: statusDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter {
            $0.pathExtension == "json" &&
            $0.lastPathComponent.hasPrefix("antigravity-")
        }
    }
}

/// Runs `agy -p "/usage" --output-format json` and parses its answer. Only a binary that carries a
/// valid Developer ID signature from Google's team is run, on a utility queue (it blocks for up to
/// the timeout), through `BoundedProcessRunner`. Its output is the account's data: never logged.
/// Never reads Antigravity's OAuth credentials and never calls its local language server; `agy`
/// does its own sign-in.
///
/// Known gap: the signature is checked on the path, and `Process` then execs that path. A process of
/// the same user that swaps the file between the two is not caught. Closing it needs a suspended
/// spawn checked by pid, which `BoundedProcessRunner` does not do. The verdict cache does not widen
/// the gap: it is keyed on facts that include the ctime, which an in-place rewrite always changes.
final class AntigravityQuotaReader: @unchecked Sendable {
    static let shared = AntigravityQuotaReader()

    private static let logger = os.Logger(subsystem: "com.kannu.app", category: "AntigravityUsage")
    private let queue = DispatchQueue(label: "com.kannu.antigravity-usage", qos: .utility)
    private let lock = NSLock()
    /// Guarded by `lock`, like `lastGood` and `verdicts`.
    private var lastFailure: Date?
    /// The last run that gave a quota, shown while it holds after runs that give none.
    private var lastGood: AntigravityQuotaReading?
    private var verdicts = AntigravitySignatureVerdicts()

    private init() {}

    /// The quota to show at `now`: a fresh run's, or else the last good one while it holds
    /// (`AntigravityQuotaReading.kept`). nil when there is neither.
    func read(now: Date, home: URL) async -> AntigravityQuotaReading? {
        let backingOff = lock.withLock {
            lastFailure.map { now.timeIntervalSince($0) < AntigravityUsageCommand.failureBackoff } ?? false
        }
        var pools: [AntigravityQuotaPool] = []
        if !backingOff {
            pools = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: self.readNow(now: now, home: home))
                }
            }
        }
        return lock.withLock {
            if !pools.isEmpty {
                lastGood = AntigravityQuotaReading(pools: pools, readAt: now)
                return lastGood
            }
            return lastGood?.kept(at: now)
        }
    }

    /// For the Usage tab's Refresh button: someone who has just signed in to `agy` should not wait
    /// out the 15-minute backoff. Automatic refreshes never call this.
    func clearBackoff() {
        lock.withLock { lastFailure = nil }
    }

    private func readNow(now: Date, home: URL) -> [AntigravityQuotaPool] {
        // Not installed, or not signed by Google: nothing to ask, and nothing to back off from.
        guard let binary = trustedBinary(home: home) else { return [] }
        let process = Process()
        process.executableURL = binary
        process.arguments = AntigravityUsageCommand.arguments
        process.standardInput = FileHandle.nullDevice
        // Away from any project: a folder's own `.agents` settings have nothing to do with quota.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if let environment = AntigravityUsageCommand.environment { process.environment = environment }
        let result = BoundedProcessRunner.run(process, timeout: AntigravityUsageCommand.timeout,
                                              stdoutCap: AntigravityUsageCommand.stdoutCap, stderrCap: 4_096)
        let pools = result.status == 0 && !result.timedOut ? AntigravityUsageReport.parse(result.stdout, now: now) : []
        lock.withLock { lastFailure = pools.isEmpty ? now : nil }
        if pools.isEmpty {
            // How the run ended, never what it printed.
            Self.logger.info("agy /usage gave no quota: status \(result.status, privacy: .public), timed out \(result.timedOut, privacy: .public), \(result.stdout.count, privacy: .public) bytes")
        }
        return pools
    }

    /// The first candidate (symlinks resolved) that is an executable signed with Google's Developer ID.
    /// A verdict, pass or fail, is reused while the file's facts are unchanged.
    private func trustedBinary(home: URL) -> URL? {
        for candidate in AntigravityUsageCommand.candidates(home: home) {
            let url = candidate.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: url.path),
                  let facts = AntigravityFileFacts.of(path: url.path) else { continue }
            let known = lock.withLock { verdicts.verdict(path: url.path, facts: facts) }
            let trusted = known ?? Self.isSignedByGoogle(url)
            if known == nil { lock.withLock { verdicts.record(trusted, path: url.path, facts: facts) } }
            if trusted { return url }
        }
        return nil
    }

    private static func isSignedByGoogle(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(AntigravityUsageCommand.codeRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
