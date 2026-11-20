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

/// Issue #24, as a rule over the source: no screen is found, stored or keyed by `localizedName`.
/// Nineteen sites did it, each one a copy of the last, so a seventeenth is the likely way back in.
/// A name is for people to read; a screen is found by `CGDirectDisplayID` (`NSScreen.withDisplayID`).
final class DisplayIdentityRulesTests: XCTestCase {

    /// Every non-comment line that compares a screen's name, or keys a dictionary by one.
    static func nameLookups(in text: String) -> [String] {
        let comparison = try! NSRegularExpression(pattern: #"localizedName\s*[!=]=|[!=]=\s*[\w$.?]*localizedName"#)
        let subscriptKey = try! NSRegularExpression(pattern: #"\[\s*[\w$.?]*\.localizedName\s*\]"#)
        let mapKey = try! NSRegularExpression(pattern: #"\(\s*\$0\.localizedName\s*,"#)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*"), !trimmed.hasPrefix("/*"),
                  line.range(of: "screen", options: .caseInsensitive) != nil else { return false }
            let range = NSRange(line.startIndex..., in: line)
            return [comparison, subscriptKey, mapKey].contains { $0.firstMatch(in: line, range: range) != nil }
        }
    }

    func testNoScreenIsFoundByItsName() {
        var offenders: [String] = []
        for (path, text) in Self.appSources() {
            offenders += Self.nameLookups(in: text).map { "\(path): \($0.trimmingCharacters(in: .whitespaces))" }
        }
        XCTAssertEqual(offenders, [], "find screens with NSScreen.withDisplayID; localizedName is for display only")
    }

    /// Each shape the old code used, as it was written, must be caught.
    func testThePlantedOffendersAreCaught() {
        let planted = [
            "        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {",
            "            .filter { $0 is KannuWindow && $0.screen?.localizedName == currentScreenName }",
            "            $0.localizedName != mainScreenName && shouldUseDynamicIslandMode(for: $0.localizedName)",
            "            byScreen[screen.localizedName] = FullscreenFallbackVerdict.menuBarIsVisible(",
            "            let menuBarVisible = menuBarVisibleByScreen?[app.screen.localizedName] ?? true",
            "            return Dictionary(NSScreen.screens.map { ($0.localizedName, false) }, uniquingKeysWith: { first, _ in first })",
            "        let currentScreen = NSScreen.screens.first { $0.localizedName == screen } ?? NSScreen.main",
        ]
        for line in planted {
            XCTAssertEqual(Self.nameLookups(in: line).count, 1, "not caught: \(line)")
        }
        // What stays legal: a name read for a log, a title or a name-keyed override.
        for line in [
            "        let screen = panel.screen?.localizedName ?? \"none\"",
            "            .map { (name: $0.localizedName, isBuiltIn: isBuiltInDisplay($0)) }",
            "    if let name = NSScreen.withDisplayID(screenID)?.localizedName,",
            "        // screens.first { $0.localizedName == name } was the bug",
        ] {
            XCTAssertEqual(Self.nameLookups(in: line), [], "a legal line was flagged: \(line)")
        }
    }

    /// The view model holds an id, and the stored preference is a UUID, never a name again.
    func testTheViewModelAndThePreferenceHoldIdentities() throws {
        let sources = Self.appSources()
        let viewModel = try XCTUnwrap(sources["Kannu/models/KannuViewModel.swift"])
        XCTAssertTrue(viewModel.contains("@Published var screenID: CGDirectDisplayID?"))
        XCTAssertFalse(viewModel.contains("@Published var screen: String?"), "the view model's screen is a name again")

        let coordinator = try XCTUnwrap(sources["Kannu/KannuViewCoordinator.swift"])
        XCTAssertFalse(coordinator.contains("@AppStorage(\"preferred_screen_name\")"),
                       "the choice is stored by name again; it is preferredScreenUUID")
        let constants = try XCTUnwrap(sources["Kannu/models/Constants.swift"])
        XCTAssertTrue(constants.contains("Key<String?>(\"preferredScreenUUID\""))
        XCTAssertFalse(constants.contains("Key<String>(\"preferred_screen_name\"")
                       || constants.contains("Key<String?>(\"preferred_screen_name\""),
                       "a declared key registers a default and would make every user look like they chose")
    }

    /// The pointer check measures this view's own display, found by id.
    func testThePointerCheckReadsItsOwnDisplay() throws {
        let content = try XCTUnwrap(Self.appSources()["Kannu/ContentView.swift"])
        let start = try XCTUnwrap(content.range(of: "private func isPointerOnOpenNotch("))
        XCTAssertTrue(content[start.upperBound...].prefix(300).contains("guard let screen = currentScreen,"))
        XCTAssertTrue(content.contains("NSScreen.withDisplayID(currentScreenID)"))
        XCTAssertTrue(content.contains("$0.screen?.displayID == currentScreenID"),
                      "the attached windows must be this display's notch window's")
    }

    /// A display that comes back under a new id, with the same name and frame, must count as a change.
    /// Two equal-sized displays swapping places must count as well, so ids and frames are compared
    /// as pairs (PR #80 review).
    func testTheScreenChangeCheckComparesIDs() throws {
        let app = try XCTUnwrap(Self.appSources()["Kannu/KannuApp.swift"])
        XCTAssertTrue(app.contains("DisplayPlacementResolver.layoutChanged(from: previousScreenLayout, to: currentLayout)"))
        XCTAssertTrue(app.contains("let viewModel = KannuViewModel(screenID: id)"))
    }

    /// The timer and music controls skip a refresh only when their display is unchanged too.
    func testTheControlWindowsRefreshOnADisplayChange() throws {
        let sources = Self.appSources()
        for path in ["Kannu/managers/TimerControlWindowManager.swift", "Kannu/managers/MusicControlWindowManager.swift"] {
            let text = try XCTUnwrap(sources[path])
            XCTAssertTrue(text.contains("DisplayPlacementResolver.canSkipRefresh(last: last, next: next)"), path)
            XCTAssertFalse(text.contains("if let lastMetrics, lastMetrics == metrics"),
                           "\(path) skips on metrics alone again: the window stays on the old display")
            XCTAssertTrue(text.contains("lastDisplayID = screen.displayID"), path)
        }
    }

    /// A battery HUD that is up while the notch moves follows it.
    func testTheBatteryHUDTargetFollowsTheNotchDisplay() throws {
        let text = try XCTUnwrap(Self.appSources()["Kannu/models/BatteryStatusViewModel.swift"])
        XCTAssertTrue(text.contains("coordinator.$selectedScreenID"))
        XCTAssertTrue(text.contains(".receive(on: DispatchQueue.main)"),
                      "without the hop the sink reads selectedScreenID before it is stored")
        XCTAssertTrue(text.contains("DisplayPlacementResolver.hudTargetDisplay("))
    }

    private static func appSources() -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let kannu = root.appendingPathComponent("Kannu")
        var out: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(at: kannu, includingPropertiesForKeys: nil) else { return out }
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            out[relative] = try? String(contentsOf: url, encoding: .utf8)
        }
        return out.compactMapValues { $0 }
    }

    /// Anti-vacuous: a broken path must fail loudly rather than scanning nothing.
    func testTheScanReadTheRealTree() {
        let sources = Self.appSources()
        XCTAssertGreaterThan(sources.count, 100, "the scan read too few files — fix appSources()")
        XCTAssertNotNil(sources["Kannu/ContentView.swift"])
        XCTAssertNotNil(sources["Kannu/sizing/matters.swift"])
    }
}
