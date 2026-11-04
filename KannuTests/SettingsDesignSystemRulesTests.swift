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
        // The whole shell has it, sidebar and pages alike, from exactly one place on the shell's own chain.
        if openers(of: "BrainShell", in: view).count != 1
            || !calls(of: "BrainShell", in: view, whereChain: { !$0.contains(".settingsDesignSystem()") }).isEmpty
            || view.components(separatedBy: ".settingsDesignSystem()").count != 2 {
            findings.append("the view applies the root to something other than its shell")
        }
        return findings
    }

    private static func snapshotSource() throws -> String {
        code(try String(contentsOf: repoRoot.appendingPathComponent("Kannu/helpers/DebugSnapshot.swift"), encoding: .utf8))
    }

    private static func filesSettingTheFormStyle(in sources: [String: String]) -> [String] {
        sources.filter { $0.key != "SettingsDesignSystem.swift" && code($0.value).contains("formStyle(") }.keys.sorted()
    }

    func testTheRootIsOneModifierSharedWithTheSnapshots() throws {
        let sources = try Self.sources()
        XCTAssertEqual(Self.rootFindings(view: Self.code(try XCTUnwrap(sources["SettingsView.swift"])),
                                         snapshots: try Self.snapshotSource(),
                                         root: Self.code(try XCTUnwrap(sources["SettingsDesignSystem.swift"]))), [])

        let good = ".settingsDesignSystem()"
        let shell = "BrainShell {\n    sidebar\n} headerAccessory: {\n    moon\n} detail: {\n    page\n}\n.environmentObject(a)\n.settingsDesignSystem()\n"
        XCTAssertEqual(Self.rootFindings(view: shell, snapshots: good, root: "formStyle(.grouped)"), [])
        XCTAssertEqual(Self.rootFindings(view: shell + ".formStyle(.grouped)", snapshots: good, root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: ".formStyle(.grouped)", snapshots: good, root: "formStyle(.grouped)").count, 3)
        XCTAssertEqual(Self.rootFindings(view: shell, snapshots: good + ".formStyle(.grouped)", root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: shell, snapshots: good, root: "font(body)").count, 1)
        // On something else, on the shell as well, on a page inside the shell, or on the next view.
        XCTAssertEqual(Self.rootFindings(view: "NavigationSplitView {}\n.settingsDesignSystem()", snapshots: good, root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: shell + "}\n.settingsDesignSystem()", snapshots: good, root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: "BrainShell {\n} detail: {\n    page.settingsDesignSystem()\n}\n", snapshots: good, root: "formStyle(.grouped)").count, 1)
        XCTAssertEqual(Self.rootFindings(view: "BrainShell {\n} detail: {\n}\nText(\"a\")\n.settingsDesignSystem()\n", snapshots: good, root: "formStyle(.grouped)").count, 1)
    }

    /// Kept out of `rootFindings`, whose plants count on a root that says only the form style.
    func testTheRootHidesAFormsBackground() throws {
        let sources = try Self.sources()
        XCTAssertTrue(Self.code(try XCTUnwrap(sources["SettingsDesignSystem.swift"])).contains(".scrollContentBackground(.hidden)"),
                      "a Form paints its own background over the panel")
        XCTAssertEqual(Self.filesUsing(".scrollContentBackground(", in: sources), ["SettingsDesignSystem.swift"])
        XCTAssertEqual(Self.filesUsing(".scrollContentBackground(", in: ["Page.swift": "Form {}\n    .scrollContentBackground(.visible)\n"]), ["Page.swift"])
    }

    func testOnlyTheRootSetsTheFormStyle() throws {
        XCTAssertEqual(Self.filesSettingTheFormStyle(in: try Self.sources()), [])

        XCTAssertEqual(Self.filesSettingTheFormStyle(in: ["Page.swift": "Form {}\n    .formStyle(.grouped)\n"]), ["Page.swift"])
        XCTAssertEqual(Self.filesSettingTheFormStyle(in: ["Page.swift": "Form {}\n    .formStyle(.columns)\n"]), ["Page.swift"])
        XCTAssertEqual(Self.filesSettingTheFormStyle(in: ["Page.swift": "// .formStyle(.grouped) comes from the root\n"]), [])
        XCTAssertEqual(Self.filesSettingTheFormStyle(in: ["SettingsDesignSystem.swift": "formStyle(.grouped)"]), [])
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
        // The shapes this folder really writes: either arm of a ternary, and the other size labels.
        #"\.opacity\([^()\n]*\b\d*\.\d"#,
        #"\.padding\([^()\n]*[?:]\s*-?\d"#,
        #"\.(?:font|foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|tint)\([^()\n]*[?:]\s*\.[a-z]"#,
        #"\b(?:minWidth|idealWidth|maxWidth|minHeight|idealHeight|maxHeight|minLength|lineWidth|radius|duration):\s*(?!0(?:\.0+)?(?![.\d]))-?\d"#,
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
                      "RoundedRectangle(cornerRadius: 7)", ".opacity(0.5)", "VStack(spacing: 4)", "VStack(spacing: 0.5)", ".frame(width: 32)", ".frame(height: 18)",
                      ".opacity(isEnabled ? 1 : 0.45)", ".fill(configuration.isOn ? .blue : .gray)", ".font(isSmall ? .caption : .body)", ".padding(isSmall ? 3 : 8)",
                      ".foregroundStyle(on ? .white : .black)", ".frame(minWidth: 44)", ".frame(maxHeight: 18)", "Spacer(minLength: 8)", ".easeOut(duration: 0.15)",
                      ".strokeBorder(line, lineWidth: 2)", ".shadow(radius: 8)"] {
            XCTAssertFalse(Self.hardCodedValues(in: plant).isEmpty, "the rule misses \(plant)")
        }
        for clean in [".foregroundStyle(SettingsTheme.ink)", ".padding(SettingsTheme.buttonInset)", ".font(SettingsTheme.body)",
                      "VStack(spacing: 0)", "HStack(spacing: SettingsMetrics.rowContent)", ".frame(width: SettingsTheme.toggleWidth)",
                      "private var labelColor: NSColor", ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)",
                      ".opacity(!isEnabled ? SettingsTheme.disabledOpacity : configuration.isPressed ? SettingsTheme.pressedOpacity : 1)",
                      ".font(isSmall ? SettingsTheme.description : SettingsTheme.bodyStrong)", "Spacer(minLength: SettingsMetrics.rowContent)",
                      ".easeOut(duration: SettingsTheme.quickAnimation)", ".frame(maxWidth: .infinity)"] {
            XCTAssertEqual(Self.hardCodedValues(in: clean), [], clean)
        }
    }

    // MARK: - Fonts

    private static func filesNamingAFont(in sources: [String: String]) -> [String] {
        sources.filter { source in
            let text = code(source.value)
            return source.key != "SettingsTheme.swift" && (text.contains(".custom(") || text.contains("NSFont(name:"))
        }.keys.sorted()
    }

    func testOnlyTheThemeNamesAFont() throws {
        XCTAssertEqual(Self.filesNamingAFont(in: try Self.sources()), [])

        XCTAssertEqual(Self.filesNamingAFont(in: ["Page.swift": ".font(.custom(\"Geist-Regular\", size: 13))"]), ["Page.swift"])
        XCTAssertEqual(Self.filesNamingAFont(in: ["Page.swift": ".font(Font(NSFont(name: \"Geist-Regular\", size: 13)!))"]), ["Page.swift"])
        XCTAssertEqual(Self.filesNamingAFont(in: ["Page.swift": "// .custom( belongs in the theme"]), [])
        XCTAssertEqual(Self.filesNamingAFont(in: ["SettingsTheme.swift": ".custom(name, size: size)"]), [])
    }

    private static func fallbackProblems(in theme: String) -> [String] {
        ["geistIsAvailable ? .custom(name, size: size) : .system(size: size, weight: weight)",
         "mono: Font = geistMonoIsAvailable",
         ".system(size: 13, weight: .regular, design: .monospaced)"].filter { !theme.contains($0) }
    }

    func testTheThemeFallsBackToTheSystemFont() throws {
        let theme = try Self.theme()
        XCTAssertEqual(Self.fallbackProblems(in: theme), [], "with no font bundled the theme must keep the system font at the same size")
        Self.assertCaught([("geistIsAvailable ? .custom(name, size: size) : .system(size: size, weight: weight)", ".custom(name, size: size)"),
                           ("mono: Font = geistMonoIsAvailable", "mono: Font = true"),
                           (".system(size: 13, weight: .regular, design: .monospaced)", ".custom(\"GeistMono-Regular\", size: 13)")],
                          in: theme, by: Self.fallbackProblems)
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
        // The labels the button style really draws, on the fills it really draws them on: `card`
        // at rest and `selection` under the pointer.
        require("onPrimary", on: ["ink"], atLeast: 7)
        require("ink", on: ["selection"], atLeast: 7)
        require("destructive", on: ["card", "selection"], atLeast: 4.5)
        // The selected segment's title, on the fill it is raised on.
        require("ink", on: ["raised"], atLeast: 7)
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

        let faintOnHover = theme.replacingOccurrences(of: "destructive = color(light: 0xBC3226", with: "destructive = color(light: 0xC4362B")
        XCTAssertNotEqual(faintOnHover, theme, "the plant must change the theme")
        XCTAssertEqual(Self.readabilityFailures(in: faintOnHover), ["destructive on selection, light"])

        let darkRaised = theme.replacingOccurrences(of: "raised = color(light: 0xFFFFFF", with: "raised = color(light: 0x3A3A3A")
        XCTAssertNotEqual(darkRaised, theme, "the plant must change the theme")
        XCTAssertTrue(Self.readabilityFailures(in: darkRaised).contains("ink on raised, light"))
    }

    // MARK: - Every token has a reader

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
        XCTAssertEqual(Self.unreadTokens(theme: theme, others: others), [], "a token nothing reads is a stale value")

        XCTAssertEqual(Self.unreadTokens(theme: theme + "\nstatic let planted = color(light: 0x000000, dark: 0x000000)\n", others: others), ["planted"])
        // A longer name is not a reader, and a comment is not a reader.
        let plantedPair = "static let ink = 1\nstatic let inkSecondary = 2\nstatic let body = 3\nstatic let bodyStrong = 4\n"
        XCTAssertEqual(Self.unreadTokens(theme: plantedPair, others: ["SettingsTheme.inkSecondary", "SettingsTheme.bodyStrong"]), ["ink", "body"])
        XCTAssertEqual(Self.unreadTokens(theme: plantedPair, others: [Self.code("// SettingsTheme.ink, SettingsTheme.body")]),
                       ["ink", "inkSecondary", "body", "bodyStrong"])
        XCTAssertEqual(Self.unreadTokens(theme: "static let paper = color(windowPaper)\nstatic let windowPaper = 1\n", others: []), ["paper"])
    }

    /// The colours and fonts the board must name. Its lists are written by hand, so a new token could
    /// otherwise miss the one render that shows it. Measures have nothing to show by name.
    private static func tokensMissingFromTheBoard(theme: String, snapshots: String) -> [String] {
        groups(of: #"static let (\w+)(?:: Font\b| = (?:color|sans|Color)\()"#, in: theme).map { $0[1] }.filter { token in
            matches(of: "\\bSettingsTheme\\.\(token)\\b", in: snapshots).isEmpty
        }
    }

    func testTheBoardNamesEveryColourAndFont() throws {
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: try Self.theme(), snapshots: try Self.snapshotSource()), [])

        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let planted = color(light: 0x000000, dark: 0x000000)\n", snapshots: ""), ["planted"])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let planted = sans(13, .regular, \"Geist-Regular\")\n", snapshots: ""), ["planted"])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let planted: Font = geistMonoIsAvailable\n", snapshots: ""), ["planted"])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let paper = Color(nsColor: windowPaper)\n", snapshots: ""), ["paper"])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let ink = color(light: 0, dark: 0)\n", snapshots: "SettingsTheme.inkSecondary"), ["ink"])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let ink = color(light: 0, dark: 0)\n", snapshots: "SettingsTheme.ink"), [])
        XCTAssertEqual(Self.tokensMissingFromTheBoard(theme: "static let controlRadius: CGFloat = 7\nstatic let windowPaper = nsColor(light: 0, dark: 0)\n", snapshots: ""), [])
    }

    // MARK: - One type per file

    private static func topLevelTypes(in code: String) -> [String] {
        matches(of: #"(?m)^(?:@\w+\s+)*(?:(?:private|fileprivate|internal|public|open|final|indirect) )*(?:struct|class|enum|actor|protocol) "#, in: code)
    }

    func testOneTypePerDesignSystemFile() throws {
        for (name, source) in try Self.designSystemSources() {
            XCTAssertLessThanOrEqual(Self.topLevelTypes(in: Self.code(source)).count, 1, "\(name) declares more than one top-level type")
        }

        XCTAssertEqual(Self.topLevelTypes(in: "struct A {}\nprivate struct B {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "final class A {}\nenum B {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "struct A {\n    private struct B {}\n    enum C {}\n}\nextension A {}\n").count, 1)
        XCTAssertEqual(Self.topLevelTypes(in: "struct A {}\n@MainActor struct B {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "struct A {}\n@MainActor\nfinal class C {}\n").count, 2)
        XCTAssertEqual(Self.topLevelTypes(in: "struct A {}\nopen class D {}\n").count, 2)
    }

    // MARK: - Native controls that stay native

    private static let labelledRowStyles = [".toggleStyle(.checkbox)", ".pickerStyle(.radioGroup)"]

    /// Lines where a style the root's labelled-row style would pull apart has no opt-out in its chain.
    private static func stylesWithoutTheOptOut(in code: String, styles: [String] = labelledRowStyles) -> [String] {
        let lines = code.components(separatedBy: "\n")
        return lines.indices.filter { index in
            guard styles.contains(where: { lines[index].contains($0) }) else { return false }
            return !chain(around: index, in: lines).contains { $0.contains(".labeledContentStyle(.automatic)") }
        }.map { lines[$0].trimmingCharacters(in: .whitespaces) }
    }

    private static func filesUsing(_ style: String, in sources: [String: String]) -> [String] {
        sources.filter { code($0.value).contains(style) }.keys.sorted()
    }

    func testASwitchIsOurs() throws {
        let sources = try Self.sources()
        XCTAssertEqual(Self.filesUsing(".toggleStyle(.switch)", in: sources), ["SettingsToggleStyle.swift"])
        XCTAssertEqual(Self.filesUsing(".toggleStyle(.checkbox)", in: sources), ["NewTaskSheet.swift"])
        XCTAssertEqual(Self.code(try XCTUnwrap(sources["NewTaskSheet.swift"])).components(separatedBy: ".toggleStyle(.checkbox)").count - 1, 2)
        for (name, source) in sources {
            XCTAssertEqual(Self.stylesWithoutTheOptOut(in: Self.code(source)), [], "\(name): the root's labelled-row style pulls this control apart")
        }

        XCTAssertEqual(Self.filesUsing(".toggleStyle(.switch)", in: ["Page.swift": "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.switch)\n"]), ["Page.swift"])
        XCTAssertEqual(Self.filesUsing(".toggleStyle(.switch)", in: ["Page.swift": "// not .toggleStyle(.switch)\n"]), [])

        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.checkbox)\n").count, 1)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Picker(\"a\") {}\n    .pickerStyle(.radioGroup)\n    .labelsHidden()\n").count, 1)
        // The neighbour's opt-out is on the neighbour.
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Toggle(\"a\", isOn: $a)\n    .labeledContentStyle(.automatic)\nToggle(\"b\", isOn: $b)\n    .toggleStyle(.checkbox)\n").count, 1)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.checkbox)\n    .labeledContentStyle(.automatic)\n").count, 0)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Picker(\"a\") {}\n    .pickerStyle(.radioGroup)\n    .labeledContentStyle(.automatic)\n    .labelsHidden()\n").count, 0)
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: Self.code("// .toggleStyle(.checkbox) must opt out")).count, 0)
    }

    /// The opt-outs in the docs/SETTINGS.md table with no rule of their own. Each site is right today;
    /// without this, deleting one or adding a site without one stays green.
    func testTheNativeSitesStayNative() throws {
        let sources = try Self.sources()

        var links = 0
        for (name, source) in sources {
            let code = Self.code(source)
            links += Self.openers(of: "Link", in: code).count
            XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: code), [], "\(name): the root's button style draws this Link as a button")
            XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: code), [], "\(name): a custom toggle style ignores .labelsHidden()")
            XCTAssertEqual(Self.bareValuesWithoutAColour(in: code), [], "\(name): the root's labelled-row style leaves a bare value primary")
        }
        XCTAssertGreaterThan(links, 0, "the scan found no Link: the pattern went blind")

        let components = Self.code(try XCTUnwrap(sources["SettingsComponents.swift"]))
        XCTAssertEqual(Self.sharedComponentProblems(in: components), [])
        XCTAssertEqual(Self.code(try XCTUnwrap(sources["AllTasksPage.swift"])).components(separatedBy: ".disclosureGroupStyle(.automatic)").count - 1, 3,
                       "All tasks' long groups keep the native disclosure")
        let segmented = Self.code(try XCTUnwrap(sources["AnimationEditorView.swift"]))
        XCTAssertTrue(segmented.contains(".pickerStyle(.segmented)"), "the animation editor's segmented picker moved: this rule reads nothing")
        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: segmented, styles: [".pickerStyle(.segmented)"]), [])
        XCTAssertEqual(Self.filesUsing(".borderedProminent", in: sources), [], "a white label cannot be read on the root's eye blue in dark")
        XCTAssertTrue(Self.permissionRowsKeepTheSystemTint(in: Self.code(try XCTUnwrap(sources["GeneralSettings.swift"]))))

        XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: "Link(\"a\", destination: u)\n").count, 1)
        // A style on the next view is not on this one.
        XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: "Link(\"a\", destination: u)\nText(\"b\").buttonStyle(.link)\n").count, 1)
        XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: "Link(\"a\", destination: u)\n    .buttonStyle(.link)\n").count, 0)
        XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: "Link(destination: u) {\n    Text(\"a\")\n}\n.buttonStyle(.link)\n").count, 0)
        // Not a `Link` view.
        XCTAssertEqual(Self.linksWithoutTheLinkStyle(in: "struct Link {\n}\nNavigationLink(\"a\") {}\nRow.Link(title: t)\n").count, 0)

        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Toggle(\"a\", isOn: $a)\n    .labelsHidden()\n").count, 1)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Defaults.Toggle(key: .a) {\n    Text(\"a\")\n}\n.labelsHidden()\n").count, 1)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Toggle(\"a\", isOn: $a)\n    .labelsHidden()\nText(\"b\")\n    .toggleStyle(SettingsToggleStyle(showsLabel: false))\n").count, 1)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Toggle(\"a\", isOn: $a)\n    .labelsHidden()\n    .toggleStyle(SettingsToggleStyle(showsLabel: false))\n").count, 0)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Defaults.Toggle(key: .a) {\n    Text(\"a\")\n}\n.labelsHidden()\n.toggleStyle(SettingsToggleStyle(showsLabel: false))\n").count, 0)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Toggle(\"a\", isOn: $a)\n    .toggleStyle(.checkbox)\n    .labelsHidden()\n").count, 0)
        XCTAssertEqual(Self.hiddenLabelsTheStyleCannotSee(in: "Toggle(\"a\", isOn: $a)\n").count, 0)

        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent(\"a\") {\n    Text(\"b\")\n}\n").count, 1)
        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent {\n    Text(\"b\")\n        .textSelection(.enabled)\n} label: {\n    Text(\"a\")\n}\n").count, 1)
        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent(\"a\") {\n    Text(\"b\")\n        .foregroundStyle(.secondary)\n}\n").count, 0)
        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent(\"a\") {\n    Text(\"b\").foregroundColor(.secondary)\n}\n").count, 0)
        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent(\"a\") {\n    Text(\"b\")\n        .settingsDescriptionStyle()\n}\n").count, 0)
        XCTAssertEqual(Self.bareValuesWithoutAColour(in: "LabeledContent(\"a\") {\n    TextField(\"b\", text: $b)\n}\n").count, 0)

        XCTAssertEqual(Self.stylesWithoutTheOptOut(in: "Picker(\"a\") {}\n    .pickerStyle(.segmented)\n", styles: [".pickerStyle(.segmented)"]).count, 1)
        XCTAssertEqual(Self.filesUsing(".borderedProminent", in: ["Page.swift": "Button(\"a\") {}\n    .buttonStyle(.borderedProminent)\n"]), ["Page.swift"])

        let rows = "LaunchPermissionRow(permission: p)\n    }\n}\n"
        XCTAssertTrue(Self.permissionRowsKeepTheSystemTint(in: rows + ".tint(.accentColor)\n"))
        XCTAssertFalse(Self.permissionRowsKeepTheSystemTint(in: rows + ".settingsHighlight(id: i)\n"))
        XCTAssertFalse(Self.permissionRowsKeepTheSystemTint(in: "Text(\"a\")\n.tint(.accentColor)\n"))

        Self.assertCaught([("SettingsToggleStyle(showsLabel: false)", "SettingsToggleStyle()"),
                           (".labeledContentStyle(.automatic)", ""),
                           ("struct SettingsActionRow", "struct RenamedActionRow"),
                           ("struct SettingsRow<", "struct RenamedRow<")],
                          in: components, by: Self.sharedComponentProblems)
    }

    /// `Link`s the root's button style would draw as buttons.
    private static func linksWithoutTheLinkStyle(in code: String) -> [String] {
        calls(of: "Link", in: code) { !$0.contains(".buttonStyle(.link)") }
    }

    /// Toggles with `.labelsHidden()` whose style still draws the label: only `showsLabel: false`
    /// hides it from ours, and a native checkbox reads the modifier itself.
    private static func hiddenLabelsTheStyleCannotSee(in code: String) -> [String] {
        (calls(of: "Toggle", in: code) { Self.hidesALabelOnlyByTheModifier($0) }
            + calls(of: "Defaults.Toggle", in: code) { Self.hidesALabelOnlyByTheModifier($0) })
    }

    private static func hidesALabelOnlyByTheModifier(_ chain: String) -> Bool {
        chain.contains(".labelsHidden()") && !chain.contains("showsLabel: false") && !chain.contains(".toggleStyle(.checkbox)")
    }

    /// A `Text` straight inside a `LabeledContent` with no colour of its own: the root's labelled-row
    /// style leaves it primary, where a native row would grey it.
    private static func bareValuesWithoutAColour(in code: String) -> [String] {
        groups(of: #"LabeledContent[^\n]*\{\s*\n\s*(Text\([^\n]*)((?:\n\s*\.[^\n]*)*)"#, in: code).compactMap { match in
            let call = match[1] + match[2]
            let coloured = call.contains(".foregroundStyle(") || call.contains(".foregroundColor(") || call.contains("settingsDescriptionStyle(")
            return coloured ? nil : match[1].trimmingCharacters(in: .whitespaces)
        }
    }

    /// `LaunchPermissionRow` lives in `Onboarding/`, so no scan here reads its `.borderedProminent`.
    private static func permissionRowsKeepTheSystemTint(in general: String) -> Bool {
        !matches(of: #"LaunchPermissionRow\([^\n]*\n\s*\}\n\s*\}\s*\.tint\(\.accentColor\)"#, in: general).isEmpty
    }

    private static func toggleProblems(in toggle: String) -> [String] {
        var problems = ["Button {", ".accessibilityRepresentation", "accessibilityReduceMotion"].filter { !toggle.contains($0) }
        // One dim, and its own: what `.plain` does to a disabled fill is the system's to change, and
        // the two together lose the knob in the track (seen on the designSystem board).
        if toggle.components(separatedBy: ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)").count != 2 {
            problems.append("a disabled switch needs exactly one dim of its own")
        }
        if toggle.contains(".buttonStyle(.plain)") { problems.append("`.plain` dims a disabled switch a second time") }
        return problems
    }

    private static func disclosureProblems(in disclosure: String) -> [String] {
        // The button holds a `Spacer`, so without the priority a description wraps at half the row
        // (seen on the agentSecurity board).
        let problems = ["accessibilityReduceMotion", ".accessibilityValue", ".accessibilityElement(children: .combine)",
                        ".layoutPriority(1)"].filter { !disclosure.contains($0) }
        // A description is selectable, and selectable text inside a button fights for the click.
        guard let title = disclosure.range(of: "configuration.label")?.lowerBound,
              let button = disclosure.range(of: "Button {")?.lowerBound,
              title < button else { return problems + ["the button must start after the title"] }
        return problems
    }

    func testTheControlsKeepKeyboardAndVoiceOver() throws {
        let sources = try Self.designSystemSources().mapValues(Self.code)
        let toggle = try XCTUnwrap(sources["SettingsToggleStyle.swift"])
        XCTAssertEqual(Self.toggleProblems(in: toggle), [])
        let dim = ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)"
        Self.assertCaught([("Button {", "Group {"), (".accessibilityRepresentation", ".accessibilityHidden"),
                           ("accessibilityReduceMotion", "accessibilityInvertColors"), (dim, ""), (dim, dim + dim),
                           (".buttonStyle(TrackButtonStyle())", ".buttonStyle(.plain)")],
                          in: toggle, by: Self.toggleProblems)

        let disclosure = try XCTUnwrap(sources["SettingsDisclosureGroupStyle.swift"])
        XCTAssertEqual(Self.disclosureProblems(in: disclosure), [])
        Self.assertCaught([("accessibilityReduceMotion", "accessibilityInvertColors"), (".accessibilityValue", ".accessibilityHint"),
                           (".accessibilityElement(children: .combine)", ".accessibilityElement(children: .ignore)"),
                           (".layoutPriority(1)", "")],
                          in: disclosure, by: Self.disclosureProblems)
        let wrapped = "Button {\n} label: {\n    configuration.label\n}\naccessibilityReduceMotion .accessibilityValue .accessibilityElement(children: .combine) .layoutPriority(1)\n"
        XCTAssertEqual(Self.disclosureProblems(in: wrapped), ["the button must start after the title"])
    }

    /// What a press, a hover and a squeeze must leave alone. A custom style's label can be squeezed
    /// where a native button's cannot: a row broke "Acknowledgements" across two lines before this.
    private static func buttonProblems(in button: String) -> [String] {
        [".fixedSize(horizontal: true, vertical: false)",
         ".opacity(!isEnabled ? SettingsTheme.disabledOpacity : configuration.isPressed ? SettingsTheme.pressedOpacity : 1)",
         "isEnabled && (configuration.isPressed || isHovering)"].filter { !button.contains($0) }
    }

    func testAButtonKeepsItsWidthAndShowsAPress() throws {
        let button = Self.code(try XCTUnwrap(try Self.designSystemSources()["SettingsButtonStyle.swift"]))
        XCTAssertEqual(Self.buttonProblems(in: button), [])
        Self.assertCaught([(".fixedSize(horizontal: true, vertical: false)", ""),
                           ("configuration.isPressed ? SettingsTheme.pressedOpacity : 1", "1"),
                           ("isEnabled && (configuration.isPressed || isHovering)", "(configuration.isPressed || isHovering)")],
                          in: button, by: Self.buttonProblems)
    }

    /// What the select keeps: VoiceOver's label, value and adjust, a trigger in our button style, a list that
    /// closes with Brain, the arrows on a segment, one dim of its own, and an ease that Reduce Motion stops.
    private static func selectProblems(in select: String) -> [String] {
        var problems = [".accessibilityAdjustableAction", ".accessibilityValue(", ".accessibilityLabel(title)",
                        ".onDisappear { isOpen = false }", ".buttonStyle(SettingsButtonStyle())",
                        ".accessibilityAddTraits(option == selection ? .isSelected : [])",
                        ".onKeyPress(keys: [.leftArrow, .rightArrow])",
                        "reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation)",
                        "guard isEnabled else { return }"].filter { !select.contains($0) }
        if select.components(separatedBy: ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)").count != 2 {
            problems.append("a disabled segment needs exactly one dim of its own")
        }
        if select.contains(".buttonStyle(.plain)") { problems.append("`.plain` dims a disabled segment a second time") }
        return problems
    }

    /// What the open list keeps: a key monitor for its own key window only, out of an input method's way and gone
    /// with the list; Return and Escape in the field and in the list; letters when it has no field; rows that never
    /// take the keyboard; a highlight that is announced and a selection that says so; the threshold; the field's chrome.
    private static func selectListProblems(in list: String) -> [String] {
        ["event.window === window", "window.isKeyWindow", "hasMarkedText()", "NSEvent.removeMonitor", "dismantleNSView",
         ".onSubmit", ".onExitCommand(perform: close)", ".onKeyPress(.return)", ".onKeyPress(.escape)",
         ".onKeyPress(characters:", ".focusable(false)", "AccessibilityNotification.Announcement(",
         ".accessibilityAddTraits(option == selection ? .isSelected : [])", "SettingsSelectNavigation.searchThreshold",
         ".settingsField("].filter { !list.contains($0) }
    }

    func testTheSelectKeepsKeyboardVoiceOverAndReduceMotion() throws {
        let sources = try Self.designSystemSources().mapValues(Self.code)
        let select = try XCTUnwrap(sources["SettingsSelect.swift"])
        XCTAssertEqual(Self.selectProblems(in: select), [])
        let dim = ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)"
        Self.assertCaught([(".accessibilityAdjustableAction", ".accessibilityAction"),
                           (".accessibilityValue(", ".accessibilityHint("),
                           (".accessibilityLabel(title)", ".accessibilityHidden(true)"),
                           (".onDisappear { isOpen = false }", ""),
                           (".buttonStyle(SettingsButtonStyle())", ".buttonStyle(BorderlessButtonStyle())"),
                           (".accessibilityAddTraits(option == selection ? .isSelected : [])", ""),
                           (".onKeyPress(keys: [.leftArrow, .rightArrow])", ".onKeyPress(keys: [.upArrow, .downArrow])"),
                           ("reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation)",
                            ".easeOut(duration: SettingsTheme.quickAnimation)"),
                           ("guard isEnabled else { return }", ""),
                           (dim, ""), (dim, dim + dim),
                           (".buttonStyle(SegmentButtonStyle())", ".buttonStyle(.plain)")],
                          in: select, by: Self.selectProblems)

        let list = try XCTUnwrap(sources["SettingsSelectList.swift"])
        XCTAssertEqual(Self.selectListProblems(in: list), [])
        // `event.window === window` emptied is a monitor that answers for any window.
        Self.assertCaught([("event.window === window", ""), ("window.isKeyWindow", "true"),
                           ("hasMarkedText()", "isEditable"), ("NSEvent.removeMonitor", "print"),
                           ("dismantleNSView", "dismantleView"), (".onSubmit", ".onAppear"),
                           (".onExitCommand(perform: close)", ""), (".onKeyPress(.return)", ".onKeyPress(.space)"),
                           (".onKeyPress(.escape)", ".onKeyPress(.tab)"), (".onKeyPress(characters:", ".onKeyPress(keys:"),
                           (".focusable(false)", ".focusable()"), ("AccessibilityNotification.Announcement(", "print("),
                           (".accessibilityAddTraits(option == selection ? .isSelected : [])", ""),
                           ("SettingsSelectNavigation.searchThreshold", "3"), (".settingsField(", ".textFieldStyle(")],
                          in: list, by: Self.selectListProblems)
    }

    /// What `SettingsField` keeps: the field native and plain inside our chrome, its label hidden for the one beside
    /// it, its own focus where the caller keeps none, one dim, and never a send-on-Return of its own:
    /// `WorklogConsentRulesTests` finds one by the literal modifier, and a parameter would slip past it.
    private static func fieldProblems(in field: String) -> [String] {
        var problems = [".textFieldStyle(.plain)", ".labelsHidden()", "content.focused($tracksFocus)"].filter { !field.contains($0) }
        if field.components(separatedBy: ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)").count != 2 {
            problems.append("a disabled field needs exactly one dim of its own")
        }
        if field.contains("onSubmit") { problems.append("the field's chrome takes no onSubmit") }
        return problems
    }

    func testTheFieldStaysNativeInside() throws {
        let field = Self.code(try XCTUnwrap(try Self.designSystemSources()["SettingsField.swift"]))
        XCTAssertEqual(Self.fieldProblems(in: field), [])
        let dim = ".opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)"
        Self.assertCaught([(".textFieldStyle(.plain)", ".textFieldStyle(.roundedBorder)"), (".labelsHidden()", ""),
                           ("content.focused($tracksFocus)", "content"), (dim, ""), (dim, dim + dim),
                           ("let isFocused: Bool?", "let isFocused: Bool?\n    let onSubmit: () -> Void")],
                          in: field, by: Self.fieldProblems)
    }

    /// The shared components the root would otherwise change. Its font replaces what a grouped `Form`
    /// gives headers and footers, so they say theirs, or every section header goes light and every
    /// footer grows. Its one-line row would squeeze a titled action row's description, and its switch
    /// would still draw a label in a row that draws the title itself.
    private static func sharedComponentProblems(in components: String) -> [String] {
        let required = [("SettingsSectionHeader", ".font(SettingsTheme.sectionTitle)"),
                        ("SettingsFooter", ".font(SettingsTheme.description)"),
                        ("SettingsActionRow", ".labeledContentStyle(.automatic)"),
                        ("SettingsRow", "SettingsToggleStyle(showsLabel: false)")]
        return required.compactMap { component, modifier -> String? in
            guard let start = components.range(of: "struct \(component)[:<]", options: .regularExpression) else { return "\(component) is gone" }
            let end = components.range(of: "\n}\n", range: start.upperBound..<components.endIndex)?.lowerBound ?? components.endIndex
            return components[start.lowerBound..<end].contains(modifier) ? nil : "\(component) lost \(modifier)"
        }
    }

    func testSectionHeadersAndFootersKeepTheirOwnType() throws {
        let components = Self.code(try XCTUnwrap(try Self.sources()["SettingsComponents.swift"]))
        XCTAssertEqual(Self.sharedComponentProblems(in: components), [])
        Self.assertCaught([(".font(SettingsTheme.sectionTitle)", ""), ("            .font(SettingsTheme.description)\n", ""),
                           ("struct SettingsSectionHeader", "struct RenamedHeader"), ("struct SettingsFooter:", "struct RenamedFooter:")],
                          in: components, by: Self.sharedComponentProblems)
    }

    /// A root button style takes a default-style `Menu`'s indicator away, and the only cures are the
    /// borderless menu style or a native button style on the menu itself.
    private static func menusWithoutAnIndicator(in code: String) -> [String] {
        calls(of: "Menu", in: code) { !($0.contains(".menuStyle(.borderlessButton)") || $0.contains(".buttonStyle(.bordered)")) }
    }

    /// The start of each call of `name` whose modifier chain `isOffender` picks.
    private static func calls(of name: String, in code: String, whereChain isOffender: (String) -> Bool) -> [String] {
        let characters = Array(code)
        return openers(of: name, in: code).compactMap { opener in
            guard isOffender(modifierChain(after: opener, nameLength: name.count, in: characters)) else { return nil }
            return String(characters[opener..<min(opener + 24, characters.count)])
        }
    }

    /// Where each call of `name` opens, as a `Character` offset. Not `SomeMenu(`, `foo.Menu(`,
    /// `resetMenu` or `struct Link {`.
    private static func openers(of name: String, in code: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z.])(?<!struct )"# + NSRegularExpression.escapedPattern(for: name) + #"(?: \{|\()"#) else {
            XCTFail("bad pattern for \(name)")
            return []
        }
        return regex.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
            Range(match.range, in: code).map { code.distance(from: code.startIndex, to: $0.lowerBound) }
        }
    }

    /// What is chained onto the call opening at `start`, past its arguments and every trailing
    /// closure, `label:` included. A modifier inside a closure is on something else.
    private static func modifierChain(after start: Int, nameLength: Int, in characters: [Character]) -> String {
        var index = start + nameLength
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
            } else if String(characters[index...].prefix(16)) == "headerAccessory:" {
                index += 16
            } else if String(characters[index...].prefix(7)) == "detail:" {
                index += 7
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
            openers += Self.openers(of: "Menu", in: code).count
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
                && !chain(around: index, in: lines).contains { $0.contains("SettingsButtonStyle(.primary)") }
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
        // The neighbour's primary style is on the neighbour.
        XCTAssertEqual(Self.flatDefaultActions(in: "Button(\"Cancel\") {}\n    .buttonStyle(SettingsButtonStyle(.primary))\nButton(\"Save\") {}\n    .keyboardShortcut(.defaultAction)\n").count, 1)
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

    /// The source with every comment blanked and every line kept, so line numbers still mean what they
    /// do in the file. Strings are respected: a URL's `//` is not a comment.
    static func code(_ source: String) -> String {
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

    /// The modifier chain a line sits in: back to the view it modifies, forward to its last modifier.
    /// A fixed window would let a neighbouring view's modifier pass for this one's.
    private static func chain(around index: Int, in lines: [String]) -> ArraySlice<String> {
        func continues(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix(".")
        }
        var first = index
        while first > 0, continues(lines[first]) { first -= 1 }
        var last = index
        while last + 1 < lines.count, continues(lines[last + 1]) { last += 1 }
        return lines[first...last]
    }

    /// Each edit must change `source`, and `problems` must report the result.
    static func assertCaught(_ edits: [(from: String, to: String)], in source: String, by problems: (String) -> [String],
                                     file: StaticString = #filePath, line: UInt = #line) {
        for edit in edits {
            let edited = source.replacingOccurrences(of: edit.from, with: edit.to)
            XCTAssertNotEqual(edited, source, "the plant must change the source: \(edit.from)", file: file, line: line)
            XCTAssertFalse(problems(edited).isEmpty, "the rule misses this edit: \(edit.from)", file: file, line: line)
        }
    }

    static func matches(of pattern: String, in text: String) -> [String] {
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
