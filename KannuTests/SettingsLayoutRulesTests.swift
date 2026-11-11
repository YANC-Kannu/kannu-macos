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

/// The Settings construction rules, pinned against the sources the way
/// `SettingsHighlightInventoryTests` and `ModalPresentationRulesTests` pin theirs. The rules
/// themselves are written down in `docs/SETTINGS.md`; this file is what keeps them true:
///
/// 1. A `Section` header uses `SettingsSectionHeader`, never a raw `Text` — headers are
///    explanatory text and must be selectable.
/// 2. A `Section` footer uses `SettingsFooter` for the plain-text case, same reason.
/// 3. Secondary/caption informational text carries `.textSelection(.enabled)` or goes through
///    `settingsDescriptionStyle()`. The survivors that deliberately stay unselectable — badges,
///    labels inside tappable cards and control labels, and text covered by a container-level
///    `.textSelection` — are pinned per file below, so a new one is a deliberate edit here, not
///    a row that quietly lost copyability.
/// 4. The shared components themselves keep their `.textSelection`, so a refactor cannot strip
///    selectability from every user at once.
/// 5. The content standard, pinned the same way: no ad-hoc font on row text, no slider or stepper
///    built by hand, no padding on a row. Each is a per-file count with a reason, so the survivors are
///    a deliberate list (cards, chips, previews, popovers) and a new one is an edit here.
final class SettingsLayoutRulesTests: XCTestCase {

    // MARK: - Rule 1: headers

    func testNoSectionHeaderIsARawText() {
        for (path, text) in Self.settingsSources() {
            for offender in Self.rawHeaderOffenders(in: text) {
                XCTFail("\(path):\(offender): a Section header is a raw Text — use SettingsSectionHeader so it can be selected and copied")
            }
        }
    }

    // MARK: - Rule 2: footers

    func testNoSectionFooterIsARawText() {
        for (path, text) in Self.settingsSources() {
            for offender in Self.rawFooterOffenders(in: text) {
                XCTFail("\(path):\(offender): a Section footer is a raw Text — use SettingsFooter so it can be selected and copied")
            }
        }
    }

    // MARK: - Rule 3: informational text is selectable, survivors are pinned

    /// Raw `Text` chains styled as secondary/caption information that carry no selection. Every
    /// entry is deliberate: a badge chip, a label inside a tappable card or a control label
    /// (a selectable Text there swallows the control's click), or text already covered by a
    /// container-level `.textSelection`. Adding a new one means either giving it
    /// `.textSelection(.enabled)` / `settingsDescriptionStyle()` or updating this table with the
    /// reason it cannot have one.
    private static let pinnedUnselectableCounts: [String: Int] = [
        "ExtensionsSettings.swift": 1,              // footer legend heading — container-selectable
        "IdleAnimationsSettingsSection.swift": 2,   // "Add" / "Add New" — labels of a tappable card
        "MusicSlotConfigurationView.swift": 1,      // palette item label — draggable/tappable chip
        "SecurityFindingRow.swift": 1,              // severity badge chip, accessibility-hidden
        // Badges: decorative chips. A choice card's name takes `settingsChoiceLabel`, so the scan no longer counts it.
        "SettingsBadge.swift": 1,                   // the one badge on a page
        "SettingsHelpers.swift": 1,                 // the "Coming soon" tag, unused
        "SettingsView.swift": 1,                    // a suggestion's tab name — label of a tappable row
        "SettingsSidebarRow.swift": 1,              // the BETA capsule, inside the row's button
        "AgentsOverview.swift": 1,                  // a row's provider — inside the button that opens the chat
    ]

    func testEveryInformationalTextIsSelectableOrPinned() {
        var counts: [String: Int] = [:]
        for (path, text) in Self.settingsSources() {
            let found = Self.unselectableInformationalChains(in: text)
            if !found.isEmpty { counts[path] = found.count }
            let allowed = Self.pinnedUnselectableCounts[path] ?? 0
            if found.count > allowed {
                XCTFail("""
                \(path): \(found.count) raw secondary/caption Text chains without .textSelection \
                (pinned: \(allowed)). New informational text must be selectable — add \
                .textSelection(.enabled) or settingsDescriptionStyle(), or pin it here with a \
                reason. First lines: \(found.prefix(6).joined(separator: " | "))
                """)
            }
        }
        // The pin shrinks with the code: a stale entry hides a future offender behind its slot.
        for (path, allowed) in Self.pinnedUnselectableCounts {
            let found = counts[path] ?? 0
            XCTAssertGreaterThanOrEqual(
                allowed, found,
                "\(path): pinned count is stale")
            XCTAssertEqual(
                allowed, found,
                "\(path): fewer raw chains (\(found)) than pinned (\(allowed)) — lower the pin so it keeps meaning something")
        }
    }

    // MARK: - Rule 5: the content standard

    /// Lines carrying a caption-sized or pixel-sized font. Every survivor is a badge or chip, a
    /// glyph, or text inside a card, popover or preview that has its own compact scale — never a
    /// row's title or description, which use the Form's type and `settingsDescriptionStyle()`.
    private static let pinnedAdHocFontCounts: [String: Int] = [
        "AnimationEditorView.swift": 11,     // the animation editor sheet: its own dense scale
        "ExtensionsSettings.swift": 1,       // the empty state's 48-pt glyph
        "IdleAnimationsSettingsSection.swift": 4,  // the Add card and the delete glyph; a card's name is `settingsChoiceLabel`
        "MusicSlotConfigurationView.swift": 7,     // the slot canvas and its draggable chips
        "SecurityFindingRow.swift": 1,       // the severity badge chip
        "SettingsSidebarRow.swift": 1,       // the BETA capsule
        "SettingsBadge.swift": 1,            // the one badge, in the caption's size
        "AppearanceSettings.swift": 1,       // an app icon card's placeholder glyph
        "CustomOSDSettings.swift": 1,        // the OSD preview
        "DevicesSettings.swift": 2,          // the icon style cards' glyphs
        "HUDAndOSDSettings.swift": 5,        // HUD style previews
        "LockScreenSettings.swift": 6,       // lock screen previews
        "SettingsColorPicker.swift": 2,      // the colour popover
        "SpotifyAuthSettingsSection.swift": 6,     // the sign-in card
    ]

    func testRowTextUsesTheFormsTypeOrTheSharedStyle() {
        assertPinnedCounts(Self.pinnedAdHocFontCounts, scanner: Self.adHocFontLines,
                           rule: "a caption-sized or pixel-sized font",
                           cure: "row text uses the root's body type, and every secondary line goes through settingsDescriptionStyle()")
    }

    /// Lines building a slider or a stepper by hand, ours or native. `SettingsSliderRow` and
    /// `SettingsStepperRow` are the only shapes a Settings *row* may use, so these are the ones that
    /// are not rows.
    private static let pinnedHandBuiltValueControlCounts: [String: Int] = [
        "AnimationEditorView.swift": 2,      // the editor sheet: the preview's zoom, and ParameterSliderRow's
        "SettingsComponents.swift": 2,       // SettingsSliderRow and SettingsStepperRow themselves
        "CustomOSDSettings.swift": 1,        // the OSD preview card's own level slider
    ]

