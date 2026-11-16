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

/// `brainAppearance` reaches Brain's window and nothing else: the notch stays dark, and every other
/// window follows macOS. Windows are not in this logic target, so the rule is read from code with its
/// comments blanked, since `applyBrainAppearance`'s own doc comment names `NSApp.appearance`, and is
/// proved against planted offenders.
final class BrainAppearanceRulesTests: XCTestCase {

    private static let controller = "components/Settings/SettingsWindowController.swift"
    private static let snapshots = "helpers/DebugSnapshot.swift"
    private static let toggle = "components/Settings/DesignSystem/SettingsAppearanceToggle.swift"
    private static let page = "components/Settings/AppearanceSettings.swift"
    private static let constants = "models/Constants.swift"
    private static let notchWindow = "components/Notch/KannuWindow.swift"
    /// The menu bar's View › Appearance: the moon's three choices, through its own `@Default`.
    private static let menuBar = "KannuApp.swift"

    /// Every file under `Kannu/` that names an appearance, by its path from there.
    private static func sources() throws -> [String: String] {
        let kannu = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kannu", isDirectory: true)
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: kannu, includingPropertiesForKeys: nil))
        var sources: [String: String] = [:]
        for case let file as URL in walker where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("ppearance") || source.contains("preferredColorScheme") else { continue }
            sources[String(file.path.dropFirst(kannu.path.count + 1))] = SettingsDesignSystemRulesTests.code(source)
        }
        return sources
    }

    private static func files(in sources: [String: String], matching pattern: String) -> Set<String> {
        Set(sources.filter { !SettingsDesignSystemRulesTests.matches(of: pattern, in: $0.value).isEmpty }.keys)
    }

    private static func problems(in sources: [String: String]) -> [String] {
        var problems: [String] = []
        // Not `==`: reading a window's appearance is fine.
        let writers = files(in: sources, matching: #"\.appearance\s*=(?!=)"#)
        if writers != [controller, snapshots] { problems.append("these set a window's appearance: \(writers.sorted())") }
        // A window that sets its own, with no receiver. The notch's is the only one.
        let ownWriters = files(in: sources, matching: #"(?<![\w.])appearance\s*=\s*(?:NSAppearance\b|\.init\b|nil\b)"#)
        if ownWriters != [notchWindow] { problems.append("these set their own appearance: \(ownWriters.sorted())") }
        // Only the moon, the row and View › Appearance write the key, each through its `@Default`.
        let keyWriters = files(in: sources, matching: #"Defaults\[\.brainAppearance\]\s*=(?!=)"#)
        if !keyWriters.isEmpty { problems.append("these write the key directly: \(keyWriters.sorted())") }
        let global = files(in: sources, matching: #"\bNSApp(?:lication\.shared)?\??\.appearance\b"#)
        if !global.isEmpty { problems.append("these touch every window through the app: \(global.sorted())") }
        let forced = files(in: sources, matching: #"\bpreferredColorScheme\b"#)
        if !forced.isEmpty { problems.append("these force a colour scheme: \(forced.sorted())") }
        // Word boundaries: not `brainAppearanceObserver`, and not the capitalised enum.
        let readers = files(in: sources, matching: #"\bbrainAppearance\b"#)
        if readers != [controller, toggle, page, constants, menuBar] { problems.append("these name the key: \(readers.sorted())") }
        return problems
    }

    private static func controllerProblems(in code: String) -> [String] {
        var problems = ["applyBrainAppearance(Defaults[.brainAppearance])",
                        "Defaults.publisher(.brainAppearance, options: [])",
                        "self?.applyBrainAppearance(change.newValue)",
                        "case .system: window?.appearance = nil",
                        "case .light: window?.appearance = NSAppearance(named: .aqua)",
                        "case .dark: window?.appearance = NSAppearance(named: .darkAqua)"].filter { !code.contains($0) }
        // The first apply comes first, or the first open can flash the other appearance.
        if let first = code.range(of: "applyBrainAppearance(Defaults[.brainAppearance])"),
           let observer = code.range(of: "Defaults.publisher(.brainAppearance"), observer.lowerBound < first.lowerBound {
            problems.append("the first apply waits for the observer")
        }
        if !code.contains("observeBrainAppearance()\n") { problems.append("nothing starts the observer") }
        let assignments = SettingsDesignSystemRulesTests.matches(of: #"[\w?.!]*\.appearance\s*=(?!=)"#, in: code)
        if Set(assignments) != ["window?.appearance ="] { problems.append("it sets more than its own window's: \(assignments)") }
        return problems
    }

    func testTheKeyReachesBrainsWindowAndNothingElse() throws {
        let sources = try Self.sources()
        for path in [Self.controller, Self.snapshots, Self.toggle, Self.page, Self.constants, Self.notchWindow, Self.menuBar] {
            XCTAssertNotNil(sources[path], "\(path) was not read, so this rule proves less than it says")
        }
        XCTAssertEqual(Self.problems(in: sources), [])
    }

    func testTheRuleCatchesAPlantedOffender() throws {
        let real = try Self.sources()
        let plants = ["NSApp.appearance = NSAppearance(named: .darkAqua)",
                      "NSApp?.appearance = nil",
                      "NSApplication.shared.appearance = nil",
                      "panel.appearance = NSAppearance(named: .aqua)",
                      "window?.appearance = nil",
                      "appearance = NSAppearance(named: .aqua)",
                      "appearance = .init(named: .aqua)",
                      "appearance = NSAppearance.init(named: .aqua)",
                      "appearance = nil",
                      "self.appearance=NSAppearance(named: .aqua)",
                      ".preferredColorScheme(.dark)",
                      "let choice = Defaults[.brainAppearance]",
                      "@Default(.brainAppearance) private var appearance"]
        for plant in plants {
            var planted = real
            planted["components/Notch/Planted.swift"] = plant
            XCTAssertFalse(Self.problems(in: planted).isEmpty, "the rule misses: \(plant)")
        }

        // In a file already allowed to name the key, so only the writers' pattern can catch it.
        var directWrite = real
        directWrite[Self.controller, default: ""] += "\nDefaults[.brainAppearance] = .system"
        XCTAssertFalse(Self.problems(in: directWrite).isEmpty, "the rule misses a direct write to the key")

        // What it must leave alone.
        for harmless in ["if window.appearance == other { }",
                         "let look = window.effectiveAppearance",
                         "appearance = colorScheme == .dark ? .light : .dark",
                         "private var brainAppearanceObserver: AnyCancellable?",
                         "let choice: BrainAppearance = .system",
                         SettingsDesignSystemRulesTests.code("// NSApp.appearance = nil, .preferredColorScheme(.dark), Defaults[.brainAppearance]")] {
            var planted = real
            planted["components/Notch/Planted.swift"] = harmless
            XCTAssertEqual(Self.problems(in: planted), [], "the rule objects to: \(harmless)")
        }

        // A reader that goes away is as wrong as one that arrives: it would leave the moon or the row dead.
        for path in [Self.controller, Self.toggle, Self.page, Self.constants, Self.notchWindow, Self.snapshots] {
            var planted = real
            planted[path] = ""
            XCTAssertFalse(Self.problems(in: planted).isEmpty, "the rule misses \(path) going quiet")
        }
    }

    func testTheControllerAppliesItAndKeepsItsOwnWindow() throws {
        let code = try XCTUnwrap(try Self.sources()[Self.controller])
        XCTAssertEqual(Self.controllerProblems(in: code), [])

        SettingsDesignSystemRulesTests.assertCaught(
            [("options: []", "options: [.initial]"),
             ("applyBrainAppearance(Defaults[.brainAppearance])\n", "\n"),
             ("self?.applyBrainAppearance(change.newValue)", "_ = change"),
             ("case .system: window?.appearance = nil", "case .system: window?.appearance = NSAppearance(named: .aqua)"),
             ("case .light: window?.appearance = NSAppearance(named: .aqua)", "case .light: NSApp.appearance = NSAppearance(named: .aqua)"),
             ("case .dark: window?.appearance = NSAppearance(named: .darkAqua)", "case .dark: break"),
             // The observer first: the window opens in the wrong appearance until the publisher speaks.
             ("applyBrainAppearance(Defaults[.brainAppearance])\n        brainAppearanceObserver = Defaults.publisher(.brainAppearance, options: [])",
              "brainAppearanceObserver = Defaults.publisher(.brainAppearance, options: [])\n        applyBrainAppearance(Defaults[.brainAppearance])\n        _ = brainAppearanceObserver"),
             ("observeBrainAppearance()\n", "\n"),
             // Every pinned line stays, so only the check on what it assigns can catch this.
             ("case .system: window?.appearance = nil", "case .system: window?.appearance = nil; NSColorPanel.shared.appearance = nil")],
            in: code, by: Self.controllerProblems)
    }

    private static func notchProblems(in code: String) -> [String] {
        code.contains("appearance = NSAppearance(named: .darkAqua)") ? [] : ["the notch no longer forces dark, so its text can vanish in light mode"]
    }

    /// The notch's own line, which the patterns above treat as the one exception: it stays dark.
    func testTheNotchStaysDark() throws {
        let code = try XCTUnwrap(try Self.sources()[Self.notchWindow])
        XCTAssertEqual(Self.notchProblems(in: code), [])
        SettingsDesignSystemRulesTests.assertCaught(
            [("named: .darkAqua", "named: .aqua"),
             ("appearance = NSAppearance(named: .darkAqua)", "")],
            in: code, by: Self.notchProblems)
    }

    /// The moon only picks the opposite of what is on screen, so this is the one way back to Match macOS.
    private static func rowProblems(in page: String) -> [String] {
        ["options: BrainAppearance.allCases", "selection: $brainAppearance", ".settingsHighlight(id: highlightID(\"Brain appearance\"))"]
            .filter { !page.contains($0) }
    }

    func testThePageOffersEveryChoice() throws {
        let page = try XCTUnwrap(try Self.sources()[Self.page])
        XCTAssertEqual(Self.rowProblems(in: page), [])
        SettingsDesignSystemRulesTests.assertCaught(
            [("options: BrainAppearance.allCases", "options: [BrainAppearance.light, .dark]"),
             ("selection: $brainAppearance", "selection: .constant(BrainAppearance.system)"),
             (".settingsHighlight(id: highlightID(\"Brain appearance\"))", "")],
            in: page, by: Self.rowProblems)
    }
}
