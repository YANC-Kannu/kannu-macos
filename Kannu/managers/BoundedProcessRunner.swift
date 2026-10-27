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

/// What a bounded child process left behind.
struct BoundedProcessResult: Equatable {
    /// The exit status, or -1 when the process never ran.
    let status: Int32
    let stdout: Data
    let stderr: Data
    /// True when the deadline passed and the process was terminated (then killed) by us.
    let timedOut: Bool
}

/// Runs a child process to completion under a deadline, reading its output the way a child needs
/// it read. One implementation, because the five hand-rolled copies it replaces disagreed on the
/// parts that matter and two of them could block a thread forever:
///
/// - **Read while waiting, never after.** A pipe holds 64 KB. A child that writes more before
///   anyone reads blocks in `write()` and never exits, so a `waitUntilExit()` that precedes the
///   read waits for it forever (`docs/REGRESSIONS.md` entry 11). Both pipes are drained on every
///   poll, with the read ends non-blocking, so the drain can never block either.
/// - **Stop reading when the child is gone.** `readDataToEndOfFile()` returns only when *every*
///   copy of the write end is closed. A grandchild that inherited the pipe — a uv shim's worker, a
///   tmux server the client spawned — keeps it open after the child exits, and the read blocked a
///   thread for the app's lifetime. After the child exits the pipes get one last non-blocking drain
///   and are closed; whatever a grandchild writes later goes nowhere.
/// - **Escalate.** SIGTERM at the deadline, SIGKILL after the grace period, `waitUntilExit()` only
///   once one of those has landed. A child that traps SIGTERM cannot hold the thread.
///
/// - **Talk, then stop.** `input` is written to the child's stdin while it runs, a non-blocking
///   write per poll, so input larger than a pipe cannot block the writer. Without `until`, stdin is
///   closed once the input is written, so a filter sees EOF and finishes. With `until`, stdin stays
///   open (a JSON-RPC server may shut down on EOF before it answers) until `until` accepts the
///   stdout kept so far. Then stdin is closed and the child gets `killGrace` to exit on that EOF,
///   the shutdown a stdio server is built for, with both pipes still drained; only a child still
///   running after it is stopped the way a child past its deadline is (SIGTERM, then SIGKILL).
///   Either way the result does not count as timed out.
///
/// Blocks the calling thread for up to `timeout + killGrace` (`timeout + 2 × killGrace` once
/// `until` has held); never call it on the main thread.
enum BoundedProcessRunner {
    /// - Parameters:
    ///   - process: configured with its executable, arguments, directory and environment; its
    ///     standard output and error are replaced here, and its standard input when `input` is set.
    ///   - stdoutCap: bytes of stdout kept (the rest is read and dropped so the child never blocks).
    ///   - stderrCap: the same for stderr.
    ///   - killGrace: how long SIGTERM gets before SIGKILL.
    ///   - input: bytes for the child's stdin; nil leaves `process.standardInput` as configured.
    ///   - until: checked against the stdout kept so far after every read; true ends the run.
    static func run(_ process: Process, timeout: TimeInterval, stdoutCap: Int = 1_000_000, stderrCap: Int = 64_000,
                    killGrace: TimeInterval = 3, pollInterval: TimeInterval = 0.05,
                    input: Data? = nil, until: ((Data) -> Bool)? = nil) -> BoundedProcessResult {
        let stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var stdout = CappedBuffer(cap: stdoutCap), stderr = CappedBuffer(cap: stderrCap)
        let stdoutFD = stdoutPipe.fileHandleForReading.fileDescriptor
        let stderrFD = stderrPipe.fileHandleForReading.fileDescriptor
        for fd in [stdoutFD, stderrFD] {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }
        let stdin = input.map { PendingInput(data: $0) }
        if let stdin {
            process.standardInput = stdin.pipe
        }
        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            stdin?.close()
        }

        do {
            try process.run()
        } catch {
            return BoundedProcessResult(status: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8), timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var answered = false
        while process.isRunning && Date() < deadline {
            if let stdin, stdin.writeMore(), until == nil { stdin.close() }
            stdout.drain(stdoutFD)
            stderr.drain(stderrFD)
            if let until, until(stdout.data) {
                answered = true
                break
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        stdin?.close()
        if answered {
            let exitDeadline = Date().addingTimeInterval(killGrace)
            while process.isRunning && Date() < exitDeadline {
                stdout.drain(stdoutFD)
                stderr.drain(stderrFD)
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        var timedOut = false
        if process.isRunning {
            timedOut = !answered
            process.terminate()
            let killDeadline = Date().addingTimeInterval(killGrace)
            while process.isRunning && Date() < killDeadline {
                stdout.drain(stdoutFD)
                stderr.drain(stderrFD)
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        stdout.drain(stdoutFD)
        stderr.drain(stderrFD)
        return BoundedProcessResult(status: process.terminationStatus, stdout: stdout.data, stderr: stderr.data, timedOut: timedOut)
    }

    /// The child's stdin: written without blocking, closed once.
    private final class PendingInput {
        let pipe = Pipe()
        private let data: Data
        private var offset = 0
        private var closed = false

        init(data: Data) {
            self.data = data
            let fd = pipe.fileHandleForWriting.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            // A child that exits before reading everything must not take Kannu down with SIGPIPE;
            // the write fails with EPIPE instead.
            _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        }

        /// Writes what the pipe takes right now. True once everything has been written, or once
        /// writing is no longer possible.
        func writeMore() -> Bool {
            guard !closed else { return true }
            let fd = pipe.fileHandleForWriting.fileDescriptor
            while offset < data.count {
                let n = data.withUnsafeBytes { bytes in
                    Darwin.write(fd, bytes.baseAddress! + offset, data.count - offset)
                }
                if n > 0 {
                    offset += n
                    continue
                }
                // -1 with EAGAIN is a full pipe: try again on the next poll. Anything else (EPIPE:
                // the child closed its stdin) means the rest can never be delivered.
                return n < 0 && errno != EAGAIN
            }
            return true
        }

        func close() {
            guard !closed else { return }
            closed = true
            try? pipe.fileHandleForWriting.close()
        }
    }

    /// Reads everything a non-blocking descriptor has right now and keeps the first `cap` bytes.
    private struct CappedBuffer {
        let cap: Int
        private(set) var data = Data()
        private var scratch = [UInt8](repeating: 0, count: 65_536)

        init(cap: Int) { self.cap = cap }

        mutating func drain(_ fd: Int32) {
            while true {
                let n = scratch.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    let room = cap - data.count
                    if room > 0 { data.append(contentsOf: scratch[0..<min(n, room)]) }
                    continue
                }
                // 0 is EOF; -1 with EAGAIN is "nothing yet"; anything else is a closed or broken
                // descriptor. None of them is worth another read on this pass.
                return
            }
        }
    }
}