    func testNoValueControlIsBuiltByHandInARow() {
        assertPinnedCounts(Self.pinnedHandBuiltValueControlCounts, scanner: Self.handBuiltValueControlLines,
                           rule: "a slider or stepper built by hand",
                           cure: "a slider row is SettingsSliderRow and a stepper row SettingsStepperRow — one width, one readout column")
    }

    /// Lines adding padding. A section pads its own rows, so padding here belongs to a
    /// card, a chip, a popover, a preview or an empty state — never to a row, which would make
    /// that one row taller than its neighbours.
    private static let pinnedRowPaddingCounts: [String: Int] = [
        "AnimationEditorView.swift": 8,      // the editor sheet
        "EditPanelView.swift": 1,            // a panel, not a Form
        "ExtensionsSettings.swift": 4,       // the empty state, the expanded details' gap, and the status chip
        "IdleAnimationsSettingsSection.swift": 5,  // the cards' scrolling strip, the delete glyph, and the Add menu's two items
        "MusicSlotConfigurationView.swift": 5,     // the slot canvas
        "SecurityFindingRow.swift": 3,       // the finding card and its badge
        "SettingsView.swift": 6,             // the highlight's ring, the search field and its suggestions
        "BrainShell.swift": 4,               // the shell's own insets
        "SettingsSidebarRow.swift": 3,       // the row's inset and the capsule's two
        "SettingsPageHeader.swift": 2,       // the large title's insets, above the page
        "SettingsPage.swift": 4,             // the page's inset from the panel's edge, its top and bottom, and the scroll view's own inset under the title
        "SettingsSection.swift": 3,          // the section's card around its rows, and its header and footer in line with them
        "SettingsProductPage.swift": 4,      // the page's inset from the panel's edge, its top and bottom, and the scroll view's own inset under the title
        "AgentsOverview.swift": 6,           // the hero's, a row's, the empty state's and a status cell's cards, Recent's heading in line with the rows, and the hero's figures on its text column
        "TimerOverview.swift": 6,            // the running timer's, the empty state's, a preset tile's and Add Preset's cards, a tile's ⋯ in its corner, and the presets' heading in line with the tiles
        "AgentStatusSettings.swift": 1,      // a preview
        "AppearanceSettings.swift": 2,       // the skin and icon grids' drop targets
        "CustomOSDSettings.swift": 1,        // the OSD preview
        "HUDAndOSDSettings.swift": 5,        // HUD style cards and previews
        "LockScreenSettings.swift": 3,       // lock screen previews (the glass sample went with its view)
        "SettingsColorPicker.swift": 1,      // the colour popover
        "SettingsHelpers.swift": 4,          // the unused "Upgrade to Pro" and "Coming soon" capsules
        "SettingsBadge.swift": 1,            // the one badge's own inset
        "SettingsCalloutCard.swift": 1,      // a callout's own card, and a row's expanded details
        "SettingsToggleStyle.swift": 1,      // the knob, inset from its track
        "SettingsButtonStyle.swift": 2,      // the button's own chrome, and a flush button pulled back onto its column
        "SettingsSelect.swift": 2,           // a segment, and the track it sits in
        "SettingsSelectList.swift": 2,       // the list inside its popover, and a row
        "SettingsField.swift": 1,            // the field inside its chrome
        "SettingsSheet.swift": 1,            // a sheet pads its own content, for every sheet but the two large ones
        "SettingsDateField.swift": 1,        // the date popover's content
        "SpotifyAuthSettingsSection.swift": 1,     // the sign-in card
        "SpotifyLoginSheet.swift": 1,        // the sign-in sheet's header bar, over its web view
        "SecurityOverview.swift": 2,         // the count strip's and a status cell's cards
        "UsageOverview.swift": 4,            // the empty state's, a provider's and a model row's cards, and the models' heading in line with the rows
    ]

    func testNoRowPadsItself() {
        assertPinnedCounts(Self.pinnedRowPaddingCounts, scanner: Self.paddingLines,
                           rule: "a padding",
                           cure: "a row in a section adds none — the section pads it")
    }

    // MARK: - Rule 6: a choice, a slider and a stepper are ours

    /// Lines building a native choice or value control. SwiftUI on macOS 14 has no custom picker, slider or
    /// stepper style, so under Settings a choice is `SettingsSelect` (docs/SETTINGS.md, "Choices") and a value
    /// `SettingsSlider` or `SettingsStepper` ("Values and fields"), and these are the ones that cannot be.
    private static let pinnedNativeControlCounts: [String: Int] = [
        // The filter menu's ticked submenus: native inside a native Menu; Stage 5 rebuilds the page with
        // SettingsSelect (plan:75).
        "AllTasksPage.swift": 4,
    ]

    private static let nativeControlNames = ["Picker", "Slider", "Stepper"]

    func testNoNativeChoiceOrValueControlIsBuiltUnderSettings() throws {
        assertPinnedCounts(Self.pinnedNativeControlCounts, scanner: { Self.nativeControlLines(in: $0, names: Self.nativeControlNames) },
                           rule: "a native Picker, Slider or Stepper",
                           cure: "a choice is SettingsSelect in a SettingsRow, `choices:` for literal options; a value is SettingsSliderRow or SettingsStepperRow")
        // A floor: the four pinned pickers are still there, so a pattern gone blind fails here.
        let found = Self.settingsSources().values.reduce(0) { $0 + Self.nativeControlLines(in: $1, names: Self.nativeControlNames).count }
        XCTAssertGreaterThan(found, 0, "the scan found no native control: the pattern went blind")

        for planted in ["Picker(\"a\", selection: $a) {}", "Picker(\n    \"a\",\n    selection: $a\n) {}",
                        "Picker (\"a\", selection: $a) {}", "SwiftUI.Picker(\"a\", selection: $a) {}",
                        "Picker<Int, Text, EmptyView>(selection: $a) {} label: {}"] {
            XCTAssertEqual(Self.nativeControlLines(in: planted, names: ["Picker"]).count, 1, planted)
        }
        for clean in ["ColorPicker(\"a\", selection: $a)", "DatePicker(\"a\", selection: $a)",
                      "SettingsColorPicker(title: \"a\", selection: $a)", "SettingsSelect(\"a\", selection: $a, choices: [1: \"b\"])",
                      "KannuColorPickerButton(color: c, accessibilityLabel: \"a\") {}", ".pickerStyle(.menu)",
                      "// Picker(\"a\")", "/* Picker( */", "Text(\"Device Picker Style\")"] {
            XCTAssertEqual(Self.nativeControlLines(in: clean, names: ["Picker"]), [], clean)
        }

        // A real page, one select put back.
        let agents = try XCTUnwrap(Self.settingsSources()["AgentStatusSettings.swift"])
        let first = try XCTUnwrap(agents.range(of: "SettingsSelect("), "the Agents page has no select to plant on")
        let planted = agents.replacingCharacters(in: first, with: "Picker(")
        XCTAssertEqual(Self.nativeControlLines(in: planted, names: ["Picker"]).count, 1)

        // Sliders and steppers, ours passing and Apple's caught, the same way.
        for planted in ["Slider(value: $x, in: 0...1)", "Stepper(value: $v, in: 0...9) {}", "Stepper(\"a\", value: $v)",
                        "SwiftUI.Slider(value: $x, in: 0...1)"] {
            XCTAssertEqual(Self.nativeControlLines(in: planted, names: Self.nativeControlNames).count, 1, planted)
        }
        for clean in ["SettingsSlider(value: $x, in: 0...1) { Text(\"a\") }", "SettingsSliderRow(\"a\", value: $x, in: 0...1, valueText: nil)",
                      "SettingsStepper(value: $v, in: 0...9) { Text(\"a\") }",
                      "SettingsStepperRow(\"a\", value: $v, in: 0...9, valueText: Text(\"b\"))", "Text(\"Slider color\")"] {
            XCTAssertEqual(Self.nativeControlLines(in: clean, names: Self.nativeControlNames), [], clean)
        }
        // A real page, one slider put back.
        let osd = try XCTUnwrap(Self.settingsSources()["CustomOSDSettings.swift"])
        let slider = try XCTUnwrap(osd.range(of: "SettingsSlider("), "the Custom OSD page has no slider to plant on")
        XCTAssertEqual(Self.nativeControlLines(in: osd.replacingCharacters(in: slider, with: "Slider("),
                                               names: Self.nativeControlNames).count, 1)
    }

