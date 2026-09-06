# The trailing pane's separator: where it should run, and what should draw it

AppTape's editor window is a `NavigationSplitView` whose detail is a hand-rolled `HStack {
detailContent; Divider(); inspectorColumn }` (`EditorView.swift`, and see
[ADR-0024](../adr/0024-the-trailing-pane-is-a-column-not-an-inspector.md) for why it is a plain
column rather than a SwiftUI `.inspector`). The window also hides the toolbar's own background
(`.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`) so the title bar reads as continuous
with the waveform beneath it. The visible result is a `Divider()` that starts below the title bar
and runs flush to the window's bottom edge — asymmetric, and it reads as a mistake. This report asks,
from primary sources: is it one?

## Method and sourcing

Four passes: (1) Apple's Human Interface Guidelines, fetched directly as the JSON payload each HIG
page's own web client renders from (`developer.apple.com/tutorials/data/design/human-interface-
guidelines/<page>.json` — the same content the page shows, without a browser); (2) Apple's AppKit
and SwiftUI API reference, fetched the same way; (3) three WWDC transcripts, fetched as raw HTML and
parsed from the `data-start`-timestamped sentence spans that carry the transcript text, so every
quote below was matched against the session's own words rather than a summary of them; (4) this
machine's own installed apps, driven with `osascript`/System Events and `screencapture`, inspected
by reading the resulting PNGs. `sw_vers` on this machine reports **macOS 27.0, build 26A5425a**.

**Sourcing caveats, stated up front:**

- **No "Inspectors" HIG page exists at the URL this task named, and none could be found under any
  URL.** Every category the current HIG groups components into was enumerated (`components`, then
  each of its eight subcategories — `layout-and-organization`, `presentation`, `menus-and-actions`,
  `navigation-and-search`, `selection-and-input`, `status`, `system-experiences`, `content`) and
  cross-checked against the Wayback Machine's CDX index for
  `developer.apple.com/design/human-interface-guidelines/inspectors*`, which returned zero snapshots
  ever. If a standalone Inspectors page existed at some point, it is gone now and unarchived; this
  report treats that premise as **not verifiable** and draws the relevant guidance instead from the
  HIG's **Split views** page (which discusses inspector panes by name, as one kind of split-view
  pane), the **Panels** page, the **Windows** page, and Apple's AppKit/SwiftUI API reference for the
  actual inspector-behavior split-view item. This is flagged once here rather than hedged in every
  section.
- **Every WWDC quote below was checked twice**: once via a fetch-and-summarize pass, then again by
  downloading the session page's raw HTML and regexing out the literal transcript sentences (Apple
  ships the full transcript inline, timestamped, in the page source) to confirm the exact wording.
  Where the two didn't match on the first pass (one sentence initially came back truncated), the raw
  HTML is what's quoted.
- **Section 3 is first-hand observation, not a secondary description.** Xcode, Finder, Notes, Mail,
  Music, and Freeform were each actually opened and driven on this machine; Keynote and Pages are
  **not installed** (`mdfind` for both bundle IDs returned nothing) and are not covered — no claim
  about either is made from memory. Mail was driven against the signed-in user's real inbox; nothing
  from its message content is reproduced here or in any committed screenshot, only the chrome
  geometry.
- **The claim that AppTape "cannot get the automatic inspector glass" (§4) is an inference from the
  API surface, not a sentence Apple wrote in those words.** It follows from three separately-sourced
  facts stated plainly where they're used: the automatic treatment is documented as attached to
  `NSSplitViewItem`'s `.inspector` behavior specifically; AppTape's trailing pane is a plain `HStack`
  column per ADR-0024, not an `NSSplitViewItem`; and no public `NSVisualEffectView.Material` case
  named "inspector" exists. The inference connecting those three dots is mine, flagged as such where
  it's drawn.
- **The concrete recipes in §5 are my own synthesis**, built from documented pieces
  (`Divider`'s fill-to-container behavior, `ignoresSafeArea`'s per-edge opt-in, `safeAreaInset`) —
  Apple does not publish a "how to replicate AppKit's full-height split-view divider inside a
  hand-rolled SwiftUI `HStack`" recipe anywhere found. This is stated again at that section's start.

---

## 1. Where should the separator run?

**Full height — title bar to bottom edge — is not a bug to fix; it is Apple's own stated design
goal for a split-view divider under a unified toolbar, and it has been since the Big Sur redesign.**
The clearest primary source for this is not the HIG at all but the WWDC20 session that introduced
the pattern:

> "Consider the Mail app. Notice how there are items in the toolbar that align with sections of
> content in the window. **The dividers of the split view reach up to the top of the window,
> creating these beautiful full-height sections.** As the dividers are resized, the toolbar items
> follow."
> — [Adopt the new look of macOS, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10104/)
> (transcript, emphasis added)

That is an explicit, unhedged statement that a split view's dividers are meant to run through the
title-bar/toolbar frame, not stop below it — the opposite of the reflex to trim a divider back so it
starts lower. The same session frames this as one piece of a single mechanism, not an accident of
one app: "Specifically, make sure your sidebar is built using an `NSSplitViewController`, and the
SplitViewItem is configured using the sidebar behavior. The second piece of API is the
`fullSizeContentView` window mask. This will allow content to be laid out under the space normally
reserved for the title bar," and later, "This will set up a split view controller with a sidebar and
automatically adjust your window for the fullSizeContentView." The full-height divider is a
*consequence* of `fullSizeContentView` plus a properly-behaviored split view item, not a separately
dialed-in property.

The HIG's own **Windows** page supplies the architectural vocabulary for why this is coherent rather
than contradictory, and it is worth quoting exactly because it draws a line this report leans on
throughout:

> "A macOS window consists of a frame and a body area. People can move a window by dragging the
> frame and can often resize the window by dragging its edges. **The frame of a window appears above
> the body area** and can include window controls and a title bar. In rare cases, a window can also
> display a bottom bar, **which is a part of the frame that appears below body content**."
> — [Windows: macOS window anatomy](https://developer.apple.com/design/human-interface-guidelines/windows#macOS-window-anatomy)
> (emphasis added)

Read against the WWDC quote, the model is: the **frame** is the title bar plus an optional bottom
bar, both first-class chrome; the **body** is everything between them, and a split view's divider —
being body content — is meant to fill the *body*, edge to edge. Under `fullSizeContentView` the body
is stretched to include the space visually behind the title bar (that's the whole point of the
style mask), so a divider that reaches "up to the top of the window" is really just a divider filling
its body all the way, in a window where the body has been extended to include the title-bar area.
**This means a bottom bar, when a window has one, is architecturally outside the split view — not a
shorter divider, a divider that simply doesn't extend into a second piece of frame chrome below it.**
Section 3 confirms this distinction is not just theoretical: every app inspected that stops its
divider short of the literal window edge does so because it has its own bottom bar (a status bar, a
path bar, a transport bar) that lives *outside* the split view, not because the divider itself is
deliberately inset from an edge that has nothing else on it.

The HIG's **Split views** page adds one more directly-relevant, load-bearing sentence, about the
divider's own thickness rather than its extent:

> "In macOS, you can arrange the panes of a split view vertically, horizontally, or both. A split
> view includes dividers between panes that can support dragging to resize them. … **Prefer the thin
> divider style. The thin divider measures one point in width**, giving you maximum space for content
> while remaining easy for people to use. Avoid using thicker divider styles unless you have a
> specific need."
> — [Split views: macOS](https://developer.apple.com/design/human-interface-guidelines/split-views#macOS)
> (emphasis added)

This page is also where Apple names inspector panes explicitly, as one *reason* apps use a split
view at all, independent of whether a page called "Inspectors" exists: "Rarely, you might also use a
split view to provide groups of functionality that supplement the primary view — for example,
**Keynote in macOS uses split view panes to present the slide navigator, the presenter notes, and
the inspector pane** in areas that surround the main slide canvas." — same page. The HIG's
**Panels** page independently confirms a split-view pane is one of exactly two sanctioned homes for
inspector content, the other being a floating panel: "Consider using a panel to present inspector
functionality… Depending on the layout of your app, you might also consider using a [split view]
pane to present an inspector." —
[Panels](https://developer.apple.com/design/human-interface-guidelines/panels). Section 3 finds both
patterns actually in use (Xcode and Finder use the split-view-pane form; Freeform uses the floating
form).

**Verdict for AppTape, specifically:** the honest reading of "full height, title bar to bottom edge"
against AppTape's own layout is that the *bottom* being flush is the part that's already right by
Apple's convention (the trailing pane has no bottom bar of its own to stop above), and the *top* —
starting below the title bar rather than reaching it — is the part that's actually inconsistent with
the pattern the WWDC session describes, not the reverse. This is developed into a concrete
recommendation in §5, with the caveat that closing that gap in SwiftUI (as opposed to AppKit, where
it's one style mask) is not a documented one-liner.

---

## 2. What does AppKit/SwiftUI actually draw by itself?

**`NSSplitViewController`'s divider is a thin (1 pt) line drawn by `NSSplitView`, and by default it
runs the full extent of the split view's own frame — which, combined with `fullSizeContentView`,
means the literal top of the window.** The API reference is terse about the geometry (Apple doesn't
publish pixel specs), but confirms the ownership and the default thickness indirectly through the
divider-style API surface: "A split view manages the dividers and orientation for a split view
controller. By default, dividers have a horizontal orientation so that the split view arranges its
panes vertically from top to bottom." —
[`NSSplitView`](https://developer.apple.com/documentation/appkit/nssplitview). The full-height
behavior itself is confirmed only by the WWDC20 transcript quoted in §1 — the API reference for
`NSSplitViewController` and `NSSplitViewItem` doesn't restate it, which is consistent with Apple
treating it as automatic, unconfigured behavior rather than a property with its own name.

**There is a real, separate, per-item property that is easy to confuse with "does the divider reach
the title bar," and this report wants to be precise about the difference.** `NSSplitViewItem`
exposes `titlebarSeparatorStyle`, described as "the type of separator that the app displays **between
the title bar and content of a window**" —
[`NSSplitViewItem.titlebarSeparatorStyle`](https://developer.apple.com/documentation/appkit/nssplitviewitem/titlebarseparatorstyle),
backed by an enum with four cases — `automatic`, `line`, `none`, and `shadow` — "styles that determine
the type of separator displayed between the title bar and content of a window" —
[`NSTitlebarSeparatorStyle`](https://developer.apple.com/documentation/appkit/nstitlebarseparatorstyle).
**This is a *horizontal* line, one per split-view-item column, governing whether that column's own
slice of the title-bar boundary shows a hairline or a shadow** — it is not the *vertical* divider
between columns that this research is actually about. The WWDC20 transcript states the relationship
between the two plainly: "You may have noticed that the toolbar doesn't have a divider below it
anymore. But that's not always true though. **A shadow will automatically appear between the toolbar
and scrolled content** to create a visual pocket where the content trails off. This happens in each
section of the window with a scroll view… If you'd like to explicitly request a separator instead of
the scroll shadow, or maybe have no separator at all, **you can do that using the
`titlebarSeparatorStyle` on each split view item**." —
[Adopt the new look of macOS, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10104/). So:
one knob (`titlebarSeparatorStyle`) controls the horizontal seam under the toolbar for a given
column; the vertical inter-column divider's full-height reach is a separate, unnamed, automatic
consequence of `fullSizeContentView` plus the split view filling its own frame.

**`allowsFullHeightLayout` is the literal opt-*out***, confirming full height is the default rather
than something requested: "A Boolean value that indicates whether full-height sidebars appear in the
window after you set a style mask… This property only applies to [sidebar and inspector split view
items]. The default value is `true`." —
[`NSSplitViewItem.allowsFullHeightLayout`](https://developer.apple.com/documentation/appkit/nssplitviewitem/allowsfullheightlayout).
Read with the WWDC transcript's "There's a new property on `NSSplitViewItem` which will allow you to
opt out. You may consider this if your sidebar is typically collapsed or if your toolbar is
crowded" — full height is the thing you have to turn *off*, not on.

**`fullSizeContentView` is the mechanism that makes any of this possible**, and its own reference
entry is the cleanest primary-source statement of what it does to the body/frame relationship named
in §1: "When set, the window's `contentView` consumes the full size of the window. Although you can
combine this constant with other window style masks, it is respected only for windows with a title
bar. Note that using this mask opts in to layer-backing. **Use the `safeAreaLayoutGuide` or the
`contentLayoutGuide` to lay out views underneath the title bar–toolbar area.**" —
[`NSWindow.StyleMask.fullSizeContentView`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview).
This is the AppKit-side version of exactly the tension AppTape is navigating in SwiftUI: the *content
view* (and anything drawn in it, including a divider) can legitimately extend under the title bar,
while individual pieces of *content* still use a safe-area guide to keep their own text and controls
clear of the traffic lights and title.

**Inspectors specifically get a dedicated, standard-sized split view item, and AppTape's own
`inspectorWidth` sits almost exactly on the default Apple ships.** `NSSplitViewItem` has a real,
named `.inspector` behavior — "This behavior corresponds to split view items that you create using
`init(inspectorWithViewController:)`" —
[`NSSplitViewItem.Behavior.inspector`](https://developer.apple.com/documentation/appkit/nssplitviewitem/behavior-swift.enum/inspector)
— and that initializer's own discussion states, precisely:

> "In macOS 14.0 and later, inspectors use standard system default values for these properties:
> `canCollapse` is `true`. `minimumThickness` and `maximumThickness` are the standard inspector size
> (270) and aren't resizable by default."
> — [`NSSplitViewItem.init(inspectorWithViewController:)`](https://developer.apple.com/documentation/appkit/nssplitviewitem/init(inspectorwithviewcontroller:))

AppTape's `EditorView.inspectorWidth` is **276** — a coincidence in the sense that nobody derived it
from this API (ADR-0024 says 276 was "the ideal the resizable version defaulted to"), but a small,
worth-naming corroboration that the number the team converged on empirically lands within 6 points of
Apple's own documented standard inspector width.

**SwiftUI's own `.inspector` modifier is described only in terms of presentation state, not
geometry** — its entire discussion is: "Apply this modifier to declare an inspector with a
context-dependent presentation. For example, an inspector can present as a trailing column in a
horizontally regular size class, but adapt to a sheet in a horizontally compact size class. Trailing
column inspectors have their presentation state restored by the framework." —
[`inspector(isPresented:content:)`](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)).
Nothing in the reference states whether the column it produces draws a hairline, a material change,
both, or neither — which is exactly why §3's direct observation matters more than the API docs here.
`NavigationSplitView`'s own reference is silent on divider rendering entirely; its discussion is
about column structure and `columnVisibility`, not paint —
[`NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview).

