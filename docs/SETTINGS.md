# Settings construction rules

Shown to users as **Brain**; code keeps the Settings names.

How a Settings section is built in Kannu. These rules exist so every tab reads as one calm product
of its own, on one theme, and so anything informational on screen can be selected and copied. They
are enforced, not advisory: `KannuTests/SettingsLayoutRulesTests.swift` scans the sources under
`Kannu/components/Settings/` and fails on a violation, and `.githooks/pre-commit` runs a fast
subset of the same checks. When a rule here and the test disagree, the test wins — fix this file.

## The one law

**Explanatory text is selectable; control labels never are.** A selectable `Text` inside a
`Toggle`/`Picker`/`Button`/`Stepper`/`Slider`/`Menu` label swallows the click meant for the
control. That is why a row with a description hides the control's own label (kept for
accessibility) and draws the title beside the control instead — and why a caption must never live
inside a control's label. If a control needs a caption, put the text next to the control
(`SettingsRow(title, description:)`, or an adjacent `VStack` with the control's label hidden),
never inside it.

## Which component for what

All in `Kannu/components/Settings/SettingsComponents.swift`; the styles and the theme they draw with
live in `DesignSystem/` beside it (below). Never rebuild these shapes by hand.

| You are adding | Use |
|---|---|
| A page | `SettingsPage { … }`: one scroll view across the panel, its sections in one column — never `Form` (below, "Pages and sections") |
| A product page: what it is about, then its settings | `SettingsProductPage(settingsTitle:) { product } settings: { sections }`, its actions on `SettingsForm` (below, "Product pages"); anything live follows "Live data" |
| A group of rows | `SettingsSection { rows } header: { … } footer: { … }`, called as `Section` was — never `Section` |
| A section header | `SettingsSectionHeader("…")` — never a raw `Text` in `header: {}` |
| Text under a group of rows | `SettingsFooter("…")` — never a raw `Text` in `footer: {}` |
| A row: title (+ caption) with a trailing control | `SettingsRow("Title", description: "…") { control }` |
| A choice of one value among several | `SettingsSelect` in a `SettingsRow` — `choices:` for literal options, `style: .segmented` for two or three short ones, never `Picker` (below, "Choices") |
| A text field | The native field with `.settingsField()` last on its chain; on a page, in a `SettingsRow` that names it; what to type in `prompt:` (below, "Values and fields") |
| A date and time | `SettingsDateField` — our button showing the date, and our popover holding the system's calendar grid and time field; never `DatePicker`. The popover focuses its calendar and Escape closes only it; a date is reached by keyboard under Full Keyboard Access |
| A row that only says something, with no control | `SettingsNoteRow("Title", description: "…")` |
| A slider row | `SettingsSliderRow` — our `SettingsSlider`, one width everywhere, selectable readout; never `Slider` (below, "Values and fields") |
| A stepper row | `SettingsStepperRow` — the value then our `SettingsStepper`, same column; never `Stepper` |
| Several footer lines under one group | `SettingsFooterStack { … }` |
| A read-only trailing value (path, date, count) | `SettingsValueText(value)` |
| A status line with a ready dot | `SettingsStatusText(text, isReady:)` |
| A red error line under a control | `SettingsErrorText(message)` |
| One or more buttons on a row | `SettingsActionRow` — trailing, never a lone left-hanging button (the one exception: a sub-page's "‹ Back" row, below). A row of buttons alone in its card takes a title and a caption too (below, "Section rules") |
| A glyph on a row (▶, ›, −), a back row, a link-like action | `SettingsButtonStyle(.quiet)` — bare at rest, filled under the pointer; never `.borderless`. A lone one under text, on that text's column (a back row, "Open ›", a finding's "Details ›"), is `flush: true`, so its label keeps the column's edge (below, "The content standard"); never one beside text, where its fill would reach over the text. Only `.quiet` takes `flush` |
| A badge beside a title ("Beta", "Alpha", "Built-in") | `SettingsBadge`, through `customBadge(text:)` and `alphaBadge()`: the secondary ink on the line colour, the caption's size, title case, a 4-pt radius. Never a capsule of a colour of its own. The sidebar's BETA pill is Stage 6's |
| A choice drawn as cards (a HUD style, an idle animation, a skin, an icon) | `.settingsChoiceRing(shape, isSelected:)` on the tile and `.settingsChoiceLabel(isSelected:)` on its name (below, "Choices") |
| A callout, or a row's expanded details, inside a section | `SettingsPermissionCallout`, or `.settingsCalloutCard()`: the card's own colour inside a 1-pt line border, never a darker slab, and its buttons the standard style. A callout's title is orange for a permission something needs and `accentStrong` for an offer (Focus, Shelf's Full Disk Access, ADR), never a colour of its own |
| Overflow actions on a row | `SettingsMoreMenu { … }` (the "…" button): our quiet button over a native menu |
| A menu | Our button over a native menu: `.menuStyle(.button)`, `.buttonStyle(SettingsButtonStyle(…))` and `.menuIndicator(.hidden)` on the `Menu`, and a `chevron.down` in its label when it needs one. The items stay a native menu, with its keyboard, type-to-select and VoiceOver |
| Tags, removable or offered to add, wrapping | `SettingsTagChip` inside a `SettingsFlowLayout` — a capsule; `tint:` washes it in a tag's colour; `init(adding:kind:)` for an offer ("#planning", "+ pl") |
| Free-standing explanatory text | `.settingsDescriptionStyle()` (selectable, secondary, wraps) |
| A spacing, a width, a dot size | `SettingsMetrics.<token>` — never a number in place |
| A copy-to-pasteboard action for agents | `CopyForAgentButton` |

## The design system

Pages use components, components use the theme. A page names neither a colour nor a font when a
component already does.

- **`DesignSystem/` holds one type per file**, each starting with the GPL block:
  `SettingsTheme` (colours, fonts and measures), `SettingsToggleStyle`, `SettingsButtonStyle`,
  `SettingsLabeledContentStyle`, `SettingsDisclosureGroupStyle`, `settingsDesignSystem()`, the choice
  control (`SettingsSelect`, `SettingsSelectList`), the field's chrome (`SettingsField`), the value
  controls (`SettingsSlider`, `SettingsStepper`), the sheet (`SettingsSheet`), the date
  (`SettingsDateField`), the page and its sections (`SettingsPage`, `SettingsSection`,
  `SettingsPageInsetKey`), the product page (`SettingsProductPage`), the badge (`SettingsBadge`), a
  choice card's and a callout's looks (`SettingsChoiceCard`, `SettingsCalloutCard`: view modifiers, no
  type), and the shell's own views (below).
- **There is one root.** `settingsDesignSystem()` is what every page inherits. The window's shell and
  the snapshot boards both apply it, so they cannot drift, and nothing else sets the form style beside
  it. It still sets the grouped form style and hides a `Form`'s background, though no page is a `Form` any
  more (below, "Pages and sections"). It has no `.foregroundStyle`: that
  would recolour the labels of native prominent buttons and menus. A sheet is a window of its own, and
  whether SwiftUI passes the root into a presentation cannot be told from source, so each presented
  window applies it again: `SettingsSheet` for every sheet, and the two large sheets, the animation
  editor and Spotify's sign-in, themselves. A sheet is never a `Form`, so the second root changes
  nothing in it.
- **The root's font reaches a section's header and footer**, so `SettingsSectionHeader` and
  `SettingsFooter` say their own, and anything else inside a footer must too. `SettingsSection` gives the
  footer the secondary ink, as a grouped `Form` did.
- **Geist when bundled, the system font at the same size when not.** Only the theme names a font, and
  only the theme uses the system's: a text style or `.system` anywhere else is pinned per file and can
  only shrink (below, "Colours and fonts").
