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
import Security

/// The process work behind the Claude card's Refresh, off the main actor: the `/usage` probe, the
/// `claude auth status` check, Claude Code's own sign-in, and the interactive fallback. Which of
/// them runs, in what order, is decided by `ClaudeUsageFetchCommand`'s steps; this file only runs
/// processes. Foundation and Security only, so a harness can run exactly this code against the
/// real CLI (REGRESSIONS entry 8 asks for a measured fetch, not a reasoned one).
/// `CursorAgentStatusMonitor` owns the state.
enum ClaudeUsageRefresh {
    static let log = os.Logger(subsystem: "com.kannu.app", category: "ClaudeUsage")

    // MARK: The running child

    private struct Running {
        var process: Process?
        var cancelled = false
    }

    /// The one child a refresh runs at a time, so Cancel and app exit can reach it.
    private static let running = OSAllocatedUnfairLock(initialState: Running())

    private static var isCancelled: Bool { running.withLock { $0.cancelled } }

    /// Registers the child so Cancel and app exit can reach it. False when the refresh was
    /// cancelled already: app exit may have picked what to stop before this child existed, so it
    /// is stopped here instead.
    @discardableResult
    private static func register(_ process: Process) -> Bool {
        let registered = running.withLock { state -> Bool in
            guard !state.cancelled else { return false }
            state.process = process
            return true
        }
        if !registered, process.isRunning { stop(process, grace: 0.5) }
        return registered
    }

    private static func unregister(_ process: Process) {
        running.withLock { state in if state.process === process { state.process = nil } }
    }

    /// Stops a sign-in waiting on the browser (or whatever step is running); the refresh then
    /// ends as `.signInDidNotFinish`.
    static func cancelSignIn() {
        running.withLock { $0.cancelled = true }
    }

    /// Called from `applicationWillTerminate`. macOS has no parent-death signal: a child left
    /// running here is reparented to launchd, and a sign-in would keep its localhost listener open
    /// (REGRESSIONS entry 19 — whoever starts a child stops it). Synchronous on purpose.
    static func terminateForAppExit() {
        let process = running.withLock { state -> Process? in
            state.cancelled = true
            return state.process
        }
        if let process, process.isRunning { stop(process, grace: 0.5) }
    }

    // MARK: One refresh

    /// What one refresh ended as.
    struct Outcome {
        /// What the refresh found; nil when new numbers landed. `ClaudeUsageFetchCommand.presentation`
        /// decides whether the card shows it.
        var status: ClaudeRefreshStatus?
        /// After a fetch: the organization Claude Code fetched for, as its own profile fetch left
        /// it in `~/.claude.json` the moment the run ended.
        var fetchedOrganization: String? = nil
    }

    /// One refresh, start to finish, on a worker thread. `manual` is a press of the card's
    /// Refresh. Logs each step's outcome and duration at `notice`, so it is kept on disk — never
    /// its output, which carries plan and spend figures and the account's name, nor a path.
    static func run(manual: Bool, signInStarted: () -> Void) -> Outcome {
        running.withLock { $0 = Running() }
        guard let binary = trustedBinary() else {
            log.notice("Usage refresh: no Claude Code binary signed by Anthropic was found")
            return Outcome(status: .notInstalled)
        }
        var step = ClaudeUsageFetchCommand.firstStep(binaryVersion: binary.version, manual: manual)
        var signedIn = false
        var fetched = false
        while true {
            step = ClaudeUsageFetchCommand.step(step, cancelled: isCancelled, signedIn: signedIn, fetched: fetched)
            switch step {
            case .probe:
                let outcome = probeUsage(binary: binary)
                fetched = outcome == .fetched
                step = ClaudeUsageFetchCommand.step(afterProbe: outcome, manual: manual, afterSignIn: signedIn)
            case .interactiveFetch:
                let started = Date()
                fetched = runInteractiveUsageFetch(binary: binary.url)
                logStep("interactive /usage", binary: binary, outcome: fetched ? "fetched" : "failed", since: started)
                step = ClaudeUsageFetchCommand.step(afterInteractiveFetch: fetched)
            case .authStatus:
                let started = Date()
                let auth = ClaudeUsageFetchCommand.parseAuthStatus(
                    runClaude(binary: binary.url, arguments: ClaudeUsageFetchCommand.authStatusArguments, timeout: 15).output)
                let decision = ClaudeUsageFetchCommand.signInDecision(for: auth)
                logStep("auth status", binary: binary, outcome: "\(decision)", since: started)
                step = ClaudeUsageFetchCommand.step(afterAuth: decision, manual: manual)
            case .signIn:
                signInStarted()
                let started = Date()
                let signIn = runSignIn(binary: binary.url)
                signedIn = true
                logStep("sign-in", binary: binary,
                        outcome: signIn.timedOut ? "timed out" : "exit \(signIn.status.map(String.init) ?? "-")",
                        since: started)
                step = ClaudeUsageFetchCommand.step(afterSignIn: signIn.status == 0 && !signIn.timedOut && !isCancelled)
            case .finish(let status):
                return Outcome(status: status, fetchedOrganization: fetched ? claudeCodeOrganization() : nil)
            }
        }
    }