**One more piece of AppKit context, cited because it explains why the window's title bar looks
seamless with content at all under `toolbarBackgroundVisibility(.hidden, ...)`:**
`NSWindow.titlebarAppearsTransparent`'s own discussion: "When the value of this property is `true`,
the title bar does not draw its background, which allows all content underneath it to show through.
It only makes sense to set this property to `true` when [`fullSizeContentView`] is also set." —
[`NSWindow.titlebarAppearsTransparent`](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent).
SwiftUI's `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` is the modern, SwiftUI-native
way to ask for this same effect; the underlying AppKit contract it rides on is exactly this pairing
of a transparent title bar with a full-size content view — which is the same pairing §1's
full-height-divider convention depends on. AppTape already has half of that pairing
(`toolbarBackgroundVisibility(.hidden, ...)`); §5 returns to what it would take to get the other half
(the divider's own full-height reach) inside a hand-rolled `HStack`.

---

## 3. What do Apple's own apps actually do?

Observed directly on this machine (macOS 27.0, build 26A5425a) by opening each app, driving it with
`osascript`/System Events, and reading the resulting screenshots.

**Xcode 27 (Xcode-beta.app — the only Xcode installed; opened `AppTape.xcodeproj` from this
worktree, then `View ▸ Inspectors ▸ File` to reveal a real, `NSSplitViewItem`-backed File
Inspector).** This is the cleanest primary-source case available, because it is Apple's own
flagship AppKit app using the actual `.inspector` split-view-item behavior documented in §2, not an
approximation.

- **Where the seam starts:** at the literal top of the window. In a tight crop of the boundary
  (`assets/0006/xcode-inspector-seam-top.png`), the editor's own toolbar segment (the two-circle and
  crossed-arrows icons, in their own darker rounded pill) and the inspector's segmented tab strip
  (File / History / Quick Help) sit side by side in the *same* toolbar row, and a faint but real
  shade seam runs between them starting immediately below the system menu bar — there is no gap,
  no separate "then the divider begins" moment. The toolbar row itself is visibly split into
  per-column zones, exactly as §2's reading of `titlebarSeparatorStyle` being a *per-item* property
  would predict.