- **The accent has two strengths.** `accent` is the logo's eye blue, for fills such as a switch that is
  on. `accentStrong` is for what must be read, and it is the root's tint, because a root tint also
  colours Markdown links. Native controls that honour `.tint` show it.
- **A disclosure's button starts after its title.** A row's description is selectable, and selectable
  text inside a button fights for the click, so the chevron and the empty space beside the title toggle
  it, as a native disclosure's chevron does.

A call-site style beats the root, so these stay on purpose:

| Site | Why |
|---|---|
| `SettingsToggleStyle(showsLabel: false)` | A row that draws the title itself. A custom style ignores `.labelsHidden()`, so it is told |
| `SettingsButtonStyle(.primary)` | A sheet's default action, or a page header's one verb; Tasks' New Task row stands in for that verb until Stage 5 gives the page its header. Never a callout's or a card's button, which take the standard style, or a page shows three to five primaries and none of them ranks. A custom style cannot see `.keyboardShortcut(.defaultAction)`, so a site says so itself |
| `.buttonStyle(.link)` on a `Link` | The root's button style would otherwise draw it as a button |
| `.labeledContentStyle(.automatic)` on a checkbox | The root's labelled-row style pushes the label and the control to opposite edges |
| `.disclosureGroupStyle(.automatic)` in `AllTasksPage` | Kept until Stage 5 rebuilds the page. A grouped `Form` built its rows lazily; on a page, the native disclosure builds them at once, as ours does |
| `.foregroundStyle(.secondary)` on a bare `LabeledContent` value | The root's labelled-row style leaves the content's colour alone, or it would grey what is typed into a field |
| `.plain` on a view that draws itself, and `AccessoryBarButtonStyle` | A card, a suggestion or a sidebar row draws its own chrome. `AccessoryBarButtonStyle` is `EditPanelView`'s, dead code (Stage 4) |

What stays native, and why:

| Control | Why |
|---|---|
| System alerts and dialogs: `ModalPresenter`'s `NSAlert`, SwiftUI's `.alert` and `.confirmationDialog` | They cannot be restyled, and `ModalPresenter` is the only modal path (docs/REGRESSIONS.md, entry 14) |
| File panels: `NSOpenPanel` through `ModalPresenter`, and `.fileImporter` | They cannot be restyled |
| The colour panel | Never opened under Settings: the swatch's own popover replaced it |
| The calendar grid and time field inside `SettingsDateField` | They cannot be restyled; the popover around them is ours |
| A popover's own arrow and chrome | `NSPopover`'s; its content paints the panel |
| Menu items: `SettingsMoreMenu`'s, `Connect…`'s, Reset's, the estimate presets', and every `.contextMenu` | A native menu keeps its keyboard, type-to-select and VoiceOver; only the trigger is ours |
| All tasks' filter menu and its four pickers | Ticked submenus of a native `Menu`, which no popover can replace. Stage 5 rebuilds the page with a Tag filter through `SettingsSelect` |
| New Task's two checkboxes | Stage 5 rebuilds the task form |
| `SettingsTagChip`'s `.bordered` capsule | Stage 5 rebuilds tags |
| The sidebar search, and a local task's inline title | Plain fields with chrome or typography of their own |
| `KeyboardShortcuts.Recorder`, Spotify's `WKWebView` | AppKit views of their own |
| `.tint(.accentColor)` around `LaunchPermissionRow` | Shared with onboarding (Stage 6), so Allow stays `.borderedProminent`, and its white label cannot be read on the root's eye blue in dark |
| The menu bar's look | The redesign plan keeps it |

**To add a token:** one flat `static let` in `SettingsTheme.swift`, in the group it belongs to, with
something reading it in the same change. `testEveryThemeTokenIsRead` rejects a token with no reader, and
a colour that text sits on or is drawn in goes into `testTheThemeIsReadable`. A new file goes in
`DesignSystem/` with no `project.pbxproj` edit. `SettingsDesignSystemRulesTests` holds all of this, and
`--kannu-snapshot-tabs designSystem` renders every resting and disabled state, and every colour and
font token by name. Hover and press take a pointer, so no board shows them.

## Colours and fonts

A colour or a font comes from the theme, through a component or a token. `SettingsLayoutRulesTests` reads
every file under Settings but the theme, with comments and strings blanked, and counts one entry per line:

- **A raw colour:** `Color.<name>` or `NSColor.<name>`; any `Color(`, so `Color(red:…)`, `Color(nsColor:)` and
  `Color(.systemX)`; a shorthand colour (`.red` to `.black`, and `.accentColor`) anywhere inside a style
  modifier's arguments (`foregroundStyle`, `fill`, `stroke`, `background`, `tint`, `shadow`, `overlay` and
  the rest), either arm of a ternary included; a `tint:`, `color:`, `foreground:`, `background:`,
  `symbolColor:` or `fill:` argument given one; and `AnyShapeStyle(.<colour>)`.
- **Not raw:** the hierarchical styles (`.primary`, `.secondary`, `.tertiary`, `.quaternary`), which follow
  the appearance and are the cure for a bare value; `.clear`, the sidebar's focus stop and the readout's
  reserved column; `NSColor(someColor)`, which only converts a colour; and every `SettingsTheme` token.
- **A system font:** a text style (`.headline`, `.caption` and the rest) or `.system` inside `.font(…)`, a
  ternary's arms and `.footnote.bold()` included; `Font.` with one of those; `.font(Font(`;
  `NSFont.systemFont…` and its siblings; and `.fontWeight(`. The theme keeps the system font as Geist's
  fallback. "No ad-hoc type in a row" (below) is about size and this rule about the family, so
  `.font(.caption)` counts in both.
- **A native button style:** `.bordered`, `.borderless` and `.borderedProminent`. A button is ours:
  `.primary` for a main action, `.quiet` for a glyph or a back row. The tag chip's capsule is the one left.

The survivors are pinned per file and can only shrink. After Stage 3 they are 127 colour lines and 106 font
lines, in previews of notch content, status and severity colours, cards with a compact scale of their own,
and the user's own colours. Stage 4 gives each a token and empties both tables; the test's pins are the
numbers, and this table only says why.

