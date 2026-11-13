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

/// D1 (layout-proposal, David 2026-11-06): a Brain list shows its selected item's page beside it once the panel fits
/// the list plus a 720-pt page, about 1,200 pt, "so 14-inch full screen qualifies and the 1,100 default doesn't";
/// narrower, the page takes the list's place. Brain's widths, which this target cannot read from `SettingsTheme`: the
/// page inset is 48 on a panel 1,000 pt or wider and 32 below (`pageInsetWide`, `pageInset`, `widePanelWidth`), and a
/// page is the 720-pt settings column (`pageMaxWidth`). A panel is the window less 208 (the sidebar and its inset).
final class ListDetailLayoutTests: XCTestCase {
    private func beside(panel: CGFloat) -> Bool {
        ListDetailLayout.showsPageBeside(panelWidth: panel, inset: panel >= 1000 ? 48 : 32, pageWidth: 720)
    }

    func testTheWindowsFirstSizeSwapsAndA14InchFullScreenShowsThePageBeside() {
        XCTAssertFalse(beside(panel: 612), "the smallest window, 820")
        XCTAssertFalse(beside(panel: 892), "the window's first size, 1,100")
        XCTAssertFalse(beside(panel: 1000), "a 1,208 window")
        XCTAssertTrue(beside(panel: 1232), "a 1,440 window, the shellWide board")
        XCTAssertTrue(beside(panel: 1302), "a 14-inch Mac in full screen, as David's screenshot measured it")
        XCTAssertTrue(beside(panel: 1304), "a 14-inch Mac in full screen, 1,512 less 208")
        XCTAssertTrue(beside(panel: 1520), "a 16-inch Mac in full screen")
        XCTAssertTrue(beside(panel: 2352), "a 2,560 display in full screen")
    }

    /// The edge is the inset, the list, the inset, the page and the inset: 48 + 360 + 48 + 720 + 48 = 1,224.
    func testTheEdgeIsTheListAndThePageWithAnInsetBeforeBetweenAndAfter() {
        XCTAssertEqual(ListDetailLayout.listWidth, 360)
        XCTAssertTrue(ListDetailLayout.showsPageBeside(panelWidth: 1224, inset: 48, pageWidth: 720))
        XCTAssertFalse(ListDetailLayout.showsPageBeside(panelWidth: 1223.5, inset: 48, pageWidth: 720))
        // Each term counts: a wider page or inset needs a wider panel, a narrower one less.
        XCTAssertFalse(ListDetailLayout.showsPageBeside(panelWidth: 1224, inset: 48, pageWidth: 721))
        XCTAssertFalse(ListDetailLayout.showsPageBeside(panelWidth: 1224, inset: 49, pageWidth: 720))
        XCTAssertTrue(ListDetailLayout.showsPageBeside(panelWidth: 1176, inset: 32, pageWidth: 720))
        XCTAssertFalse(ListDetailLayout.showsPageBeside(panelWidth: 1175, inset: 32, pageWidth: 720))
    }
}
