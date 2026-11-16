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

import CoreGraphics
import XCTest

/// Geist ships as static TrueType files in `Kannu/Fonts/`, and the system activates them from
/// `ATSApplicationFontsPath`, so no launch code registers a font and nothing runs before the Terms of
/// Use. Nothing else fails when this breaks: a Git LFS pointer copies into the app like any file,
/// SwiftUI's `.custom` falls back to the system font in silence when a name is one letter off, and
/// `geistIsAvailable` asks only for `Geist-Regular`. So the files, the key and the names are held here.
final class GeistBundleRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Each TrueType file in `Kannu/Fonts/` by base name, with the PostScript name it declares.
    private static func bundledFaces() throws -> [String: String] {
        let folder = repoRoot.appendingPathComponent("Kannu/Fonts", isDirectory: true)
        var faces: [String: String] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where file.pathExtension == "ttf" {
            let data = try Data(contentsOf: file)
            // A pointer starts "version https://git-lfs"; a TrueType font starts with its version tag.
            XCTAssertEqual([UInt8](data.prefix(4)), [0x00, 0x01, 0x00, 0x00], "\(file.lastPathComponent) is not a TrueType font")
            let font = try XCTUnwrap(CGDataProvider(data: data as CFData).flatMap { CGFont($0) },
                                     "\(file.lastPathComponent) does not load as a font")
            faces[file.deletingPathExtension().lastPathComponent] = (font.postScriptName as String?) ?? "<no PostScript name>"
        }
        return faces
    }

    /// `.` because the synchronized group copies every resource flat into `Contents/Resources`: a
    /// `Fonts` value would name a folder the app does not have, and the build would stay green.
    func testThePlistActivatesTheResourcesFolder() throws {
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent("Kannu/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ATSApplicationFontsPath"] as? String, ".")
    }

    func testEachFileIsTheFaceItIsNamedFor() throws {
        let faces = try Self.bundledFaces()
        XCTAssertFalse(faces.isEmpty, "found no fonts: the folder moved")
        for (file, postScriptName) in faces {
            XCTAssertEqual(postScriptName, file, "\(file).ttf declares another face")
        }
    }

    /// Both ways: a name with no file falls back in silence, and a file nothing names ships for nothing.
    static func nameProblems(theme: String, bundled: Set<String>) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(theme)
        let named = Set(SettingsDesignSystemRulesTests.matches(of: #""Geist[^"]*""#, in: code).map { String($0.dropFirst().dropLast()) })
        return named.subtracting(bundled).map { "the theme names \($0), which no bundled file is" }.sorted()
            + bundled.subtracting(named).map { "\($0) is bundled, and the theme never names it" }.sorted()
    }

    func testTheThemeNamesExactlyTheBundledFaces() throws {
        let theme = try Self.read("Kannu/components/Settings/DesignSystem/SettingsTheme.swift")
        let bundled = Set(try Self.bundledFaces().values)
        XCTAssertEqual(Self.nameProblems(theme: theme, bundled: bundled), [])

        let typo = theme.replacingOccurrences(of: "\"Geist-SemiBold\"", with: "\"Geist-Semibold\"")
        XCTAssertEqual(Self.nameProblems(theme: typo, bundled: bundled),
                       ["the theme names Geist-Semibold, which no bundled file is", "Geist-SemiBold is bundled, and the theme never names it"])
        XCTAssertEqual(Self.nameProblems(theme: theme, bundled: bundled.union(["GeistMono-Medium"])),
                       ["GeistMono-Medium is bundled, and the theme never names it"])
        XCTAssertEqual(Self.nameProblems(theme: "// \"Geist-Thin\"\n", bundled: []), [], "a comment named a face")
    }

    /// Resources flatten, and `LICENSE` in `Contents/Resources` is already Kannu's GPL.
    func testTheLicenceShipsBesideTheFonts() throws {
        XCTAssertTrue(try Self.read("Kannu/Fonts/Geist-OFL.txt").contains("SIL Open Font License, Version 1.1"))
        let notice = try Self.read("NOTICE")
        XCTAssertTrue(notice.contains("Geist") && notice.contains("Geist-OFL.txt"), "NOTICE no longer credits Geist")
    }

    static func registrations(in sources: [String: String]) -> [String] {
        sources.filter { $0.value.contains("CTFontManagerRegister")
            && SettingsDesignSystemRulesTests.code($0.value).contains("CTFontManagerRegister") }.keys.sorted()
    }

    /// The plist key already activates the fonts. A registration call is launch work it makes needless,
    /// and `LaunchGateRulesTests` bans `CTFontManager` before the gate.
    func testNothingRegistersAFontAtRunTime() throws {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: Self.repoRoot.appendingPathComponent("Kannu"),
                                                                  includingPropertiesForKeys: nil))
        // Keyed by path: two files sharing a name must not hide one of them.
        var sources: [String: String] = [:]
        for case let file as URL in walker where file.pathExtension == "swift" {
            sources[file.path] = try String(contentsOf: file, encoding: .utf8)
        }
        XCTAssertTrue(sources.keys.contains { $0.hasSuffix("/DesignSystem/SettingsTheme.swift") }, "the walk read nothing")
        XCTAssertEqual(Self.registrations(in: sources), [])

        XCTAssertEqual(Self.registrations(in: ["A.swift": "CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)"]), ["A.swift"])
        XCTAssertEqual(Self.registrations(in: ["A.swift": "// CTFontManagerRegisterFontsForURL used to run here"]), [])
    }
}
