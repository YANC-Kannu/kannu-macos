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

/// A Claude request's tokens, added up from its transcripts (the chat's own from the size the hook
/// recorded at the turn's start, and every subagent transcript the turn wrote).
///
/// Every model call of a turn reads the chat's whole context again, from the prompt cache, so summing
/// what each call read counts that context once per call: a turn with 83 k new input tokens and a
/// 458 k context showed "24M in". The sums here are of what is new; the context is a size, not a sum.
struct TurnTokens: Equatable {
    /// Which turn these belong to: a card shows them only when both match its own turn.
    let startedAt: Date
    let startOffset: Int64
    /// Input the model had not seen: uncached input plus cache writes, summed over every call.
    var newInput: Int
    /// Context read back from the cache, summed over every call. Kept, not shown: mostly the same
    /// tokens again and again.
    var cacheRead: Int = 0
    /// Output, summed over every call.
    var output: Int
    /// The chat's context at its latest call: that one call's uncached input, cache writes and cache
    /// reads. Taken from the main transcript only, never a subagent's, and replaced by each call,
    /// never summed. nil until the turn's first call is written.
    var context: Int? = nil
}

/// What to follow for one chat card.
struct ClaudeTurnTokenRequest: Equatable {
    let conversationID: String
    let mainPath: String
    let startOffset: Int64
    let startedAt: Date

    /// Records a little older than the turn still count (the hook's clock and Claude's are the same
    /// machine's, but the prompt's record can land a moment before its hook); anything older is
    /// history copied into the file by a resume or a fork, never this request's.
    static let clockSlack: TimeInterval = 60
    var windowStart: Date { startedAt.addingTimeInterval(-Self.clockSlack) }

    /// `<session>.jsonl` keeps its subagents in `<session>/subagents/` (workflow agents one level
    /// deeper, under `workflows/wf_*/`).
    var subagentDirectory: String { String(mainPath.dropLast(".jsonl".count)) + "/subagents" }

    /// Visible Claude cards whose turn names a followable transcript and a start offset.
    static func requests(from sessions: [AgentSessionStatus], home: String) -> [ClaudeTurnTokenRequest] {
        var seen = Set<String>()
        var out: [ClaudeTurnTokenRequest] = []
        for session in sessions where session.isVisible && session.provider.lowercased() == "claude" {
            guard let turn = session.turn, let path = turn.transcriptPath, let offset = turn.transcriptOffset,
                  HookTurn.isFollowableTranscript(path, home: home),
                  seen.insert(session.conversationID).inserted else { continue }
            out.append(ClaudeTurnTokenRequest(conversationID: session.conversationID, mainPath: path,
                                              startOffset: offset, startedAt: turn.startedAt))
        }
        return out
    }
}

/// Reads one transcript forward from a byte offset and adds up the usage of the assistant records
/// in the time window. Pure over the bytes it is handed; the reader does the file access.
struct ClaudeTranscriptTokenAccumulator {
    enum Step: Equatable {
        case upToDate
        case read(from: Int64, count: Int)
    }

    static let chunkLimit = 4 << 20
    /// A line longer than this is skipped (the largest seen is ~1.3 MB); a split record repeats
    /// its message's usage, so a sibling record still counts.
    static let partialLimit = 8 << 20
    static let seenLimit = 1024

    let windowStart: Date
    private(set) var readOffset: Int64
    private(set) var fileID: UInt64?
    /// Uncached input plus cache writes.
    private(set) var newInput = 0
    private(set) var cacheRead = 0
    private(set) var output = 0
    /// The latest call's whole prompt (`UsageRecord.promptTokens`), from a record that is not a
    /// sidechain's. Only the main transcript's is shown; the reader ignores a subagent file's.
    private(set) var context: Int?
    private var partial = Data()
    private var skippingToNewline = false
    private var seenOrder: [String] = []
    /// What has been counted for each message, so a later line of it adds only what it reports beyond.
    private var seen: [String: UsageRecord] = [:]

    init(startOffset: Int64, windowStart: Date) {
        readOffset = max(0, startOffset)
        self.windowStart = windowStart
    }

