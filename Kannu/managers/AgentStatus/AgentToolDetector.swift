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

/// Which agent tools have run on this Mac: the one answer the notch's empty state and Brain's Agents page share.
/// `AgentHookLayout.toolIsPresent` says yes for Cursor, VS Code, Codex, Claude and Antigravity whatever is installed,
/// so it cannot say which tool to offer a hook for; this can.
///
/// File checks and Launch Services only. Never Warp's container: statting it raises macOS's "access data from other
/// apps" dialog, which belongs to onboarding's Permissions step. A view calls `detect()` once per visit, from
/// `onAppear`, never from its `body`.
enum AgentToolDetector {
    struct Tool: Identifiable, Equatable {
        /// As a session names its provider, so `AgentProviderIconSource(rawProvider:)` draws its icon.
        let provider: String
        let name: String
        /// Where the notch has little room.
        let shortName: String
        /// The hook that gives it richer status, if it has one.
        let hook: AgentHookProvider?
        let detected: Bool

        var id: String { provider }
    }

    static func detect(fileManager: FileManager = .default) -> [Tool] {
        let home = fileManager.homeDirectoryForCurrentUser
        func exists(_ path: String) -> Bool { fileManager.fileExists(atPath: home.appendingPathComponent(path).path) }
        return [
            Tool(provider: "cursor", name: "Cursor", shortName: "Cursor", hook: .cursor,
                 detected: exists("Library/Application Support/Cursor/User/globalStorage/state.vscdb")),
            Tool(provider: "claude", name: "Claude Code", shortName: "Claude Code", hook: .claude, detected: exists(".claude/projects")),
            Tool(provider: "codex", name: "Codex", shortName: "Codex", hook: .codex, detected: exists(".codex/sessions")),
            Tool(provider: "antigravity", name: "Antigravity", shortName: "Antigravity", hook: .antigravity, detected: exists(".gemini")),
            Tool(provider: "warp", name: "Warp", shortName: "Warp", hook: nil,
                 detected: LaunchPermissionManager.isWarpInstalled),
            Tool(provider: "claudedesktop", name: "Claude Desktop", shortName: "Desktop", hook: nil,
                 detected: fileManager.fileExists(atPath: ClaudeDesktopAgentSessionStore.defaultRoot.path)),
        ]
    }

    /// The tools on this Mac whose hook is not installed, in the order above: what an install button may offer.
    static func hookOffers(in tools: [Tool], installed: (AgentHookProvider) -> Bool) -> [Tool] {
        tools.filter { tool in
            guard tool.detected, let hook = tool.hook else { return false }
            return !installed(hook)
        }
    }
}
