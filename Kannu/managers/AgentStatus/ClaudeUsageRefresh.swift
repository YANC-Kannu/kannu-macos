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

import Darwin
import Foundation
import os

/// What the last refresh needs the user to know, when anything. The card renders it.
enum ClaudeRefreshStatus: Equatable {
    /// Claude Code's own sign-in is open in the browser; Kannu fetches again once it finishes.
    case signingIn
    /// A sign-in is needed and has not happened here. The card offers Refresh again and
    /// Terminal, which shows the prompt when the browser route cannot finish.
    case signInNeeded
    /// Claude Code signs in some other way on this Mac (API key, key helper, cloud provider,
    /// gateway) and plan limits need claude.ai. Kannu never switches that by itself.
    case otherSignInMethod
    /// No Claude Code binary was found.
    case notInstalled
    /// The fetch ran and failed: it timed out or exited with an error.
    case fetchFailed

    /// States the automatic refresh must leave alone until the user acts.
    var holdsAutomaticRefresh: Bool { self != .fetchFailed }
}

/// The process work behind the Claude card's Refresh, off the main actor: the `/usage` probe, the
/// `claude auth status` check, Claude Code's own sign-in, and the interactive fallback. Foundation
/// only, so a harness can run exactly this code against the real CLI (REGRESSIONS entry 8 asks
/// for a measured fetch, not a reasoned one). `CursorAgentStatusMonitor` owns the state.
enum ClaudeUsageRefresh {
    /// The sign-in while it runs, so Cancel on the main actor can stop it.
    private static let signInProcess = OSAllocatedUnfairLock<Process?>(initialState: nil)

    static let log = os.Logger(subsystem: "com.kannu.app", category: "ClaudeUsage")

    /// Stops a sign-in that is waiting on the browser; `run` then ends as `.signInNeeded`.
    static func cancelSignIn() {
        signInProcess.withLock { $0 }?.terminate()
    }

    /// One refresh, start to finish, on a worker thread. Returns what the card should say, or
    /// nil when new numbers landed. Logs each step's outcome and duration, never its output: that
    /// carries plan and spend figures and the account's name.
    static func run(
        binary: ClaudeCodeBinary.Candidate,
        allowSignIn: Bool,
        signInStarted: () -> Void
    ) -> ClaudeRefreshStatus? {
        switch probeUsage(binary: binary) {
        case .fetched:
            return nil
        case .failed:
            // The probe is new; the interactive spawn has a track record, so it stays as the
            // fallback until the probe has one too.
            let started = Date()
            let fetched = runInteractiveUsageFetch(binary: binary.url)
            logStep("interactive /usage", binary: binary, outcome: fetched ? "fetched" : "failed", since: started)
            return fetched ? nil : .fetchFailed
        case .noPlanData:
            break
        }

        let started = Date()
        let auth = ClaudeUsageFetchCommand.parseAuthStatus(
            runClaude(binary: binary.url, arguments: ClaudeUsageFetchCommand.authStatusArguments, timeout: 15).output)
        let decision = ClaudeUsageFetchCommand.signInDecision(for: auth)
        logStep("auth status", binary: binary, outcome: "\(decision)", since: started)
        switch decision {
        case .otherSignInMethod: return .otherSignInMethod
        case .unknown: return .signInNeeded
        case .startSignIn: break
        }
        guard allowSignIn else { return .signInNeeded }

        signInStarted()
        let signInStart = Date()
        let signIn = runSignIn(binary: binary.url)
        logStep("sign-in", binary: binary,
                outcome: signIn.timedOut ? "timed out" : "exit \(signIn.status.map(String.init) ?? "-")",
                since: signInStart)
        guard signIn.status == 0, !signIn.timedOut else { return .signInNeeded }
        return probeUsage(binary: binary) == .fetched ? nil : .signInNeeded
    }

