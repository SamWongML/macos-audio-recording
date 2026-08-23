# When a window has both a sidebar and an inspector, do their toggles have to look like a mirrored pair?

Research triggered while resolving [issue #7](https://github.com/SamWongML/macos-audio-recording/issues/7) (part of the [map](https://github.com/SamWongML/macos-audio-recording/issues/1)): the editor window is converging on **one window** with a leading sidebar (the Library — a list of Recordings) and a trailing inspector (Export: Quality Preset, Loudness/Gain, estimated size, Export button) around a central waveform/Trim view. Issue #7's own prototype already tried each pane separately — variant N put a sidebar on the Library, variant O put Export in "the inspector, permanently" — but never both together. Putting both in one window raises a concrete visual-design question: a leading sidebar-toggle button and a trailing inspector-toggle button read as two redundant mirror-image toggles. Does Apple's own guidance and practice sanction that pairing, discourage it, or just not address it — and if there's a better pattern, what is it?

## Recommendation

**Make the sidebar the only toggleable pane; keep the inspector permanently visible.** This is design option (b) below, and it is not an arbitrary pick — three independent lines of evidence converge on it:

1. **AppTape's own content model wants the inspector to stay put.** Per the map's decisions ([issue #9](https://github.com/SamWongML/macos-audio-recording/issues/9)), the Export panel's estimated size is "recomputed continuously while a Trim handle is dragged" — the whole point of putting Export controls beside the waveform is live feedback while trimming. Hiding that panel defeats its own purpose. The Library sidebar has no equivalent live-feedback role; it is pure navigation between Recordings, which HIG itself treats as the more optional, hideable half of a sidebar+detail relationship (see §1).
2. **SwiftUI's own API is asymmetric in exactly this direction.** `NavigationSplitView` gets a free, automatic, removable sidebar-toggle toolbar button (`ToolbarDefaultItemKind.sidebarToggle`, documented as "the sidebar toggle toolbar item a `NavigationSplitView` adds by default"). `.inspector(isPresented:content:)` gets nothing automatic — no `ToolbarDefaultItemKind` case for it exists at all (confirmed by reading the full enum in the SDK, §4). If you build the two panes with plain SwiftUI and only wire up what the framework gives you for free, you already land on "sidebar toggleable, inspector not" — this recommendation is the path of least resistance, not a fight against the framework.
3. **It is issue #7's own prior art.** Variant O already decided the inspector is "permanent." This research adds the sidebar half on top of that decision rather than reopening it.

The second-place option, if AppTape's designer wants both panes toggleable, is **(a) both toggles at opposite toolbar edges** — which is what HIG's own Toolbars page describes (leading edge carries the sidebar control, trailing edge carries "buttons that open nearby inspectors," §1) and what Xcode actually ships. The concrete fix for the "reads as a mirrored pair" complaint, if this path is taken, is to **not** style the two buttons identically: Xcode's own leading and trailing controls are different shapes (a two-icon segmented pill on the leading edge vs. a single lone circular button on the trailing edge, §2) precisely because they are not, in fact, the same kind of control.

Every other option evaluated in §5 is workable but has a weaker fit for AppTape specifically — reasoning for each is in that section.

## 1. What Apple's HIG actually says

Fetched directly from `developer.apple.com`'s HIG data endpoints (the HIG site is a JavaScript single-page app; the rendered HTML carries no body text, so each page's JSON payload was fetched from `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json` and its `primaryContentSections` text extracted programmatically — this is the same underlying content the browser renders, not a paraphrase). Quotes below are verbatim from that extraction.

### Sidebars

[developer.apple.com/design/human-interface-guidelines/sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) — "Sidebars," last updated June 8, 2026 per the page's own changelog.

> "Consider letting people hide the sidebar. People sometimes want to hide the sidebar to create more room for content details or to reduce distraction. When possible, let people hide and show the sidebar using the platform-specific interactions they already know. For example, in iPadOS, people expect to use the built-in edge swipe gesture; **in macOS, you can include a show/hide button or add Show Sidebar and Hide Sidebar commands to your app's View menu.** In visionOS, a window typically expands to accommodate a sidebar, so people rarely need to hide it. **Avoid hiding the sidebar by default to ensure that it remains discoverable.**"

> "Consider automatically hiding and revealing a sidebar when its container window resizes. For example, **reducing the size of a Mail viewer window can automatically collapse its sidebar**, making more room for message content."

> "Avoid putting critical information or actions at the bottom of a sidebar. People often relocate a window in a way that hides its bottom edge."

Two things worth pulling out: the toggle is explicitly *optional* ("Consider letting people hide the sidebar," not "Provide a way to hide the sidebar"), and macOS gets two co-equal mechanisms named in the same sentence — a toolbar button *or* View-menu commands — not a mandate for both.

### There is no dedicated "Inspectors" HIG page

`developer.apple.com/design/human-interface-guidelines/inspectors` and `/the-inspector` both return **HTTP 404** (confirmed directly with `curl`, both the rendered page and the JSON data endpoint). Inspector guidance instead lives inside two other pages:

**Panels** ([developer.apple.com/design/human-interface-guidelines/panels](https://developer.apple.com/design/human-interface-guidelines/panels), macOS-only page — "Not supported in iOS, iPadOS, tvOS, visionOS, or watchOS"):

> "**Consider using a panel to present inspector functionality.** An inspector displays the details of the currently selected item, automatically updating its contents when the item changes or when people select a new item. In contrast, if you need to present an Info window — which always maintains the same contents, even when the selected item changes — use a regular window, not a panel. **Depending on the layout of your app, you might also consider using a split view pane to present an inspector.**"

> "Write a brief title that describes the panel's purpose... macOS provides familiar panels titled 'Fonts' and 'Colors,' and **many apps use the title 'Inspector.'**"

> "Refer to panels by title in your interface and in help documentation. In menus, use the panel's title without including the term panel: for example, 'Show Fonts,' 'Show Colors,' and **'Show Inspector.'**"

So HIG's model of "inspector" is a *content pattern* (a live, selection-following detail view), not a fixed UI region — it can legitimately be a floating panel **or** a split-view pane, and the page explicitly anticipates it living inline in the window (which is what SwiftUI's `.inspector()` modifier actually builds — a trailing split-view column, not an `NSPanel`).

**Split views** ([developer.apple.com/design/human-interface-guidelines/split-views](https://developer.apple.com/design/human-interface-guidelines/split-views)) confirms this is real, shipping practice, with a named first-party example:

> "Rarely, you might also use a split view to provide groups of functionality that supplement the primary view — for example, **Keynote in macOS uses split view panes to present the slide navigator, the presenter notes, and the inspector pane in areas that surround the main slide canvas.**"

> "Consider letting people hide a pane when it makes sense. If your app includes an editing area, for example, consider letting people hide other panes to reduce distractions or allow more room for editing — **in Keynote, people can hide the navigator and presenter notes panes when they want to edit slide content.**"

> "**Provide multiple ways to reveal hidden panes.** For example, you might provide a toolbar button **or** a menu command — including a keyboard shortcut — that people can use to restore a hidden pane."

Note what that last sentence does *not* say: it never asks for a symmetric pair of toolbar buttons. "A toolbar button or a menu command" is stated as alternatives, and nothing in either page requires every hideable pane to get its own permanent toolbar icon.

### Toolbars — HIG puts the two controls in genuinely different zones

[developer.apple.com/design/human-interface-guidelines/toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) describes three toolbar zones and assigns the sidebar and inspector controls to different ones, in the same paragraph:

> "You can position toolbar items in three locations: the leading edge, center area, and trailing edge of the toolbar... **Leading edge.** Elements that let people return to the previous document and **show or hide a sidebar** appear at the far leading edge, followed by the view title... To ensure these items are always available, **items on the toolbar's leading edge aren't customizable.**"

> "**Trailing edge.** The trailing edge contains important items that need to remain available, **buttons that open nearby inspectors**, an optional search field, and the More menu that contains additional items and supports toolbar customization... **Items on the trailing edge remain visible at all window sizes.**"

This is the closest HIG comes to directly addressing the two-toggle question, and it reads as **implicit sanction of the opposite-ends placement**, not a call for the two controls to look alike: they're grouped with different neighbors (sidebar toggle keeps company with the back button and title; inspector toggle keeps company with search and the More menu), and one zone is described as permanently non-customizable while the other explicitly supports customization. HIG is specifying *where each individually belongs*, not designing them as a matched set.

### The canonical View menu has a Sidebar item and no Inspector item

[developer.apple.com/design/human-interface-guidelines/the-menu-bar#View-menu](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#View-menu) gives an explicit, ordered table of "top-level menu items" the View menu "typically contains":

| Menu item | Action |
|---|---|
| Show/Hide Tab Bar | Toggles the visibility of the tab bar above the body area in a tab-based window |
| Show All Tabs/Exit Tab Overview | Enters and exits a Mission-Control-like tab overview |
| Show/Hide Toolbar | In a window that includes a toolbar, toggles the toolbar's visibility |
| Customize Toolbar | Opens a view that lets people customize toolbar items |
| **Show/Hide Sidebar** | In a window that includes a sidebar, toggles the sidebar's visibility |
| Enter/Exit Full Screen | Opens the window at full-screen size in a new space |

**There is no Inspector row in this table.** The same page's Window-menu section comes closer, but frames it as optional and panel-scoped, not View-menu material: "**Consider including menu items for showing and hiding panels.** A panel provides information, configuration options, or tools for interacting with content in a primary window... There's no need to provide access to the font panel or text color panel because the Format menu lists these panels." HIG's own canonical menu-item enumeration simply never standardized an inspector show/hide command the way it standardized the sidebar one — three years of API history back this up independently (§4's `SidebarCommands` vs. `InspectorCommands` gap).

### Verdict on "sanctioned, discouraged, or unaddressed"

- **(a) Sidebar on macOS**: thoroughly addressed, with a named toolbar zone, a canonical View-menu item, and explicit "hide by default is bad, but hiding is a reasonable option" guidance.
- **(b) Inspector on macOS**: addressed, but as a *pattern* (Panels page) rather than a *component with its own HIG page* — its toolbar-button convention is inferred from the Toolbars page's "buttons that open nearby inspectors" line and from real-app practice (§2), not from a dedicated inspector rulebook the way sidebars get one.
- **(c) Where each toggle belongs**: explicitly addressed for both — leading edge for sidebar, trailing edge for inspector (Toolbars page) — and reinforced by an explicit, ordered View-menu table for sidebar (no equivalent table entry exists for inspector).
- **(d) Whether having both in one window is sanctioned, discouraged, or unaddressed**: **unaddressed as a combination, but not because it's discouraged** — it's unaddressed because HIG documents sidebars and inspectors as separate, independently-optional patterns and never discusses them appearing together. The Split Views page's Keynote example is the one place HIG acknowledges a window can carry a navigator *and* an inspector at once, and even there it's presented as "rare" — a fact about how infrequently apps need three-plus split-view panes, not a comment on the two-toggle visual question this research was asked to resolve.

## 2. What Apple's own apps do

Every claim below was checked live on this machine via `osascript`'s System Events accessibility bridge (menu-bar item enumeration, including `AXMenuItemCmdChar`/`AXMenuItemCmdModifiers` for keyboard shortcuts) and, where a real window could be coaxed onto screen, `screencapture -x`. Per the task's own environment note, CGEvent synthetic clicks don't work here and were not used; every click was a System Events accessibility action. One genuine tooling limit surfaced and is treated honestly below: `tell application "X" to activate` on a never-before-scripted app triggers a macOS Automation permission dialog ("'Ghostty' wants access to control 'X'"), and clicking that dialog's own buttons was correctly refused by this environment's action classifier as a system-security decision outside an agent's authority — so activation was done via `tell application "System Events" to set frontmost of process "X" to true` instead, which needs no such grant and is why every app below could still be queried.

| App | Version (measured) | Sidebar toggle | Inspector-equivalent toggle | Verified how |
|---|---|---|---|---|
| Notes | 4.13 | View ▸ **Hide/Show Sidebar**, ⌃⌘S | none — Notes has no inspector | Screenshot + View-menu enumeration |
| Mail | 16.0 | View ▸ **Hide/Show Sidebar** | none | View-menu enumeration |
| Freeform | 5.0 | View ▸ **Show/Hide Sidebar** | none in the View menu (its Format/style panel, if any, isn't a View-menu item) | View-menu enumeration; screenshot only reached first-run onboarding, not the canvas |
| Reminders | 7.0 | View ▸ **Hide/Show Sidebar** | none | View-menu enumeration |
| Music | 1.7 | **none found** | **none found** | View-menu enumeration (no window/toolbar screenshot obtained — see "could not verify") |
| Shortcuts | 10.0 | View ▸ **Hide/Show Sidebar** | View ▸ **Hide/Show Preview**, plus separate **Show Action Library** / **Show Shortcut Details** items — three-plus toggleable regions, not two | View-menu enumeration (no window was open; see "could not verify") |
| Photos | 12.0 | View ▸ **Show Sidebar** | none in View menu; **Info** is a Window-menu item instead (⌘I), matching HIG's "Info window, not a panel" language | View-menu enumeration; screenshot reached only the "What's New" splash |
| Numbers | 14.5 | none found | View ▸ **Inspector** (single boolean item, first entry in the menu, no visible keyboard shortcut in this state) | View-menu enumeration only — see "could not verify" for why no window/toolbar screenshot exists |
| Pages | 15.3.1 | none found | View ▸ **Inspector** (same pattern as Numbers) | View-menu enumeration only |
| Keynote | 15.3.1 | View ▸ **Navigator** / **Slide Only** / **Light Table** / **Outline** — a *mode picker*, not a boolean sidebar toggle | View ▸ **Inspector** (same single boolean item, listed first) | View-menu enumeration only |
| Xcode 27 (`/Applications/Xcode-beta.app`) | 27.0 (beta) | View ▸ Navigators ▸ **Hide/Show Navigator**; toolbar: leading two-icon segmented control | View ▸ Inspectors ▸ **File / History / Quick Help** tabs, plus **Show/Hide Inspector**; toolbar: one standalone trailing icon | Screenshot + View-menu enumeration, detailed below |

**Notes and Mail** are the clean baseline: a single leading-edge sidebar toggle, nothing resembling an inspector, confirming these apps never had the two-toggle question to answer in the first place. Screenshot: `/private/tmp/claude-501/-Users-demon-codes-macos-audio-recording/6b8d2cec-d031-4694-9a90-28bee35944c6/scratchpad/shots/notes-after-cmdn.png` — Notes' toolbar shows exactly one leading circular sidebar-toggle icon and no counterpart on the trailing edge.

**Numbers, Pages, and Keynote** (the classic "spreadsheet/document + inspector" family) all put a single un-prefixed **"Inspector"** command as the very first item in the View menu — not "Show Inspector" or "Hide Inspector," just "Inspector," which reads as a state-agnostic toggle rather than the state-reflecting Show/Hide naming HIG's own View-menu guidance asks for ("Ensure that each show/hide item title reflects the current state of the corresponding view"). None of the three expose a "Sidebar" item in the View menu at all — Keynote instead offers a **mode picker** (Navigator / Slide Only / Light Table / Outline) confirming the Split Views HIG page's own description of Keynote's navigator+inspector arrangement as split-view panes, not a simple boolean sidebar. **I could not get a document window open for any of the three** to screenshot their toolbars: all three apps opened with zero windows (`System Events` reported `count windows = 0`), and forcing one open triggered a macOS Automation permission dialog ("'Ghostty' wants access to control 'Numbers'") that this environment correctly refuses to click through — so the toolbar-button question for this app family (does "Inspector" get a dedicated button, and where) is verified at the menu level only, not visually. See "What I could not verify."

**Shortcuts** is the one app checked that has *more* than two toggleable regions — Sidebar, Preview, Action Library, and Shortcut Details all appear as separate View-menu items — which is itself evidence against "exactly two mirrored toggles" being some kind of natural end state; Apple ships apps with one, two, or several independently-toggleable regions depending on what the content needs, not a fixed template.

**Xcode** is the most directly relevant exemplar, because it is the one app checked that genuinely ships both a leading navigator toggle and a trailing inspector toggle at once, and it was possible to both enumerate its menus and photograph its actual toolbar. Screenshots: `/private/tmp/claude-501/-Users-demon-codes-macos-audio-recording/6b8d2cec-d031-4694-9a90-28bee35944c6/scratchpad/shots/xcode-raised.png` (full window), `xcode-toolbar-left-zoom.png` (leading edge, cropped/enlarged), `xcode-toolbar-zoom.png` (trailing edge, cropped/enlarged) — all in the same directory.

- View ▸ **Navigators** is a submenu: Project / Source Control / Bookmarks / Find / Issues / Tests / Debug / Breakpoints / Reports (per-tab jumps), then a separator, then **Show Coding Assistant**, **Hide Navigator**, **Filter in Navigator**. Xcode calls this pane "Navigator," not "Sidebar."
- View ▸ **Inspectors** is a submenu: File / History / Quick Help (per-tab jumps), then a separator, then **Show Inspector**.
- View ▸ **Debug Area** is a third submenu, with **Hide Debug Area** bound to **⇧⌘Y** (confirmed via `AXMenuItemCmdChar`/`AXMenuItemCmdModifiers` — this is the one shortcut of the three I could read a live binding for; "Hide Navigator" and "Show Inspector" reported no `AXMenuItemCmdChar` in this session's window state, discussed under "could not verify").
- The **toolbar itself**, screenshotted directly: the leading edge (right after the traffic lights) is a single rounded two-icon segmented control — a list icon (Navigator, shown selected/on) paired with a sparkle icon (Coding Assistant) — followed by back/forward navigation arrows. The trailing edge ends in one **standalone circular button** bearing a rectangle-divided-into-two-columns glyph — the Inspector toggle. These two controls do not look alike: one is a pill containing two icons, the other is a lone circle. Apple's own developer tutorial independently corroborates the position: "**Show the inspector by clicking the button at the top right of the window** or by choosing View > Inspectors > Show Inspector" (`developer.apple.com/tutorials/Develop-in-Swift/Design-an-interface`, Step 4, fetched via `mcp__xcode__DocumentationSearch`).

One caveat on this evidence: the specific Xcode window screenshotted was running in what the project's own environment notes (`CLAUDE.md`) already flag as Xcode 27's "simplified files-focused mode with no classic project editor" — a single-file window, not a full multi-navigator/multi-inspector project IDE window. The toolbar observed is genuinely real and genuinely Xcode's, but it may not be the maximal case (a full project window might show more than one navigator-region icon, or a wider inspector cluster). Treated as representative but not necessarily exhaustive.

## 3. Keyboard and menu-bar conventions

Primary source: [developer.apple.com/design/human-interface-guidelines/keyboards#Standard-keyboard-shortcuts](https://developer.apple.com/design/human-interface-guidelines/keyboards#Standard-keyboard-shortcuts), "People expect each of the following standard keyboard shortcuts to perform the action listed in the table below" — fetched the same way as §1 (JSON data endpoint, verbatim extraction). The relevant rows, quoted directly from that table:

| Primary key | Shortcut | Action (HIG's own wording) |
|---|---|---|
| I | **Command-I** | "Display an Info window." |
| I | **Option-Command-I** | "Display an inspector window." |
| T | **Command-T** | "Display the Fonts window." |
| T | **Option-Command-T** | "Show or hide a toolbar." |

Two things stand out. First, **Option-Command-I is HIG's own documented standard shortcut for an inspector** — this is a primary-source answer to the "is it ⌥⌘I?" question, verbatim from Apple. Second, **there is no sidebar row in this table at all** — no `S`-key entry for Show/Hide Sidebar anywhere in HIG's "standard keyboard shortcuts" list, despite the View-menu table (§1) listing Show/Hide Sidebar as a canonical menu item.

Real-app verification filled that gap empirically: querying Notes' "Hide Sidebar" menu item's accessibility attributes directly (`AXMenuItemCmdChar` = `S`, `AXMenuItemCmdModifiers` = `4`, which decodes to the Control+Command modifier combination in the standard `AXMenuItemCmdModifiers` bitmask) gives **Control-Command-S (⌃⌘S)** as Notes' actual sidebar shortcut. So the sidebar shortcut is real, consistent, and in wide use — it's just not one of the ~26 shortcuts HIG chose to enumerate in its flagship table, which skews toward shortcuts useful across many kinds of apps (Cut/Copy/Paste-adjacent, window management) rather than ones specific to a particular UI pattern.

This asymmetry has a matching root cause in the SDK: SwiftUI's `SidebarCommands` (which supplies the Show/Hide Sidebar menu item and its shortcut for free) has existed since **macOS 11**; the equivalent `InspectorCommands` didn't arrive until **macOS 14**, three OS releases later (both confirmed by file:line in §4). Apple's own `CommandGroupPlacement.sidebar` documentation states plainly: "By default, this group includes the following commands in macOS: Show/Hide Sidebar, Enter/Exit Full Screen" (fetched via `mcp__xcode__DocumentationSearch`) — sidebar and full-screen were bundled as a pair from the start; inspector was not part of that original bundle and got its own, later, separate command group.

## 4. The macOS 27 SDK surface

Every claim grepped directly from the real interface files on this machine. SDK root:

```
/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk
```

Confirmed version: `SDKSettings.plist` → `DisplayName = macOS 27.0`; this machine's `sw_vers` → `ProductVersion: 27.0`, `BuildVersion: 26A5416b`; `Xcode-beta.app`'s own `kMDItemVersion` → `27.0`.

Two interface files were read, both `arm64e-apple-macos.swiftinterface`:
- **SwiftUI**: `$SDK/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
- **SwiftUICore**: `$SDK/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`

`grep -n "func inspector"` against SwiftUICore returned nothing — `.inspector` and everything else below lives in the **SwiftUI** interface, not SwiftUICore, so all line numbers are against the SwiftUI file unless stated otherwise.

**`NavigationSplitView` composes with `.inspector(isPresented:)` — both are old APIs, not new in macOS 27:**
- `.inspector(isPresented:content:)` — `SwiftUI...swiftinterface:14965`: `nonisolated public func inspector<V>(isPresented: SwiftUICore.Binding<Swift.Bool>, @SwiftUICore.ContentBuilder content: () -> V) -> some SwiftUICore.View where V : SwiftUICore.View`, under `@available(iOS 17.0, macOS 14.0, *)` (line 14960). Two width modifiers sit in the same block: `inspectorColumnWidth(min:ideal:max:)` (line 14967) and `inspectorColumnWidth(_:)` (line 14969), same availability.
- `NavigationSplitView` struct — `SwiftUI...swiftinterface:27508`: `nonisolated public struct NavigationSplitView<Sidebar, Content, Detail> : SwiftUICore.View...`, under `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)` (line 27507).
- `navigationSplitViewColumnWidth(_:)` (line 325) and `navigationSplitViewColumnWidth(min:ideal:max:)` (line 327), both under `@available(iOS 16.0, macOS 13.0, ...)` (line 323).

Since `.inspector` is a plain `View` modifier and `NavigationSplitView` is a plain `View`, they chain with no special glue (`NavigationSplitView { ... } detail: { ... }.inspector(isPresented: $x) { ... }` is ordinary SwiftUI). The pairing has been *possible* since macOS 14 (2023) — nothing about macOS 27 newly enables it.

**No automatic inspector toggle exists — this is the SDK's sharpest, most decision-relevant asymmetry:**
- `ToolbarDefaultItemKind` struct — line 22464, `@available(iOS 17.0, macOS 14.0, ...)`. Its complete member list, read directly from the file: `.sidebarToggle` (line 22465, same availability as the struct), `.title` (line 22469, `@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)`), `.search` (line 22473, `@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`). **There is no `.inspectorToggle` case, or anything resembling one, anywhere in the struct.** Apple's own documentation for `.sidebarToggle` (fetched via `mcp__xcode__DocumentationSearch`) reads: "The sidebar toggle toolbar item **a `NavigationSplitView` adds by default**." No equivalent sentence, or equivalent API, exists for an inspector.
- `.toolbar(removing:)` — line 22851, `@available(iOS 17.0, macOS 14.0, ...)`, signature `nonisolated public func toolbar(removing defaultItemKind: SwiftUI.ToolbarDefaultItemKind?) -> some SwiftUICore.View`. This is how you'd suppress the automatic sidebar toggle (`.toolbar(removing: .sidebarToggle)`) — there is nothing to remove on the inspector side because nothing is added automatically.
- Practical consequence: a developer who builds a `NavigationSplitView` + `.inspector()` window and does nothing extra gets a free, system-placed sidebar toggle and **zero** inspector toggle — they must hand-build an inspector button and wire it to the modifier's own `isPresented: Binding<Bool>` themselves. This is exactly the asymmetry the Recommendation leans on.

**`ToolbarItemPlacement` — `.navigation` and `.primaryAction` are old, and `.navigation` doesn't mean "for a sidebar":**
- Struct — line 7768, `@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)`.
- `.navigation` — line 7773, no additional `@available` beyond the struct's own (so macOS 11+).
- `.primaryAction` — line 7774, same.
- `topBarPinnedTrailing` — line 7806, `@available(iOS 27.0, visionOS 27.0, *)` **immediately followed by `@available(macOS, unavailable)`** — genuinely new in the 27 cycle, but explicitly not usable on macOS at all.

**macOS 27 (and macOS 26.1) additions checked one by one:**
- `visibilityPriority(_:)` on `ToolbarContent`/`CustomizableToolbarContent` — line 13396, `@available(iOS 27.0, macOS 26.1, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)`. Exists on macOS, but shipped in the **26.1** point release, not "27.0" by Apple's own version number even though it's part of the same design cycle. Controls overflow priority for a toolbar item, not sidebar/inspector visibility directly — relevant only if AppTape ever needs the toggle button itself to survive toolbar overflow at narrow widths.
- `ToolbarOverflowMenu` struct and its `toolbarOverflowMenu(content:)` modifier — lines 31420 and 31412, both `@available(iOS 27.0, visionOS 27.0, *)` **immediately followed by `@available(macOS, unavailable)`.** Real API, genuinely new, but **explicitly unavailable on macOS** — not usable here at all.
- `topBarPinnedTrailing` — see above; also macOS-unavailable.
- `toolbarMinimizeBehavior` — **does not exist anywhere in either interface file.** A case-sensitive and case-insensitive grep for `toolbarMinimizeBehavior` and `MinimizeBehavior` across both files found only `tabBarMinimizeBehavior(_:)` (line 11415, `TabBarMinimizeBehavior` struct at 11419 — governs a tab bar's scroll-triggered minimize behavior, unrelated to sidebars/inspectors) and `windowMinimizeBehavior(_:)` (line 5631, a whole-window minimize-button behavior). The specific symbol named in the research brief is not real on this SDK.
- `contentMarginsRemoved(_:)` on `ToolbarContent`/`CustomizableToolbarContent` — lines 6203 and 6208, `@available(anyAppleOS 27.0, *)` — this is a genuine, umbrella-versioned macOS 27 addition (the `anyAppleOS 27.0` annotation applies the same floor across every Apple platform at once). Removes a toolbar item's content margins; a fit-and-finish knob, not a visibility mechanism.
- `safeAreaBar(edge:alignment:spacing:content:)` (two overloads, vertical- and horizontal-edge) — lines 22856/22859, `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)`. Real and macOS-available, but it's a **macOS 26** addition, not new in 27, and it's a generic edge-anchored persistent-bar mechanism (the closest thing in the SDK to "a bottom-anchored sidebar accessory," if ApptTape ever wanted one) — not sidebar- or inspector-specific.

**`SidebarCommands` vs. `InspectorCommands` — the three-OS-release gap that mirrors everything above:**
- `SidebarCommands` — line 21203, `@available(iOS 14.0, macOS 11.0, *)`, `@available(tvOS, unavailable)`, `@available(watchOS, unavailable)`.
- `ToolbarCommands` — line 21174, same availability as `SidebarCommands` (`macOS 11.0`).
- `InspectorCommands` — line 21232, `@available(iOS 17.0, macOS 14.0, *)`, same tvOS/watchOS exclusions. Apple's own doc text for `.inspector(isPresented:content:)` cross-references it directly: "**Seealso:** `InspectorCommands` for including the default inspector commands and keyboard shortcuts" (fetched via `mcp__xcode__DocumentationSearch`) — confirming `InspectorCommands` is the App-level opt-in (`.commands { InspectorCommands() }`) that supplies whatever the framework considers the inspector's canonical View-menu item and shortcut, symmetric in *purpose* to `SidebarCommands` but shipped three years (macOS 11 → macOS 14) later.

## 5. Named design options, ranked

Ranked for AppTape's specific case (sidebar = Library navigation, inspector = live Export controls), not as a universal ranking.

1. **(b) Sidebar toggle only, inspector permanently visible — recommended.** No exact real-app exemplar was found among the apps checked (every app either had neither control, both, or a sidebar-only setup with no inspector at all) — but it is exactly what SwiftUI hands you if you build `NavigationSplitView` + `.inspector()` and simply never add an inspector-hiding button, since the framework already treats the two panes asymmetrically (§4). Fits AppTape because the inspector's estimated-size figure is defined to update live while trimming (issue #9) — hiding it defeats its purpose — while the Library sidebar is pure secondary navigation, the half HIG itself treats as more optional (§1). Directly continues issue #7 variant O's "the inspector, permanently" decision.
2. **(a) Both toggles at opposite toolbar edges — HIG's own default placement, and what Xcode ships.** Sanctioned by the Toolbars page's explicit leading/trailing assignment (§1) and demonstrated live in Xcode (§2). The fix for "reads as a mirrored pair," if this path is chosen, is Xcode's own move: make the two controls visually unlike each other (a segmented pill vs. a lone circle) rather than two identical mirrored icons — the redundant-mirror complaint is a styling problem, not a placement problem, and HIG never asks for the two controls to match.
3. **(e) One unified control showing both panes' state.** No Apple app checked does this for a sidebar+inspector pair specifically — Shortcuts' Gallery/Automations/All Shortcuts control and Keynote's Navigator/Slide Only/Light Table/Outline control are both *view-mode* pickers (mutually exclusive states), not a joint visibility toggle for two independent panes that can each be shown or hidden on their own. Building this for AppTape would be a genuinely novel-for-Apple control with no first-party precedent to validate against — workable, but higher design risk than the other options.
4. **(d) No toolbar toggles at all — View menu and keyboard shortcut only.** Directly permitted by the Split Views page's "toolbar button **or** menu command" phrasing (§1), and possibly already how Numbers/Pages/Keynote's Inspector command works in practice — though this research could not confirm or rule that out visually (§2, "could not verify"). Safe and HIG-compliant, but weaker first-run discoverability than a visible icon, which matters more for a small utility app without iWork's decades of user familiarity.
5. **(c) Inspector toggle only, sidebar permanent.** The mirror image of the recommendation, and a weaker fit for AppTape specifically: Library-switching is occasional (pick a Recording, then work on it), so pinning the sidebar open all the time costs more window width for less continuous benefit than pinning the inspector open. Shortcuts is the closest real analog (sidebar effectively primary, several other panes separately toggled) but it's a weak fit since Shortcuts' sidebar is structural app navigation between galleries, not a single Library list.
6. **(f) Collapse the inspector's content into the sidebar so there's only one pane.** Weakest fit — rejected. No app checked merges its sidebar and inspector into one pane even when both exist (Xcode and the iWork trio keep them structurally separate on opposite edges); Library-browsing and Export-configuring are unrelated tasks in AppTape's own domain model (CONTEXT.md keeps "Library" and "Export" as distinct glossary terms), and collapsing them would force a mode switch inside a single pane instead of letting both stay visible at once, which is the entire reason the design brief wants two panes in the first place.

**Other pattern actually found, worth a footnote:** Xcode's inspector (and its navigator) aren't flat show/hide toggles alone — each carries its own **sub-navigation of named tabs** (File / History / Quick Help for the inspector; Project / Source Control / Bookmarks / Find / Issues / Tests / Debug / Breakpoints / Reports for the navigator), reachable directly from the View menu, with a single boolean show/hide command underneath all of them. Not relevant to AppTape's much simpler single-purpose inspector (Export has one job, not several tabs' worth), but worth knowing the pattern exists if Export's inspector ever grows a second, unrelated function.

## What I could not verify

- **Whether Numbers, Pages, or Keynote actually show a toolbar button for their "Inspector" View-menu command, and if so where it sits.** All three apps launched with zero open windows in this environment, and forcing a document open (`Cmd+N` on a template chooser, etc.) triggered a macOS Automation permission dialog ("'Ghostty' wants access to control 'Numbers' ... Allowing control will provide access to documents and data") that this environment's own action-safety classifier correctly refused to let me click through, since granting cross-app automation control is a system security decision outside an agent's authority. The View-menu enumeration itself (§2) did not require this permission and is solid; the toolbar-button question for this app family is not.
- **The exact keyboard shortcut Xcode's "Hide Navigator" and "Show Inspector" commands currently carry.** `AXMenuItemCmdChar`/`AXMenuItemCmdModifiers`/`AXMenuItemCmdVirtualKey`/`AXMenuItemCmdGlyph` all came back empty for both items in the window state I queried, whereas the sibling "Hide Debug Area" command in the same submenu tree cleanly reported ⇧⌘Y — so the accessibility bridge itself works, but these two specific commands either have no shortcut bound in this build, or their shortcut is context-dependent on window/editor state I didn't have active. The historical ⌘0 / ⌥⌘0 shortcuts for these commands (widely known from older Xcode versions) were not independently confirmed on this build.
- **Whether SwiftUI's `InspectorCommands` actually binds Option-Command-I** (HIG's documented standard "inspector window" shortcut, §3) **or some other combination.** Apple's own doc text for `.inspector(isPresented:content:)` confirms `InspectorCommands` supplies "default inspector commands and keyboard shortcuts" but the fetched documentation for `InspectorCommands` itself didn't state the literal key combination, and no SDK interface file exposes command-level keyboard shortcuts as literal `@available`-style text (those live in compiled command-group logic, not the swiftinterface). Treated as likely ⌥⌘I on the strength of the HIG convention, not confirmed.
- **Music's actual toolbar/sidebar layout.** The View-menu enumeration (no Sidebar or Inspector-equivalent item found) is solid and accessibility-verified, but Music opened with zero windows in this session and no screenshot of an actual Music window (library view or MiniPlayer) was obtained, so I can't rule out a sidebar existing without a View-menu toggle, or a toggle living somewhere I didn't check (a toolbar button with no menu counterpart, which would itself violate HIG's own "make every toolbar item available as a command in the menu bar" toolbar guidance — worth independently re-checking if Music specifically matters to a future decision).
- **Shortcuts' actual window/toolbar.** Same limitation as Music — the View-menu data (Sidebar, Preview, Action Library, Shortcut Details all present as separate items) is solid, but no window was open to screenshot, so the physical toolbar arrangement of however-many buttons is unconfirmed.
- **Freeform's and Photos' real canvas/library toolbars.** Both screenshots obtained only reached first-run onboarding screens (Freeform: "Welcome to Freeform" / Continue; Photos: "What's New in Photos" / Get Started) rather than the actual working UI. Clicking through Freeform's own "Continue" button (an ordinary in-app control, not a system security dialog) was attempted via System Events but the button wasn't found at the expected location in time; not pursued further to stay within scope. The View-menu data for both apps (§2) was captured before/independent of this and is solid.
- **Whether any Apple app anywhere ships true design option (e)** (one literal unified control reflecting both a sidebar's and an inspector's visibility state, as two independent booleans in one control) rather than the mode-picker pattern (Shortcuts, Keynote) noted as the closest real analog. Not found in the eleven apps checked; absence-of-evidence rather than a confirmed negative across all of Apple's own apps.
- **HIG's EBU/W3C-style page-history metadata was taken at face value** (e.g., the Sidebars page's own "Updated guidance for sidebar icon colors... June 8, 2026" changelog entry) as evidence the fetched content is current, since the HIG site doesn't expose any other version marker.