| File | Colours | Fonts | Why they remain |
|---|---|---|---|
| `AgentStatusSettings.swift` | 1 | 0 | Status green (Detected Editors' green and caption left with it, Stage 4 child 2) |
| `AllTasksPage.swift` | 1 | 0 | The partial-result orange |
| `AnimationEditorView.swift` | 8 | 22 | The editor's own dense scale and previews |
| `AppearanceSettings.swift` | 5 | 1 | The skin and icon grids' drop targets, an icon's backdrop and placeholder, a skin's black and edge |
| `BatterySettings.swift` | 0 | 2 | Battery previews |
| `ClipboardSettings.swift` | 4 | 1 | Status colours |
| `CustomOSDSettings.swift` | 0 | 1 | The "Live Preview" caption |
| `DevicesSettings.swift` | 1 | 2 | The icon style cards' resting fill and glyphs |
| `DownloadsSettings.swift` | 3 | 0 | The style cards' resting fill and the progress tint |
| `EditPanelView.swift` | 1 | 1 | Dead code but its `#Preview` |
| `ExtensionsSettings.swift` | 3 | 12 | Status colours; the legend and detail cards |
| `GeneralSettings.swift` | 1 | 0 | `.tint(.accentColor)` around `LaunchPermissionRow`, shared with onboarding |
| `HUDAndOSDSettings.swift` | 15 | 6 | HUD style previews and the cards' resting fill |
| `IdleAnimationsSettingsSection.swift` | 3 | 5 | The cards' resting fill, the Add card and the delete glyph |
| `LiveActivitiesSettings.swift` | 10 | 0 | Each activity's own colour |
| `LockScreenSettings.swift` | 15 | 6 | Lock screen previews |
| `MusicSlotConfigurationView.swift` | 10 | 10 | The slot canvas |
| `ScreenAssistantSettings.swift` | 5 | 1 | Status colours |
| `SecurityFindingRow.swift` | 3 | 1 | Severity badges |
| `SettingsColorPicker.swift` | 2 | 2 | The user's colours (presets, sampler) |
| `SettingsHelpers.swift` | 3 | 2 | The unused "Upgrade to Pro" and "Coming soon" capsules |
| `SettingsPermissionCallout.swift` | 0 | 1 | The callout's title |
| `SettingsProviderIcons.swift` | 1 | 0 | An icon's fallback tint |
| `SpotifyAuthSettingsSection.swift` | 1 | 6 | Status dot; the sign-in card |
| `StatsSettings.swift` | 2 | 1 | Graph colours |
| `TaskDetailPage.swift` | 3 | 0 | The unreadable-estimate orange |
| `TaskRowList.swift` | 2 | 0 | The same orange |
| `TasksSettings.swift` | 1 | 0 | `ReminderPermissionNote`'s orange |
| `TimerSettings.swift` | 1 | 5 | The preset editor |

`SettingsDesignSystemRulesTests` holds `DesignSystem/`'s animations to Reduce Motion the same way: every
`withAnimation` and `.animation` there is `reduceMotion ? nil :` the theme's `quickAnimation` ease, never a
spring or the default. Pages keep their own until Stage 4.

## Choices

A choice of one value among several is `SettingsSelect`, in a `SettingsRow` that draws its title. SwiftUI on
macOS 14 has no custom picker style, and a custom view cannot read `.tag()`s, so the options are data:
`options:` with an `optionTitle:` (`\.localizedName`), or `choices: [value: String(localized: "…")]` for
literal ones, in the order written. `Picker` is banned under Settings; `SettingsLayoutRulesTests` pins the four
All tasks keeps.

- **The trigger** is a button in our style showing the value and a chevron. A short list keeps its widest
  title's width, so the row does not move when the choice changes. A saved value no longer among the options
  shows its own title (a dash when `choices:` has none for it), so the button is never blank. It draws no
  title: the row does, and VoiceOver reads the title as its label and the value as its value.
- **The list** is our own popover: one row per option, a tick on the chosen one, the keyboard's row
  highlighted. Past ten options (`SettingsSelectNavigation.searchThreshold`) a search field leads, ranked as
  Brain's search ranks, and the rows scroll at ten and a half rows' height; a shorter list takes typed letters.
- **Segments**, `style: .segmented`, draw two or three short options in place: one click, every choice in view.
- **Choice cards** (a HUD style, an idle animation, a notch skin, an app icon, a download or Bluetooth icon style) say
  "selected" one way: a 2-pt `accentStrong` ring around the tile (`settingsChoiceRing`; the eye blue is 2.3:1 on a
  light card, under the 3:1 a state mark needs), and the name under it in ink, `bodyStrong` when chosen and `body`
  when not (`settingsChoiceLabel`). No dot, no pill and no tinted fill. A second state, such as an idle animation's
  "Built-in", is the badge. Each card is a `Button` in the `.plain` style that carries `.isSelected` itself, as a
  sidebar row does, so the keyboard reaches it and VoiceOver hears which card is chosen; its name is not selectable,
  and a glyph on it (an idle animation's delete) is an overlay over the button, never inside its label.

| Key | Where | Does |
|---|---|---|
| Space | The trigger, under Full Keyboard Access | Opens the list. Return stays with the window's default button |
| ↑ ↓ | The list, with or without a field | Moves the highlight, announced |
| Return | The list or its field | Picks the highlight, or the first match |
| Escape | The list or its field | Closes; the choice stays as it was |
| Letters | A list with no field | Type-to-select, a one-second prefix |
| Typing | The field | Filters, best match first; the highlight goes to the first match |
| ← → | A segment, under Full Keyboard Access | Moves the choice |
| VoiceOver adjust | The trigger | Steps the choice without opening the list |

- **A popover closes on disappear.** Closing Brain takes its content out of the window and runs `onDisappear`
  (docs/REGRESSIONS.md, entry 22), while the flag that opened it survives the close, so a list left open would
  come back on reopening. Every `.popover(isPresented:)` under Settings sets its flag to false there, and
  `SettingsDesignSystemRulesTests` holds that.
- **The arrows reach the list through a key monitor**, because a focused field's editor takes them before
  SwiftUI sees them. It acts only on the list's own window while that window is key, never while an input
  method is composing, and goes with the list (`dismantleNSView`).
- **The list is a view of its own, `SettingsSelectList`,** because a popover is a window of its own and no
  board captures one: `--kannu-snapshot-tabs selectList` draws it open, and `designSystem` and `components`
  draw the select in its rows.

## Values and fields

A slider is `SettingsSlider` and a stepper `SettingsStepper`, inside `SettingsSliderRow` and `SettingsStepperRow`,
which draw the title and the readout. SwiftUI on macOS 14 has no custom slider or stepper style, so both are our
own views. `Slider` and `Stepper` are banned under Settings, and `SettingsLayoutRulesTests` pins the few of ours
drawn by hand outside a row.

- **A slider's value is its readout**, `valueText` ("Width" and "36 px"), never part of its title, where it left the
  readout column empty and the bar 40 pt short of its neighbours'. `valueText: nil` is for a row with no number.
- **The slider** is a track filled with the accent up to a knob. A click on the track jumps the knob there and a
  drag moves it: Brain moves by its title row only, so the drag is the slider's. A step snaps from the lower
  bound; with none, a key moves it by 5 % of its range. No animation: the knob follows the value. Right to left it
  is drawn mirrored, as a native slider is.
- **The stepper** is − and + in one capsule, its value beside it in the row, never inside. A button at its end of
  the range turns grey and does nothing. No press-and-hold repeat; a held arrow key repeats.
- **One element for VoiceOver**: the row's title is its label, the readout (or else the number) its value, and an
  adjustable action lets VoiceOver move it. A disabled one ignores every key and VoiceOver's adjust too.

| Key | Where | Does |
|---|---|---|
| ← → | A slider, under Full Keyboard Access | One step back or on, mirrored right to left |
| ↑ ↓ | A slider or a stepper, under Full Keyboard Access | One step on or back |
| Home, End | A slider, under Full Keyboard Access | The lower or the upper end |
| VoiceOver adjust | Either | One step |

**A field** is the native `TextField` or `SecureField`, plain, inside our chrome: `.settingsField()`, last on its
chain, so typing, the caret, input methods, secure entry, `.focused`, `.onSubmit` and `.onExitCommand` stay the
field's. Its name sits beside it, never inside:

- On a page, a field goes in a `SettingsRow`, or a `LabeledContent` with a `SettingsRowLabel`, that names it. The
  chrome hides the field's own label, which VoiceOver keeps.
- What to type goes in `prompt:`: a catalog key, or `Text(verbatim:)` for an example such as a host name. In a
  sheet, where the field's title was its placeholder, the prompt says it again.
- A field that keeps its own focus with `.focused` passes it in, `.settingsField(isFocused:)`, so it never carries
  a second focus binding, and nothing sets focus after the chrome.
- A field's `.disabled` goes after the chrome, so the chrome dims with it, once.
- `.textFieldStyle` belongs to the chrome. Two fields keep chrome of their own: the sidebar search, around a glyph
  and a clear button, and a local task's title, typed in place in the body font so it reads as the row's title.

`SettingsDesignSystemRulesTests` holds the controls' keyboard, VoiceOver and one dim, and every field to its
chrome, the two above pinned. `--kannu-snapshot-tabs designSystem` draws each in its resting and disabled
states, and `components` draws the slider and stepper rows in one column.

## Pages and sections

A page is a `SettingsPage` and a group of rows a `SettingsSection`, both in `DesignSystem/`. macOS 14 has no API
for a custom form style to take a `Form`'s sections apart, so both are our own views, called the way `Form` and
`Section` were: `SettingsSection { rows } header: { SettingsSectionHeader("…") } footer: { SettingsFooter("…") }`,
either closure left out when there is none.

- **The page is one scroll view across the panel**, so its scrollbar sits at the panel's edge and the wheel works
  anywhere on it. Its sections stand in one column, `sectionGap` apart, capped at `pageMaxWidth` and started
  `settingsPageInset` from the panel's leading edge (below, "The window"). The large title stays outside it.
- **The scroll view starts `pageScrollInset` (12 pt) under the title**, and the column gives up as much of its top
  padding. So a scrolled page is cut 12 pt under the title, never against it, and a page at rest starts where it did.
  `SettingsProductPage` does the same.
- **It builds every row as it appears.** A plain `VStack`, not a lazy one: a search or a deep link scrolls to a
  row's id, and a lazy stack cannot scroll to a row it has not built. So a row's `onAppear` and `.task` run as
  the page opens, not as the row scrolls into view, and `onDisappear` as the page goes or Brain closes, not as
  the row scrolls away. A row that animates keeps animating while its page is open, in view or not; a closed
  Brain still costs nothing (docs/REGRESSIONS.md, entry 22).
- **Except four long lists, which are lazy inside the page:** the task rows (`TaskRowList`: All tasks, Local
  tasks, a source, a project), the Archive once expanded, Security's findings, and Notes' notes. Each can hold
  hundreds of rows (Notes' do with Apple Notes' whole account synced), and a plain stack would build them all as the
  page opens. No search or deep link lands on one of their rows: Tasks' and Notes' rows carry no highlight id, and the
  findings' link lands on their section's header. Going back to a task or a note scrolls to its row by the `ForEach`'s
  own id, which a lazy stack reaches before the row is built. The
  lazy stack holds only the list's rows, spaced as they were (`sectionRowGap` in a card, the disclosure's default
  in the Archive), and is left out while the list is empty, since an empty one still takes a row's gap. Anything
  a search can reach stays outside it.
- **A section is its rows in a soft card** (`card`, `sectionRadius`), `sectionRowGap` apart: space, never a
  divider. Its header and footer sit outside the card, in line with the rows' text, as the grouped `Form` placed
  them. `SettingsSectionHeader` is the heading for VoiceOver, not the whole header, so a Beta badge or a count
  beside it is not one; the footer takes the secondary ink. A missing header or footer adds no gap. For VoiceOver
  the section is one group, as `SettingsPermissionCallout` is, so like buttons in two of them are told apart
  (Shelf's two "Open Privacy & Security"). A modifier on a section (`.disabled`, `.opacity`, `.onAppear`,
  `.sheet`) reaches all of it, its header and footer too.
- **A section with no rows draws an empty card**, where a `Form` drew nothing, so a section whose rows are all
  conditional sits inside an `if` that guarantees one, as each such section does.
- **Nothing stays a `Form` or a `Section`.** `SettingsLayoutRulesTests` bans both under Settings, `SwiftUI.Form`
  and `Section(header:)` included, proven on planted offenders; its pin table is empty, and a site that must stay
  native goes there with its reason. `SettingsDesignSystemRulesTests` holds the section's card, spacing, header,
  footer and group, and keeps hooks, animators and laziness out of both views (the three lazy lists above are
  inside pages, not in either view); `BrainShellRulesTests` holds the page's column and the inset's one
  measurement.

## Product pages

A product page opens on what it is about, then its settings. Brain › Agents, Brain › Usage and Brain › Notes are the
ones so far; the redesign plan gives Security, Timer and Clipboard theirs in Stage 4b, and Tasks in Stage 5.

- **`SettingsProductPage(settingsTitle:) { product } settings: { sections }`**, in `DesignSystem/`: one scroll view
  across the panel, as `SettingsPage`, held the page inset from the leading edge and never centred. The product
  stands in a column up to `productMaxWidth`, 1,200 pt; past it the extra width is right margin. A full-width
  "<Page> settings" rule starts the settings, which keep `pageMaxWidth`, so a label stays near its switch. Plain
  stacks, so a search or a deep link still scrolls to a settings row. The same items in the same order at every
  width, only wider: no breakpoint and no second layout.
- **The header's actions** sit on the title's row, at its trailing end, which stops where the product column does:
  `SettingsForm(tab:actions:)` hands them to `SettingsPageHeader`. Icon buttons first, the page's one primary verb
  last, each reading its own store. `.toolbar` stays banned.
- **Agents** leads with a hero for the session `primarySession` ranks first, at least `heroMinHeight` (200 pt) tall,
  in three bands. Top: its state as the title ("Needs you", "Working", "Finished"), in `cardTitle` and in its light's
  colour, with the light at the right. Middle: the icon, provider · project, the chat and the state in words. Bottom,
  pinned: the run's figures, each over a small label (Run time, Tool calls, Tokens in · out), from the text column, and
  "Open chat ›" at the right. The whole card is one button, so "Open chat ›" is a label drawn like a quiet button, never
  a button inside a button. Then Recent chats, rows `listRowHeight` tall and `listRowGap` apart, each with a trailing
  column of `listTrailingWidth`: the state in words and in its light's colour, the metrics and the light. Then a status
  row of three equal cells: Editors & hooks (one line, "5 tools watched · hooks installed", or "2 of 3 hooked" and then
  each tool missing its hook, with Install; only a tool that has a hook counts toward "hooked", so Warp and Claude
  Desktop are watched, never hooked), Usage
  (readings near their limit, each its percentage over what it measures, with its reset and "As of"; never a read of
  its own) and Security (only while findings wait for review). A cell's headline figure is `cardTitle`, and a quiet
  cell is one line. A click on the hero or a row opens its chat.
- **An empty state** keeps the hero's place and height: the status in `cardTitle`, one short sentence at most
  `proseMaxWidth` wide (two lines at most) in `body` on `inkSecondary`, at most one action. No sessions: "No agents running", with "Install <tool> hook" for the
  first tool on this Mac without its hook. Agent Status off: "Agent Status is off", with Turn On. The status row and the
  settings show in both.
- **Agents' header** holds the gear alone, which goes to the first settings row. **Each missing hook is offered once:**
  the empty state, while shown, offers the first and the Editors & hooks cell the rest; otherwise the cell offers them
  all. Never in the header, never twice (the cell's `showsFirstOffer`). The tools come from `AgentToolDetector` (`Kannu/managers/AgentStatus/`): file checks and
  Launch Services from the page's `onAppear`, once a visit, never in `body` and never Warp's container; the notch asks as
  its empty state appears, never on the hover-opens while an agent works.
- **Nothing moved out of reach.** Every settings row keeps its id, its search entry and its deep link, below the
  product: Smart caffeinate's link from the notch lands there. Detected Editors became the Editors & hooks cell. Editor
  Hooks stays a settings section: every hook with its tool's icon, and the one place a hook can be removed.
- **Boards**: `agents0`, `agents1` and `agents3` draw Agents at the window's first size with no session, one and three,
  from fixtures (`AgentsOverview.snapshotFixture`), never this Mac's sessions, tools, readings or findings. `agents0`
  shows the install offer in the empty state, `agents1` the Editors & hooks cell's quiet line (every hook in) and
  `agents3` the offer in that cell. `shellWide` and `shellWidest` (2,560 pt) draw it wide, and `shellDeepLinkAgents` the
  caffeinate link landing below the product.
- **Usage** leads with the notch's provider cards in Brain's style, built from the usage store's readings and outlooks
  (`UsageAlertManager`): a card for each provider that is on, among those whose limits the store keeps (Claude, Codex,
  Cursor). The card's title is the provider's icon and name; then each live window (`isLive`: not past its reset or
  its expiry) is a row, its name over "Resets … · As of …" and the forecast when it says something, with the bar and
  the percentage, rounded half away from zero as the notch's, in a trailing column of `listTrailingWidth`. Each
  organization's windows stay together, its own first, and in each the 5-hour window, then the week, then the rest. The
  bar is the slider's track, filled with the accent, and near the limit, as the alerts count it, the bar and the figure
  are `destructive`; a warning forecast is too. A provider with no live reading is one quiet line. Then "Models this
  week", from each provider's last read (`UsageSnapshot.models`), in Recent chats' rows: the provider over the model,
  the tokens in and out trailing, and the cost only where the provider bills per token (Cursor), with a "+" when some
  of its events had no price, as the notch writes it; VoiceOver hears the counts in words. Hidden when empty.
  Antigravity's quotas are not among the store's readings, so it has no card; the notch shows them.
- **Usage's empty state**, with no such provider on: "No limits to show", one line, and "Turn on a provider" (the
  standard style), which goes to the Providers switches, or to the monitor's while it is off. **While Agent Status is
  off**, which stops the usage store, Agents' own "Agent Status is off" with Turn On stands in place of the cards.
- **Usage's header** holds the gear, which goes to the monitor's switch, then **Refresh**, the page's one primary verb,
  off while a refresh runs, no provider is on or Agent Status is off. It runs on a press only, through the notch's own
  paths, unchanged: its Refresh usage (`LLMUsageManager.refreshRequestedByUser`), and Claude's `/usage` as the automatic
  refresh runs it (`refreshClaudeUsageFromCLI(manual: false)`), so a press here never starts a browser sign-in; that
  stays a press of the notch's Claude ↻, beside the status line and Cancel it needs. Claude's run is skipped while that
  line shows a status that holds the automatic refresh, read at the press, so the press never clears it
  (docs/REGRESSIONS.md, entry 8).
- **Boards**: `usage0`, `usage1` and `usage3` draw Usage at the window's first size with no provider on, Claude alone,
  and Claude, Codex (no reading yet) and Cursor (near its limit), and `usageOff` the three with Agent Status off, from
  fixtures (`UsageOverview.snapshotFixture`), never this Mac's readings or its Agent Status; the settings rows below
  still read its switches, as Agents' do. `llmUsage` draws the page whole at the narrowest panel.
- **Notes** leads with the notes in one card, pinned first and then the latest edit first, as the notch's Notes tab
  lists them, in a lazy list (above, "Pages and sections"). A row is the note's colour (a pin in that colour when it is
  pinned, as the notch marks one, in a column a list row's icon wide, so the titles share an edge), its title and a
  caption: when it was last edited, by the time of day or the date, so the page keeps no clock, then its text's first
  line. Then a › to its own page; its right-click menu holds Open note, Pin or Unpin (while pinning is on, as in the
  notch), Copy, Open in Notes for a note made there, and Delete. While Apple Notes sync is on, one status line above the
  notes says that a sync runs, when the last one ran, or its error; it reads the page's copy and starts nothing. With no
  note, "No notes yet", "Write your first note here or in the notch." and New note in the standard style, the header's
  verb again, as Security's empty state draws its own. While Notes is off, one card, "Notes is off", with Turn On.
- **A note's own page** is an in-tab swap (below, "Section rules"): the › opens it under a "‹ Notes" back row, with the
  note's title as the page's title, at its top; going back scrolls to the note's row. It shows the note whole and
  read-only: when it was edited ("Made in Apple Notes" after it for a note shown read-only), the text, selectable, and
  its image as a preview at most the prose width and a hero card's height, read from its file once, off the main
  thread. Then Pin or Unpin, Copy and Delete, and Open in Notes for a note made there: the notch edits notes, and Apple
  Notes the ones made there. `NotePage` is handed the note and nothing else, so the list-detail layout
  (layout-proposal.md, D1) can stand it beside the list from the same selection. Each visit opens on the list, since a
  note left open would come back whole on a reopened Brain, which can be on a shared screen; a Notes search or deep link
  takes the tab back to the list too, where its row is.
- **Notes' presses:** Delete asks first for a note made in Apple Notes, since it moves to Recently Deleted there too, as
  the notch's rows ask; any other goes at once, as there. **The page starts no work of its own:** no sync and no
  AppleScript as it appears or follows, though the notch's Notes tab syncs as it appears. Pin, Copy, Open in Notes
  (AppleScript, behind the sync manager's gate) and Delete act on a press only, through `NotesManager`, the notes' one
  write path; Delete then reads the notes again at once, so the row goes with the note. A note's image file is read
  only by Copy's press and by a note's page, once, off the main thread, never by a row. The settings keep their three
  syncs, each on a press: the scope's choice, the narrowing question's Sync Kannu folder, and Sync now.
- **Notes' header** holds the gear, which goes to the first settings row, Enable Notes, then **New note**, the page's one
  primary verb, which opens New note's sheet on a press. No New note while Notes is off.
- **New note's sheet** (`NewNoteSheet`; layout-proposal.md §5 item 7, David's "Yes, add the sheet"): the title and the
  text, each with a prompt that says what to type, and the colour, a `SettingsSelect` of the notch's six with each
  colour's dot. Add saves the note through `NotesManager.save`, as a note made in the notch is, and never one with no
  title and no text (a title of spaces is none); nothing is saved as it is typed, so Cancel leaves nothing. Return is
  Add in the title; in the text, which runs to several lines, Return is the text's own and ⌘Return is Add, so a list
  typed line by line is never saved half done. One id for the sheet, so Return reaching both the title and Add saves
  once. A note's own page stays read-only.
- **What changed** in Notes' settings, by the copy pass's rules (4-3c skips Notes): the switches in sentence case; the
  General footer, which said no fact, dropped; Last synced by the time of day, with no spinner and no relative date,
  since the status line above says when a sync runs; the Apple Notes footer as two facts, a line each; the two scope
  choices' captions about 8 words. Every row keeps its id and search entry, and Enable Notes registers one, the gear's
  landing.
- **Boards**: `notes0` and `notes4` draw Notes at the window's first size with no note and four (a pinned one, one with
  an image, one made in Apple Notes and one with no text), `notePage` the page of the one with the image and
  `notePageMirror` the one made in Apple Notes, from fixtures (`NotesOverview.snapshotFixture`), never this Mac's notes,
  sync state or image files. `notes` draws the page at the narrowest panel, and `newNoteSheet` the sheet half typed,
  never saved. The switches drawn under the product are this Mac's, so the boards run with `-enableNotes '<true/>'`,
  the sync's with `-enableAppleNotesSync '<true/>'` and `notePageMirror` with `-appleNotesSyncScope 'Whole account'`
  too: the argument domain, nothing saved. A bare `YES` reaches Defaults as text, which reads as the switch's default.

