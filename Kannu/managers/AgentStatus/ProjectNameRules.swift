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

/// Which rule named a chat's project. The raw value is what the `ProjectName` log prints.
enum ProjectNameRule: String {
    /// The last component of the working directory.
    case folderName = "folder-name"
    /// `<repo>/.claude/worktrees/<name>[/…]`, a Claude Desktop worktree, named after `<repo>`.
    case claudeDesktopWorktree = "claude-desktop-worktree"
    /// No working directory on the hook file; the name the hook script wrote is kept.
    case hookProjectField = "hook-project-field"
    /// A Cursor project slug decoded back into a folder that exists.
    case cursorSlugFolder = "cursor-slug-folder"
    /// A Cursor project slug that could not be decoded: the old best guess (its last word).
    case cursorSlugGuess = "cursor-slug-guess"
    /// A Cursor project slug that could not be decoded and is not under the home folder: the whole
    /// slug is the name. It spells out the folder path, so the log keeps it private.
    case cursorSlugUnresolved = "cursor-slug-unresolved"
    /// Nothing to name the project from.
    case none = "none"
}

/// How Kannu names a chat's project from where the chat runs. Foundation-only, so the logic test
/// target compiles it (`ProjectNameRulesTests`); every resolution point in the monitor and the
/// transcript parsers goes through it, so one rule cannot differ between sources.
enum ProjectNameRules {

    struct Resolution: Equatable {
        let name: String
        let rule: ProjectNameRule
    }

    /// The project a chat in `path` belongs to: the folder name, except inside a Claude Desktop
    /// worktree (`<repo>/.claude/worktrees/<name>` and anything below it), which is `<repo>`.
    /// Desktop gives each worktree a random name, which is not the project the user knows.
    static func projectName(forWorkingDirectory path: String) -> String? {
        resolution(forWorkingDirectory: path)?.name
    }

    static func resolution(forWorkingDirectory path: String) -> Resolution? {
        let components = pathComponents(path)
        // The first `.claude/worktrees/<name>` wins: the folder above it is the repository the
        // worktree was cut from. `.claude/worktrees` itself, and every other `.claude` folder
        // (`~/.claude`, `<repo>/.claude/skills`), are ordinary folders.
        if let index = components.indices.first(where: { index in
            index > 0
                && index + 2 < components.count
                && components[index] == ".claude"
                && components[index + 1] == "worktrees"
        }) {
            return Resolution(name: components[index - 1], rule: .claudeDesktopWorktree)
        }
        guard let last = components.last else { return nil }
        return Resolution(name: last, rule: .folderName)
    }

    /// Non-empty components of a path or `file://` URL, with no root and no trailing slash.
    private static func pathComponents(_ path: String) -> [String] {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") {
            // A file URL escapes its path (`acme%20api`); the folder is `acme api`.
            if let url = URL(string: trimmed), url.isFileURL {
                trimmed = url.path
            } else {
                let stripped = String(trimmed.dropFirst("file://".count))
                trimmed = stripped.removingPercentEncoding ?? stripped
            }
        }
        return trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Cursor project slugs

    /// Cursor names a project's folder under `~/.cursor/projects/` after the project's path, with
    /// the leading slash dropped and every character that is not an ASCII letter or digit written
    /// as `-`: `/Users/alice/code/acme-api` is `Users-alice-code-acme-api`. The mapping loses
    /// information (`code/acme-api`, `code-acme/api` and `code.acme/api` share a slug), so the slug
    /// is decoded against the folders that exist: `contentsOfDirectory` lists one folder, or
    /// returns nil for a folder that must not be read. Without a match, the old guess remains:
    /// the slug's last word after the home folder.
    static func cursorProjectName(
        fromSlug slug: String?,
        homeDirectory: String,
        contentsOfDirectory: (String) -> [String]?
    ) -> Resolution? {
        guard let slug else { return nil }
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Temporary folders and Cursor's numeric scratch projects are never a project.
        if trimmed.hasPrefix("var-") { return nil }
        if trimmed.allSatisfy(\.isNumber) { return nil }

        var budget = maxSlugListings
        if let path = decode(slug: trimmed, in: "/", contentsOfDirectory: contentsOfDirectory, budget: &budget),
           let resolved = resolution(forWorkingDirectory: path) {
            return Resolution(
                name: resolved.name,
                rule: resolved.rule == .claudeDesktopWorktree ? .claudeDesktopWorktree : .cursorSlugFolder
            )
        }

        // The home folder goes through the same encoding as the slug: a home with a dot or an
        // underscore in it (`/Users/alice.smith`) is `Users-alice-smith` in the slug.
        let homeSlug = cursorSlug(forPath: homeDirectory)
        if !homeSlug.isEmpty {
            if trimmed == homeSlug, let home = projectName(forWorkingDirectory: homeDirectory) {
                return Resolution(name: home, rule: .cursorSlugGuess)
            }
            if trimmed.hasPrefix(homeSlug + "-") {
                let suffix = trimmed.dropFirst(homeSlug.count + 1)
                if let last = suffix.split(separator: "-", omittingEmptySubsequences: true).last {
                    return Resolution(name: String(last), rule: .cursorSlugGuess)
                }
            }
        }
        return Resolution(name: trimmed, rule: .cursorSlugUnresolved)
    }