    /// `claude -p "/usage"`, classified. Success is judged from disk (`fetchedAtMs`) first; the
    /// printed rows only settle the case Claude Code's own write throttle leaves ambiguous.
    private static func probeUsage(binary: ClaudeCodeBinary.Candidate) -> ClaudeUsageFetchCommand.ProbeOutcome {
        let started = Date()
        let before = cachedUsageFetchedAtMs()
        let run = runClaude(binary: binary.url, arguments: ClaudeUsageFetchCommand.printProbe,
                            timeout: ClaudeUsageFetchCommand.printProbeTimeout)
        let after = cachedUsageFetchedAtMs()
        let outcome = ClaudeUsageFetchCommand.classifyProbe(
            exitStatus: run.status, timedOut: run.timedOut,
            fetchStampAdvanced: after != nil && after != before, output: run.output)
        logStep("-p /usage", binary: binary, outcome: "\(outcome)", since: started)
        return outcome
    }

    private static func logStep(_ step: String, binary: ClaudeCodeBinary.Candidate,
                                            outcome: String, since started: Date) {
        let seconds = Date().timeIntervalSince(started)
        log.info("Usage refresh \(step, privacy: .public): Claude Code \(binary.version, privacy: .public), \(outcome, privacy: .public), \(seconds, format: .fixed(precision: 1))s")
    }

