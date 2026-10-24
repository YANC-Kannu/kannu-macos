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

import Security
import XCTest

/// Where Kannu looks for a native `codex` binary, and which file it will run. The paths follow the
/// standalone installer (`chatgpt.com/codex/install.sh`: `$HOME/.local/bin`), Homebrew's prefixes,
/// and npm's `codex-cli/bin/codex.js` (current and `rust-v0.120.0`). Built in temp folders; no
/// real Codex install was available.
final class CodexBinaryLocatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexBinaryLocatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A file whose first bytes are MH_MAGIC_64: what the locator takes for a native binary.
    @discardableResult
    private func machO(at url: URL, executable: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    private func script(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/usr/bin/env node\nconsole.log('shim')\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func real(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    // MARK: - The invocation

    func testTheInvocationIsTheBareDocumentedOne() {
        XCTAssertEqual(CodexBinaryLocator.appServerArguments, ["app-server"])
    }

    func testTheSignatureMustBeDeveloperIDForCodex() {
        let requirement = CodexBinaryLocator.signingRequirement
        XCTAssertTrue(requirement.contains(#"identifier "codex""#))
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("certificate 1[field.1.2.840.113635.100.6.2.6] exists"), "Developer ID intermediate")
        XCTAssertTrue(requirement.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"), "Developer ID Application leaf")
    }

    /// A requirement that does not compile makes every binary untrusted, which silently sends
    /// every foreground refresh to wham/usage and its read of Codex's token.
    func testTheSignatureRequirementCompiles() {
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(CodexBinaryLocator.signingRequirement as CFString, [], &requirement),
                       errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testAnApplePlatformBinaryDoesNotPassTheRequirement() throws {
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(URL(fileURLWithPath: "/bin/ls") as CFURL, [], &code), errSecSuccess)
        let ls = try XCTUnwrap(code)
        XCTAssertEqual(SecStaticCodeCheckValidity(ls, [], nil), errSecSuccess, "the signature itself is valid")
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(CodexBinaryLocator.signingRequirement as CFString, [], &requirement),
                       errSecSuccess)
        XCTAssertNotEqual(SecStaticCodeCheckValidity(ls, [], requirement), errSecSuccess,
                          "Apple's ls is neither Developer ID-signed nor identified as codex")
    }

    // MARK: - The verdict cache's key

    func testTheFileIdentityHoldsWhileTheFileIsUntouched() throws {
        let file = try machO(at: directory.appendingPathComponent("codex"))
        XCTAssertNotNil(CodexBinaryLocator.FileIdentity(path: file.path))
        XCTAssertEqual(CodexBinaryLocator.FileIdentity(path: file.path), CodexBinaryLocator.FileIdentity(path: file.path))
        XCTAssertNil(CodexBinaryLocator.FileIdentity(path: directory.appendingPathComponent("missing").path))
    }

    func testAnOverwriteKeepingSizeAndDateChangesTheIdentity() throws {
        let file = try machO(at: directory.appendingPathComponent("codex"))
        let modified = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        let before = try XCTUnwrap(CodexBinaryLocator.FileIdentity(path: file.path))
        // Lets the clock move past the first write's change time on any file system.
        Thread.sleep(forTimeInterval: 0.02)
        // Same size, written in place, date put back: what the old size-and-date key could not see.
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x02]))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        let after = try XCTUnwrap(CodexBinaryLocator.FileIdentity(path: file.path))
        XCTAssertEqual(after.size, before.size)
        XCTAssertEqual(after.inode, before.inode, "the same file, written in place")
        XCTAssertNotEqual(after, before, "the change time moved and cannot be set back")
    }

    func testAReplacementFileChangesTheIdentity() throws {
        let file = try machO(at: directory.appendingPathComponent("codex"))
        let before = try XCTUnwrap(CodexBinaryLocator.FileIdentity(path: file.path))
        let other = try machO(at: directory.appendingPathComponent("payload"))
        _ = try FileManager.default.replaceItemAt(file, withItemAt: other)
        let after = try XCTUnwrap(CodexBinaryLocator.FileIdentity(path: file.path))
        XCTAssertNotEqual(after.inode, before.inode)
        XCTAssertNotEqual(after, before)
    }

    // MARK: - Candidates

    func testCandidatesPreferTheStandaloneInstallThenHomebrewThenNpm() {
        let home = URL(fileURLWithPath: "/Users/dev", isDirectory: true)
        let root = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules", isDirectory: true)
        let paths = CodexBinaryLocator.candidates(home: home, nodeModulesRoots: [root],
                                                  triple: "aarch64-apple-darwin", npmArch: "arm64").map(\.path)
        XCTAssertEqual(paths, [
            "/Users/dev/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex",
        ])
    }

    func testIntelUsesTheX64Package() {
        let paths = CodexBinaryLocator.candidates(home: directory, binDirectories: [],
                                                  nodeModulesRoots: [directory], triple: "x86_64-apple-darwin", npmArch: "x64")
        XCTAssertEqual(paths.first?.path,
                       directory.appendingPathComponent("@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex").path)
    }

    func testNodeModulesRootsIncludeEveryNvmNodeNewestFirst() throws {
        for version in ["v18.20.4", "v22.11.0", "v9.0.0"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(".nvm/versions/node/\(version)/lib/node_modules"),
                                                    withIntermediateDirectories: true)
        }
        let roots = CodexBinaryLocator.nodeModulesRoots(home: directory).map(\.path)
        XCTAssertEqual(Array(roots.prefix(3)), ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules",
                                                directory.appendingPathComponent(".npm-global/lib/node_modules").path])
        XCTAssertEqual(Array(roots.dropFirst(3)), ["v22.11.0", "v18.20.4", "v9.0.0"].map {
            directory.appendingPathComponent(".nvm/versions/node/\($0)/lib/node_modules").path
        })
    }

    // MARK: - Resolving

    func testTheNodeShimIsNeverRunAndItsVendorBinaryIs() throws {
        let root = directory.appendingPathComponent("lib/node_modules", isDirectory: true)
        let shim = try script(at: root.appendingPathComponent("@openai/codex/bin/codex.js"))
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("codex"), withDestinationURL: shim)
        let vendor = try machO(at: root.appendingPathComponent("@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"))

        var offered: [String] = []
        let resolved = CodexBinaryLocator.resolve(
            CodexBinaryLocator.candidates(home: directory, binDirectories: [bin], nodeModulesRoots: [root],
                                          triple: "aarch64-apple-darwin", npmArch: "arm64")) { url in
            offered.append(url.path)
            return true
        }
        XCTAssertEqual(resolved?.path, real(vendor))
        XCTAssertEqual(offered, [real(vendor)], "the shim is not even offered for a signature check")
    }

    func testASymlinkResolvesToTheFileThatIsCheckedAndRun() throws {
        let release = try machO(at: directory.appendingPathComponent(".codex/packages/standalone/releases/0.150.0/bin/codex"))
        let bin = directory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("codex"), withDestinationURL: release)
        let other = directory.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("codex"), withDestinationURL: release)

        var offered: [String] = []
        let resolved = CodexBinaryLocator.resolve([bin.appendingPathComponent("codex"), other.appendingPathComponent("codex")]) { url in
            offered.append(url.path)
            return false
        }
        XCTAssertNil(resolved)
        XCTAssertEqual(offered, [real(release)], "two links to one file: one check")
    }

    func testAnUntrustedBinaryIsSkippedForTheNextOne() throws {
        let first = try machO(at: directory.appendingPathComponent("a/codex"))
        let second = try machO(at: directory.appendingPathComponent("b/codex"))
        let resolved = CodexBinaryLocator.resolve([first, second]) { $0.path == self.real(second) }
        XCTAssertEqual(resolved?.path, real(second))
    }

    func testMissingNonExecutableAndDirectoryCandidatesAreSkipped() throws {
        let missing = directory.appendingPathComponent("missing/codex")
        let notExecutable = try machO(at: directory.appendingPathComponent("plain/codex"), executable: false)
        let folder = directory.appendingPathComponent("folder/codex", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let good = try machO(at: directory.appendingPathComponent("good/codex"))
        var offered: [String] = []
        let resolved = CodexBinaryLocator.resolve([missing, notExecutable, folder, good]) { url in
            offered.append(url.path)
            return true
        }
        XCTAssertEqual(resolved?.path, real(good))
        XCTAssertEqual(offered, [real(good)])
    }

    func testMachOMagicIsRecognisedAndAScriptIsNot() throws {
        XCTAssertTrue(CodexBinaryLocator.isMachO(try machO(at: directory.appendingPathComponent("thin"))))
        let fat = directory.appendingPathComponent("fat")
        try Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02]).write(to: fat)
        XCTAssertTrue(CodexBinaryLocator.isMachO(fat))
        XCTAssertFalse(CodexBinaryLocator.isMachO(try script(at: directory.appendingPathComponent("shim"))))
        let short = directory.appendingPathComponent("short")
        try Data([0xCF, 0xFA]).write(to: short)
        XCTAssertFalse(CodexBinaryLocator.isMachO(short))
    }

    func testTheRealSystemBinaryIsAMachOFile() {
        // A real Mach-O on every Mac, so the magic check is not only proven against hand-made bytes.
        XCTAssertTrue(CodexBinaryLocator.isMachO(URL(fileURLWithPath: "/bin/ls")))
    }
}
