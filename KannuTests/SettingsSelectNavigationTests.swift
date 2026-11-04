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

/// How `SettingsSelect`'s list answers the keyboard: what a search keeps, where an arrow lands and which
/// row typed letters pick. The list itself is a view, which this target does not compile.
final class SettingsSelectNavigationTests: XCTestCase {
    private typealias Navigation = SettingsSelectNavigation

    func testAnEmptyQueryKeepsEveryRowInOrder() {
        XCTAssertEqual(Navigation.matches(["Hourglass", "Glass", "Frosted"], query: ""), [0, 1, 2])
        XCTAssertEqual(Navigation.matches(["Hourglass", "Glass", "Frosted"], query: "   "), [0, 1, 2],
                       "a query of spaces is empty: `rank` alone would match nothing")
        XCTAssertEqual(Navigation.matches([], query: ""), [])
    }

    func testAWholeWordRanksBeforeASubstring() {
        XCTAssertEqual(Navigation.matches(["Hourglass", "Glass", "Frosted"], query: "glass"), [1, 0])
        XCTAssertEqual(Navigation.matches(["Hourglass", "Glass", "Frosted"], query: "GLA"), [1, 0])
    }

    func testTheSearchFoldsAsBrainsSearchDoes() {
        XCTAssertEqual(Navigation.matches(["Accent", "Color"], query: "colour"), [1])
        XCTAssertEqual(Navigation.matches(["Éclair", "Apple"], query: "ecl"), [0])
    }

    func testNoMatchIsEmpty() {
        XCTAssertEqual(Navigation.matches(["Hourglass", "Glass"], query: "zzz"), [])
    }

    func testAnArrowLandsInsideTheList() {
        XCTAssertEqual(Navigation.moved(from: nil, by: 1, count: 5), 0, "down from none is the first row")
        XCTAssertEqual(Navigation.moved(from: nil, by: -1, count: 5), 4, "up from none is the last row")
        XCTAssertEqual(Navigation.moved(from: 2, by: 1, count: 5), 3)
        XCTAssertEqual(Navigation.moved(from: 2, by: -1, count: 5), 1)
        XCTAssertEqual(Navigation.moved(from: 4, by: 1, count: 5), 4, "never past the last row")
        XCTAssertEqual(Navigation.moved(from: 0, by: -1, count: 5), 0, "never past the first row")
        XCTAssertNil(Navigation.moved(from: nil, by: 1, count: 0))
        XCTAssertNil(Navigation.moved(from: 3, by: -1, count: 0))
    }

    func testTypedLettersMakeOnePrefixUntilAPause() {
        XCTAssertEqual(Navigation.typed("b", after: "a", pause: 0.5), "ab")
        XCTAssertEqual(Navigation.typed("b", after: "a", pause: Navigation.typeSelectPause), "ab",
                       "a pause of exactly the limit still extends")
        XCTAssertEqual(Navigation.typed("b", after: "a", pause: 2), "b", "a longer pause starts again")
        XCTAssertEqual(Navigation.typed("b", after: "", pause: 0), "b")
    }

    func testTypeSelectFoldsCaseAndAccents() {
        let titles = ["Apple", "Éclair", "Eclipse"]
        XCTAssertEqual(Navigation.typeSelect("e", in: titles), 1, "the first row that starts with it")
        XCTAssertEqual(Navigation.typeSelect("ECLI", in: titles), 2)
        XCTAssertEqual(Navigation.typeSelect("écl", in: titles), 1)
        XCTAssertEqual(Navigation.typeSelect("a", in: titles), 0)
        XCTAssertNil(Navigation.typeSelect("x", in: titles))
        XCTAssertNil(Navigation.typeSelect("", in: titles))
        XCTAssertNil(Navigation.typeSelect("pple", in: titles), "a prefix, not a substring")
    }

    func testOnlyAListPastTheThresholdSearches() {
        XCTAssertEqual(Navigation.searchThreshold, 10, "docs/SETTINGS.md, \"Choices\", names ten")
        XCTAssertEqual(Navigation.typeSelectPause, 1)
    }
}