## Live data

Brain's content is built once and kept for the app's life. Closing takes it out of the window, and a change published
while it is out still re-runs `body` (docs/REGRESSIONS.md, entry 22). The agent monitor publishes on every hook write,
up to about 20 times a second, and Agents is the page Brain opens on. So a page that shows live data keeps three rules,
which `AgentsPageLiveDataRulesTests` reads from the source, each checked against planted offenders:

1. **Throttled and scoped.** The page copies what it shows into `@State` from one subscription to the one value it
   needs: Agents' sessions through `$sessions.throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest:
   true)`, at most twice a second, and the style preview's light through `$trafficLightState.removeDuplicates()`.
   Nothing under Settings observes the whole monitor (`ClosedNotchObservationTests`). Security's cell follows the
   findings store's `objectWillChange` on the same throttle and redraws only when its summary changes: while a
   session runs with permission checks off, every hook write restamps its finding and the store republishes. One leaf
   runs faster: `AgentTurnMetricsView` observes the token follower, which republishes every 50 ms while it catches up
   on a long turn, as it does for the notch.
2. **Stopped while Brain is not on screen.** The subscription is a `.task(id: visibility.isOnScreen)` that returns at
   once while the flag is false, so it ends when the flag goes false and starts again when it comes back. Security's
   is the live status row's own `.task`, and that row exists only while the flag is true. Neither wraps its loop in a
   `Task`, which would outlive the cancel. `BrainVisibility.isOnScreen` follows the window's occlusion state
   (`windowDidChangeOcclusionState`): false while Brain is closed, minimised, hidden with the app, fully covered or in
   another Space, where a full-screen Brain keeps `isVisible` true. Opening and closing set it too, rather than wait
   for that change, which can come late, or not at all for a window never shown. It starts false, so nothing live
   runs before Brain is first on screen. The page reads once as it appears, so it opens on what is happening, not on
   an empty state.
3. **No work while nothing is on screen.** The live leaves give way to a static copy. `AgentTurnMetricsView`, which
   observes the token follower and ticks once a second, becomes the run time as it froze and the tool count, without
   tokens; the status row, which observes the usage store and follows the findings store, is read once instead. The
   page, its scroll position and anything typed stay. The hero's figures are the same leaf with its `figures` option
   (nil in the notch and in Brain's rows), and their static copy lays out through the same `figureRow`, with no clock.

A click resolves where it goes in its action (`AgentSessionOpener.open`), never in `body`: finding a session's target
walks parent processes and asks `NSWorkspace`. **Not measured:** the CPU of Agents open, closed, and parked full
screen in another Space during a busy agent. It needs a real window, so it is David's check before install.

**Usage** keeps the same three, and `UsagePageLiveDataRulesTests` holds them against planted offenders. Its readings,
outlooks and models come through one subscription to `UsageAlertManager`'s `$readings` and `$outlooks` and
`LLMUsageManager`'s `$results`, throttled to 500 ms and assigned only on a change; the header's "a refresh is running"
through one to the two refresh flags that drops repeats; each a `.task(id: visibility.isOnScreen)`, and the stores are
read once as the page appears. It keeps no clock and no animation: a reset and a reading are told by the time of day,
and the page leaves out a window past its reset or expiry itself as it draws (`isLive`), since the store drops one only
while it runs, which is while Agent Status is on; off screen the copy simply stays. **It never reads usage of its own**
(docs/REGRESSIONS.md, entry 8): Claude's limits come from the agent monitor's reads, Codex's and Cursor's from the
notch's Usage tab, the opt-in background check or Refresh, so a reading can be hours old and each says when it was
taken. Refresh's press is the one way in, and the rule test pins its two calls, and the hold Claude's run checks, to it.

**Notes** keeps the same three, and `NotesPageLiveDataRulesTests` holds them against planted offenders. The notch
autosaves a note every 1.5 s while one is typed, and a sync rewrites the notes, so the page never observes them: what the
list, a note's page and the settings show is copied into one value, `NotesPageData`, from one subscription, the notes
and the sync's switch, scope and date through `Defaults.publisher(keys:options: [])` merged with the sync manager's
`objectWillChange`, throttled to 500 ms and assigned only on a change, in a `.task(id: visibility.isOnScreen)`. The
copy is read once as the page appears and again each time Brain comes back. Nothing on the page observes the sync
manager or holds the notes in a `@Default`, and nor do the notch's coordinator and view model, which the page before
observed whole and never used. It keeps no clock: a note's edit and the last sync are told by the time of day or the
date. A note's page has one hook, which reads its image from its file once, off the main thread. **It starts no sync:**
the notch's Notes tab syncs, and so runs Notes' AppleScript, as it appears; Brain's page syncs only on a press of the
settings' three. **Not measured:** the CPU of Notes open while a note is typed in the notch; it needs a real window.

## The shell and navigation

`BrainShell` is the layout: a title row, the sidebar on the paper, and the page in an inset panel. It
takes its three parts as slots, so it knows no page. `SettingsSidebarRow` takes strings, never a tab.

- **Two lists, and no mode flag.** The product list ends at Settings and About; the settings list starts
  with Back. Which one shows is read from the selected tab (`SettingsTab.group`), and `selectedTab` is
  the only navigation state. So a search or a deep link moves the sidebar through the writers it already
  had, with no path of its own. `lastProductTab` and `lastSettingsTab` remember the tab last left on each
  list, which is where Back and the Settings row return to. A search's jumps write neither: the tab a query
  started from is remembered, and the tabs it passes through while being typed are not.
- **A query shows one flat list** of the matching tabs, with no Back row and no Settings row. Clearing it
  returns to the list the selected tab is on. A deep link to a tab that list leaves out clears the query, so
  the sidebar still shows the tab. The suggestions render inside the sidebar's column.
- **A suggestion is a row:** its title in `body`, two lines at most, and its tab under it in `description`. Whether
  the list scrolls is decided from what is known at once: more than seven matches, or a last row not yet measured,
  scroll, in at most 344 pt, so the list is never taller than that, even unmeasured. Each row measures where its
  bottom edge falls, and the measures only trim the scroll view to the lowest one under 344 pt, so it never cuts a
  row's text; they are cleared when the matches change. While rows sit below the foot, a short fade
  (`suggestionFade`) says there is more.
- **A page's large title is its tab's**, from `SettingsForm`, so a page needs no edit to have one. A
  sub-page that has a title of its own says `settingsPageTitle(_:)`, as Brain › Tasks does. The title
  sits outside the page's scroll view, so it stays put while the page scrolls.
- **The sidebar is a custom list, not `List(selection:)`**, which draws its own selection on macOS. So it
  takes arrow keys itself and follows its own selection, and a row, Back and the Settings row each hand it
  the keyboard. Up and down walk the list on screen; About is a foot row and not in that order. Left is Back
  and right is the Settings row. The focus stop is a background, so each row keeps its own ring under Full
  Keyboard Access.
- **The moon writes `brainAppearance`,** and the window applies it (below). From Match macOS it picks the
  opposite of what is on screen.

`BrainShellRulesTests` holds this. `--kannu-snapshot-tabs shell,shellSettings,shellDeepLink,shellWide,shellSearch,shellSearchList`
draws the whole window: both lists, a deep link's scroll and ring, the stand-in for full screen, and a search
with its suggestions and without. An animated scroll does not move in their off-screen window, so the boards scroll at
once (`snapshotScrollsAtOnce`), and the 0.45 s is never drawn. The window's own title bar is not in them, and
arrow keys and hover take a real window.

## The window

- **Sizes.** It opens at 1100×760 and goes down to 820×560, centred on the screen under the pointer and
  clamped to it. A page stops at 720 pt (a product page's product at 1,200: "Product pages"), so a row does not stretch across a full-screen panel, and it is
  never centred: it starts 32 pt from the panel's leading edge, or 48 pt on a panel 1,000 pt or wider, so a
  full-screen panel's spare width gathers on the right instead of on both sides of a floating column.
  `SettingsForm` measures the panel and hands the inset to the page and its title (`settingsPageInset`), so
  titles and cards line up. Its title is 24 pt on every page, its cap height 44 pt below the panel's top. The
  values are `SettingsTheme`'s `window…` tokens, `pageMaxWidth`, `pageInset`, `pageInsetWide`, `widePanelWidth`
  and `pageHeaderTop`. The root's frame
  has a minimum and no maximum, because SwiftUI's size bridge clamps the window to it (`docs/REGRESSIONS.md`,
  entry 17).
- **Transparent title bar.** The title is hidden, and kept for the Window menu and Mission Control. The shell's
  title row lies under the bar, level with the traffic lights, and the bar's top centre stays empty, because
  a closed notch can sit over it in full screen. The window moves by its title row, not by its background.
- **Full screen.** The green button enters it. A close from there leaves full screen first, then closes,
  so Brain reopens windowed unless the exit itself failed (entry 22). Nothing restores it at launch:
  `isRestorable` is false, and `WindowFullscreenRulesTests` holds that.
- **The notch ignores it.** `FullscreenMediaDetector` skips Kannu's own pid, so Brain in full screen does not hide
  the closed notch under Hide set to Always.
- **`brainAppearance` is this window's alone.** Match macOS, Light or Dark. `SettingsWindowController` applies it to
  its own window, synchronously at setup and on every change after, because a view would not react while Brain
  is closed. Only the moon and Brain › Settings › Appearance write it, and that row is the way back to Match macOS.
  `NSApp.appearance` and `preferredColorScheme` are banned, so the notch stays dark and every other window follows
  macOS. `BrainAppearanceRulesTests` holds this.

A board's window is borderless, so the moon draws in the PNGs and the traffic lights never do. No board can
enter full screen: `shellWide`, at 1440×900, stands in for it. A board renders the layer tree, which draws no
video and no liquid glass: Devices' 3D icon, a looping movie in the app, shows the movie's first frame on a board
(`DevicesSettingsView.snapshotDrawsStill`), and a glass panel would come out white.
Every page renders at 612 pt, the narrowest panel
the window can have: a `SettingsPage` insets itself, in a tab or on its own. `shellSearch` and `shellSearchList`
render at the smallest window, where the sidebar has the least room.

**Never list `shelf`, and never run the boards without `--kannu-snapshot-tabs`.** An unfiltered run renders
every tab, and the Shelf page touches `~/Documents` and `~/Downloads` through its folder access store, whose
first touch blocks the main thread on a macOS permission prompt (AGENTS.md, "Nothing runs before the Terms of
Use are accepted"). Check the Shelf page by hand.

## The content standard

The components above already imply one set of numbers. `SettingsMetrics` in
`SettingsComponents.swift` is now where those numbers live, and it is the source of truth — this
section describes it, it does not define it.

| Dimension | The rule | Token |
|---|---|---|
| A row's title | The root's `SettingsTheme.body`. Never restyled. | — |
| Every secondary line | `settingsDescriptionStyle()` — `SettingsTheme.description`, secondary, selectable. Pass `tint:` only when the colour means something (red for a failure, orange for a partial result). | — |
| Title to description | 2 | `labelStack` |
| Inside a row's trailing content | 8 | `rowContent` |
| Between footer lines | 6 | `footerStack` |
| A slider's or stepper's whole trailing column, or a typed value beside its button (a task's Time row) | 220 | `sliderWidth` |
| Its readout, trailing, monospaced digits | minWidth 40 | `valueColumn` |
| The ready dot in a status line | 7 | `statusDot` |
| A control's title to its glyph ("Open ›", "‹ Tasks", a tag chip's ×) | 4 | `iconGap` |
| Inside a card | 12 | `cardPadding` |

- **One inset, 12 pt, for text inside and beside a card.** A section's rows, header and footer (`sectionPadding`), the
  hero and an empty state (`heroPadding`) and a status cell (`cardPadding`) all start their text 12 pt in, so a page's
  titles share one edge. Only the page's title and the "<Page> settings" rule sit on the column's edge. A lone quiet
  button keeps that edge with `flush`: bare at rest, its 8-pt inset would set its label off the text above it, so the
  label sits on the edge and the fill under the pointer reaches left instead.
- **A card's title is `cardTitle`, 17 pt,** the step between the page's 24 and a row's 13: the hero's state, an empty
  state's status (Agents, Extensions) and a status cell's headline figure. An empty state's one line is `body` on
  `inkSecondary`, not a description: it teaches, so it reads as text.
- **No card inside a card.** Paper, panel and card are three surfaces already; a darker slab inside a section's card
  makes a fourth. An entry of a list is a row of the card, `sectionRowGap` from the next, as General's Permissions
  are (`LaunchPermissionRow(asRow: true)`; onboarding keeps its own card). Only a callout, or a row's expanded
  details (an extension's), keeps a card of its own: `.settingsCalloutCard()`, the card's colour inside a 1-pt
  `line` border, so it is a boundary, not another surface.
- **A colour swatch is ringed:** a 1-pt `knob` ring inside a 1-pt `line` ring (`KannuColorPickerButton`), so it never
  reads as a status dot, which stays a bare `statusDot` (7 pt).

- **No ad-hoc type in a row.** `.caption`, `.caption2` and `.system(size:)` do not belong on text
  that sits in a row's label or control column — that is what made one section's descriptions
  wrap at three different widths. They survive only where pinned, for badges, chips and icon glyphs,
  and inside a card that has its own compact scale: `SettingsLayoutRulesTests` pins them per file
  twice, by size here and as system fonts ("Colours and fonts").
- **A row adds no padding.** Its section pads its rows already, so `.padding(.vertical, …)`
  on a row makes that one row taller than its neighbours. Padding belongs to cards, popovers,
  chips and empty states — nowhere else. Pinned per file.
- **One control size per section.** A row uses the default size. `.small` is for controls
  inside a card (`SettingsPermissionCallout`, `SecurityFindingRow`, an extension's expanded
  panel), and then for every control in that card.
- **Every row is a row.** `SettingsRow`, `SettingsActionRow`, `SettingsSliderRow`,
  `SettingsStepperRow`, `SettingsNoteRow` or a raw `LabeledContent` — so the label column and the
  control column line up down the whole section. A bare `VStack` with `frame(maxWidth: .infinity)`
  is not a row: it runs the full width and breaks the grid. Use `SettingsNoteRow` for a line that
  only says something.
- **A slider or a stepper is never hand-built in a row.** `SettingsSliderRow` and `SettingsStepperRow`
  are the only row shapes; `SettingsSlider` and `SettingsStepper` by hand only outside a row, pinned.
  The value goes in the readout (`valueText`), never in the title ("Width: 36px" was); a row with no
  number passes `valueText: nil`, and the readout column stays reserved, so the bar is the same length
  everywhere.
- **An error line is a sibling of the row it belongs to**, so it takes that row's inset — including
  inside an Advanced disclosure.
- **`SettingsValueText` is for a trailing value, never for a leading line.** It is one line with
  middle truncation, which is right for `/Users/…/snapshot.json` — both ends carry the meaning — and
  wrong for anything that reads as a sentence, which renders with its middle amputated. A full-width
  line under a title takes `.settingsDescriptionStyle()`, which wraps and matches the summary above
  it. An earlier version of this rule said the opposite ("a card's metadata goes in
  `SettingsValueText`"), and `SecurityFindingRow` followed it for four prose lines in 1.3.1; the
  component's own doc comment says trailing, and the component wins.
- **A card's metadata appears only when it says something.** Suppress it when it adds nothing: a row
  standing for a single occurrence, with two identical dates, is noise dressed as information —
  `SecurityFindingRow` omits its recurrence line in exactly that case. And state a fact once. The
  same count in prose *and* as a value reads as two different facts, which is why the sighting
  summaries stopped appending "Seen N times." once the row began showing the real total.

## Section rules

- `SettingsRow`'s control slot is for controls whose own label the row replaces — Toggle,
  `SettingsSelect`, a field. It applies `.labelsHidden()` to the whole slot, an environment modifier: a
  `Menu` placed there loses its label and its items' titles and reads as dead (the "Policy rules" "…"
  bug). Such controls go in a raw `LabeledContent` with a `SettingsRowLabel` (the `analysisRow` shape) or
  a `SettingsActionRow`. `SettingsSelect` may sit in the slot, popover and all, because its trigger and
  its list's rows are buttons with plain text, which the modifier leaves alone: the `components` board
  shows its value in a row beside a native picker's. A `Menu` still may not.

- `onAppear` runs again every time Brain reopens, not only on arriving at a page: closing takes the
  content out of the window (docs/REGRESSIONS.md, entry 22). One that loads a field must not read
  over what was typed and not yet saved. And it runs for every row as the page opens, not as the row
  scrolls into view: a page builds all its rows (below, "Pages and sections").

- One concern per `SettingsSection`; separate concerns get separate sections, never a `Divider` inside one.
- A Section earns its gap: a one-row Section spends a whole section gap on one row, so a row that
  serves a Section joins it. A row that only narrows a list (a Find field) is that list's first
  row, not a Section of its own, and a page's folded extras (All tasks' Recently closed, Archive
  and Tag colours) are rows of one Section at its end — the one exception to "one concern per
  Section". A row that is a concern of its own still stands alone: a sub-page's back row (below),
  or a page's one setting (Local tasks' colour).
- A section that mixes everyday controls with rarely-needed ones may tuck the rare rows into one
  `DisclosureGroup` labelled **Advanced** (collapsed by default), keeping the section glanceable.
  Rows inside it carry no highlight ids; their search entries point at the disclosure's own id,
  so search always lands on something visible (the ADR scans section is the model).
- A sub-page is an in-tab view swap (Brain has no navigation stack): a row with an Open button
  ("40 open ›") swaps the tab's content, and the sub-page starts with a back row. The same rule
  applies: its rows carry no highlight ids, their search entries land on the row that opens it,
  and a search or deep link into the tab returns to the tab's first page (Brain › Tasks is the
  model).
  - Sub-pages may nest, as a tree: the tab keeps a path of pages, opening one appends it, and the
    back row goes up one level and names where it goes ("‹ GitLab", "‹ Tasks"). A page opens at its
    top; going back scrolls to the row that opened it. Search entries for any page below the first
    land on the first page's row that leads there (Brain › Tasks: a source's settings land on the
    source's row).
  - A row that exists only in some states (a task source's row, only while it is connected) has a
    standing row its entries land on until then (Brain › Tasks › Add a source), through a redirect
    `SettingsHighlightInventoryTests` pins. docs/TASK-SOURCES.md lists what a new source adds.
  - The back row is a lone leading quiet `Button` (`SettingsButtonStyle(.quiet, flush: true)`), its
    chevron `iconGap` before its title, alone in its own `Section` — the one sanctioned lone
    left-hanging button, because it is navigation, not an action on a row. Nothing else on a page
    takes this shape. The sidebar's Back row is shell chrome, not a row of a page.
  - A caller that means a sub-page itself (a notch "Show all" link, a notification click) uses
    a deep link of its own, registered on that page's back row (`SettingsDeepLink.tasksListOpenID`
    opens All tasks); the tab opens the page for that id alone. Search entries keep pointing at the
    opening row.
  - All tasks' filters are view-only: they narrow that page and nothing else. While a filter or its
    Find field is set, a "Filtered" row above the rows says so ("3 of 12 tasks"), with a Show All
    that resets the filters and empties Find. The page shows no total otherwise: that row is its
    one count.
- A long list of similar rows (tasks) keeps each row to its title, one short caption and at most
  two trailing controls: the row's main action (▶) and a › to the item's own page, where everything
  about it lives. Its other actions go in a `.contextMenu` that opens with "Show Details" — never a
  ⋯ menu on every row. Rows are not dragged, numbered or stepped up and down (David, 2026-10-23:
  "no drag and order tasks or numbering"): the menu's Move to Top is the one move, picking what the
  notch's Up next shows first, and it is a named accessibility action too. A value typed on an item
  is typed in place on its page (a task's estimate in its Time row, `TaskEstimateField`; a local
  task's title in its title row, a plain field in the body font, so it still reads as the row's
  title).
- A list's Add is one row (Brain › Tasks' Add a task), whose prominent New Task button opens a
  sheet holding every field the item takes — never fields inline in the list (David, 2026-10-24:
  "a add task button maybe giving popup"). Its shortcut (⌘N) sits on the tab's page, never on the
  row's button, which the lazy `Form` dropped, shortcut and all, once it scrolled away.
- A sheet is a `SettingsSheet`, never a `Form`: its title (and a secondary line under it), the
  fields, then trailing buttons — Cancel (`.cancelAction`), then the primary, named for what it does
  ("Add", "Schedule", "Done"; `.defaultAction`). A `Spacer` of the sheet's own spreads them only
  when something leads (Clear All, Remove Estimate). A field's name is a `LabeledContent` label
  beside it. Return is the primary in every field, except while a tag is being typed, where it
  completes the tag (Tags, New Task).
- Every row with a `settingsSearchIndex` entry carries a `.settingsHighlight(id:)` whose id
  matches the entry exactly (`SettingsHighlightInventoryTests` pins the pairing and the counts;
  the counts move only as a deliberate edit).
- A row's description says what the control does, in about 8 words. No "Off: …" sentence, no
  mechanics, and no repeat of the title.
- A menu item that acts in place, opens a small sheet or asks a confirmation carries no ellipsis
  ("Add Tags", "Set Estimate", "Delete"); a confirmation alone does not earn one. "…" marks only a
  menu item that goes on to a connect flow or another window ("Connect Jira…", "Manage tasks…").
  The Sources rows' "Connect…" and "Disconnect…" are row buttons, not menu items, and keep theirs.
- Footers carry privacy or trust facts only ("Tasks and their time stay on this Mac."), one short
  line each. The one exception: a list whose rows keep their other actions in a `.contextMenu`, and
  has no row left to say so, may name it once under the list (All tasks' "Right-click a task for
  more, such as Move to Top.").
- Error and recovery text is specific but short: what failed, and the one thing to do next.
- Badges (`customBadge`, `comingSoonTag`, `alphaBadge`, `proFeatureBadge`) are decorative chips
  and stay unselectable — they are the pinned exceptions in `SettingsLayoutRulesTests`, along
  with labels inside tappable cards. A new exception is added to that pin with a reason, not
  slipped past it. A page's badge is `SettingsBadge` ("Beta", "Alpha", "Built-in"), one look for one
  fact; `customBadge` and `alphaBadge` draw it.
- A row of buttons alone in its card takes a title and a caption on the left, as every row does
  (Lock screen's Preview widgets, the Actions of Clipboard and Screen Assistant), and the footer
  that explained the buttons goes into the caption. Buttons on one theme share one
  `SettingsActionRow` (About's Report a Problem… and Copy Latest Report), each keeping its own
  highlight id.
- User-facing strings use `String(localized:)`; the shared components take `LocalizedStringKey`
  so literals localize on their own.

## Selectability in practice

- New informational `Text` styled secondary/caption gets `.textSelection(.enabled)` or goes
  through `settingsDescriptionStyle()`; the layout test counts the survivors per file.
- A container-level `.textSelection(.enabled)` covers every `Text` inside it — fine for a small
  legend or a two-line prose row.
- `LabeledContent` labels and values are display, not controls: both sides may be selectable.
