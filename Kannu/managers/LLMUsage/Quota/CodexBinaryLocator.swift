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

/// Finds a native `codex` binary to run `codex app-server` with. Never a Node shim: the npm
/// package's `bin/codex.js` is skipped, and the native binary it would have launched is found in
/// the package's vendor folder instead.
///
/// Where each install method puts it (none of them checked on a real install; Codex is not
/// installed on the development Mac):
/// - the standalone installer (`chatgpt.com/codex/install.sh`): `$CODEX_INSTALL_DIR`, default
///   `~/.local/bin/codex`, a symlink into `~/.codex/packages/standalone/releases/<version>/`;
/// - Homebrew: `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`, a symlink to the cask's release
///   binary, or to the npm shim when npm itself came from Homebrew;
/// - npm (`@openai/codex`): `<global node_modules>/@openai/codex-darwin-<arch>/vendor/<triple>/bin/codex`
///   (current `codex-cli/bin/codex.js`), the same package nested under `@openai/codex/node_modules`,
///   or `@openai/codex/vendor/<triple>/codex/codex` (releases up to at least 0.120).
///
/// Foundation-only, so the KannuTests target compiles it. The signature check that decides which
/// candidate may run needs the Security framework and lives in `CodexAppServerClient`.
enum CodexBinaryLocator {
    /// Exactly the documented invocation (`codex app-server`, stdio by default). The root CLI's
    /// `-s` and `-a` exist, but `codex-rs/cli/src/main.rs` does not hand them to the app-server,
    /// and Kannu never starts a thread they could apply to. The root CLI already refuses some root
    /// options with a subcommand (`--remote`, `--strict-config`), so an unneeded flag is a way for
    /// a future release to break the read; docs/REGRESSIONS.md entry 8 is that lesson for Claude.
    static let appServerArguments = ["app-server"]

    /// Developer ID, and the identifier OpenAI's release workflow signs the binary with
    /// (`.github/workflows/rust-release.yml`: `sign_macos_code.sh --identifier "$binary"`).
    /// OpenAI's Team ID is NOT pinned: no public source found states the Team ID of the Codex
    /// CLI's signing certificate, and Codex is not installed here to read it off a binary. Any
    /// Developer ID holder can sign a binary named "codex", so this stops an unsigned or
    /// ad-hoc-signed file (a Homebrew formula built from source among them), not a determined
    /// impostor. Once a real install shows the team, append
    /// `and certificate leaf[subject.OU] = "<team>"`.
    static let signingRequirement = #"identifier "codex" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#

    /// The Rust target triple and npm's architecture name for this Mac's build of Kannu.
    static var hostPlatform: (triple: String, npmArch: String) {
#if arch(arm64)
        return ("aarch64-apple-darwin", "arm64")
#else
        return ("x86_64-apple-darwin", "x64")
#endif
    }

    /// Global `node_modules` folders npm may have installed `@openai/codex` into: Homebrew's
    /// Node on either architecture, a `~/.npm-global` prefix, and every nvm-managed Node, newest
    /// version first.
    static func nodeModulesRoots(home: URL, fileManager: FileManager = .default) -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/opt/homebrew/lib/node_modules", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/lib/node_modules", isDirectory: true),
            home.appendingPathComponent(".npm-global/lib/node_modules", isDirectory: true),
        ]
        let nvm = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let versions = (try? fileManager.contentsOfDirectory(atPath: nvm.path)) ?? []
        for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
            roots.append(nvm.appendingPathComponent(version).appendingPathComponent("lib/node_modules", isDirectory: true))
        }
        return roots
    }

    /// Every path a `codex` binary may be at, most preferred first.
    static func candidates(home: URL, binDirectories: [URL]? = nil, nodeModulesRoots roots: [URL],
                           triple: String = hostPlatform.triple, npmArch: String = hostPlatform.npmArch) -> [URL] {
        let directories = binDirectories ?? [
            home.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
        var paths = directories.map { $0.appendingPathComponent("codex") }
        let platformPackage = "@openai/codex-darwin-\(npmArch)"
        for root in roots {
            let package = root.appendingPathComponent("@openai/codex", isDirectory: true)
            for vendor in [root.appendingPathComponent(platformPackage).appendingPathComponent("vendor"),
                           package.appendingPathComponent("node_modules").appendingPathComponent(platformPackage)
                               .appendingPathComponent("vendor"),
                           package.appendingPathComponent("vendor")] {
                paths.append(vendor.appendingPathComponent(triple).appendingPathComponent("bin/codex"))
            }
            paths.append(package.appendingPathComponent("vendor").appendingPathComponent(triple)
                .appendingPathComponent("codex/codex"))
        }
        return paths
    }

    /// The first candidate that is a native executable and passes `isTrusted`, as its real path
    /// (symlinks resolved), which is also the path to launch: the file that was checked. Each
    /// real file is offered to `isTrusted` once.
    static func resolve(_ candidates: [URL], fileManager: FileManager = .default, isTrusted: (URL) -> Bool) -> URL? {
        var seen = Set<String>()
        for candidate in candidates {
            let real = candidate.resolvingSymlinksInPath()
            guard seen.insert(real.path).inserted,
                  fileManager.isExecutableFile(atPath: real.path),
                  isMachO(real) else { continue }
            if isTrusted(real) { return real }
        }
        return nil
    }

    /// The candidates on this Mac, resolved.
    static func resolve(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        fileManager: FileManager = .default, isTrusted: (URL) -> Bool) -> URL? {
        resolve(candidates(home: home, nodeModulesRoots: nodeModulesRoots(home: home, fileManager: fileManager)),
                fileManager: fileManager, isTrusted: isTrusted)
    }

    /// What a cached signature verdict is keyed on: values no process of the user's can put back.
    /// Size and modification date are not that: padding restores a size and `touch -r` or
    /// `utimes` a date, so a payload written over a checked binary would inherit its verdict. The
    /// change time moves on every write, rename, `chmod` and `utimes`, and only a change of the
    /// system clock (root) can set it; device and inode tell a replacement file from the one that
    /// was checked.
    struct FileIdentity: Equatable {
        var device: Int32
        var inode: UInt64
        var size: Int64
        var changedSeconds: Int
        var changedNanoseconds: Int

        /// nil when the path cannot be `stat`ed.
        init?(path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            changedSeconds = info.st_ctimespec.tv_sec
            changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }

    /// A Mach-O file, thin or universal, by its first four bytes. A `#!` script (the npm shim)
    /// is not one.
    static func isMachO(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magics: [[UInt8]] = [
            [0xCF, 0xFA, 0xED, 0xFE], // MH_MAGIC_64, little-endian
            [0xCE, 0xFA, 0xED, 0xFE], // MH_MAGIC, little-endian
            [0xCA, 0xFE, 0xBA, 0xBE], // FAT_MAGIC
            [0xCA, 0xFE, 0xBA, 0xBF], // FAT_MAGIC_64
        ]
        return magics.contains([UInt8](head))
    }
}