    /// The binary for the Terminal fallback, resolved again when the button is pressed: the one
    /// a refresh found earlier may have been reaped by an update since.
    static func trustedBinaryURL() -> URL? {
        trustedBinary()?.url
    }

    private static func trustedBinary() -> ClaudeCodeBinary.Candidate? {
        ClaudeCodeBinary.resolve(isTrusted: isSignedByAnthropic)
    }

    /// Read straight after Claude Code's own run, which rewrites `oauthAccount` from its token's
    /// profile — later, a desktop-hosted session may rewrite it with the desktop's organization.
    private static func claudeCodeOrganization() -> String? {
        guard let data = try? Data(contentsOf: ClaudeCachedUsage.defaultURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let organization = account["organizationUuid"] as? String, !organization.isEmpty else { return nil }
        return organization
    }

    /// `claude -p "/usage"`, classified, in `printProbeAttempts` order: the bare probe runs only
    /// when the first fails outright. Success is judged from disk (`fetchedAtMs`) first; the
    /// printed rows only settle the case Claude Code's own write throttle leaves ambiguous.
    private static func probeUsage(binary: ClaudeCodeBinary.Candidate) -> ClaudeUsageFetchCommand.ProbeOutcome {
        var outcome = ClaudeUsageFetchCommand.ProbeOutcome.failed
        for (index, arguments) in ClaudeUsageFetchCommand.printProbeAttempts.enumerated() {
            let started = Date()
            let before = cachedUsageFetchedAtMs()
            let run = runClaude(binary: binary.url, arguments: arguments,
                                timeout: ClaudeUsageFetchCommand.printProbeTimeout)
            let after = cachedUsageFetchedAtMs()
            outcome = ClaudeUsageFetchCommand.classifyProbe(
                exitStatus: run.status, timedOut: run.timedOut,
                fetchStampAdvanced: after != nil && after != before, output: run.output)
            logStep(index == 0 ? "-p /usage (hooks off)" : "-p /usage", binary: binary,
                    outcome: "\(outcome)", since: started)
            if outcome != .failed || isCancelled { break }
        }
        return outcome
    }

    private static func logStep(_ step: String, binary: ClaudeCodeBinary.Candidate,
                                outcome: String, since started: Date) {
        let seconds = Date().timeIntervalSince(started)
        log.notice("Usage refresh \(step, privacy: .public): Claude Code \(binary.version, privacy: .public), \(outcome, privacy: .public), \(seconds, format: .fixed(precision: 1))s")
    }

    private static func cachedUsageFetchedAtMs() -> Double? {
        guard let data = try? Data(contentsOf: ClaudeCachedUsage.defaultURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = json["cachedUsageUtilization"] as? [String: Any] else { return nil }
        return (cache["fetchedAtMs"] as? NSNumber)?.doubleValue
    }

    // MARK: Trust

    /// Anthropic's Developer ID and Claude Code's identifier, read from the binaries on this Mac
    /// (Desktop's bundled copies and the terminal install all carry exactly this). A child process
    /// inherits Kannu's privacy permissions, and every folder Claude Code is found in is writable
    /// by any process of the user's, so a binary that fails this is never run. The check and the
    /// launch are separate moments: a process that can swap the file in between, keeping its size
    /// and date, is not stopped by it.
    static let anthropicRequirement = #"identifier "com.anthropic.claude-code" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "Q6L2SF6YDW""#

    /// Verdicts by path, for as long as the file's size and modification date stand. Checking
    /// reads the whole binary, so it is done once per version, not once per refresh.
    private static let trustVerdicts = OSAllocatedUnfairLock(initialState: [String: (size: Int, modified: Date, trusted: Bool)]())

    static func isSignedByAnthropic(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize, let modified = values?.contentModificationDate else { return false }
        if let verdict = trustVerdicts.withLock({ $0[url.path] }), verdict.size == size, verdict.modified == modified {
            return verdict.trusted
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let trusted = SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && SecRequirementCreateWithString(anthropicRequirement as CFString, [], &requirement) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, [], requirement) == errSecSuccess } == true
        trustVerdicts.withLock { $0[url.path] = (size, modified, trusted) }
        if !trusted { log.notice("Usage refresh: skipped a claude binary not signed by Anthropic") }
        return trusted
    }

    // MARK: Processes

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
        register(process)
        defer { unregister(process) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline && !isCancelled { Thread.sleep(forTimeInterval: 0.1) }
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
        register(process)
        defer { unregister(process) }

        // Cancel only raises a flag; the stop happens here, so a Claude Code that traps SIGTERM
        // still goes, through `stop`'s SIGKILL, instead of holding the spinner for five minutes.
        let deadline = Date().addingTimeInterval(ClaudeUsageFetchCommand.signInTimeout)
        while process.isRunning && Date() < deadline && !isCancelled { Thread.sleep(forTimeInterval: 0.25) }
        let timedOut = process.isRunning
        if timedOut { stop(process) }
        process.waitUntilExit()
        return (timedOut ? nil : process.terminationStatus, timedOut)
    }

    /// terminate() only signals, and Claude Code can trap SIGTERM; escalate so waitUntilExit()
    /// can never block the worker and strand the spinner.
    private static func stop(_ process: Process, grace: TimeInterval = 2) {
        process.terminate()
        let killDeadline = Date().addingTimeInterval(grace)
        while process.isRunning && Date() < killDeadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// A hook can still leave a status file for the probe (the bare fallback, or a Claude Code
    /// that ignores `disableAllHooks`); its id is remembered so the next rescan drops it under the
    /// status lock, as for the interactive probe. `ClaudeUsageFetchCommand.isProbeHookFile` says
    /// which files are the probe's.
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
                  ClaudeUsageFetchCommand.isProbeHookFile(json: json) else { return nil }
            return String(name.dropFirst("claude-".count).dropLast(".json".count))
        }
    }

    /// The interactive `/usage` spawn the probe replaced: a pseudo-terminal, `/usage` typed after
    /// the TUI comes up. It types blind into a terminal session, so `ClaudeUsageFetchCommand`'s
    /// steps reach it only on a press — for a probe that failed outright, or a Claude Code too old
    /// for the probe. Unchanged otherwise, guards included (entry 8).
    private static func runInteractiveUsageFetch(binary: URL) -> Bool {
        // Two attempts. The first suppresses the remote-control device registration (the phantom
        // chat); if that flag turns out to be rejected or ineffective and no fetch lands, fall back
        // to the bare invocation, which is proven to fetch. Better a working refresh than a clean
        // one that does nothing.
        for arguments in ClaudeUsageFetchCommand.attempts {
            if isCancelled { return false }
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

        register(process)
        defer { unregister(process) }
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
            if !process.isRunning || isCancelled { break }
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