    private static func cachedUsageFetchedAtMs() -> Double? {
        guard let data = try? Data(contentsOf: ClaudeCachedUsage.defaultURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = json["cachedUsageUtilization"] as? [String: Any] else { return nil }
        return (cache["fetchedAtMs"] as? NSNumber)?.doubleValue
    }

    private struct ClaudeRun {
        let status: Int32?
        let timedOut: Bool
        let output: String
    }

    /// One Claude Code command, run to completion: nothing on stdin, cwd `/`, both pipes drained
    /// so the child can never block on a full buffer, stopped at the deadline (SIGTERM, then
    /// SIGKILL). stdout is returned for classification and never logged; stderr is discarded.
    /// The environment is inherited, minus an agent session's own variables, as
    /// `ClaudeUsageFetchCommand.environment(inheriting:)` pins.
    private static func runClaude(binary: URL, arguments: [String], timeout: TimeInterval) -> ClaudeRun {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ClaudeUsageFetchCommand.environment()
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let collected = OSAllocatedUnfairLock(initialState: (data: Data(), done: false))
        let cap = 256 * 1024
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            collected.withLock { state in
                if chunk.isEmpty {
                    state.done = true
                } else if state.data.count < cap {
                    state.data.append(chunk.prefix(cap - state.data.count))
                }
            }
            if chunk.isEmpty { handle.readabilityHandler = nil }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        do { try process.run() } catch {
            // Reachable: Claude Code reaps old version directories, so the binary resolved a
            // moment ago can be gone.
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return ClaudeRun(status: nil, timedOut: false, output: "")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        let timedOut = process.isRunning
        if timedOut { stop(process) }
        process.waitUntilExit()
        // Output written just before exit can still be in flight; give the handler a moment to
        // reach end of file, but never wait on a descendant that kept the pipe open.
        let drainDeadline = Date().addingTimeInterval(1)
        while !collected.withLock({ $0.done }) && Date() < drainDeadline { Thread.sleep(forTimeInterval: 0.02) }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        let output = String(decoding: collected.withLock { $0.data }, as: UTF8.self)
        return ClaudeRun(status: timedOut ? nil : process.terminationStatus, timedOut: timedOut, output: output)
    }

    /// `claude auth login --claudeai` under a pseudo-terminal: its prompt is an interactive
    /// screen, which needs a terminal to draw into. Nothing is ever typed; the browser and
    /// Claude Code's localhost callback do the work. Output is drained and discarded.
    private static func runSignIn(binary: URL) -> (status: Int32?, timedOut: Bool) {
        let process = Process()
        process.executableURL = binary
        process.arguments = ClaudeUsageFetchCommand.signInArguments
        process.environment = ClaudeUsageFetchCommand.environment()
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        var master: Int32 = 0, slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return (nil, false) }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        masterHandle.readabilityHandler = { _ = $0.availableData }
        defer {
            // An armed readability source on a closing descriptor is FileHandle's documented crash.
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            try? slaveHandle.close()
        }
        do { try process.run() } catch { return (nil, false) }
        signInProcess.withLock { $0 = process }
        defer { signInProcess.withLock { $0 = nil } }

        let deadline = Date().addingTimeInterval(ClaudeUsageFetchCommand.signInTimeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        let timedOut = process.isRunning
        if timedOut { stop(process) }
        process.waitUntilExit()
        return (timedOut ? nil : process.terminationStatus, timedOut)
    }

    /// terminate() only signals, and Claude Code can trap SIGTERM; escalate so waitUntilExit()
    /// can never block the worker and strand the spinner.
    private static func stop(_ process: Process) {
        process.terminate()
        let killDeadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < killDeadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// The probe runs in `/` with no terminal, so its SessionStart hook can leave a status file
    /// that would otherwise read as a chat. Any Claude hook file written in `/` during the refresh
    /// is the probe's; its id is remembered so the next rescan drops it under the status lock, as
    /// for the interactive probe.
    static func probeHookConversationIDs(in directory: URL, since start: Date) -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files.compactMap { file -> String? in
            let name = file.lastPathComponent
            guard name.hasPrefix("claude-"), file.pathExtension == "json",
                  let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified >= start.addingTimeInterval(-1),
                  let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["cwd"] as? String == "/" else { return nil }
            return String(name.dropFirst("claude-".count).dropLast(".json".count))
        }
    }

    /// The interactive `/usage` spawn this predates the probe with: a pseudo-terminal, `/usage`
    /// typed after the TUI comes up. Kept as the fallback for a probe that fails outright.
    private static func runInteractiveUsageFetch(binary: URL) -> Bool {
        // Two attempts. The first suppresses the remote-control device registration (the phantom
        // chat); if that flag turns out to be rejected or ineffective and no fetch lands, fall back
        // to the bare invocation, which is proven to fetch. Better a working refresh than a clean
        // one that does nothing.
        for arguments in ClaudeUsageFetchCommand.attempts {
            guard ClaudeUsageFetchCommand.isValidForInteractiveSession(arguments: arguments) else { continue }
            if attemptUsageFetch(binary: binary, arguments: arguments) { return true }
        }
        return false
    }

    /// One interactive `/usage` run. Returns true when the on-disk fetch stamp advanced.
    private static func attemptUsageFetch(binary: URL, arguments: [String]) -> Bool {
        let before = cachedUsageFetchedAtMs()

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        // Plain inheritance (nil) on a normal launch, exactly as the version that was proven to
        // fetch. Setting CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC here suppressed nonessential
        // network traffic — which is what the usage fetch is — so nothing was ever fetched.
        process.environment = ClaudeUsageFetchCommand.environment()

        // A pty is required: the interactive `/usage` only runs in a terminal session.
        var master: Int32 = 0, slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return false }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle
        // Drain the pty so the child never blocks on a full buffer; the output itself is unused.
        masterHandle.readabilityHandler = { _ = $0.availableData }

        do { try process.run() } catch {
            // Every exit path clears the handler before the handle is dropped — an armed
            // readability source on a closing descriptor is FileHandle's documented crash.
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            try? slaveHandle.close()
            return false
        }

        // Give the TUI time to come up before typing, then issue the command.
        Thread.sleep(forTimeInterval: 3)
        if !process.isRunning {
            // Rejected argument or instant exit — nothing was typed, so report failure and let the
            // caller try the next invocation.
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            return false
        }
        masterHandle.write(Data("/usage\r".utf8))

        var fetched = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if let now = cachedUsageFetchedAtMs(), now != before { fetched = true; break }
            if !process.isRunning { break }
        }

        if process.isRunning && fetched {
            masterHandle.write(Data("/exit\r".utf8))
            let quitDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < quitDeadline { Thread.sleep(forTimeInterval: 0.1) }
        }
        if process.isRunning {
            stop(process)
            process.waitUntilExit()
        }
        masterHandle.readabilityHandler = nil
        try? masterHandle.close()
        return fetched
    }
}