- **Where it stops:** *not* at the literal bottom of the window. In a second tight crop
  (`assets/0006/xcode-inspector-seam-bottom.png`), the shade seam is visible running down to a
  precise horizontal line, at which point Xcode's own bottom status bar (`Line: 1 Col: 1 |
  research/trailing-pane-separator`) begins — and that status bar's background is **one uniform
  shade spanning the full window width**, underneath both the editor and the inspector. The seam
  does not continue into it. This is exactly the frame/body split named in §1's HIG Windows quote:
  the status bar is a second piece of frame chrome below the body, and the split view (and its
  seam) fills the body only.
- **Nature of the seam:** a soft, low-contrast shade/material difference, not a hairline rule. No
  1-point line is visible anywhere along it at 2× — only a gradient-like shift in background
  luminance between the editor's dark gray and the inspector's very slightly different dark gray.

**Finder (column view, `⌘3`, with `View ▸ Show Preview` enabled — the closest built-in analogue to a
trailing inspector, and Apple's own primary use of the phrase "preview column").**

- Between the last file-list column and the preview pane, there is **no divider at all** — not a
  soft seam, not a hard line. Both panes share the identical background color; the only visible
  break is the file column's own scrollbar track, and the preview content (in this case a white
  document thumbnail) simply begins in open space to its right
  (`assets/0006/finder-column-preview-no-hairline.png` shows the toolbar row and the seamless top of
  this boundary). This is the strongest single piece of evidence in this report for §4's answer:
  Apple's own Finder does not draw a rule between a file list and its inspector-like preview column
  at all.
- Where a scrollbar/seam *does* exist (sidebar-to-file-list), it behaves exactly like Xcode's: it
  begins right below the toolbar row and ends with rounded end-caps well above the bottom path bar
  (`Macintosh HD ▸ Users ▸ … ▸ filename`), which — like Xcode's status bar — is a second, uniform,
  full-width bar sitting outside the split view.

**Mail (default three-pane: mailbox sidebar, message list, message content).** Mail is not an
inspector layout — its third pane is the primary content, not a supplementary inspector of a
selection elsewhere — but it is a live three-pane split view under a unified toolbar, and its
divider geometry is data for §1 regardless. Both dividers present as a thin scrollbar-style track
(not a static hairline) that begins just below the toolbar/title row and ends a small, fixed inset
above the window's literal bottom edge (there is no separate bottom bar in this view — the small
inset is ordinary scrollbar end-cap padding, not a second piece of frame chrome). No content from
the inbox is reproduced here or in any committed asset.

**Music (`Search`/`Library` sidebar plus content pane).** Same pattern as Mail's sidebar boundary: a
scrollbar-style seam confined to the body, stopping short of the window's bottom because Music has
its own bottom transport bar (play/scrub controls) as a second piece of frame chrome outside the
split view. Music has **no trailing inspector column** in any view reached in this session — only
the two-pane sidebar/content split.

**Notes (notes-list sidebar plus content editor).** **No trailing inspector column exists in Notes'
default layout at all** — it is a two-pane split (list, then the note body), the same shape as
Music. Worth recording plainly rather than stretching to fit: Notes is not a relevant three-pane case
for this research.

**Freeform (opened an existing board, selected a drawn line).** **Freeform does not use a trailing
split-view column for its inspector at all** — selecting an object shows a small, floating,
non-modal popover anchored near the selection (line style, weight, and color swatches), which is the
*other* HIG-sanctioned pattern named in §1 ("Consider using a panel to present inspector
functionality"), not the split-view-pane pattern. Its `View` menu was checked directly and has no
"Show Format Panel," "Inspector," or equivalent item — confirming this is the app's only inspector
mechanism, not one of several. This is a clean, useful negative data point: not every Apple app that
has an "inspector" puts it in a trailing column.

**Keynote and Pages: not installed on this machine** (`mdfind` for `com.apple.iWork.Keynote` and
`com.apple.iWork.Pages` both returned nothing). No claim is made about either app anywhere in this
report.

**Summary table, all from direct observation above:**

| App | Trailing inspector column? | Seam starts | Seam stops | Seam is a rule or a material shift? |
|---|---|---|---|---|
| Xcode | Yes (`.inspector` behavior) | Literal top of window | Above the shared bottom status bar | Material/shade only, no hairline |
| Finder | Yes (column view + Preview) | N/A — no seam at all | N/A | **No seam of any kind** |
| Mail | No (3rd pane is content, not an inspector) | Below toolbar | Small inset above literal bottom (no bottom bar present) | Scrollbar track, not a static rule |
| Music | No inspector column (2-pane only) | Below toolbar | Above its own transport bar | Scrollbar track |
| Notes | No inspector column (2-pane only) | — | — | — |
| Freeform | No — floating popover, not a column | — | — | — |
| Keynote / Pages | Not installed; not observed | — | — | — |

---

## 4. Is a visible separator even the norm?

**No — the weight of both the newest primary sources and the direct observation in §3 point the
other way: material/shade separation is the current norm for an inspector-like trailing pane, and a
drawn hairline is the thing that reads as dated.** Two independent 2025 WWDC sessions state this for
the *inspector* case specifically, not just for panes in general.

AppKit's own current guidance, verified against the session's raw transcript:

> "With glass toolbars handled, I'll move on to the main content of the window, which is often
> organized using a split view. In the new design, **sidebars appear as a pane of glass that floats
> above the window's content, whereas inspectors use an edge-to-edge glass that sits alongside the
> content.** To get this effect in your application, use `NSSplitViewController`. **When you create
> split items with a sidebar or inspector behaviors, AppKit presents them with the appropriate glass
> material automatically.**"
> — [Build an AppKit app with the new design, WWDC25](https://developer.apple.com/videos/play/wwdc2025/310/)
> (transcript, emphasis added)

"Edge-to-edge glass" is a material description, not a line description — and "AppKit presents them
with the appropriate glass material **automatically**" is the same shape of unconditional promise
the Liquid Glass material guarantee makes elsewhere (compare this repo's own research report 0005,
on `research/accessibility-adaptations`, which found the identical "available automatically…
across the board" wording for Reduce Transparency/Contrast/Motion — cited as a parallel finding, not
re-fetched here): it is a property of using the real `.inspector` behavior,
not something the app paints in by hand. SwiftUI's equivalent session says the same thing about the
same feature, independently:

> "With the new backgroundExtensionEffect modifier, views can extend outside the safe area, without
> clipping their content… **The new design makes inspectors shine, with more Liquid Glass!** Opposite
> the sidebar in Landmarks, **the inspector hosts content with a more subtle layering.** This
> associates the inspector with its related selection."
> — [Build a SwiftUI app with the new design, WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
> (transcript)

"A more subtle layering" is, again, a material/depth description. Neither session mentions a divider
line for the inspector case at all — a real, checked absence, not an oversight in this research: both
transcripts were searched specifically for "divider" and "separator" and neither term appears in
either one.

The HIG's **Materials** page supplies the general principle underneath both quotes, phrased as an
instruction rather than a description of one app: "Liquid Glass forms a distinct functional layer for
controls and navigation elements — like tab bars and sidebars — that floats above the content layer…
**Don't use Liquid Glass in the content layer.** … Instead, use [standard materials] for elements in
the content layer." —
[Materials: Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass).
A companion session states the content-layer-boundary version of the same rule even more bluntly, in
words that happen to describe a hairline `Divider` precisely: "Elements using Liquid Glass require
clear separation from content to maintain legibility. Like in Safari today, controls sit on top of a
system material, not directly on content. Without that separation, contrast can suffer. **Scroll edge
effects reinforce that boundary, replacing hard dividers with subtle blur** to reduce clutter and
keep UI legible." —
[Get to know the new design system, WWDC25](https://developer.apple.com/videos/play/wwdc2025/356/)
(transcript). That specific sentence is about the toolbar/scrolled-content boundary (the *scroll edge
effect*), not the inspector's own side boundary — flagged here so it isn't overclaimed — but it is the
same design instinct restated a third time: **the current-generation answer to "how do I show a
boundary" is a material or blur transition, and a flat drawn rule is explicitly named as the thing
being *replaced*.**

Section 3's Finder observation is the empirical confirmation that this isn't only a 2025-and-later
posture invented for Liquid Glass marketing: Finder's column-view preview pane — a feature that
predates Liquid Glass by over a decade — already separates by whitespace and background-color
identity alone, with no rule at all.

**What this means concretely for the trailing pane's background, and the interaction with
`toolbarBackgroundVisibility(.hidden, ...)`:** the material the HIG names for exactly this situation
is a **standard material** (not Liquid Glass — Liquid Glass is reserved for the navigation layer, and
an inspector's *content* is content-layer, per the Materials quote above), or a plain semantic
background color one step apart from the content pane's own background — for
example `NSColor.controlBackgroundColor` (a color AppKit defines specifically to sit one step apart
from `NSColor.windowBackgroundColor`) rather than `.regularMaterial`'s translucency, since AppTape's
own map already commits chrome to non-blurred materials only. Either choice is unaffected by
`toolbarBackgroundVisibility(.hidden, ...)`: that modifier governs the *toolbar's* background only —
"the preferred visibility flows up to the nearest container that renders a bar… the root view of a
`NavigationSplitView` in macOS" —
[`toolbarBackgroundVisibility(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:))
— it says nothing about, and does not compete with, a background color or material applied to one
column of the detail view beneath it. The two are orthogonal: one hides the toolbar's own paint, the
other colors a body-area pane. Both Xcode and Finder run both effects simultaneously — a
transparent/unified title bar *and* a distinctly-toned inspector or preview column — without one
interfering with the other, which is itself evidence the two mechanisms don't fight.