    // MARK: - Rule 8: a page and a section are ours

    /// Lines building a native `Form` or `Section`. macOS 14 has no API for a custom form style to take a section
    /// apart, so under Settings a page is `SettingsPage` and a group of rows `SettingsSection`, called the same way
    /// (docs/SETTINGS.md, "Pages and sections"). These are the ones that cannot be: none, so a pin needs a reason.
    private static let pinnedNativeContainerCounts: [String: Int] = [:]

    private static let nativeContainerNames = ["Form", "Section"]

    private static func nativeContainerLines(in text: String, names: [String] = SettingsLayoutRulesTests.nativeContainerNames) -> [String] {
        nativeControlLines(in: text, names: names, opening: #"[({]"#)
    }

    func testNoNativeFormOrSectionIsBuiltUnderSettings() throws {
        assertPinnedCounts(Self.pinnedNativeContainerCounts, scanner: { Self.nativeContainerLines(in: $0) },
                           rule: "a native Form or Section",
                           cure: "a page is SettingsPage and a group of rows SettingsSection: the rows, then header: and footer:")
        // A floor: the same scan, pointed at ours, finds the pages and their sections, so a pattern gone blind fails here.
        let sources = Self.settingsSources()
        let pages = sources.values.reduce(0) { $0 + Self.nativeContainerLines(in: $1, names: ["SettingsPage"]).count }
        let sections = sources.values.reduce(0) { $0 + Self.nativeContainerLines(in: $1, names: ["SettingsSection"]).count }
        XCTAssertGreaterThan(pages, 0, "the scan found no page: the pattern went blind")
        XCTAssertGreaterThan(sections, 0, "the scan found no section: the pattern went blind")

        for planted in ["Form {}", "Form{\n}", "SwiftUI.Form {}", "Form (\n) {}", "Section {}", "Section(\"a\") {}",
                        "Section(header: Text(\"a\")) {}", "SwiftUI.Section {}", "return Section {",
                        "Section {\n    row\n} header: {\n    SettingsSectionHeader(\"a\")\n}", "Section<Text, Text, EmptyView> {"] {
            XCTAssertEqual(Self.nativeContainerLines(in: planted).count, 1, planted)
        }
        for clean in ["SettingsPage {}", "SettingsSection {}", "SettingsSectionHeader(\"a\")", "IdleAnimationsSettingsSection()",
                      "TimeToLogSection(draft: d)", "Shortcuts().shortcutsSection", "private var tasksSection: some View {",
                      "TaskForm(draft: d)", ".formStyle(.grouped)", "// Form {", "/* Section { */", "Text(\"Form {\")",
                      "SettingsFooter(\"Section {\")"] {
            XCTAssertEqual(Self.nativeContainerLines(in: clean), [], clean)
        }

        // Real pages, one section and one page put back.
        let general = try XCTUnwrap(sources["GeneralSettings.swift"])
        let section = try XCTUnwrap(general.range(of: "SettingsSection {"), "the General page has no section to plant on")
        XCTAssertEqual(Self.nativeContainerLines(in: general.replacingCharacters(in: section, with: "Section {")).count, 1)
        let downloads = try XCTUnwrap(sources["DownloadsSettings.swift"])
        let page = try XCTUnwrap(downloads.range(of: "SettingsPage {"), "the Downloads page has no page to plant on")
        XCTAssertEqual(Self.nativeContainerLines(in: downloads.replacingCharacters(in: page, with: "SwiftUI.Form {")).count, 1)
    }

    /// One entry per line holding a call of one of `names`, read with comments and strings blanked:
    /// `Picker(`, `Picker (`, `SwiftUI.Picker(` and `Picker<…>(`, never `ColorPicker(`, `.pickerStyle(`
    /// or a title such as "Device Picker Style". Not the `openers` lookbehind of the design-system rules,
    /// which misses `SwiftUI.Picker(`. `opening` is what starts the call; a container opens with a brace too.
    static func nativeControlLines(in text: String, names: [String], opening: String = #"\("#) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(text, blankingStrings: true)
        let pattern = #"(?<![A-Za-z0-9_])(?:SwiftUI\s*\.\s*)?(?:"# + names.joined(separator: "|") + #")\s*(?:<[^>]*>)?\s*"# + opening
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad pattern for \(names)")
            return []
        }
        let nsCode = code as NSString
        let lineNumbers = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length)).map { match in
            nsCode.substring(to: match.range.location).components(separatedBy: "\n").count - 1
        }
        let lines = text.components(separatedBy: "\n")
        return Array(Set(lineNumbers)).sorted().map { lines[$0].trimmingCharacters(in: .whitespaces) }
    }

    /// The tokens exist and something reads each of them, so a number cannot drift back into a
    /// row and a token cannot linger after its last user is gone.
    func testEveryMetricTokenIsDeclaredAndUsed() throws {
        let sources = Self.settingsSources()
        let components = try XCTUnwrap(sources["SettingsComponents.swift"],
                                       "SettingsComponents.swift not found")
        for token in ["labelStack", "rowContent", "footerStack", "sliderWidth", "valueColumn",
                      "statusDot", "cardPadding"] {
            XCTAssertTrue(components.contains("static let \(token)"),
                          "SettingsMetrics.\(token) is gone — update docs/SETTINGS.md with it")
            XCTAssertTrue(sources.values.contains { $0.contains("SettingsMetrics.\(token)") },
                          "SettingsMetrics.\(token) is declared but nothing reads it")
        }
    }

    // MARK: - Rule 7: colours, fonts and button styles come from the theme

    /// Lines building a raw colour. Each survivor is a preview of notch content, a status or severity colour, a card
    /// of its own or the user's own colours. Only Stage 4 lowers these, by giving each a theme token; until then a
    /// pin can only shrink. The theme is excepted: it is where the colours are made.
    private static let pinnedRawColourCounts: [String: Int] = [
        "AgentStatusSettings.swift": 1,      // status green
        "AllTasksPage.swift": 1,             // the partial-result orange
        "AnimationEditorView.swift": 7,      // the editor's own previews and cards
        "AppearanceSettings.swift": 5,       // the drop targets, an icon's backdrop, and a skin's black and edge
        "DevicesSettings.swift": 1,          // the icon style card's resting fill
        "DownloadsSettings.swift": 3,        // the download style card's resting fill and its progress tint
        "EditPanelView.swift": 1,            // dead code but its #Preview
        "ExtensionsSettings.swift": 3,       // status colours
        "GeneralSettings.swift": 1,          // .tint(.accentColor) around LaunchPermissionRow, shared with onboarding
        "HUDAndOSDSettings.swift": 15,       // HUD style previews and the cards' resting fill
        "IdleAnimationsSettingsSection.swift": 3,  // the cards' resting fill and the delete glyph
        "LiveActivitiesSettings.swift": 10,  // each activity's own colour
        "LockScreenSettings.swift": 15,      // lock screen previews (the glass sample went with its view)
        "MusicSlotConfigurationView.swift": 10,    // the slot canvas
        "ScreenAssistantSettings.swift": 5,  // status colours
        "SecurityFindingRow.swift": 3,       // severity badges
        "SecurityOverview.swift": 1,         // a partial scan's orange, moved up with the newest scan's line
        "SettingsColorPicker.swift": 2,      // the user's colours: presets and the sampler
        "SettingsHelpers.swift": 3,          // the unused "Upgrade to Pro" and "Coming soon" capsules
        "SettingsProviderIcons.swift": 1,    // an icon's fallback tint
        "SpotifyAuthSettingsSection.swift": 1,     // the status dot
        "StatsSettings.swift": 2,            // graph colours
        "TaskDetailPage.swift": 3,           // the unreadable-estimate orange
        "TaskRowList.swift": 2,              // the same orange
        "TasksSettings.swift": 1,            // ReminderPermissionNote's orange
    ]

    /// Lines using a system font: the text styles and `.system`. The same survivors' compact scales, pinned the same
    /// way. Separate from the ad-hoc font rule above, which is about size, so `.font(.caption)` counts in both.
    private static let pinnedSystemFontCounts: [String: Int] = [
        "AnimationEditorView.swift": 22,     // the editor's own dense scale and previews
        "AppearanceSettings.swift": 1,       // an app icon card's placeholder glyph
        "BatterySettings.swift": 2,          // battery previews
        "CustomOSDSettings.swift": 1,        // the "Live Preview" caption
        "DevicesSettings.swift": 2,          // the icon style cards' glyphs
        "EditPanelView.swift": 1,            // dead code but its #Preview
        "ExtensionsSettings.swift": 12,      // the legend and the detail cards
        "HUDAndOSDSettings.swift": 6,        // HUD style previews
        "IdleAnimationsSettingsSection.swift": 5,  // the Add card and the delete glyph
        "LockScreenSettings.swift": 6,       // lock screen previews
        "MusicSlotConfigurationView.swift": 10,    // the slot canvas
        "ScreenAssistantSettings.swift": 1,  // a status line
        "SecurityFindingRow.swift": 1,       // the severity badge
        "SettingsColorPicker.swift": 2,      // the colour popover
        "SettingsHelpers.swift": 2,          // the unused "Upgrade to Pro" and "Coming soon" capsules
        "SettingsPermissionCallout.swift": 1,  // the callout's title
        "SpotifyAuthSettingsSection.swift": 6,     // the sign-in card
        "StatsSettings.swift": 1,            // a graph caption
        "TimerSettings.swift": 1,            // the custom timer's length, its mono readout at medium weight
    ]

    /// The theme makes the colours and holds the system font as Geist's fallback.
    private static let theTheme: Set<String> = ["SettingsTheme.swift"]

    func testNoRawColourIsBuiltUnderSettings() throws {
        assertPinnedCounts(Self.pinnedRawColourCounts, scanner: Self.rawColourLines, rule: "a raw colour",
                           cure: "a colour comes from SettingsTheme, or is a hierarchical style such as .secondary",
                           skipping: Self.theTheme)
        // A floor: the survivors are still there, so a pattern gone blind fails here.
        let found = Self.settingsSources().filter { !Self.theTheme.contains($0.key) }
            .values.reduce(0) { $0 + Self.rawColourLines(in: $1).count }
        XCTAssertGreaterThan(found, 0, "the scan found no raw colour: the pattern went blind")

        for planted in [".foregroundStyle(.red)", ".fill(isOn ? .green : .gray)", "Color.orange.opacity(0.9)",
                        "Color(red: 0.5, green: 0, blue: 1)", "Color(nsColor: .systemBlue)", "NSColor.systemRed",
                        ".settingsDescriptionStyle(tint: .orange)", "AnyShapeStyle(.orange)", ".shadow(color: .black, radius: 2)",
                        ".tint(.accentColor)", ".background(\n    Capsule()\n        .fill(.blue)\n)"] {
            XCTAssertEqual(Self.rawColourLines(in: planted).count, 1, planted)
        }
        for clean in [".foregroundStyle(.secondary)", ".foregroundStyle(Color.secondary)", "Color.clear", ".fill(.clear)",
                      ".foregroundStyle(SettingsTheme.ink)", "// Color.red", "Text(\"Color.red\")", "case .blue:",
                      "selection = .blue", ".tint(tag.tint)", "NSColor(selection)", ".fill(Color.primary.opacity(0.08))"] {
            XCTAssertEqual(Self.rawColourLines(in: clean), [], clean)
        }

        // A real page: the Connect sheet's error line given back its red.
        let sheets = try XCTUnwrap(Self.settingsSources()["TaskConnectSheets.swift"])
        let errorLine = try XCTUnwrap(sheets.range(of: "SettingsErrorText(problem)"), "the Connect sheets have no error line to plant on")
        let planted = sheets.replacingCharacters(in: errorLine, with: "Text(verbatim: problem).settingsDescriptionStyle(tint: .red)")
        XCTAssertEqual(Self.rawColourLines(in: planted).count, (Self.pinnedRawColourCounts["TaskConnectSheets.swift"] ?? 0) + 1)
    }

    func testNoSystemFontIsUsedUnderSettings() throws {
        assertPinnedCounts(Self.pinnedSystemFontCounts, scanner: Self.systemFontLines, rule: "a system font",
                           cure: "a font comes from SettingsTheme, or from the root",
                           skipping: Self.theTheme)
        let found = Self.settingsSources().filter { !Self.theTheme.contains($0.key) }
            .values.reduce(0) { $0 + Self.systemFontLines(in: $1).count }
        XCTAssertGreaterThan(found, 0, "the scan found no system font: the pattern went blind")

        for planted in [".font(.headline)", ".font(.caption2)", ".font(.system(size: 11))", ".font(.system(.caption, design: .monospaced))",
                        ".font(Font.system(size: 9))", ".font(.footnote.bold())", ".font(.subheadline.weight(.semibold))",
                        ".font(isSmall ? .caption : .body)", ".fontWeight(.medium)", "NSFont.systemFont(ofSize: 12)",
                        "let title = Font.title3", ".font(Font(NSFont.labelFont(ofSize: 11)))", ".font(\n    .system(size: 13,\n            weight: .semibold))"] {
            XCTAssertEqual(Self.systemFontLines(in: planted).count, 1, planted)
        }
        for clean in [".font(SettingsTheme.body)", ".font(SettingsTheme.caption)", "// .font(.headline)", "Text(\".font(.title)\")",
                      ".font(isSmall ? SettingsTheme.description : SettingsTheme.bodyStrong)", ".font(SettingsTheme.body.weight(.medium))",
                      "Text(item.title)", ".font(font)"] {
            XCTAssertEqual(Self.systemFontLines(in: clean), [], clean)
        }

        // A real page: the Spotify sheet's title back on the system's headline.
        let spotify = try XCTUnwrap(Self.settingsSources()["SpotifyLoginSheet.swift"])
        let title = try XCTUnwrap(spotify.range(of: ".font(SettingsTheme.sheetTitle)"), "the Spotify sheet has no title to plant on")
        XCTAssertEqual(Self.systemFontLines(in: spotify.replacingCharacters(in: title, with: ".font(.headline)")).count,
                       (Self.pinnedSystemFontCounts["SpotifyLoginSheet.swift"] ?? 0) + 1)
    }

    /// The tag chip's capsule: `SettingsTagChip` keeps the bordered bezel its colour wash shows through, until Stage 5
    /// rebuilds tags.
    private static let pinnedNativeButtonStyleCounts: [String: Int] = ["SettingsComponents.swift": 1]

    func testNativeButtonStylesArePinned() throws {
        assertPinnedCounts(Self.pinnedNativeButtonStyleCounts, scanner: Self.nativeButtonStyleLines,
                           rule: "a native button style",
                           cure: "a button is the root's SettingsButtonStyle, .primary for a main action and .quiet for a glyph or a back row")
        let found = Self.settingsSources().values.reduce(0) { $0 + Self.nativeButtonStyleLines(in: $1).count }
        XCTAssertGreaterThan(found, 0, "the scan found no native button style: the pattern went blind")

        for planted in [".buttonStyle(.bordered)", ".buttonStyle(.borderless)", ".buttonStyle(.borderedProminent)",
                        ".buttonStyle( .bordered )", ".buttonStyle(BorderlessButtonStyle())", ".buttonStyle(BorderedButtonStyle())",
                        "let style = .borderedProminent"] {
            XCTAssertEqual(Self.nativeButtonStyleLines(in: planted).count, 1, planted)
        }
        for clean in [".buttonStyle(SettingsButtonStyle(.quiet))", ".buttonStyle(.plain)", ".buttonStyle(.link)",
                      ".menuStyle(.borderlessButton)", ".buttonBorderShape(.capsule)", "// .buttonStyle(.bordered)",
                      "Text(\".buttonStyle(.borderless)\")"] {
            XCTAssertEqual(Self.nativeButtonStyleLines(in: clean), [], clean)
        }

        // A real page: a task row's ▶ back on the borderless style.
        let rows = try XCTUnwrap(Self.settingsSources()["TaskRowList.swift"])
        let quiet = try XCTUnwrap(rows.range(of: ".buttonStyle(SettingsButtonStyle(.quiet))"), "the task rows have no quiet button to plant on")
        XCTAssertEqual(Self.nativeButtonStyleLines(in: rows.replacingCharacters(in: quiet, with: ".buttonStyle(.borderless)")).count, 1)
    }

    /// `.primary` means the one thing to do here, so it is a sheet's default action or a page header's one verb, never a
    /// callout's or a card's button (2026-11-05, the design review's finding 4; docs/SETTINGS.md). An exact list: a new
    /// primary anywhere else, or one gone from here, fails.
    private static let pinnedPrimaryButtonCounts: [String: Int] = [
        "AnimationEditorView.swift": 1,      // the animation editor sheet's Save or Import
        "IdleAnimationsSettingsSection.swift": 1,  // the URL sheet's Add
        "NewTaskSheet.swift": 1,             // the New Task sheet's Add
        "PolicyRulesEditor.swift": 1,        // the rules editor sheet's Save
        "TaskConnectSheets.swift": 3,        // the three Connect sheets' Connect
        "TaskTagsSheet.swift": 1,            // the Tags sheet's Done
        "TasksSettings.swift": 1,            // the estimate, schedule and end-time sheet's primary
        "TimerPresetSheet.swift": 1,         // the preset sheet's Add or Save
        "TimerOverview.swift": 1,            // Start timer: the Timer page header's one verb
        "TaskRowList.swift": 1,              // New Task: the Tasks page's one verb until Stage 5 gives the page a header
        // A page header's one verb: Security's Scan now, or Connect ADR while ADR Discovery is not found. One style for
        // both, set where the header draws the verb; the empty state draws the same verb in the standard style.
        "SecurityOverview.swift": 1,
        "UsageOverview.swift": 1,            // Refresh: the Usage page header's one verb
        "ClipboardOverview.swift": 1,        // a page header's one verb: Clipboard's Open history panel
    ]

    func testOnlySheetsAndNewTaskArePrimary() throws {
        assertPinnedCounts(Self.pinnedPrimaryButtonCounts, scanner: Self.primaryButtonLines,
                           rule: "a primary button",
                           cure: "a callout's or a card's button takes the standard style; .primary is a sheet's default action or a page header's one verb")
        for planted in [".buttonStyle(SettingsButtonStyle(.primary))", ".buttonStyle(SettingsButtonStyle( .primary ))",
                        "let style = SettingsButtonStyle(.primary)", "SettingsButtonStyle(\n    .primary)"] {
            XCTAssertEqual(Self.primaryButtonLines(in: planted).count, 1, planted)
        }
        for clean in [".buttonStyle(SettingsButtonStyle())", ".buttonStyle(SettingsButtonStyle(.quiet, flush: true))",
                      "// .buttonStyle(SettingsButtonStyle(.primary))", "Text(\"SettingsButtonStyle(.primary)\")",
                      "if prominence == .primary { return SettingsTheme.onPrimary }"] {
            XCTAssertEqual(Self.primaryButtonLines(in: clean), [], clean)
        }

        // A real page: Appearance's Upload skin, a card's button, given back the primary style.
        let appearance = try XCTUnwrap(Self.settingsSources()["AppearanceSettings.swift"])
        let upload = try XCTUnwrap(appearance.range(of: "isSkinImporterPresented = true\n                    }"), "Appearance has no Upload skin to plant on")
        let planted = appearance.replacingCharacters(in: upload, with: "isSkinImporterPresented = true\n                    }\n                    .buttonStyle(SettingsButtonStyle(.primary))")
        XCTAssertEqual(Self.primaryButtonLines(in: planted).count, 1)
        XCTAssertEqual(Self.primaryButtonLines(in: appearance), [])
    }

    /// One entry per line naming `SettingsButtonStyle(.primary)`, its spacing and wrapping aside, read with comments and
    /// strings blanked.
    static func primaryButtonLines(in text: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(text, blankingStrings: true)
        return lines(at: matchOffsets(of: #"\bSettingsButtonStyle\s*\(\s*\.primary\b"#, in: code), in: code, text: text)
    }

    /// The shorthand colours a style or a colour argument can be handed.
    private static let shorthandColours = "red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|gray|black|accentColor"
    private static let systemFontStyles = "largeTitle|title2|title3|title|headline|subheadline|body|callout|footnote|caption2|caption|system"

    /// One entry per line building a raw colour, read with comments and strings blanked: `Color.<name>` or
    /// `NSColor.<name>` but `clear` and the hierarchical styles; any `Color(`, so `Color(red:…)`, `Color(nsColor:)`
    /// and `Color(.systemX)`; a shorthand colour anywhere inside a style modifier's balanced arguments, either arm of
    /// a ternary included; a colour argument (`tint:`, `color:`, `foreground:`, `background:`, `symbolColor:`,
    /// `fill:`) given one; and `AnyShapeStyle(.<colour>)`. `NSColor(someColor)` converts a colour, so it is not one.
    static func rawColourLines(in text: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(text, blankingStrings: true)
        var offsets = matchOffsets(of: #"(?<![A-Za-z0-9_.])(?:NS)?Color\s*\.\s*(?!(?:clear|primary|secondary|tertiary|quaternary)\b)[a-z]\w*"#,
                                   in: code)
        offsets += matchOffsets(of: #"(?<![A-Za-z0-9_.])Color\s*\("#, in: code)
        offsets += matchOffsets(of: #"\b(?:tint|color|foreground|background|symbolColor|fill)\s*:\s*\.(?:"# + shorthandColours + #")\b"#, in: code)
        offsets += matchOffsets(of: #"AnyShapeStyle\(\s*\.(?:"# + shorthandColours + #")\b"#, in: code)
        let styles = #"\.(?:foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|tint|accentColor|shadow|border|overlay)\s*\("#
        for arguments in balancedArguments(after: styles, in: code) {
            offsets += matchOffsets(of: #"(?<![A-Za-z0-9_])\.(?:"# + shorthandColours + #")\b"#, in: code, range: arguments)
        }
        return lines(at: offsets, in: code, text: text)
    }

    /// One entry per line using a system font, read with comments and strings blanked: a text style or `.system`
    /// anywhere inside `.font(…)`'s balanced arguments, ternary arms and `.footnote.bold()` included; `Font.` with one
    /// of those; `.font(Font(`; `NSFont.systemFont…` and its siblings; and `.fontWeight(`.
    static func systemFontLines(in text: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(text, blankingStrings: true)
        var offsets = matchOffsets(of: #"(?<![A-Za-z0-9_.])Font\s*\.\s*(?:"# + systemFontStyles + #")\b"#, in: code)
        offsets += matchOffsets(of: #"\.font\s*\(\s*Font\s*\("#, in: code)
        offsets += matchOffsets(of: #"(?<![A-Za-z0-9_.])NSFont\s*\.\s*(?:systemFont|boldSystemFont|monospacedSystemFont|monospacedDigitSystemFont|labelFont|messageFont|controlContentFont|menuFont|menuBarFont|toolTipsFont|titleBarFont|paletteFont|userFont|userFixedPitchFont)"#,
                                in: code)
        offsets += matchOffsets(of: #"\.fontWeight\s*\("#, in: code)
        for arguments in balancedArguments(after: #"\.font\s*\("#, in: code) {
            offsets += matchOffsets(of: #"(?<![A-Za-z0-9_])\.(?:"# + systemFontStyles + #")\b"#, in: code, range: arguments)
        }
        return lines(at: offsets, in: code, text: text)
    }

    /// One entry per line setting a native button style: `.buttonStyle(.bordered)` or `.buttonStyle(.borderless)`,
    /// in either spelling, and `.borderedProminent` anywhere. Read with comments and strings blanked.
    static func nativeButtonStyleLines(in text: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(text, blankingStrings: true)
        let pattern = #"\.buttonStyle\s*\(\s*(?:\.(?:bordered|borderless)|(?:Bordered|Borderless)ButtonStyle\s*\(\s*\))\s*\)"#
            + #"|(?<![A-Za-z0-9_])\.borderedProminent\b|\bBorderedProminentButtonStyle\b"#
        return lines(at: matchOffsets(of: pattern, in: code), in: code, text: text)
    }

    /// Where each match of `pattern` starts in `code`, in UTF-16 units, within `range` when one is given.
    private static func matchOffsets(of pattern: String, in code: String, range: NSRange? = nil) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad pattern: \(pattern)")
            return []
        }
        let whole = NSRange(location: 0, length: (code as NSString).length)
        return regex.matches(in: code, range: range ?? whole).map(\.range.location)
    }

    /// The inside of each call `opener` starts, which ends at its `(`: from there to the matching `)`. Strings are
    /// already blanked, so a paren in one never counts.
    private static func balancedArguments(after opener: String, in code: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: opener) else {
            XCTFail("bad pattern: \(opener)")
            return []
        }
        let text = code as NSString
        return regex.matches(in: code, range: NSRange(location: 0, length: text.length)).map { match in
            let open = match.range.location + match.range.length - 1
            var depth = 0, index = open
            repeat {
                let unit = text.character(at: index)
                if unit == 0x28 { depth += 1 } else if unit == 0x29 { depth -= 1 }
                index += 1
            } while index < text.length && depth > 0
            // Past the closing paren, or at the end of an unbalanced call.
            let end = depth == 0 ? index - 1 : index
            return NSRange(location: open + 1, length: max(0, end - open - 1))
        }
    }

    /// The source lines holding `offsets`, once each, in order, trimmed. Blanking keeps every line, so a line of the
    /// blanked code is the same line of the source.
    private static func lines(at offsets: [Int], in code: String, text: String) -> [String] {
        let nsCode = code as NSString
        let numbers = Set(offsets.map { nsCode.substring(to: $0).components(separatedBy: "\n").count - 1 })
        let lines = text.components(separatedBy: "\n")
        return numbers.sorted().map { lines[$0].trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Rule 4: the components stay selectable

    func testTheSharedComponentsKeepTheirTextSelection() throws {
        let text = try XCTUnwrap(Self.settingsSources()["SettingsComponents.swift"],
                                 "SettingsComponents.swift not found")
        for component in ["SettingsSectionHeader", "SettingsFooter", "SettingsValueText"] {
            let region = Self.region(of: component, in: text)
            XCTAssertNotNil(region, "\(component) is gone — update this test and docs/SETTINGS.md")
            if let region {
                XCTAssertTrue(region.contains(".textSelection(.enabled)"),
                              "\(component) lost its .textSelection — every caller loses copyability at once")
            }
        }
        // These select through settingsDescriptionStyle, which carries the .textSelection — and,
        // for the tinted ones, keeps them the same size as every other secondary line.
        for component in ["SettingsStatusText", "SettingsRowLabel", "SettingsErrorText"] {
            let region = Self.region(of: component, in: text)
            XCTAssertNotNil(region, "\(component) is gone — update this test and docs/SETTINGS.md")
            if let region {
                XCTAssertTrue(region.contains("settingsDescriptionStyle("),
                              "\(component) stopped going through settingsDescriptionStyle — it loses selectability and drifts off the type scale")
            }
        }
        let style = Self.region(of: "View", in: text) ?? text
        XCTAssertTrue(style.contains(".textSelection(.enabled)"),
                      "settingsDescriptionStyle() lost its .textSelection")
    }

    // MARK: - The scanners must actually catch things

    func testTheHeaderScannerCatchesAPlantedOffender() {
        let planted = """
        Section {
            row
        } header: {
            Text("Planted")
        }
        """
        XCTAssertEqual(Self.rawHeaderOffenders(in: planted).count, 1)
        XCTAssertEqual(Self.rawHeaderOffenders(in: planted.replacingOccurrences(
            of: "Text(", with: "SettingsSectionHeader(")).count, 0)
        XCTAssertEqual(Self.rawHeaderOffenders(in: "} header: { Text(\"X\") }").count, 1)
        // A comment explaining the rule is not an offender.
        XCTAssertEqual(Self.rawHeaderOffenders(in: "// } header: { Text(\"X\") }").count, 0)
    }

    func testTheFooterScannerCatchesAPlantedOffender() {
        let planted = """
        } footer: {
            Text("Planted")
        }
        """
        XCTAssertEqual(Self.rawFooterOffenders(in: planted).count, 1)
        XCTAssertEqual(Self.rawFooterOffenders(in: planted.replacingOccurrences(
            of: "Text(", with: "SettingsFooter(")).count, 0)
    }

    func testTheChainScannerCatchesAPlantedOffenderAndPassesTheCures() {
        let planted = """
        Text("info")
            .font(.caption)
            .foregroundStyle(.secondary)
        """
        XCTAssertEqual(Self.unselectableInformationalChains(in: planted).count, 1)
        XCTAssertEqual(Self.unselectableInformationalChains(
            in: planted + "\n    .textSelection(.enabled)").count, 0)
        XCTAssertEqual(Self.unselectableInformationalChains(in: """
        Text("info")
            .settingsDescriptionStyle()
        """).count, 0)
        // The older spelling counts too.
        XCTAssertEqual(Self.unselectableInformationalChains(in: """
        Text("Inactive")
            .foregroundColor(.secondary)
        """).count, 1)
        // Primary text is not the rule's business.
        XCTAssertEqual(Self.unselectableInformationalChains(in: "Text(\"title\")").count, 0)
        // The theme's spellings of the same text count too, or moving to a token would hide it.
        for token in [".foregroundStyle(SettingsTheme.inkSecondary)", ".font(SettingsTheme.description)",
                      ".font(SettingsTheme.caption)", ".font(SettingsTheme.micro)"] {
            let themed = "Text(\"info\")\n    \(token)"
            XCTAssertEqual(Self.unselectableInformationalChains(in: themed).count, 1, token)
            XCTAssertEqual(Self.unselectableInformationalChains(in: themed + "\n    .textSelection(.enabled)").count, 0, token)
        }
        XCTAssertEqual(Self.unselectableInformationalChains(in: "Text(\"title\")\n    .font(SettingsTheme.body)").count, 0)
    }

    func testTheContentStandardScannersCatchPlantedOffenders() {
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.caption)").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.caption2)").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.system(size: 11))").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.system(.caption, design: .monospaced))").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "// .font(.caption) is banned on row text").count, 0)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").settingsDescriptionStyle()").count, 0)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.subheadline)").count, 0)
        // A token, or a font by name, cannot launder a small font past the rule.
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(.custom(\"Geist-Regular\", size: 10))").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(SettingsTheme.caption)").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(SettingsTheme.micro)").count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: "Text(\"x\").font(SettingsTheme.body)").count, 0)

        XCTAssertEqual(Self.handBuiltValueControlLines(in: "Slider(value: $x, in: 0...1)").count, 1)
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "// Slider(value: $x, in: 0...1)").count, 0)
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "SettingsSliderRow(\"T\", value: $x, in: 0...1, valueText: nil)").count, 0)
        // Ours, by hand, count once each: only a row is not hand-built.
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "SettingsSlider(value: $x, in: 0...1)").count, 1)
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "SettingsStepper(value: $v, in: 0...9) { Text(\"a\") }").count, 1)
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "SettingsSlider<Double>(value: $x, in: 0...1) { Text(\"a\") }").count, 1)
        XCTAssertEqual(Self.handBuiltValueControlLines(in: "Stepper (value: $v, in: 0...9) { Text(\"a\") }").count, 1)

        XCTAssertEqual(Self.paddingLines(in: ".padding(.vertical, 8)").count, 1)
        XCTAssertEqual(Self.paddingLines(in: "// .padding(12)").count, 0)
        XCTAssertEqual(Self.paddingLines(in: ".frame(width: 220)").count, 0)

        // The same offenders, wrapped the way a long call is usually written. A rule that only
        // reads one physical line at a time is one reformat away from being switched off.
        XCTAssertEqual(Self.handBuiltValueControlLines(in: """
        Slider(
            value: $value,
            in: range
        )
        """).count, 1)
        XCTAssertEqual(Self.adHocFontLines(in: """
        Text("x")
            .font(.system(size: 13,
                          weight: .semibold))
        """).count, 1)
        XCTAssertEqual(Self.paddingLines(in: """
        Text("x")
            .padding(
                .vertical, 8)
        """).count, 1)
        // Joining lines must not join across a comment that sits inside the call.
        XCTAssertEqual(Self.handBuiltValueControlLines(in: """
        Slider(
            // value comes from the binding above
            value: $value, in: range)
        """).count, 1)
    }

    func testTheScanReadTheRealSources() {
        let sources = Self.settingsSources()
        XCTAssertGreaterThan(sources.count, 8, "the Settings directory moved — fix settingsSources()")
        XCTAssertNotNil(sources["SettingsView.swift"])
        XCTAssertNotNil(sources["SettingsComponents.swift"])
        XCTAssertNotNil(sources["SettingsTheme.swift"], "the scan no longer reaches DesignSystem/")
    }

    /// A rule that cannot see a subfolder passes on every file in it, so the walk itself is proved.
    func testTheWalkReachesSubfoldersAndReportsARepeatedName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("DesignSystem/Inner")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        for path in ["Top.swift", "DesignSystem/Theme.swift", "DesignSystem/Inner/Top.swift", "DesignSystem/Notes.md"] {
            try Data().write(to: root.appendingPathComponent(path))
        }
        let files = Self.swiftFiles(under: root)
        XCTAssertEqual(files.map(\.lastPathComponent).sorted(), ["Theme.swift", "Top.swift", "Top.swift"])
        XCTAssertEqual(Self.repeatedNames(in: files), ["Top.swift"])
        XCTAssertEqual(Self.repeatedNames(in: files.filter { $0.deletingLastPathComponent().lastPathComponent != "Inner" }), [])
    }

    // MARK: - Plumbing

    /// Every `.swift` file under `Kannu/components/Settings`, at any depth, keyed by file name. The
    /// views are not compiled into this target, so the rules read the sources as text — the same
    /// route `SettingsHighlightInventoryTests` takes. Keyed by name, so a second file with the same
    /// name would hide the first from every rule here: that is a failure, not a quiet overwrite.
    private static func settingsSources() -> [String: String] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kannu/components/Settings")
        let files = swiftFiles(under: dir)
        XCTAssertEqual(repeatedNames(in: files), [], "two files under Settings share a name, so a rule reads only one of them")
        var out: [String: String] = [:]
        for file in files {
            out[file.lastPathComponent] = try? String(contentsOf: file, encoding: .utf8)
        }
        return out
    }

    private static func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            files.append(file)
        }
        return files
    }

    private static func repeatedNames(in files: [URL]) -> [String] {
        Dictionary(grouping: files, by: \.lastPathComponent).filter { $0.value.count > 1 }.keys.sorted()
    }

    /// The shared shape of every pinned-count rule: no file may exceed its pin, and no pin may
    /// outlive the code it describes — a stale pin hides the next offender behind its slot.
    /// `skipped` files are where a rule's subject is defined, such as the theme for colours.
    private func assertPinnedCounts(_ pinned: [String: Int],
                                    scanner: (String) -> [String],
                                    rule: String,
                                    cure: String,
                                    skipping skipped: Set<String> = [],
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        var counts: [String: Int] = [:]
        for (path, text) in Self.settingsSources() where !skipped.contains(path) {
            let found = scanner(text)
            if !found.isEmpty { counts[path] = found.count }
            let allowed = pinned[path] ?? 0
            if found.count > allowed {
                XCTFail("""
                \(path): \(found.count) lines with \(rule) (pinned: \(allowed)). \(cure). Fix it, \
                or pin it here with the reason it cannot follow the rule. \
                First lines: \(found.prefix(6).joined(separator: " | "))
                """, file: file, line: line)
            }
        }
        for (path, allowed) in pinned {
            let found = counts[path] ?? 0
            XCTAssertEqual(allowed, found,
                           "\(path): pinned \(allowed) lines with \(rule) but found \(found) — move the pin so it keeps meaning something",
                           file: file, line: line)
        }
    }

    /// Non-comment lines carrying a caption-sized, pixel-sized or named font. The small theme tokens
    /// count too, so a token cannot launder a font this rule would otherwise catch.
    private static func adHocFontLines(in text: String) -> [String] {
        matchingLines(in: text) {
            $0.contains(".font(.caption") || $0.contains(".font(.system(size:")
                || $0.contains(".font(.system(.caption") || $0.contains(".font(.custom(")
                || $0.contains(".font(SettingsTheme.caption") || $0.contains(".font(SettingsTheme.micro")
        }
    }

    /// Non-comment lines building a slider or a stepper directly, Apple's or ours: `Slider(value:`,
    /// `SettingsSlider(value:`, `Stepper(value:` and `SettingsStepper(value:`, never a row.
    private static func handBuiltValueControlLines(in text: String) -> [String] {
        matchingLines(in: text) {
            $0.range(of: #"(?<![A-Za-z0-9_])(?:Settings)?(?:Slider|Stepper)\s*(?:<[^>]*>)?\s*\(\s*value:"#, options: .regularExpression) != nil
        }
    }

    /// Non-comment lines adding padding.
    private static func paddingLines(in text: String) -> [String] {
        matchingLines(in: text) { $0.contains(".padding(") }
    }

    private static func matchingLines(in text: String, where predicate: (String) -> Bool) -> [String] {
        joinedStatements(in: text).filter(predicate)
    }

    /// Comment lines dropped, then every line break that sits inside a call — after an opening
    /// paren or a comma — joined up. Without this the rules would only see code as it happens to
    /// be wrapped today: `Slider(value: $x, in: r)` would fail the guard while the same call
    /// split across four lines would sail through it.
    private static func joinedStatements(in text: String) -> [String] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isComment($0) }
            .joined(separator: "\n")
        let joined = code.replacingOccurrences(of: #"([(,])[ \t]*\n[ \t]*"#, with: "$1",
                                               options: .regularExpression)
        return joined.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func isComment(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
    }

    /// Line numbers (1-based) where a `header: {` is immediately answered by a raw `Text(`.
    private static func rawHeaderOffenders(in text: String) -> [Int] {
        offenders(in: text, opener: "header: {")
    }

    private static func rawFooterOffenders(in text: String) -> [Int] {
        offenders(in: text, opener: "footer: {")
    }

    private static func offenders(in text: String, opener: String) -> [Int] {
        var out: [Int] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where !isComment(line) {
            guard let range = line.range(of: opener) else { continue }
            let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("Text(") {
                out.append(index + 1)
            } else if rest.isEmpty, index + 1 < lines.count,
                      lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix("Text(") {
                out.append(index + 2)
            }
        }
        return out
    }

    /// First lines of `Text(` chains styled secondary/caption/subheadline with no selection and
    /// no `settingsDescriptionStyle()`. Mirrors what a reader sees: the chain is the `Text(` line
    /// plus the `.modifier` lines that follow it.
    private static func unselectableInformationalChains(in text: String) -> [String] {
        var out: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            // A bare `Text(` — not the tail of `SettingsValueText(` and friends.
            guard let range = line.range(of: "Text("),
                  range.lowerBound == line.startIndex
                    || !line[line.index(before: range.lowerBound)].isLetter,
                  !isComment(line[...]) else { index += 1; continue }
            var chain = [line]
            var next = index + 1
            while next < lines.count,
                  lines[next].trimmingCharacters(in: .whitespaces).hasPrefix(".") {
                chain.append(lines[next])
                next += 1
            }
            let joined = chain.joined(separator: "\n")
            let informational = joined.contains(".foregroundStyle(.secondary)")
                || joined.contains(".foregroundColor(.secondary)")
                || joined.contains(".font(.caption")
                || joined.contains(".font(.subheadline")
                || joined.contains(".foregroundStyle(SettingsTheme.inkSecondary)")
                || joined.contains(".font(SettingsTheme.description")
                || joined.contains(".font(SettingsTheme.caption")
                || joined.contains(".font(SettingsTheme.micro")
            if informational, !joined.contains(".textSelection"),
               !joined.contains(".settingsDescriptionStyle") {
                out.append(line.trimmingCharacters(in: .whitespaces))
            }
            index = next
        }
        return out
    }

    private static func region(of declaration: String, in text: String) -> String? {
        guard let start = text.range(of: "struct \(declaration)")
            ?? text.range(of: "extension \(declaration)")
            ?? text.range(of: "func \(declaration)") else { return nil }
        let rest = text[start.lowerBound...]
        if let end = rest.range(of: "\nstruct ") ?? rest.range(of: "\nextension ") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }
}
