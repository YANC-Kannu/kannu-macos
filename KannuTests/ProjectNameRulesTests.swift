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

import XCTest

/// How a chat's project is named from where it runs (`ProjectNameRules`). A Claude Desktop chat in
/// a worktree runs in `<repo>/.claude/worktrees/<random>`, and its card used to say `<random>`.
final class ProjectNameRulesTests: XCTestCase {

    // MARK: - Working directories

    func testAPlainRepositoryIsNamedAfterItsFolder() {
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api"), "acme-api")
        XCTAssertEqual(
            ProjectNameRules.resolution(forWorkingDirectory: "/Users/alice/code/acme-api")?.rule,
            .folderName
        )
    }

    func testAClaudeDesktopWorktreeIsNamedAfterItsRepository() {
        let path = "/Users/alice/code/acme-api/.claude/worktrees/brave-otter-7f3a"
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: path), "acme-api")
        XCTAssertEqual(ProjectNameRules.resolution(forWorkingDirectory: path)?.rule, .claudeDesktopWorktree)
    }

    func testAFolderInsideAWorktreeIsNamedAfterTheRepository() {
        XCTAssertEqual(
            ProjectNameRules.projectName(
                forWorkingDirectory: "/Users/alice/code/acme-api/.claude/worktrees/brave-otter-7f3a/Sources/App"
            ),
            "acme-api"
        )
    }

    func testATrailingSlashOrAFileURLChangesNothing() {
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/"), "acme-api")
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api///"), "acme-api")
        XCTAssertEqual(
            ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/.claude/worktrees/brave-otter-7f3a/"),
            "acme-api"
        )
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "file:///Users/alice/code/acme-api"), "acme-api")
    }

    func testAFileURLIsDecodedBeforeItIsNamed() {
        // `file:///Users/alice/code/acme%20api` is the folder `/Users/alice/code/acme api`.
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "file:///Users/alice/code/acme%20api"), "acme api")
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "file:///Users/alice/code/acme%20api/"), "acme api")
        XCTAssertEqual(
            ProjectNameRules.projectName(
                forWorkingDirectory: "file:///Users/alice/code/acme%20api/.claude/worktrees/brave-otter-7f3a"
            ),
            "acme api"
        )
        // An ordinary path keeps a literal percent sign.
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme%20api"), "acme%20api")
    }

    func testTheRootAndAnEmptyPathHaveNoName() {
        XCTAssertNil(ProjectNameRules.projectName(forWorkingDirectory: "/"))
        XCTAssertNil(ProjectNameRules.projectName(forWorkingDirectory: "///"))
        XCTAssertNil(ProjectNameRules.projectName(forWorkingDirectory: ""))
        XCTAssertNil(ProjectNameRules.projectName(forWorkingDirectory: "   "))
    }

    func testEveryOtherClaudeFolderIsAnOrdinaryFolder() {
        // `~/.claude` and a repository's own `.claude` folder.
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/.claude"), ".claude")
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/.claude"), ".claude")
        // `.claude/worktrees` itself is not inside a worktree.
        XCTAssertEqual(
            ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/.claude/worktrees"),
            "worktrees"
        )
        // Another folder under `.claude`.
        XCTAssertEqual(
            ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/.claude/skills/review"),
            "review"
        )
        XCTAssertEqual(
            ProjectNameRules.resolution(forWorkingDirectory: "/Users/alice/code/acme-api/.claude/skills/review")?.rule,
            .folderName
        )
        // A folder merely called `worktrees`, outside `.claude`.
        XCTAssertEqual(
            ProjectNameRules.projectName(forWorkingDirectory: "/Users/alice/code/acme-api/worktrees/feature"),
            "feature"
        )
        // `.claude/worktrees/<name>` at the root has no repository above it: the folder name stays.
        XCTAssertEqual(ProjectNameRules.projectName(forWorkingDirectory: "/.claude/worktrees/brave-otter-7f3a"), "brave-otter-7f3a")
    }

    func testTheFirstWorktreeOnThePathNamesTheProject() {
        XCTAssertEqual(
            ProjectNameRules.projectName(
                forWorkingDirectory: "/Users/alice/code/acme-api/.claude/worktrees/one/.claude/worktrees/two"
            ),
            "acme-api"
        )
    }

    // MARK: - Cursor project slugs

    /// A made-up folder tree, listed the way `FileManager.contentsOfDirectory` would.
    private static let tree: [String: [String]] = [
        "/": ["Users", "Volumes"],
        "/Users": ["alice"],
        "/Users/alice": ["code", "Documents", "acme-web"],
        "/Users/alice/code": ["acme", "acme-api", "proj_123", "acme-site"],
        "/Users/alice/code/acme-api": [".claude", "Sources"],
        "/Users/alice/code/acme-api/.claude": ["worktrees"],
        "/Users/alice/code/acme-api/.claude/worktrees": ["brave-otter-7f3a"],
        "/Users/alice/code/acme": ["site-docs"],
        "/Users/alice/code/acme-site": [],
        "/Users/alice/acme-web": [],
    ]

    private func cursorName(_ slug: String, home: String = "/Users/alice",
                            tree: [String: [String]] = ProjectNameRulesTests.tree) -> ProjectNameRules.Resolution? {
        ProjectNameRules.cursorProjectName(fromSlug: slug, homeDirectory: home, contentsOfDirectory: { tree[$0] })
    }

    func testAHyphenatedCursorProjectKeepsItsWholeName() {
        // The old decoder split the slug on "-" and kept the last word: "api".
        XCTAssertEqual(cursorName("Users-alice-code-acme-api"),
                       ProjectNameRules.Resolution(name: "acme-api", rule: .cursorSlugFolder))
        XCTAssertEqual(cursorName("Users-alice-acme-web")?.name, "acme-web")
        XCTAssertEqual(cursorName("Users-alice-code-acme")?.name, "acme")
    }

    func testACursorSlugDecodesDotsAndUnderscoresToTheRealFolder() {
        XCTAssertEqual(cursorName("Users-alice-code-proj-123")?.name, "proj_123")
        XCTAssertEqual(cursorName("Users-alice-code-acme-api--claude-worktrees-brave-otter-7f3a"),
                       ProjectNameRules.Resolution(name: "acme-api", rule: .claudeDesktopWorktree))
    }

    func testACursorSlugBacktracksOutOfAFolderThatLeadsNowhere() {
        // "acme-site" is the longest folder that fits, and is tried first, but it has no "docs";
        // "acme/site-docs" is the folder that exists.
        XCTAssertEqual(cursorName("Users-alice-code-acme-site-docs")?.name, "site-docs")
    }

    func testAnUndecodableCursorSlugFallsBackToTheOldGuess() {
        // A folder Kannu may not list (the closure returns nil), or one that no longer exists.
        XCTAssertEqual(cursorName("Users-alice-Documents-acme"),
                       ProjectNameRules.Resolution(name: "acme", rule: .cursorSlugGuess))
        XCTAssertEqual(cursorName("Users-alice-code-gone-project")?.name, "project")
        XCTAssertEqual(cursorName("empty-window")?.name, "empty-window")
    }

    func testAWholeSlugFallbackIsMarkedUnresolved() {
        // Not under the home folder and not decodable: the whole slug is the name. It spells out a
        // folder path, so its rule tells the log to keep the name private.
        XCTAssertEqual(cursorName("Volumes-Backup-acme-api"),
                       ProjectNameRules.Resolution(name: "Volumes-Backup-acme-api", rule: .cursorSlugUnresolved))
        XCTAssertEqual(cursorName("empty-window")?.rule, .cursorSlugUnresolved)
    }

    func testACursorHomeWithADotOrUnderscoreStillMatchesItsSlug() {
        // Cursor writes `/Users/alice.smith` as `Users-alice-smith`. The old decoder encoded only
        // the slashes, so the home never matched and the card showed the whole slug.
        XCTAssertEqual(cursorName("Users-alice-smith-acme", home: "/Users/alice.smith", tree: [:]),
                       ProjectNameRules.Resolution(name: "acme", rule: .cursorSlugGuess))
        XCTAssertEqual(cursorName("Users-alice-smith-acme", home: "/Users/alice_smith", tree: [:])?.name, "acme")
        XCTAssertEqual(cursorName("Users-alice-smith", home: "/Users/alice.smith", tree: [:])?.name, "alice.smith")
    }

    func testScratchCursorProjectsHaveNoName() {
        XCTAssertNil(cursorName("var-folders-xy-abc123-T-0858023b"))
        XCTAssertNil(cursorName("1776979051047"))
        XCTAssertNil(cursorName(""))
        XCTAssertNil(ProjectNameRules.cursorProjectName(fromSlug: nil, homeDirectory: "/Users/alice",
                                                        contentsOfDirectory: { _ in nil }))
    }

    func testTheCursorSlugOfAPathMatchesCursorsEncoding() {
        XCTAssertEqual(ProjectNameRules.cursorSlug(forPath: "/Users/alice/code/acme-api"), "Users-alice-code-acme-api")
        XCTAssertEqual(ProjectNameRules.cursorSlug(forPath: "/Users/alice.smith/"), "Users-alice-smith")
        XCTAssertEqual(ProjectNameRules.cursorSlug(forPath: "/"), "")
    }

    func testACursorSlugDecodeListsABoundedNumberOfFolders() {
        // Every folder offers the same two names, so a slug that never ends in a real folder would
        // otherwise explore every combination.
        var listings = 0
        let result = ProjectNameRules.cursorProjectName(
            fromSlug: String(repeating: "a-", count: 40) + "zzz",
            homeDirectory: "/Users/alice",
            contentsOfDirectory: { _ in listings += 1; return ["a", "a-a"] }
        )
        XCTAssertEqual(result?.rule, .cursorSlugUnresolved)
        XCTAssertLessThanOrEqual(listings, 48)
    }

    // MARK: - Folders a slug decode may read

    /// A scratch folder tree on disk: `code/acme/api` (a folder), `code/acme-api` (a file),
    /// `code/acme-web` (a symbolic link to `elsewhere/acme-web`), `Documents/acme` and `Documents-old/acme`.
    private func makeDiskTree() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectNameRulesTests-\(UUID().uuidString)").path
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/code/acme/api", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/elsewhere/acme-web", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Documents/acme", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/Documents-old/acme", withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: root + "/code/acme-api", contents: Data("not a folder".utf8)))
        try fm.createSymbolicLink(atPath: root + "/code/acme-web", withDestinationPath: root + "/elsewhere/acme-web")
        addTeardownBlock { try? fm.removeItem(atPath: root) }
        return root
    }

    func testASlugDecodeReadsOnlyRealFolders() throws {
        let root = try makeDiskTree()
        // The file and the symbolic link are left out: neither can be followed into.
        XCTAssertEqual(ProjectNameRules.slugDecodableFolders(in: root + "/code", homeDirectory: root), ["acme"])
    }

    func testASlugDecodeNeverChoosesAFileOverTheFolderItNames() throws {
        // `code/acme-api` (a file) and `code/acme/api` (the project) share the slug `code-acme-api`.
        // Longest-first would pick the file if the listing offered it.
        let root = try makeDiskTree()
        let result = ProjectNameRules.cursorProjectName(
            fromSlug: "code-acme-api",
            homeDirectory: "/Users/alice",
            contentsOfDirectory: { path in
                ProjectNameRules.slugDecodableFolders(in: path == "/" ? root : root + path, homeDirectory: root)
            }
        )
        XCTAssertEqual(result, ProjectNameRules.Resolution(name: "api", rule: .cursorSlugFolder))
    }

    func testASlugDecodeNeverReadsAPromptingFolderOrAnotherDisk() throws {
        let root = try makeDiskTree()
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: root + "/Documents", homeDirectory: root))
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: root + "/Documents/acme", homeDirectory: root))
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: root + "/Documents", homeDirectory: root + "/"))
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: "/Volumes", homeDirectory: root))
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: "/Volumes/Backup", homeDirectory: root))
        XCTAssertNil(ProjectNameRules.slugDecodableFolders(in: root + "/missing", homeDirectory: root))
        // A folder whose name merely starts with a prompting folder's name is ordinary.
        XCTAssertEqual(ProjectNameRules.slugDecodableFolders(in: root + "/Documents-old", homeDirectory: root), ["acme"])
    }
}