    /// What to read next, given the file's current size and identity. A replaced file (a new
    /// inode) or one that shrank below what was read is read again from the start — never from
    /// an offset into the old file; the time window keeps its older records out.
    mutating func step(size: Int64, fileID id: UInt64) -> Step {
        if (fileID != nil && fileID != id) || size < readOffset {
            restart()
        }
        fileID = id
        guard readOffset < size else { return .upToDate }
        return .read(from: readOffset, count: Int(min(size - readOffset, Int64(Self.chunkLimit))))
    }

    /// The bytes at `readOffset`. Complete lines are counted; the tail waits for the next chunk.
    mutating func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        readOffset += Int64(chunk.count)
        var rest = chunk[...]
        if skippingToNewline {
            guard let newline = rest.firstIndex(of: 0x0A) else { return }
            rest = rest[rest.index(after: newline)...]
            skippingToNewline = false
        }
        while let newline = rest.firstIndex(of: 0x0A) {
            if partial.isEmpty {
                tally(Data(rest[rest.startIndex..<newline]))
            } else {
                partial.append(contentsOf: rest[rest.startIndex..<newline])
                tally(partial)
                partial.removeAll(keepingCapacity: false)
            }
            rest = rest[rest.index(after: newline)...]
        }
        partial.append(contentsOf: rest)
        if partial.count > Self.partialLimit {
            partial.removeAll(keepingCapacity: false)
            skippingToNewline = true
        }
    }

    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let usageMarker = Data(#""usage":{"#.utf8)

    private mutating func tally(_ line: Data) {
        // A cheap hint first: most lines are tool results and user records. The parse decides.
        guard line.range(of: Self.assistantMarker) != nil, line.range(of: Self.usageMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let record = ClaudeUsageLine.parse(object),
              record.timestamp >= windowStart else { return }
        var counted = record
        if let key = record.dedupKey {
            if let earlier = seen[key] {
                // Another line of a message already counted. Usually the same usage again; in Claude
                // Code 2.1.219–2.1.304 subagent files the first line was a mid-stream snapshot and a
                // later one carries the real output, so add whatever this one reports beyond it.
                counted = earlier.merging(record)
                seen[key] = counted
                add(uncached: counted.uncachedInputTokens - earlier.uncachedInputTokens,
                    cacheWrite: counted.cacheWriteTokens - earlier.cacheWriteTokens,
                    cacheRead: counted.cacheReadTokens - earlier.cacheReadTokens,
                    output: counted.outputTokens - earlier.outputTokens)
            } else {
                seen[key] = record
                seenOrder.append(key)
                if seenOrder.count > Self.seenLimit {
                    seen[seenOrder.removeFirst()] = nil
                }
                add(uncached: record.uncachedInputTokens, cacheWrite: record.cacheWriteTokens,
                    cacheRead: record.cacheReadTokens, output: record.outputTokens)
            }
        } else {
            add(uncached: record.uncachedInputTokens, cacheWrite: record.cacheWriteTokens,
                cacheRead: record.cacheReadTokens, output: record.outputTokens)
        }
        // A sidechain record is a subagent's call written into the chat's own file (older Claude
        // Code): its context is not the chat's.
        if object["isSidechain"] as? Bool != true {
            context = counted.promptTokens
        }
    }

    private mutating func add(uncached: Int, cacheWrite: Int, cacheRead: Int, output: Int) {
        newInput += uncached + cacheWrite
        self.cacheRead += cacheRead
        self.output += output
    }

    private mutating func restart() {
        readOffset = 0
        newInput = 0
        cacheRead = 0
        output = 0
        context = nil
        partial.removeAll(keepingCapacity: false)
        skippingToNewline = false
        seenOrder.removeAll()
        seen.removeAll()
    }
}

/// Follows the requested turns' transcripts across passes: each pass reads at most `passBudget`
/// new bytes and reports a chat's tokens only once every one of its files has been read up to the
/// size it had when the pass began (so the numbers never climb in steps while catching up). Not
/// thread-safe: `ClaudeTurnTokenFollower` confines it to one serial queue (hence `@unchecked`).
///
/// Reads only inside `~/.claude/projects` (the real path, symlinks resolved, and the file opened
/// with `O_NOFOLLOW`), only regular files, and only token counts — never content.
final class ClaudeTurnTokenReader: @unchecked Sendable {
    struct Pass: Equatable {
        var tokens: [String: TurnTokens] = [:]
        /// Some chat is not caught up yet; run another pass soon.
        var behind = false
    }

    static let subagentFileLimit = 256

    let projectsRoot: String
    var passBudget = 16 << 20
    var idleEviction: TimeInterval = 30
    private var entries: [String: (accumulator: ClaudeTranscriptTokenAccumulator, lastUsed: Date)] = [:]

    init(projectsRoot: String) {
        self.projectsRoot = projectsRoot
    }

    func reset() { entries.removeAll() }

    func pass(_ requests: [ClaudeTurnTokenRequest], now: Date) -> Pass {
        var result = Pass()
        var budget = passBudget
        guard let realRoot = Self.realPath(projectsRoot) else { return result }
        for request in requests {
            let subagents = Self.subagentTranscripts(under: request.subagentDirectory, modifiedSince: request.windowStart)
            guard !subagents.truncated else { continue }   // hide rather than undercount
            var total = TurnTokens(startedAt: request.startedAt, startOffset: request.startOffset, newInput: 0, output: 0)
            var complete = true
            var available = true
            for (path, startOffset) in [(request.mainPath, request.startOffset)] + subagents.paths.map({ ($0, Int64(0)) }) {
                let key = "\(request.conversationID)|\(Int64(request.startedAt.timeIntervalSince1970 * 1000))|\(startOffset)|\(path)"
                var accumulator = entries[key]?.accumulator
                    ?? ClaudeTranscriptTokenAccumulator(startOffset: startOffset, windowStart: request.windowStart)
                switch Self.follow(path, realRoot: realRoot, accumulator: &accumulator, budget: &budget) {
                case .caughtUp: break
                case .behind: complete = false
                case .unavailable: available = false
                }
                entries[key] = (accumulator, now)
                total.newInput += accumulator.newInput
                total.cacheRead += accumulator.cacheRead
                total.output += accumulator.output
                if path == request.mainPath {
                    // The chat's context is its own latest call's; a subagent has a context of its own.
                    total.context = accumulator.context
                }
            }
            if !complete { result.behind = true }
            if complete && available { result.tokens[request.conversationID] = total }
        }
        entries = entries.filter { now.timeIntervalSince($0.value.lastUsed) <= idleEviction }
        return result
    }

    private enum FileOutcome { case caughtUp, behind, unavailable }

    private static func follow(_ path: String, realRoot: String,
                               accumulator: inout ClaudeTranscriptTokenAccumulator, budget: inout Int) -> FileOutcome {
        guard isInside(path, realRoot: realRoot) else { return .unavailable }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return .unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return .unavailable }
        let size = Int64(info.st_size)
        let id = UInt64(info.st_ino)
        while true {
            switch accumulator.step(size: size, fileID: id) {
            case .upToDate:
                return .caughtUp
            case let .read(offset, count):
                guard budget > 0 else { return .behind }
                let length = min(count, budget)
                var chunk = Data(count: length)
                let got = chunk.withUnsafeMutableBytes { pread(fd, $0.baseAddress, length, off_t(offset)) }
                guard got > 0 else { return .unavailable }
                if got < length { chunk.removeSubrange(got...) }
                accumulator.consume(chunk)
                budget -= got
            }
        }
    }

    /// Subagent transcripts (`agent-*.jsonl`, regular files, never through a symlink, at most
    /// three levels down) written since the turn began. `truncated` when there are more than the
    /// limit — then no total is shown rather than a short one.
    static func subagentTranscripts(under directory: String, modifiedSince: Date) -> (paths: [String], truncated: Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory, isDirectory: true),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ([], false) }
        var paths: [String] = []
        for case let url as URL in enumerator {
            if enumerator.level > 3 {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                  values.isRegularFile == true, url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("agent-"),
                  (values.contentModificationDate ?? .distantPast) >= modifiedSince else { continue }
            paths.append(url.path)
            if paths.count > subagentFileLimit { return ([], true) }
        }
        return (paths.sorted(), false)
    }

    /// True when the file's real path (symlinks resolved) lies inside `realRoot`.
    static func isInside(_ path: String, realRoot: String) -> Bool {
        guard let real = realPath(path) else { return false }
        return real.hasPrefix(realRoot + "/")
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