**AppTape-specific inference (mine, not documented, and flagged as such per the sourcing caveats
above):** because AppTape's trailing pane is a plain `HStack` column rather than a real
`NSSplitViewItem` with `.inspector` behavior — the change ADR-0024 made specifically to escape the
`.inspector`-on-`NavigationSplitView` bug — it does not, and structurally cannot, receive the
"AppKit presents them with the appropriate glass material automatically" treatment quoted above. That
treatment is documented as attached to the real inspector split-view-item type, and no public
`NSVisualEffectView.Material` case named "inspector" exists to invoke by hand (the material enum was
enumerated in full via the API reference; the closest named cases are `.sidebar`,
`.contentBackground`, and `.windowBackground`, none inspector-specific) —
[`NSVisualEffectView.Material`](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum).
So whatever AppTape's trailing column gets, it will be hand-applied, not inherited "for free" the way
a real inspector split-view item's would be. That is a real, structural cost of the ADR-0024 decision
that ADR-0024 itself doesn't discuss (it argues the trailing pane's *behavior* costs nothing extra to
rebuild by hand; it doesn't address the trailing pane's automatic *material* treatment, because that
treatment postdates the framework bug the ADR was written to route around).

---

## 5. Concrete SwiftUI recipe(s)

**Everything in this section is applied synthesis, not a documented Apple recipe** — stated once
here rather than hedged line by line. Two independent directions follow from §§1–4, and they are not
mutually exclusive; AppTape can take either, or both together.