    /// The slug Cursor would give `path`.
    static func cursorSlug(forPath path: String) -> String {
        let components = pathComponents(path)
        guard !components.isEmpty else { return "" }
        return encodedComponent(components.joined(separator: "/"))
    }

    /// A slug decode lists at most this many folders, so a deep or pathological slug stays cheap.
    private static let maxSlugListings = 48

    private static func decode(
        slug: String,
        in directory: String,
        contentsOfDirectory: (String) -> [String]?,
        budget: inout Int
    ) -> String? {
        guard budget > 0 else { return nil }
        budget -= 1
        guard let entries = contentsOfDirectory(directory) else { return nil }
        // Longest first: `acme-api` beats `acme` when both exist and both fit the slug.
        let candidates = entries
            .map { (entry: $0, encoded: encodedComponent($0)) }
            .filter { !$0.encoded.isEmpty && (slug == $0.encoded || slug.hasPrefix($0.encoded + "-")) }
            .sorted { $0.encoded.count > $1.encoded.count }
        for candidate in candidates {
            let path = directory == "/" ? "/" + candidate.entry : directory + "/" + candidate.entry
            if slug == candidate.encoded { return path }
            let rest = String(slug.dropFirst(candidate.encoded.count + 1))
            if let found = decode(slug: rest, in: path, contentsOfDirectory: contentsOfDirectory, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func encodedComponent(_ name: String) -> String {
        String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// Home folders whose first read raises a macOS privacy prompt. Kannu must not raise a
    /// permission dialog to name a card (AGENTS.md, "No permission dialog before onboarding's
    /// Permissions step"), so a slug under one of them falls back to the guess.
    static let promptingHomeFolders = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures"]

    /// The folders in `directory` a slug decode may descend into, or nil for a directory it must
    /// not read: `/Volumes` (another disk) and the prompting home folders. Only real folders are
    /// returned. A file cannot be a project folder, and a symbolic link is never followed, because
    /// its target can be a prompting folder that no path check here would see.
    static func slugDecodableFolders(in directory: String, homeDirectory home: String,
                                     fileManager: FileManager = .default) -> [String]? {
        if directory == "/Volumes" || directory.hasPrefix("/Volumes/") { return nil }
        let homePath = home.hasSuffix("/") ? String(home.dropLast()) : home
        for folder in promptingHomeFolders {
            let protected = homePath + "/" + folder
            if directory == protected || directory.hasPrefix(protected + "/") { return nil }
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: directory, isDirectory: true),
            includingPropertiesForKeys: keys
        ) else { return nil }
        return entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return entry.lastPathComponent
        }
    }
}

/// The `ProjectName` log: one line each time a chat's project name, or what it was named from,
/// changes. `log stream --predicate 'subsystem == "com.kannu.app" AND category == "ProjectName"'`.
///
/// Privacy: the working directory and workspace roots are full paths, which carry the user's
/// account name and folder layout, so they are `.private`. Public: the agent, the source and the
/// rule (fixed vocabularies), the session id (an id the agent generated, not user content, and the only way to
/// match a line to a card), and the chosen name, which is one folder name the notch already shows
/// on screen, and without which the log could not show that a label matches its folder. The one
/// exception is `cursor-slug-unresolved`, whose name is a whole slug, a folder path with dashes
/// for slashes: it is private like the paths.
enum ProjectNameLog {
    private static let logger = os.Logger(subsystem: "com.kannu.app", category: "ProjectName")
    private static let lock = NSLock()
    private static var lastLineBySession: [String: String] = [:]
    private static let maxRemembered = 512

    /// Where a resolution point read the working directory from.
    enum Source: String {
        case hookFile = "hook-file"
        case claudeSessionRecord = "claude-session-record"
        case transcript = "transcript"
    }

    static func record(
        agent: String,
        source: Source,
        sessionID: String,
        cwd: String?,
        workspaceRoots: [String]? = nil,
        resolution: ProjectNameRules.Resolution?
    ) {
        let name = resolution?.name ?? "-"
        let rule = (resolution?.rule ?? .none).rawValue
        let roots = workspaceRoots.map { $0.joined(separator: ", ") } ?? "-"
        let cwdText = cwd ?? "-"
        // Every scan re-reads every source; log only what changed, so the stream reads as events.
        let key = source.rawValue + "|" + agent + "|" + sessionID
        let line = [cwdText, roots, name, rule].joined(separator: "\u{1F}")
        lock.lock()
        let changed = lastLineBySession[key] != line
        if changed {
            if lastLineBySession.count >= maxRemembered { lastLineBySession.removeAll() }
            lastLineBySession[key] = line
        }
        lock.unlock()
        guard changed else { return }
        if resolution?.rule == .cursorSlugUnresolved {
            logger.notice(
                "agent=\(agent, privacy: .public) source=\(source.rawValue, privacy: .public) session=\(sessionID, privacy: .public) name=\(name, privacy: .private) rule=\(rule, privacy: .public) cwd=\(cwdText, privacy: .private) workspace_roots=\(roots, privacy: .private)"
            )
            return
        }
        logger.notice(
            "agent=\(agent, privacy: .public) source=\(source.rawValue, privacy: .public) session=\(sessionID, privacy: .public) name=\(name, privacy: .public) rule=\(rule, privacy: .public) cwd=\(cwdText, privacy: .private) workspace_roots=\(roots, privacy: .private)"
        )
    }
}
