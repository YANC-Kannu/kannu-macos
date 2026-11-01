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

/// What `docs/SETTINGS.md` says about the design system, held against the sources, because the views
/// are not compiled into this logic-only target. "Under Settings" always means the walk below, at any
/// depth, and every scanner reads code with its comments blanked. Each rule is proved against planted
/// offenders, so a pattern that matches nothing cannot pass for ever.
final class SettingsDesignSystemRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let settingsDirectory = repoRoot.appendingPathComponent("Kannu/components/Settings", isDirectory: true)

    // MARK: - The walk

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            files.append(file)
        }
        return files
    }

    private static func repeatedNames(in files: [URL]) -> [String] {
        Dictionary(grouping: files, by: \.lastPathComponent).filter { $0.value.count > 1 }.keys.sorted()
    }

    /// Everything under Settings, keyed by file name. A repeated name would hide a file from every rule.
    private static func sources() throws -> [String: String] {
        let files = try swiftFiles(under: settingsDirectory)
        XCTAssertEqual(repeatedNames(in: files), [], "two files under Settings share a name, so a rule reads only one of them")
        var sources: [String: String] = [:]
        for file in files {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        XCTAssertNotNil(sources["SettingsTheme.swift"], "the scan no longer reaches DesignSystem/")
        return sources
    }

    /// `DesignSystem/` only.
    private static func designSystemSources() throws -> [String: String] {
        var sources: [String: String] = [:]
        for file in try swiftFiles(under: settingsDirectory.appendingPathComponent("DesignSystem", isDirectory: true)) {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        return sources
    }

    private static func theme() throws -> String {
        code(try XCTUnwrap(try designSystemSources()["SettingsTheme.swift"]))
    }

    func testTheWalkReachesSubfoldersAndReportsARepeatedName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("DesignSystem/Inner")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        for path in ["Top.swift", "DesignSystem/Theme.swift", "DesignSystem/Inner/Top.swift", "DesignSystem/Notes.md"] {
            try Data().write(to: root.appendingPathComponent(path))
        }
        let files = try Self.swiftFiles(under: root)
        XCTAssertEqual(files.map(\.lastPathComponent).sorted(), ["Theme.swift", "Top.swift", "Top.swift"])
        XCTAssertEqual(Self.repeatedNames(in: files), ["Top.swift"])
    }

    // MARK: - One root

    private static func rootFindings(view: String, snapshots: String, root: String) -> [String] {
        var findings: [String] = []
        for (name, text) in [("view", view), ("snapshots", snapshots)] {
            if !text.contains(".settingsDesignSystem()") { findings.append("\(name) does not apply the root") }
            if text.contains("formStyle(.grouped)") { findings.append("\(name) sets the form style itself") }
        }
        if root.components(separatedBy: "formStyle(.grouped)").count != 2 { findings.append("the root lost its form style") }
        return findings
    }

    func testTheRootIsOneModifierSharedWithTheSnapshots() throws {
        let sources = try Self.sources()
        let snapshots = try String(contentsOf: Self.repoRoot.appendingPathComponent("Kannu/helpers/DebugSnapshot.swift"), encoding: .utf8)
        XCTAssertEqual(Self.rootFindings(view: Self.code(try XCTUnwrap(sources["SettingsView.swift"])),
                                         snapshots: Self.code(snapshots),
                                         root: Self.code(try XCTUnwrap(sources["SettingsDesignSystem.swift"]))), [])

        let good = ".settingsDesignSystem()"
        XCTAssertEqual(Self.rootFindings(view: good, snapshots: good, root: "formStyle(.grouped)"), [])
        XCTAssertEqual(Self.rootFindings(view: ".formStyle(.grouped)", snapshots: good, root: "formStyle(.grouped)").count, 2)
        XCTAssertEqual(Self.rootFindings(view: good, snapshots: good + ".formStyle(.grouped)", root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: good, snapshots: good, root: "font(body)").count, 1)
    }

    // MARK: - Values come from the theme

    private static let hardCodedValuePatterns = [
        #"\bColor\("#,
        #"\bColor\."#,
        #"\.font\(\."#,
        #"\bFont\."#,
        #"cornerRadius:\s*\d"#,
        #"\.opacity\(0\."#,
        #"\.padding\((?:[^()]*,\s*)?-?\d"#,
        #"\.(?:foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|tint)\(\s*\.[a-z]"#,
        #"\b(?:spacing|width|height):\s*(?!0(?:\.0+)?(?![.\d]))-?\d"#,
    ]

    private static func hardCodedValues(in code: String) -> [String] {
        hardCodedValuePatterns.flatMap { matches(of: $0, in: code) }
    }

    func testDesignSystemValuesComeFromTheTheme() throws {
        let files = try Self.designSystemSources().filter { $0.key != "SettingsTheme.swift" }
        XCTAssertFalse(files.isEmpty, "the scan read nothing: the folder moved")
        for (name, source) in files {
            XCTAssertEqual(Self.hardCodedValues(in: Self.code(source)), [], "\(name) holds a value that belongs in SettingsTheme")
        }

        for plant in [".foregroundStyle(.white)", ".fill(.blue)", ".background( .red)", ".tint(.orange)", ".padding(.horizontal, 6)",
                      ".padding(12)", ".padding(-4)", ".font(Font.system(size: 9))", ".font(.caption)", "Color.red", "Color(red: 0, green: 0, blue: 0)",
                      "RoundedRectangle(cornerRadius: 7)", ".opacity(0.5)", "VStack(spacing: 4)", "VStack(spacing: 0.5)", ".frame(width: 32)", ".frame(height: 18)"] {
            XCTAssertFalse(Self.hardCodedValues(in: plant).isEmpty, "the rule misses \(plant)")
        }
        for clean in [".foregroundStyle(SettingsTheme.ink)", ".padding(SettingsTheme.buttonInset)", ".font(SettingsTheme.body)",
                      "VStack(spacing: 0)", "HStack(spacing: SettingsMetrics.rowContent)", ".frame(width: SettingsTheme.toggleWidth)",
                      "private var labelColor: NSColor", ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)"] {
            XCTAssertEqual(Self.hardCodedValues(in: clean), [], clean)
        }
    }

    // MARK: - Fonts

    private static func filesNamingAFont(in sources: [String: String]) -> [String] {
        sources.filter { $0.key != "SettingsTheme.swift" && code($0.value).contains(".custom(") }.keys.sorted()
    }

    func testOnlyTheThemeNamesAFont() throws {
        XCTAssertEqual(Self.filesNamingAFont(in: try Self.sources()), [])

        XCTAssertEqual(Self.filesNamingAFont(in: ["Page.swift": ".font(.custom(\"Geist-Regular\", size: 13))"]), ["Page.swift"])
        XCTAssertEqual(Self.filesNamingAFont(in: ["Page.swift": "// .custom( belongs in the theme"]), [])
        XCTAssertEqual(Self.filesNamingAFont(in: ["SettingsTheme.swift": ".custom(name, size: size)"]), [])
    }

    func testTheThemeFallsBackToTheSystemFont() throws {
        XCTAssertTrue(try Self.theme().contains("geistIsAvailable ? .custom(name, size: size) : .system(size: size, weight: weight)"),
                      "with no font bundled the theme must keep the system font at the same size")
    }

    // MARK: - Contrast

    private static func relativeLuminance(_ hex: Int) -> Double {
        func channel(_ shift: Int) -> Double {
            let value = Double(hex >> shift & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func contrast(_ first: Int, _ second: Int) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func readabilityFailures(in code: String) -> [String] {
        var colours: [String: (light: Int, dark: Int)] = [:]
        for match in groups(of: #"static let (\w+) = (?:color|nsColor)\(light: 0x(\w{6}), dark: 0x(\w{6})\)"#, in: code) {
            colours[match[1]] = (Int(match[2], radix: 16) ?? 0, Int(match[3], radix: 16) ?? 0)
        }
        var failures: [String] = []
        // `paper` has no hex of its own: it is `windowPaper`, for as long as this line says so.
        if code.contains("static let paper = Color(nsColor: windowPaper)") {
            colours["paper"] = colours["windowPaper"]
        } else {
            failures.append("paper is no longer windowPaper")
        }
        func require(_ text: String, on backgrounds: [String], atLeast minimum: Double) {
            for background in backgrounds {
                guard let foreground = colours[text], let behind = colours[background] else {
                    failures.append("\(text) on \(background) cannot be read from the theme")
                    continue
                }
                if contrast(foreground.light, behind.light) < minimum { failures.append("\(text) on \(background), light") }
                if contrast(foreground.dark, behind.dark) < minimum { failures.append("\(text) on \(background), dark") }
            }
        }
        require("ink", on: ["paper", "panel", "card"], atLeast: 7)
        require("inkSecondary", on: ["paper", "panel", "card"], atLeast: 4.5)
        require("accentStrong", on: ["paper", "panel", "card"], atLeast: 4.5)
        require("controlOff", on: ["panel", "card"], atLeast: 3)
        // The two labels the button style really draws.
        require("onPrimary", on: ["ink"], atLeast: 7)
        require("destructive", on: ["panel", "card"], atLeast: 4.5)
        if let accent = colours["accent"] {
            if accent.light != 0x4DA3FF || accent.dark != 0x4DA3FF { failures.append("accent is no longer the eye blue") }
        } else {
            failures.append("accent cannot be read from the theme")
        }
        return failures
    }

    func testTheThemeIsReadable() throws {
        let theme = try Self.theme()
        XCTAssertEqual(Self.readabilityFailures(in: theme), [])

        let faintInk = theme.replacingOccurrences(of: "ink = color(light: 0x1C1A16", with: "ink = color(light: 0x8A877F")
        XCTAssertNotEqual(faintInk, theme, "the plant must change the theme")
        XCTAssertTrue(Self.readabilityFailures(in: faintInk).contains("ink on panel, light"))

        let faintDark = theme.replacingOccurrences(of: "dark: 0xA3A199", with: "dark: 0x3A3A3A")
        XCTAssertNotEqual(faintDark, theme, "the plant must change the theme")
        XCTAssertTrue(Self.readabilityFailures(in: faintDark).contains("inkSecondary on card, dark"))

        let otherBlue = theme.replacingOccurrences(of: "accent = color(light: 0x4DA3FF", with: "accent = color(light: 0x1D69C9")
        XCTAssertNotEqual(otherBlue, theme, "the plant must change the theme")
        XCTAssertTrue(Self.readabilityFailures(in: otherBlue).contains("accent is no longer the eye blue"))

        let otherPaper = theme.replacingOccurrences(of: "static let paper = Color(nsColor: windowPaper)", with: "static let paper = Color.white")
        XCTAssertNotEqual(otherPaper, theme, "the plant must change the theme")
        XCTAssertTrue(Self.readabilityFailures(in: otherPaper).contains("paper is no longer windowPaper"))
    }

    // MARK: - Every token has a reader

    /// Child 2 gives each of these a reader and deletes this set.
    private static let notReadYet: Set<String> = ["paper", "panel", "hover", "inkSecondary", "pageTitle", "caption", "micro"]

    private static func unreadTokens(theme: String, others: [String]) -> Set<String> {
        let tokens = groups(of: #"static let (\w+)"#, in: theme).map { $0[1] }
        return Set(tokens.filter { token in
            let readInside = matches(of: "\\b\(token)\\b", in: theme).count > 1
            let readOutside = others.contains { !matches(of: "\\bSettingsTheme\\.\(token)\\b", in: $0).isEmpty }
            return !readInside && !readOutside
        })
    }

    /// Scope: everything under Settings but the theme. Never `DebugSnapshot.swift`: its board names
    /// every token, which would make this rule pass whatever the pages do.
    func testEveryThemeTokenIsRead() throws {
        let theme = try Self.theme()
        let others = try Self.sources().filter { $0.key != "SettingsTheme.swift" }.values.map(Self.code)
        XCTAssertEqual(Self.unreadTokens(theme: theme, others: others), Self.notReadYet,
                       "a token nothing reads is a stale value; a token in notReadYet that has a reader must leave the set")

        XCTAssertEqual(Self.unreadTokens(theme: theme + "\nstatic let planted = color(light: 0x000000, dark: 0x000000)\n", others: others),
                       Self.notReadYet.union(["planted"]))
        // A longer name is not a reader, and a comment is not a reader.
        let plantedPair = "static let ink = 1\nstatic let inkSecondary = 2\nstatic let body = 3\nstatic let bodyStrong = 4\n"
        XCTAssertEqual(Self.unreadTokens(theme: plantedPair, others: ["SettingsTheme.inkSecondary", "SettingsTheme.bodyStrong"]), ["ink", "body"])
        XCTAssertEqual(Self.unreadTokens(theme: plantedPair, others: [Self.code("// SettingsTheme.ink, SettingsTheme.body")]),
                       ["ink", "inkSecondary", "body", "bodyStrong"])
        XCTAssertEqual(Self.unreadTokens(theme: "static let paper = color(windowPaper)\nstatic let windowPaper = 1\n", others: []), ["paper"])
    }

    // MARK: - One type per file

    private static func topLevelTypes(in code: String) -> [String] {
        matches(of: #"(?m)^(?:(?:private|fileprivate|internal|public|final) )*(?:struct|class|enum|actor|protocol) "#, in: code)
    }

    func testOneTypePerDesignSystemFile() throws {
        for (name, source) in try Self.designSystemSources() {
            XCTAssertLessThanOrEqual(Self.topLevelTypes(in: Self.code(source)).count, 1, "\(name) declares more than one top-level type")
        }

        XCTAssertEqual(Self.topLevelTypes(in: "struct A {}\nprivate struct B {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "final class A {}\nenum B {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "struct A {\n    private struct B {}\n    enum C {}\n}\nextension A {}\n").count, 1)
    }

    // MARK: - Native controls that stay native

    /// Lines where a style the root's labelled-row style would pull apart has no opt-out nearby.
    private static func stylesWithoutTheOptOut(in code: String) -> [String] {
        let lines = code.components(separatedBy: "\n")
        return lines.indices.filter { index in
            guard lines[index].contains(".toggleStyle(.checkbox)") || lines[index].contains(".pickerStyle(.radioGroup)") else { return false }
            return !nearby(index, in: lines).contains { $0.contains(".labeledContentStyle(.automatic)") }
        }.map { lines[$0].trimmingCharacters(in: .whitespaces) }
    }

    func testASwitchIsOurs() throws {
        let sources = try Self.sources().mapValues(Self.code)
        XCTAssertEqual(sources.filter { $0.value.contains(".toggleStyle(.switch)") }.keys.sorted(), ["SettingsToggleStyle.swift"])
        XCTAssertEqual(sources.filter { $0.value.contains(".toggleStyle(.checkbox)") }.keys.sorted(), ["NewTaskSheet.swift"])
        XCTAssertEqual(try XCTUnwrap(sources["NewTaskSheet.swift"]).components(separatedBy: ".toggleStyle(.checkbox)").count - 1, 2)
        for (name, source) in sources {
            XCTAssertEqual(Self.stylesWithoutTheOptOut(in: source), [], "\(name): the root's labelled-row style pulls this control apart")
        }

        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.checkbox)\n").count, 1)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Picker(\"a\") {}\n    .pickerStyle(.radioGroup)\n    .labelsHidden()\n").count, 1)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.checkbox)\n    .labeledContentStyle(.automatic)\n").count, 0)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Picker(\"a\") {}\n    .pickerStyle(.radioGroup)\n    .labeledContentStyle(.automatic)\n    .labelsHidden()\n").count, 0)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: Self.code("// .toggleStyle(.checkbox) must opt out")).count, 0)
    }

    func testTheControlsKeepKeyboardAndVoiceOver() throws {
        let sources = try Self.designSystemSources().mapValues(Self.code)
        let toggle = try XCTUnwrap(sources["SettingsToggleStyle.swift"])
        for required in ["Button {", ".accessibilityRepresentation", "accessibilityReduceMotion"] {
            XCTAssertTrue(toggle.contains(required), "SettingsToggleStyle lost \(required)")
        }
        // Its `.plain` button dims a disabled switch; an opacity of its own dims it twice, and the
        // knob disappears into the track (seen on the designSystem board).
        XCTAssertTrue(toggle.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(toggle.contains(".opacity("), "SettingsToggleStyle dims a disabled switch twice")
        let disclosure = try XCTUnwrap(sources["SettingsDisclosureGroupStyle.swift"])
        for required in ["accessibilityReduceMotion", ".accessibilityValue"] {
            XCTAssertTrue(disclosure.contains(required), "SettingsDisclosureGroupStyle lost \(required)")
        }
    }

    /// A custom style's label can be squeezed where a native button's cannot: a row broke
    /// "Acknowledgements" across two lines before this.
    func testAButtonKeepsItsWidth() throws {
        let button = try XCTUnwrap(try Self.designSystemSources()["SettingsButtonStyle.swift"])
        XCTAssertTrue(Self.code(button).contains(".fixedSize(horizontal: true, vertical: false)"))
    }

    /// The root's font replaces what a grouped `Form` gives its headers and footers, so the shared
    /// components must say theirs, or every section header goes light and every footer grows.
    func testSectionHeadersAndFootersKeepTheirOwnType() throws {
        let components = Self.code(try XCTUnwrap(try Self.sources()["SettingsComponents.swift"]))
        for (component, font) in [("SettingsSectionHeader", "SettingsTheme.sectionTitle"), ("SettingsFooter", "SettingsTheme.description")] {
            let start = try XCTUnwrap(components.range(of: "struct \(component):"), "\(component) is gone")
            let end = components.range(of: "\n}\n", range: start.upperBound..<components.endIndex)?.lowerBound ?? components.endIndex
            XCTAssertTrue(components[start.lowerBound..<end].contains(".font(\(font))"), "\(component) lost .font(\(font))")
        }
    }

    /// A root button style takes a default-style `Menu`'s indicator away, and the only cures are the
    /// borderless menu style or a native button style on the menu itself.
    private static func menusWithoutAnIndicator(in code: String) -> [String] {
        let characters = Array(code)
        return menuOpeners(in: code).compactMap { opener in
            let chain = modifierChain(after: opener, in: characters)
            let keeps = chain.contains(".menuStyle(.borderlessButton)") || chain.contains(".buttonStyle(.bordered)")
            return keeps ? nil : String(characters[opener..<min(opener + 24, characters.count)])
        }
    }

    /// Where each `Menu` opens, as a `Character` offset. Not `SomeMenu(`, `foo.Menu(` or `resetMenu`.
    private static func menuOpeners(in code: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z.])Menu(?: \{|\()"#) else {
            XCTFail("bad Menu pattern")
            return []
        }
        return regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
            Range(match.range, in: code).map { code.distance(from: code.startIndex, to: $0.lowerBound) }
        }
    }

    /// What is chained onto the call opening at `start`, past its arguments and every trailing
    /// closure, `label:` included. A modifier inside a closure is on something else.
    private static func modifierChain(after start: Int, in characters: [Character]) -> String {
        var index = start + "Menu".count
        func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }
        func skipBalanced() {
            var depth = 0, inString = false
            while index < characters.count {
                let character = characters[index]
                if inString {
                    if character == "\\" { index += 2; continue }
                    if character == "\"" { inString = false }
                } else if character == "\"" {
                    inString = true
                } else if character == "(" || character == "{" {
                    depth += 1
                } else if character == ")" || character == "}" {
                    depth -= 1
                    if depth == 0 { index += 1; return }
                }
                index += 1
            }
        }
        // The call's own arguments and closures.
        while true {
            skipWhitespace()
            guard index < characters.count else { return "" }
            if characters[index] == "(" || characters[index] == "{" {
                skipBalanced()
            } else if String(characters[index...].prefix(6)) == "label:" {
                index += 6
            } else if String(characters[index...].prefix(14)) == "primaryAction:" {
                index += 14
            } else {
                break
            }
        }
        // The modifiers: `.name`, then its arguments and closures.
        var chain = ""
        while index < characters.count, characters[index] == "." {
            let modifierStart = index
            index += 1
            while index < characters.count, characters[index].isLetter || characters[index].isNumber { index += 1 }
            while true {
                var next = index
                while next < characters.count, characters[next] == " " { next += 1 }
                guard next < characters.count, characters[next] == "(" || characters[next] == "{" else { break }
                index = next
                skipBalanced()
            }
            chain += String(characters[modifierStart..<index]) + "\n"
            skipWhitespace()
        }
        return chain
    }

    func testEveryMenuKeepsItsIndicator() throws {
        var openers = 0
        for (name, source) in try Self.sources() {
            let code = Self.code(source)
            openers += Self.menuOpeners(in: code).count
            XCTAssertEqual(Self.menusWithoutAnIndicator(in: code), [], "\(name): the root's button style takes this Menu's indicator away")
        }
        XCTAssertGreaterThan(openers, 0, "the scan found no Menu: the pattern went blind")

        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "Menu(\"Connect…\") { Button(\"a\") {} }\n.fixedSize()\n").count, 1)
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "Menu(\"Connect…\") { Button(\"a\") {} }\n.menuStyle(.button)\n").count, 1)
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "return Menu {\n    Button(\"a\") {}\n} label: {\n    Text(\"x\")\n}\n").count, 1)
        // A style inside the label is on the label, not on the menu.
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "Menu {\n} label: {\n    Text(\"x\").menuStyle(.borderlessButton)\n}\n").count, 1)
        // A modifier on the next view is not on this one.
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "Menu(\"a\") {}\nText(\"b\")\n    .buttonStyle(.bordered)\n").count, 1)

        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "Menu(\"Connect…\") {\n}\n.buttonStyle(.bordered)\n.fixedSize()\n").count, 0)
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "return Menu {\n    Button(\"a {\") {}\n} label: {\n    Text(\"x\")\n}\n.help(\"h\")\n.menuStyle(.borderlessButton)\n").count, 0)
        XCTAssertEqual(Self.menusWithoutAnIndicator(in: "resetMenu\n.buttonStyle(.plain)\nSomeMenu(\"a\") {}\nfoo.Menu(\"b\") {}\n").count, 0)
    }

    /// Lines naming the default action with no primary style beside them. A custom style cannot see
    /// the shortcut, so a sheet's Connect would otherwise look the same as its Cancel.
    private static func flatDefaultActions(in code: String) -> [String] {
        let lines = code.components(separatedBy: "\n")
        return lines.indices.filter { index in
            lines[index].contains("defaultAction")
                && !nearby(index, in: lines).contains { $0.contains("SettingsButtonStyle(.primary)") }
        }.map { lines[$0].trimmingCharacters(in: .whitespaces) }
    }

    func testADefaultActionLooksPrimary() throws {
        var sites = 0
        for (name, source) in try Self.sources() {
            let code = Self.code(source)
            sites += code.components(separatedBy: "defaultAction").count - 1
            XCTAssertEqual(Self.flatDefaultActions(in: code), [], "\(name): a default action needs SettingsButtonStyle(.primary)")
        }
        XCTAssertGreaterThan(sites, 0, "the scan found no default action: the pattern went blind")

        XCTAssertEqual(Self.flatDefaultActions(in: "Button(\"Connect\") {}\n    .keyboardShortcut(.defaultAction)\n").count, 1)
        XCTAssertEqual(Self.flatDefaultActions(in: "Button(\"Add\") {}\n    .keyboardShortcut(typing ? nil : .defaultAction)\n    .disabled(x)\n").count, 1)
        XCTAssertEqual(Self.flatDefaultActions(in: "Button(\"Connect\") {}\n    .buttonStyle(SettingsButtonStyle(.primary))\n    .keyboardShortcut(.defaultAction)\n").count, 0)
        XCTAssertEqual(Self.flatDefaultActions(in: "Button(\"Connect\") {}\n    .keyboardShortcut(.defaultAction)\n    .buttonStyle(SettingsButtonStyle(.primary))\n").count, 0)
        XCTAssertEqual(Self.flatDefaultActions(in: Self.code("// .defaultAction needs the primary style")).count, 0)
    }

    // MARK: - Licence

    private static func filesWithoutTheLicence(in sources: [String: String], licence: String) -> [String] {
        sources.filter { !$0.value.hasPrefix(licence) }.keys.sorted()
    }

    func testEveryDesignSystemFileCarriesTheLicence() throws {
        let donor = try String(contentsOf: Self.repoRoot.appendingPathComponent("Kannu/components/Notch/TimerTaskForm.swift"), encoding: .utf8)
        let licence = donor.components(separatedBy: "\n").prefix(17).joined(separator: "\n") + "\n"
        XCTAssertTrue(licence.hasSuffix(" */\n"), "the donor's GPL block moved")
        let files = try Self.designSystemSources()
        XCTAssertFalse(files.isEmpty, "the scan read nothing: the folder moved")
        XCTAssertEqual(Self.filesWithoutTheLicence(in: files, licence: licence), [])

        XCTAssertEqual(Self.filesWithoutTheLicence(in: ["Planted.swift": "import SwiftUI\n"], licence: licence), ["Planted.swift"])
        XCTAssertEqual(Self.filesWithoutTheLicence(in: ["Planted.swift": licence + "import SwiftUI\n"], licence: licence), [])
    }

    // MARK: - Plumbing

    /// The source with every comment blanked and every line kept, so line numbers and "within two
    /// lines" still mean what they do in the file. Strings are respected: a URL's `//` is not a comment.
    private static func code(_ source: String) -> String {
        let characters = Array(source)
        var out = ""
        var index = 0
        var inString = false
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if inString {
                out.append(character)
                if character == "\\", let next {
                    out.append(next)
                    index += 2
                    continue
                }
                if character == "\"" || character == "\n" { inString = false }
                index += 1
            } else if character == "\"" {
                inString = true
                out.append(character)
                index += 1
            } else if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "/", next == "*" {
                index += 2
                while index < characters.count, !(characters[index] == "*" && index + 1 < characters.count && characters[index + 1] == "/") {
                    if characters[index] == "\n" { out.append("\n") }
                    index += 1
                }
                index += 2
            } else {
                out.append(character)
                index += 1
            }
        }
        return out
    }

    /// A line and the two either side of it.
    private static func nearby(_ index: Int, in lines: [String]) -> ArraySlice<String> {
        lines[max(0, index - 2)...min(lines.count - 1, index + 2)]
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        groups(of: pattern, in: text).map { $0[0] }
    }

    /// Each match's whole text, then its capture groups.
    private static func groups(of pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad pattern: \(pattern)")
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            (0..<match.numberOfRanges).map { group in
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : nsText.substring(with: range)
            }
        }
    }
}