### Recipe A — material separation, no hairline (follows §4 directly)

Drop `Divider()` and give the trailing column its own flat background, one step apart from the
content pane's, using a semantic `NSColor` rather than a translucent material (consistent with the
map's existing "standard materials/flat fills only in chrome" commitment):

```swift
private var detail: some View {
    HStack(spacing: 0) {
        detailContent
            .frame(maxWidth: .infinity)

        inspectorColumn
            .frame(width: Self.inspectorWidth)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

`.controlBackgroundColor` is the semantic AppKit color meant to read as "one layer apart from the
window's own background" in exactly this kind of adjacent-pane situation, without importing
`NSVisualEffectView`'s translucency or vibrancy machinery. `toolbarBackgroundVisibility(.hidden,
...)` on the detail wrapper is untouched by this — as established in §4, the two don't interact.
This is the option most directly supported by primary sources (§4), and it makes the "where does the
line start and stop" question moot, since there is no line — only a boundary between two flat
colors, which (per Finder's own precedent in §3) does not need to be visually announced at all.

### Recipe B — keep the hairline, but make it actually full-height (follows §1's reading directly)

If a drawn `Divider()` is kept — which is a legitimate, cheaper choice, and is what AppTape already
ships — then §1's finding is that the current asymmetry is a **half-finished** full-height divider,
not an over-extended one: it already reaches the bottom (correctly, since the trailing pane has no
bottom bar of its own to stop above), and the fix consistent with the WWDC20 convention is to extend
it *upward* to the literal top of the window as well, not to trim it down to "match" a shorter top.

`SwiftUI.Divider` fills the cross-axis of whatever stack contains it — "When contained in a stack,
the divider extends across the minor axis of the stack" —
[`Divider`](https://developer.apple.com/documentation/swiftui/divider) — which is exactly why it
already reaches the literal bottom of the `HStack` today: nothing is constraining it short of that.
Making it also reach the literal top means the `HStack` itself needs to be laid out under the space
`toolbarBackgroundVisibility(.hidden, ...)` is only *painting* as transparent, not actually vacating —
the SwiftUI-side equivalent of pairing `fullSizeContentView` with a `safeAreaLayoutGuide`-respecting
content view described in §2. One way to do this without pulling the pane's actual *content* (the
waveform, the ruler, the Export ladder) up under the title text:

```swift
private var detail: some View {
    HStack(spacing: 0) {
        detailContent
            .frame(maxWidth: .infinity)
            .safeAreaPadding(.top, Self.titleBarHeight)   // content still clears the title text

        Divider()
        // the divider itself is not view-modified — it is the HStack's background
        // that is asked to bleed upward, below, so the 1pt line runs the full height
        // while each pane's *content* stays where it visually needs to be.

        inspectorColumn
            .frame(width: Self.inspectorWidth)
            .safeAreaPadding(.top, Self.titleBarHeight)
    }
    .ignoresSafeArea(edges: .top)
}
```

`.ignoresSafeArea(edges: .top)` on the whole `HStack` is what lets the `Divider` (and any background
color from Recipe A, if combined) paint all the way to the literal top of the window — "to extend
your content into these regions, you can ignore safe areas on specific edges by applying this
modifier" —
[`ignoresSafeArea(_:edges:)`](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:));
`.safeAreaPadding(.top, ...)` reintroduced on each *pane's own content* (not on the stack, and not on
the divider) is what keeps the waveform, ruler, and Export ladder from sliding up under the traffic
lights and title text — the SwiftUI-level version of the same body/frame split §1 and §2 describe
for AppKit. `Self.titleBarHeight` is not a documented constant anywhere; it would need to be measured
against the real title bar's height on this window (or read via `GeometryReader` against the
window's safe-area top inset before it's ignored), which is exactly the kind of fragile-feeling
number `fullSizeContentView` and `contentLayoutGuide` exist to spare an AppKit app from computing by
hand — this recipe is the more fragile of the two for that reason, and is offered because §1's source
supports it, not because it is the easier or safer implementation.

**Recommendation between the two, given AppTape's specific situation:** Recipe A. It is smaller, has
no magic-number height to keep in sync with the system title bar, is the one both current (2025)
primary sources in §4 point to, and Finder's own precedent (§3) shows Apple's own apps are entirely
comfortable shipping *no* visible boundary at all in this exact configuration — which is a lower bar
to clear than a correctly-inset full-height hairline.

---

## What I could not verify

- **The exact URL or historical existence of a standalone HIG "Inspectors" page.** Exhaustively
  searched (every current HIG component category, plus the Wayback Machine's full CDX index for the
  URL pattern) with zero results. Treated as not verifiable rather than assumed either way — see the
  sourcing caveats.
- **Xcode's precise pixel-level material** behind its inspector seam (§3) — confirmed as a soft
  shade/material transition rather than a hairline by direct visual inspection at 2×, but not
  measured to an exact `NSColor` or opacity value; would require inspecting Xcode's own view
  hierarchy (not available from outside the app) rather than a screenshot.
- **FB20061521 and FB20061260**, the Feedback Assistant bug numbers ADR-0024 cites for the
  `.inspector`-on-`NavigationSplitView` breakage this whole report's premise depends on. Per the
  task's own framing these are informal, team-internal references to Feedback Assistant threads,
  which are not publicly browsable without an Apple Developer account tied to the filer — this
  research did not attempt to verify them and takes ADR-0024's account of the underlying bug as
  given context, not as a claim re-verified here.
- **Keynote and Pages**, per §3 — not installed on this machine, not observed, no claim made.
- **Whether real estate constraints in a compact Mac window ever force SwiftUI's `.inspector`
  modifier itself to fall back to material-only rendering identical to what §4 found for AppKit** —
  the SwiftUI `.inspector` API reference (§2) doesn't describe its own rendering at all, and AppTape
  cannot use the modifier per ADR-0024, so this was not pursued further.
