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

/// Kannu 2.0's What's New window (openspec `whats-new`) opens once, for people who update: never before the Terms of
/// Use are accepted, never on a fresh install, never while onboarding runs, and never again once closed. The window is
/// AppKit and SwiftUI, so its rules are read from the source, as `LaunchGateRulesTests` and `FirstLaunchRulesTests`
/// read theirs; `WhatsNewTests` holds the decision's truth table. Nothing here builds or opens the window.
///
/// Never before the Terms holds because the window is decided and opened in `continueLaunch()` alone, which runs only
/// once the terms are accepted (`LaunchGateRulesTests`). Never a permission dialog holds because the window's files
/// touch nothing that asks, and `FirstLaunchRulesTests` pins every prompt-raising call to its gated files.
final class WhatsNewRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let app = "Kannu/KannuApp.swift"
    private static let view = "Kannu/components/WhatsNew/WhatsNewView.swift"
    private static let window = "Kannu/components/WhatsNew/WhatsNewWindow.swift"
    private static let snapshots = "Kannu/helpers/DebugSnapshot.swift"
    private static let onboarding = "Kannu/components/Onboarding/OnboardingView.swift"
    private static let settings = "Kannu/components/Settings/SettingsView.swift"
    private static let constants = "Kannu/models/Constants.swift"
    private static let coordinator = "Kannu/KannuViewCoordinator.swift"

    private static let watched = [app, view, window, snapshots, onboarding, settings, constants, coordinator]

    func testTheWindowFollowsTheRules() throws {
        XCTAssertEqual(Self.problems(in: try Self.sources()), [])
    }

    func testTheScannerCatchesEachBrokenRule() throws {
        let sources = try Self.sources()
        func planted(_ path: String, _ old: String, _ new: String) -> [String: String] {
            var copy = sources
            copy[path] = copy[path]?.replacingOccurrences(of: old, with: new)
            XCTAssertNotEqual(copy[path], sources[path], "the plant did not take in \(path): \(old)")
            return copy
        }
        let gateCall = "        startLaunchInvariants()\n"

        // Never before the Terms of Use.
        XCTAssertEqual(Self.problems(in: planted(Self.app, gateCall,
            gateCall + "        _ = WhatsNew.decision(isUpgrade: true, onboardingComplete: true, seenEdition: 0)\n")),
                       ["What's New is decided outside continueLaunch()"])
        XCTAssertEqual(Self.problems(in: planted(Self.app, gateCall, gateCall + "        showWhatsNewWindow()\n")),
                       ["What's New opens outside continueLaunch()"])

        // Never on a fresh install.
        XCTAssertEqual(Self.problems(in: planted(Self.app, "isUpgrade: isUpgrade,", "isUpgrade: true,")),
                       ["What's New can open on a fresh install"])
        XCTAssertEqual(Self.problems(in: planted(Self.app,
            "            case .markSeen:\n                Defaults[.whatsNewSeenEdition] = WhatsNew.currentEdition\n",
            "            case .markSeen:\n                break\n")),
                       ["a fresh install's first launch no longer counts What's New as seen"])

        // Never during onboarding.
        XCTAssertEqual(Self.problems(in: planted(Self.app, "onboardingComplete: LaunchPermissionManager.isOnboardingComplete,",
                                                 "onboardingComplete: true,")),
                       ["What's New can open during onboarding"])
        XCTAssertEqual(Self.problems(in: planted(Self.onboarding, "    let onFinish: () -> Void\n",
                                                 "    let onFinish: () -> Void\n    let whatsNew = WhatsNewContent.kannu2()\n")),
                       ["What's New can open during onboarding"])

        // Shown once.
        XCTAssertEqual(Self.problems(in: planted(Self.app, "seenEdition: Defaults[.whatsNewSeenEdition])", "seenEdition: 0)")),
                       ["closing What's New no longer counts it as seen"])
        XCTAssertEqual(Self.problems(in: planted(Self.app,
            "        Defaults[.whatsNewSeenEdition] = WhatsNew.currentEdition\n        whatsNewWindow = nil\n",
            "        whatsNewWindow = nil\n")),
                       ["closing What's New no longer counts it as seen"])
        XCTAssertEqual(Self.problems(in: planted(Self.window, "        onClose?()\n", "")),
                       ["closing What's New no longer counts it as seen"])
        XCTAssertEqual(Self.problems(in: planted(Self.app, "if !AppRuntimeEnvironment.isUITesting {\n            switch WhatsNew.decision(",
                                                 "if true {\n            switch WhatsNew.decision(")),
                       ["What's New opens under UI testing"])

        // The keyboard, VoiceOver and Reduce Motion.
        XCTAssertEqual(Self.problems(in: planted(Self.view, "                .keyboardShortcut(.defaultAction)\n", "")),
                       ["Return no longer presses Continue"])
        XCTAssertEqual(Self.problems(in: planted(Self.window, "event.keyCode == Self.escapeKeyCode", "event.keyCode == 36")),
                       ["Escape no longer closes What's New"])
        XCTAssertEqual(Self.problems(in: planted(Self.view, "        .settingsDesignSystem()\n",
                                                 "        .settingsDesignSystem()\n        .animation(.default, value: content)\n")),
                       ["something in What's New animates"])
        XCTAssertEqual(Self.problems(in: planted(Self.window,
            "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .default", ".default")),
                       ["the What's New window animates under Reduce Motion"])
        XCTAssertEqual(Self.problems(in: planted(Self.view, "        .accessibilityElement(children: .combine)\n", "")),
                       ["VoiceOver no longer reads each card's title and text together"])

        // Brain's theme, the window's size, the board and the keys.
        XCTAssertEqual(Self.problems(in: planted(Self.view, ".font(SettingsTheme.cardTitle)", ".font(.headline)")),
                       ["What's New leaves Brain's theme"])
        XCTAssertEqual(Self.problems(in: planted(Self.view, ".background(SettingsTheme.panel)", ".background(Color.white)")),
                       ["What's New leaves Brain's theme"])
        XCTAssertEqual(Self.problems(in: planted(Self.window, "window.setHostedContent(hostingView)", "window.contentView = hostingView")),
                       ["SwiftUI can size the What's New window"])
        XCTAssertEqual(Self.problems(in: planted(Self.snapshots, "WhatsNewView(content: DebugSnapshotFixtures.whatsNew(language: \"en\")",
                                                 "WhatsNewView(content: .kannu2()")),
                       ["the What's New board no longer draws its fixture"])
        XCTAssertEqual(Self.problems(in: planted(Self.view, "title: String(localized: \"Tasks\", bundle: bundle)",
                                                 "title: String(localized: \"Task list\", bundle: bundle)")),
                       ["the Tasks card no longer shares the sidebar's key"])
        XCTAssertEqual(Self.problems(in: planted(Self.coordinator, "    @Published var notchEye = NotchEyeState.settled\n",
            "    @Published var notchEye = NotchEyeState.settled\n    @AppStorage(\"showWhatsNew\") var showWhatsNew: Bool = true\n")),
                       ["What's New's seen state lives outside Constants.swift"])

        // Prose about a rule is not the rule.
        XCTAssertEqual(Self.problems(in: planted(Self.app, gateCall, gateCall + "        // showWhatsNewWindow() used to run here\n")), [])
    }

    /// Only the launch builds the window: no other file, a board least of all, calls its factory or the method that opens
    /// it. So no test and no board can pop it on this Mac's screen.
    func testOnlyTheLaunchBuildsTheWindow() throws {
        let files = try Self.appFiles()
        XCTAssertEqual(Self.files(in: files, containing: "WhatsNewWindow.make("), ["KannuApp.swift"])
        XCTAssertEqual(Self.files(in: files, containing: "showWhatsNewWindow()"), ["KannuApp.swift"])
        XCTAssertEqual(Self.files(in: files, containing: "whatsNewSeenEdition"), ["Constants.swift", "KannuApp.swift"],
                       "only the launch and the window's close may read or write the seen edition")
    }

    // MARK: - The catalog (task 5.3)

    private static let languages = ["ar", "cs", "de", "en-GB", "es", "fr", "hu", "it", "ko", "nl", "pl", "pt-BR", "ru",
                                    "th", "tr", "uk", "zh-Hans"]
    /// Names, which a language may keep as English writes them.
    private static let names: Set<String> = ["Tasks", "Tags"]
    private static let tagsText = "Type #launch or @3pm in a task's name for a tag or a reminder, shown as chips. Filter any list by tag."

    /// Every string the window shows is in the catalog in all 17 languages, translated, with Brain never translated.
    func testEveryStringIsInTheCatalogInAllSeventeenLanguages() throws {
        let sources = try Self.sources()
        let keys = Self.localizedKeys(in: sources[Self.view] ?? "") + Self.localizedKeys(in: sources[Self.window] ?? "")
        XCTAssertEqual(Set(keys), [
            "Welcome to Kannu 2.0", "The notch is the front door. Brain is the room behind it.", "Brain",
            "Settings is now Brain: pages for your agents, tasks, notes and more, full screen, with a menu bar of its own.",
            "Tasks",
            "Jira, GitLab, GitHub, Linear, Todoist and Reminders, beside your own. Open a task beside the list, time it, and log the time.",
            "Tags", Self.tagsText, "Continue", "What's New",
        ], "the window's strings changed: check the catalog and this list together")

        let strings = try Self.catalogStrings()
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "\(key) is not in the catalog")
            if key == "Brain" {
                XCTAssertEqual(entry["shouldTranslate"] as? Bool, false, "Brain is a name, never translated")
                continue
            }
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(key) has no translations")
            for language in Self.languages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "\(key) has no \(language)")
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) in \(language) is not marked translated")
                if language != "en-GB" && !Self.names.contains(key) {
                    XCTAssertNotEqual(value, key, "\(key) is English in \(language)")
                }
            }
        }
    }

    /// `#launch` and the clock time are what the user types, so every translation keeps them as words the quick-add parser
    /// reads (`TaskQuickAdd`). Arabic isolates them, so they read left to right inside the sentence; the isolates are not
    /// typed, so they are taken out first.
    func testEveryTranslationKeepsTheTypedTokens() throws {
        let entry = try XCTUnwrap(try Self.catalogStrings()[Self.tagsText] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for language in ["en"] + Self.languages {
            let text: String
            if language == "en" {
                text = Self.tagsText
            } else {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                text = unit?["value"] as? String ?? ""
            }
            let typed = text.replacingOccurrences(of: "\u{2066}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
            let parsed = TaskQuickAdd.parse(typed, now: now, calendar: calendar)
            XCTAssertEqual(parsed.tags, ["launch"], "\(language) lost #launch")
            XCTAssertNotNil(parsed.reminder, "\(language) lost the reminder's time")
            let tokens = TaskQuickAdd.tokens(of: typed).map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(["#", "@", ":"])) }
            XCTAssertTrue(tokens == ["#launch", "@3pm"] || tokens == ["#launch", "@15:00"], "\(language) types \(tokens)")
        }
    }

    // MARK: - The rules

    static func problems(in sources: [String: String]) -> [String] {
        var problems: [String] = []
        let app = code(sources[Self.app] ?? "")
        let launch = body(after: "private func continueLaunch() {", in: app) ?? ""
        let show = body(after: "private func showWhatsNewWindow() {", in: app) ?? ""
        let didClose = body(after: "private func whatsNewWindowDidClose() {", in: app) ?? ""
        let onboardingWindow = body(after: "private func showOnboardingWindow() {", in: app) ?? ""
        let view = code(sources[Self.view] ?? "")
        let window = code(sources[Self.window] ?? "")
        let decision = "WhatsNew.decision("
        let call = launch.range(of: decision).map { String(launch[$0.lowerBound...].prefix(300)) } ?? ""

        // Never before the Terms of Use: continueLaunch() alone decides and opens it.
        if occurrences(of: decision, in: app) != 1 || !launch.contains(decision) {
            problems.append("What's New is decided outside continueLaunch()")
        }
        // The definition and its one call.
        if occurrences(of: "showWhatsNewWindow()", in: app) != 2 || !launch.contains("            case .show:\n                showWhatsNewWindow()\n") {
            problems.append("What's New opens outside continueLaunch()")
        }

        // Never on a fresh install: an upgrade is an install whose hello cleared `firstLaunch`, and a fresh install's
        // first launch records the edition, so the next launch, which looks like an upgrade, does not open it.
        if !launch.contains("let isUpgrade = !coordinator.firstLaunch") || !call.contains("isUpgrade: isUpgrade,") {
            problems.append("What's New can open on a fresh install")
        }
        if !launch.contains("            case .markSeen:\n                Defaults[.whatsNewSeenEdition] = WhatsNew.currentEdition\n") {
            problems.append("a fresh install's first launch no longer counts What's New as seen")
        }

        // Never during onboarding: the decision waits for it, and nothing in onboarding opens the window.
        let onboardingView = code(sources[Self.onboarding] ?? "")
        if !call.contains("onboardingComplete: LaunchPermissionManager.isOnboardingComplete,")
            || onboardingWindow.contains("WhatsNew") || onboardingView.contains("WhatsNew") {
            problems.append("What's New can open during onboarding")
        }

        // Shown once: every close records the edition, and a recorded edition is never shown again.
        if !call.contains("seenEdition: Defaults[.whatsNewSeenEdition])")
            || !show.contains("window.onClose = { [weak self] in self?.whatsNewWindowDidClose() }")
            || !didClose.contains("Defaults[.whatsNewSeenEdition] = WhatsNew.currentEdition")
            || !(body(after: "override func close() {", in: window) ?? "").contains("onClose?()") {
            problems.append("closing What's New no longer counts it as seen")
        }
        if !launch.contains("if !AppRuntimeEnvironment.isUITesting {\n            switch WhatsNew.decision(") {
            problems.append("What's New opens under UI testing")
        }

        // Return presses Continue and Escape closes the window, whatever has focus: both are key equivalents.
        if occurrences(of: ".keyboardShortcut(.defaultAction)", in: view) != 1 {
            problems.append("Return no longer presses Continue")
        }
        let keys = body(after: "override func performKeyEquivalent(with event: NSEvent) -> Bool {", in: window) ?? ""
        if !keys.contains("event.keyCode == Self.escapeKeyCode") || !keys.contains("close()")
            || !window.contains("private static let escapeKeyCode: UInt16 = 53") {
            problems.append("Escape no longer closes What's New")
        }
        // Under Reduce Motion nothing animates: the view never does, and the window drops its own under it.
        if ["withAnimation", ".animation(", ".transition(", "matchedGeometryEffect", ".spring"].contains(where: { view.contains($0) || window.contains($0) }) {
            problems.append("something in What's New animates")
        }
        if !window.contains("window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .default") {
            problems.append("the What's New window animates under Reduce Motion")
        }
        if !view.contains(".accessibilityElement(children: .combine)") || !view.contains(".accessibilityAddTraits(.isHeader)") {
            problems.append("VoiceOver no longer reads each card's title and text together")
        }

        // Brain's theme in light and dark: its root, its panel, and no colour or font of its own.
        let ownStyle = [#"\bColor\b"#, "NSColor", #"\.system\("#, #"\.fontWeight\("#,
                        #"\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\b"#]
        if !view.contains(".settingsDesignSystem()") || !view.contains(".background(SettingsTheme.panel)")
            || ownStyle.contains(where: { view.range(of: $0, options: .regularExpression) != nil }) {
            problems.append("What's New leaves Brain's theme")
        }
        // The window takes its content's height once, and SwiftUI never resizes it (docs/REGRESSIONS.md, entry 17).
        if !window.contains("window.setHostedContent(hostingView)") || window.contains("contentView =") {
            problems.append("SwiftUI can size the What's New window")
        }
        if !code(sources[Self.snapshots] ?? "").contains("WhatsNewView(content: DebugSnapshotFixtures.whatsNew(language: \"en\")") {
            problems.append("the What's New board no longer draws its fixture")
        }
        if !code(sources[Self.settings] ?? "").contains("case .tasks: return String(localized: \"Tasks\")")
            || !view.contains("title: String(localized: \"Tasks\", bundle: bundle)") {
            problems.append("the Tasks card no longer shares the sidebar's key")
        }
        if !code(sources[Self.constants] ?? "").contains("static let whatsNewSeenEdition = Key<Int>(\"whatsNewSeenEdition\", default: 0)")
            || code(sources[Self.coordinator] ?? "").contains("showWhatsNew") {
            problems.append("What's New's seen state lives outside Constants.swift")
        }
        return problems
    }

    // MARK: - Reading the code

    /// The `String(localized: "…"` keys a file uses.
    static func localizedKeys(in source: String) -> [String] {
        let pattern = #"String\(localized: "((?:[^"\\]|\\.)*)""#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]).replacingOccurrences(of: "\\\"", with: "\"") }
        }
    }

    /// From the `{` that ends `header` to its matching `}`.
    private static func body(after header: String, in source: String) -> String? {
        guard let start = source.range(of: header) else { return nil }
        var depth = 0
        var index = source.index(before: start.upperBound)
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[source.index(before: start.upperBound)...index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Source with comment lines dropped, so prose about a rule never trips it or satisfies it.
    private static func code(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
        }.joined(separator: "\n")
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func sources() throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: watched.map { path in
            (path, try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8))
        })
    }

    private static func catalogStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Kannu/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(catalog["strings"] as? [String: Any])
    }

    private static func appFiles() throws -> [URL: String] {
        let folder = root.appendingPathComponent("Kannu")
        let urls = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try Dictionary(uniqueKeysWithValues: urls.map { ($0, code(try String(contentsOf: $0, encoding: .utf8))) })
    }

    private static func files(in files: [URL: String], containing text: String) -> [String] {
        files.filter { $0.value.contains(text) }.map(\.key.lastPathComponent).sorted()
    }
}
