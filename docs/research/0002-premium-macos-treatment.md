# What makes a macOS app read as premium, not just native

Research for [#72](https://github.com/SamWongML/macos-audio-recording/issues/72), part of the map in [#70](https://github.com/SamWongML/macos-audio-recording/issues/70). Answers: what separates a merely-native macOS app from one that reads as premium, studied across ten deliberately non-audio comparison apps (they teach visual treatment, not structure) and grounded in Apple's own macOS 26/27 Human Interface Guidelines and Liquid Glass material guidance. This feeds [#74](https://github.com/SamWongML/macos-audio-recording/issues/74), which decides AppTape's design language.

## Method and sourcing

Three research passes ran in parallel and are synthesized below: (1) first-party Apple documentation — the HIG and API references, via `mcp__xcode__DocumentationSearch` and direct fetches of `developer.apple.com/design/human-interface-guidelines/*`; (2) design-treatment research on Craft, Things 3, Raycast, Bear, and Fantastical/Cardhop; (3) design-treatment research on Sketch, Ivory, Sofa, NotchNook, and Reeder, plus a scan of recent Apple Design Award macOS winners. Every claim below carries its source URL inline.

**Sourcing caveats, stated up front rather than buried:**

- **No screenshots were captured.** Direct `WebFetch` of App Store listing pages (`apps.apple.com`) consistently redirected to a generic, localized "Today" tab rather than the target app's page, for all apps tried. Every app-specific claim below rests on **written** sources — marketing pages, designer blog posts, and design-teardown/review articles that describe (rather than show) the interface. Where a source itself is describing a screenshot it saw, that's noted; nothing here was independently visually verified against a screenshot by this research.
- **A few hex/pixel values are third-party reverse-engineering, not official specs** (an inferred Raycast token sheet, an inferred Bear color/line-height teardown). These are flagged inline at the point of use — treat them as directionally right, not exact.
- **Sofa and NotchNook are thinly documented everywhere.** Both are small, low-profile apps; design-focused writing about them essentially doesn't exist. Their entries below are honest about the resulting gaps rather than padded.
- **Empty states are undocumented in writing for all ten apps.** No design blog, review, or marketing page in either research pass described an empty-state treatment for any of the ten apps. This is itself a finding — see §5.

---

## 1. Accent discipline

### HIG grounding

- Custom app accent colors are explicitly sanctioned "to enhance the visual experience of your app or game and express its unique personality," settable via asset catalog. — https://developer.apple.com/design/human-interface-guidelines/color
- **The system accent color wins by default.** A custom accent color only actually renders when the person has set System Settings → General → Accent color to **Multicolor**; any other choice overrides the app's custom color everywhere — with one carved-out exception: a sidebar icon *deliberately* given a fixed, meaning-carrying color (Mail's yellow VIP flag is Apple's own example) is left alone, because it's conveying information, not theme. — https://developer.apple.com/design/human-interface-guidelines/color#App-accent-colors, https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices
- **Liquid Glass has no inherent color** — by default it takes the color of what's behind it. Apply color "sparingly," reserved for elements that "truly benefit from emphasis, such as status indicators or primary actions." Prefer tinting a *control's background* (as the system does for prominent buttons) over tinting symbols or text, and explicitly avoid tinting more than one control's background at once — Apple's own do/don't example colors only the Done button in a toolbar, not the whole bar. — https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color
- Contrast floor, enforced by Accessibility Inspector: text up to 17pt needs **4.5:1**; 18pt+ needs **3:1**; bold text at any size needs **3:1**. — https://developer.apple.com/design/human-interface-guidelines/accessibility#Vision

### Across the comparison apps

| App | Accent approach | Source |
|---|---|---|
| Things 3 | One committed brand blue ("Things blue" box/checkbox motif, Magic Plus button); in the 2025 OS-26 redesign it's now filtered through "a touch of glass ... that lets a hint of color shine through" rather than flat-filled | [Things for OS 26](https://culturedcode.com/things/blog/2025/09/things-for-os-26/) |
| Raycast | One committed accent, **Raycast Red `#FF6363`**, used sparingly — "reserved for selection, status, and the brand," described as "the page is 98% achromatic." A secondary blue (~`#55b3ff`, reverse-engineered figure) carries more day-to-day link/focus weight. Canvas is near-black blue-tinted, not pure black | [Inside Raycast's Design System](https://aiskill.market/blog/inside-raycasts-design-system) |
| Bear | One committed brand red (~`#D7494C`, third-party estimate), used for tag color, link color, cursor, and the bear-face icon; OLED dark theme swaps to orange to hold contrast on true black; deliberately **absent from loading states** ("no spinners, no skeleton loading screens") | [Mobbin](https://mobbin.com/colors/brand/bear), [Bear: Typography-First Writing](https://blakecrosley.com/guides/design/bear) |
| Reeder | Accent used "infrequently but effectively, putting the emphasis on the content of your feeds above all else" — no fixed hex documented, but restraint is the stated design principle | [Reeder: A New Approach to Following Feeds — MacStories](https://www.macstories.net/reviews/reeder-a-new-approach-to-following-feeds/) |
| Craft | No fixed accent — 10 user-selectable interface accent colors, plus a document-driven "App Style" that bleeds the open document's own colors into sidebar/toolbar chrome (Home/Browse views and typography are explicitly exempt) | [Craft 3.6.0](https://www.craft.do/blog/craft-update-3-6-0), [App Style in Craft](https://support.craft.do/hc/en-us/articles/19224488955676-App-Style-in-Craft) |
| Ivory | No fixed accent — 10–11 user-selectable accent colors across 4 themes | [Ivory for Mastodon Review — MacStories](https://www.macstories.net/reviews/ivory-for-mastodon-review-tapbots-reborn/) |
| Sketch | No fixed in-app accent — ties Layer List/Inspector highlight color directly to the **system** accent color since Sketch 52; the yellow-diamond brand color lives only in the app icon/marketing | [Dark Mode, Data, a brand new look — Sketch Blog](https://www.sketch.com/blog/dark-mode-data-a-brand-new-look-and-more-in-sketch-52/) |
| Fantastical | No single UI accent — calendar color-per-event is the organizing chromatic principle instead | [Fantastical Tips to Unclutter your Calendar](https://flexibits.com/blog/2022/10/fantastical-tips-to-unclutter-your-calendar/) |
| Cardhop | Dark theme by default; the Notes panel gets an isolated yellow (light) / gray (dark) accent, visually set apart from the rest of the app | [MacStories Cardhop review](https://www.macstories.net/reviews/cardhop-by-flexibits-takes-on-contacts/), [flexibits.com/cardhop](https://flexibits.com/cardhop) |
| Sofa | No single accent — 100+ user-selectable themes | [Sofa](https://www.sofahq.com/), [9to5Mac hands-on](https://9to5mac.com/2021/03/16/sofa-iphone-app-organize-movies-music-books-podcasts-apps/) |
| NotchNook | Not documented in any source found | — |

### Pattern

The ten apps split cleanly into two camps: **apps that commit to one brand accent used sparingly** (Things, Raycast, Bear, Reeder) and **apps that hand the accent decision to the user entirely** (Craft, Ivory, Sofa, Sketch — which defers straight to the system accent). Within the committed-accent camp, the shared discipline isn't just "pick one color" — it's *how little of the UI carries it*: Raycast's own design write-up puts the figure at roughly 2% of the surface; Bear withholds its accent specifically from loading/progress chrome; Reeder's reviewer language is "infrequently but effectively." AppTape's map has already committed to "one committed non-system accent" (issue #70), which puts it in the Things/Raycast/Bear/Reeder camp — the load-bearing lesson from that camp is restraint in *coverage*, not merely in *count*.

**Forbidden zones, converging from three directions:** the HIG says don't tint more than one control's background at once and prefer tinting backgrounds over text/symbols; Bear excludes its accent from loading states; and the sidebar-icon exception in the HIG (fixed color only for a genuinely meaningful flag, not theme) argues against sprinkling the accent decoratively across sidebar iconography the way a system-accent-following app would.

---

## 2. Typography

### HIG grounding

**The macOS built-in text-style table** (HIG Typography page):

| Text style | Weight | Size (pt) | Line height (pt) | Emphasized weight |
|---|---|---|---|---|
| Large Title | Regular | 26 | 32 | Bold |
| Title 1 | Regular | 22 | 26 | Bold |
| Title 2 | Regular | 17 | 22 | Bold |
| Title 3 | Regular | 15 | 20 | Semibold |
| Headline | Bold | 13 | 16 | Heavy |
| Body | Regular | 13 | 16 | Semibold |
| Callout | Regular | 12 | 15 | Semibold |
| Subheadline | Regular | 11 | 14 | Semibold |
| Footnote | Regular | 10 | 13 | Semibold |
| Caption 1 | Regular | 10 | 13 | Medium |
| Caption 2 | Medium | 10 | 13 | Semibold |

— https://developer.apple.com/design/human-interface-guidelines/typography#macOS-built-in-text-styles

- System font is **SF Pro**. **macOS does not support Dynamic Type** (unlike every other Apple platform); hierarchy still comes from the fixed table above. macOS additionally exposes "dynamic system font variants" (Control content, Label, Menu, Menu bar, Title, Tool tips, Monospaced, Bold system, etc.) as dedicated `NSFont` factory methods, for matching system-chrome typography exactly. — https://developer.apple.com/design/human-interface-guidelines/typography#macOS
- Default legible size on macOS is **13pt**, minimum **10pt** — smaller than every other Apple platform's minimum. "In general, avoid light font weights," especially at small sizes. — https://developer.apple.com/design/human-interface-guidelines/typography#Ensuring-legibility
- Custom fonts are permitted but the app must manually replicate the accessibility behaviors (legibility minimums, Bold Text support) that come free with system fonts. — https://developer.apple.com/design/human-interface-guidelines/typography#Using-custom-fonts
- Hierarchy guidance: "Adjust font weight, size, and color as needed to emphasize important information... **Minimize the number of typefaces you use**, even in a highly customized interface" — too many typefaces "can obscure your information hierarchy." — https://developer.apple.com/design/human-interface-guidelines/typography#Conveying-hierarchy

### Across the comparison apps

| App | System font or departure | Source |
|---|---|---|
| Bear | **Full departure**: commissioned a custom typeface, **Bear Sans** (built on Brandon Knap's Clarika, redrawn glyphs, larger x-height, tighter tracking, true italics), replacing Avenir because it "became fatiguing at small sizes." Used consistently across editor *and* app chrome. SF Mono for code | [Meet Bear Sans](https://blog.bear.app/2023/08/learn-about-our-new-custom-font-bear-sans/) |
| Raycast | **Departure in chrome**: Inter everywhere (headings/body/buttons/captions, with OpenType features enabled) + GeistMono for code — a deliberate break from SF to signal "developer tool." Size contrast is deliberately modest — density over dramatic hierarchy | [Inside Raycast's Design System](https://aiskill.market/blog/inside-raycasts-design-system) |
| Reeder | **Content-scoped departure only**: app chrome stays system font; the article *reading* surface (Reeder 5) added New York (serif) and Helvetica Neue as selectable alternatives — the departure lives in content, not chrome. Widgets separately offer System/Rounded/Serif/Compact | [Reeder 5 Review — MacStories](https://www.macstories.net/reviews/reeder-5-review-read-later-tagging-icloud-sync-and-design-refinements/) |
| Things 3 | No custom typeface — system font throughout — but exposes **14 discrete Mac text-size steps**, with vector icons that scale proportionally alongside text, an unusually granular user-facing size-contrast control | [Things Big and Small](https://culturedcode.com/things/blog/2023/09/things-big-and-small/) |
| Ivory | **No departure**, on principle: exclusively system font, with the designer's own framing — "Personality belongs in art and sound, not typography" | [Ivory: Playful Precision — design teardown](https://blakecrosley.com/guides/design/ivory) |
| Craft | System font for UI chrome even when its document-driven "App Style" is active; per-document typefaces are a content-only feature | [App Style in Craft](https://support.craft.do/hc/en-us/articles/19224488955676-App-Style-in-Craft) |
| Fantastical | No custom typeface documented; size contrast comes from "a large month label and thicker day separators" | [The New Fantastical Review — MacStories](https://www.macstories.net/reviews/the-new-fantastical-review/) |
| Sketch, Sofa, NotchNook, Cardhop | No typography specifics found in any source reviewed — gap | — |

### Pattern

Two legitimate strategies, not one. **Stay on SF entirely** (Ivory, Things, Craft's chrome) is the majority pattern and is explicitly argued for by Ivory's own designers as keeping "personality" out of a place it doesn't belong. **Depart, but scope the departure to content, not chrome** (Reeder: serif only in the reading pane) is the other legitimate pattern. Bear and Raycast are the outliers that commit a custom face to the whole shell — and both tie that choice to a specific identity claim (Bear: distraction-free writing tool; Raycast: developer tool), not decoration for its own sake. Given AppTape's settled rule that vibrancy — and by extension, visual distinctiveness — concentrates in *content* (the waveform, the Trim region) rather than chrome, **Reeder's content-scoped departure is the closer precedent** to reach for if AppTape ever wants a typographic voice beyond SF, over Bear's whole-app custom-font commitment.

---

## 3. Density and spacing

### HIG grounding

- Pointer-target padding: "it works well to add about **12 points of padding**" around bezeled interactive elements, and "about **24 points of padding**" around non-bezeled ones; adjacent bar buttons should have contiguous hit regions with no dead space between them. — https://developer.apple.com/design/human-interface-guidelines/pointing-devices#Standard-pointers-and-effects
- Button sizing on macOS: default **28×28pt**, minimum **20×20pt** (smaller than every touch platform — iOS is 44×44/28×28). — https://developer.apple.com/design/human-interface-guidelines/designing-for-games#Look-stunning-on-every-display
- **No fixed row-height number is published.** Row height instead scales with the sidebar's Small/Medium/Large size setting (user-adjustable in General settings, or set programmatically) — see §4. — https://developer.apple.com/design/human-interface-guidelines/sidebars#macOS
- "Avoid placing controls or critical information at the bottom of a window" — people routinely move windows so the bottom edge goes off-screen. — https://developer.apple.com/design/human-interface-guidelines/layout#macOS
- Liquid Glass's own hierarchy rule: "differentiate controls from content... Instead of a background, use a scroll edge effect to provide a transition between content and the control area" — i.e. density and material choices are meant to work together to keep chrome legibly separate from content. — https://developer.apple.com/design/human-interface-guidelines/layout#Visual-hierarchy

### Across the comparison apps

| App | Density direction | Source |
|---|---|---|
| Raycast | Explicitly **tight/dense** — "compact padding, uniform row heights, minimal gaps," reinforcing "a finely machined instrument" for fast keyboard scanning; the search bar was deliberately *enlarged* to signal importance, breaking uniformity on purpose at one point | [Inside Raycast's Design System](https://aiskill.market/blog/inside-raycasts-design-system), [A fresh look and feel — Raycast](https://www.raycast.com/blog/a-fresh-look-and-feel) |
| Sketch | Dense, tool-focused — the Inspector redesign added "collapsible sections, so the only information on screen is the information you actually need," inline values, shortcut hints in tooltips | [Sketch 52 — Sketch Blog](https://www.sketch.com/blog/dark-mode-data-a-brand-new-look-and-more-in-sketch-52/) |
| Things 3 | Moved toward **more air**: the 2025 redesign explicitly added "wider spacing that feels more relaxed" plus softened corner curvature app-wide | [Things for OS 26](https://culturedcode.com/things/blog/2025/09/things-for-os-26/) |
| Fantastical | Explicitly **traded density for legibility**: the Mac redesign shows "3-4 fewer items on screen" than the prior version, in exchange for cleaner day separators and clearer hierarchy — a documented before/after case of a team choosing air over cramming | [The New Fantastical Review — MacStories](https://www.macstories.net/reviews/the-new-fantastical-review/) |
| Reeder | "Simple and well spaced out **without coming off as sparse**" — generous but not empty | [Reeder — MacStories](https://www.macstories.net/reviews/reeder-a-new-approach-to-following-feeds/) |
| Bear | Content width capped near 680px (~75 characters), line-height ~1.6 (third-party estimate) for reading comfort | [Bear: Typography-First Writing](https://blakecrosley.com/guides/design/bear) |
| Craft | Marketing describes "low density"/generous whitespace; no numeric sourcing found | — |
| Ivory, Sofa, NotchNook, Cardhop | No density specifics found — gap | — |

### Pattern

Density is **context-dependent, not universal** — and the split tracks the app's job. Power-user tools aimed at fast repeated scanning (Raycast, Sketch's Inspector) lean tight and dense on purpose. Consumer-facing browsing/reading/planning apps (Things, Fantastical, Reeder) lean toward *more* air, and multiple of them **explicitly moved toward more air in a named redesign**, framing the tighter, denser predecessor as the thing being improved away from. AppTape is a small utility, but its job — reviewing a handful of Recordings, trimming one at a time — is closer to Things/Fantastical/Reeder's browsing-and-deciding mode than to Raycast's rapid-fire command-palette scanning. The comparison set argues for the generous, "relaxed" direction over compression.

---

## 4. Sidebar row composition

### HIG grounding

- Sidebar row height, text, and glyph size **scale with the sidebar's size setting (Small/Medium/Large)** — set programmatically, or changed by the person via General settings' sidebar-icon-size control. No fixed point value is published beyond that. — https://developer.apple.com/design/human-interface-guidelines/sidebars#macOS
- "Consider using familiar symbols to represent items in the sidebar" — SF Symbols preferred over bitmap images. — https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices
- **Sidebar icons follow the user's chosen system accent color by default** — "make sure your sidebar icons display the color people choose" — with the same fixed-color exception as §1 (a deliberately meaningful color like Mail's VIP flag is left alone). — https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices
- Sidebars sit in the Liquid Glass functional layer, floating above content; to reinforce that separation, extend content *underneath* the sidebar (via `backgroundExtensionEffect()`) rather than stopping it abruptly at the sidebar's edge. — https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices
- Show **no more than two levels of hierarchy** in a sidebar; beyond that, use a content-list split view instead. — https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices
- **A genuine gap in Apple's own documentation**: no HIG page specifies a selection-indicator visual treatment (full-row fill vs. tint vs. inset/capsule) for sidebar rows, and none specifies a sidebar-row-specific hover state. The closest available guidance is the platform-wide pointer content-effects taxonomy (highlight for small transparent elements, lift for small opaque elements, hover for large elements), which isn't sidebar-specific. — https://developer.apple.com/design/human-interface-guidelines/pointing-devices#Standard-pointers-and-effects

### Across the comparison apps

| App | Row composition | Source |
|---|---|---|
| Things 3 | Areas group Projects hierarchically; per-row metadata "tucked away in the corner until you need them" (minimal by default); circular **Progress Pies** as trailing completion metadata; the six top-level categories (Inbox/Today/Upcoming/Anytime/Someday/Logbook) each get a **distinctly colored icon** | [Things features page](https://culturedcode.com/things/features/) |
| Bear | **260 "TagCons"** — auto-assigned icon glyphs paired to tags, shown both in the sidebar and inline in the editor, "softer shapes and unified stroke weights" — unusually iconography-forward versus Apple Notes' plain-text folders | [Bear 2.7 coverage — AlternativeTo](https://alternativeto.net/news/2026/3/markdown-note-taking-app-bear-2-7-revamps-tagcons-and-adds-tag-management-option-on-macos) |
| Reeder | Sidebar lists feeds "alongside their favicons," sectioned, long-press to manage. Content rows (not the sidebar itself) share a uniform layout: favicon + source line, preview text, plus an image for articles or cover art for audio items | [Reeder — MacStories](https://www.macstories.net/reviews/reeder-a-new-approach-to-following-feeds/) |
| Fantastical | Plain calendar toggle list; light theme renders a **black sidebar against a white schedule pane** — a striking value contrast rather than the usual pale-gray inset sidebar (lower-confidence — not tied to one primary citation) | — |
| Cardhop | Contact-group sidebar mirrors Apple Contacts' own group list; the main pane favors recents + upcoming birthdays over an alphabetical list | [MacStories Cardhop review](https://www.macstories.net/reviews/cardhop-by-flexibits-takes-on-contacts/) |
| Raycast | Rows "compact and uniform," selection is keyboard-driven with a high-contrast state change rather than hover-first; icons share consistent stroke width and corner radii | [A fresh look and feel — Raycast](https://www.raycast.com/blog/a-fresh-look-and-feel) |
| Sketch | Nested-tree Layer List (pages → frames → layers) with a search field at the bottom; no citable detail on per-row icon/selection treatment — gap | [The Mac app interface — Sketch](https://www.sketch.com/docs/designing/the-interface/) |
| Craft, Sofa, NotchNook, Ivory | No citable sidebar-row detail found — gap | — |

### Pattern

Icon-per-row shows up specifically where rows represent **heterogeneous kinds of things that benefit from fast visual differentiation** — Things' six differently-colored category icons, Bear's 260 per-tag TagCons, Reeder's per-feed favicons — not as a blanket "always add an icon" rule. **No source anywhere, including Apple's own HIG, specifies a selection-indicator geometry** (fill vs. tint vs. inset capsule) — this is a real, load-bearing gap: AppTape's design language will have to make this call without direct precedent from either Apple's documentation or citable written description of any of the ten comparison apps. It should be settled by trying options against the running app (per the map's own "judged by running the real app and screenshotting it" rule), not by more research.

---

## 5. Empty states

### HIG grounding

- **No dedicated HIG "Empty States" page exists.** The only first-party guidance is one paragraph on the Writing page: "Provide clear next steps on any blank screens. An empty state... can provide a good opportunity to make people feel welcome and educate them about your app... guide people on actions they can take, and give them a button or link to do so if possible. Remember that empty states are usually temporary, so don't show crucial information that could then disappear." — https://developer.apple.com/design/human-interface-guidelines/writing#Best-practices
- **`ContentUnavailableView`** is Apple's own recommended SwiftUI answer: "It is recommended to use `ContentUnavailableView` in situations where a view's content cannot be displayed" — network error, an empty list, no search results. Built from a `Label` plus optional `description` and `actions`. A ready-made `ContentUnavailableView.search(text:)` covers the no-search-results case specifically. — https://developer.apple.com/documentation/SwiftUI/ContentUnavailableView

### Across the comparison apps

**No written source in either research pass described an empty-state treatment for any of the ten apps.** Marketing pages, designer blog posts, and reviews for Craft, Things 3, Raycast, Bear, Fantastical, Cardhop, Sketch, Ivory, Sofa, and NotchNook were all searched with this specifically in mind; none discuss what the app shows when a list has nothing in it. This absence, across ten apps that are otherwise well-documented on every other dimension, is itself informative.

### Pattern

With zero citable comparison-app precedent, the only grounded guidance available is Apple's own: bespoke, on-voice, welcoming copy with a concrete next action, and never load-bearing information that might vanish once the state resolves. Given `ContentUnavailableView` is Apple's explicitly "recommended" default and none of these ten premium apps appear to have spent visible design effort building something more elaborate (or if they did, nobody wrote about it), **empty states read as a low-leverage place to invest bespoke illustration** — a well-considered `ContentUnavailableView` (a chosen SF Symbol, on-voice copy, and a real action) is a defensible, non-compromising default rather than a corner being cut. If this needs to be pinned down more precisely, it requires direct screenshot capture of these apps' empty states, not further literature search — flagged in "what I could not verify" below.

---

## 6. Material and depth

### HIG grounding

- **Two separate material systems.** Liquid Glass is a dynamic material for the *functional layer* (controls, navigation — tab bars, sidebars) that floats above content "without obscuring" it. Standard materials (blur, vibrancy, blending) are for the *content layer*, conveying structure within the content itself. — https://developer.apple.com/design/human-interface-guidelines/materials
- **The load-bearing rule: "Don't use Liquid Glass in the content layer."** The sole exception is transient interactive content-layer controls (sliders, toggles), which pick up a glass appearance only while actively being manipulated. — https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass
- **Use it sparingly.** "If you apply Liquid Glass effects to a custom control, do so sparingly... overusing this material in multiple custom controls can provide a subpar user experience by distracting from that content. Limit these effects to the most important functional elements in your app." There's also a stated performance cost to overusing glass containers/effects. — https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass, https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views#Optimize-performance-when-using-Liquid-Glass-effects
- Two variants: `.regular` (legibility-preserving, for text-heavy elements — "alerts, sidebars, or popovers") and `.clear` (highly translucent, for floating over rich media like photos/video). — https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass
- Toolbar-specific instruction: "Reduce the use of toolbar backgrounds and tinted controls... Instead, use the content layer to inform the color and appearance of the toolbar, and use a `ScrollEdgeEffectStyle`" for the content/toolbar transition. — https://developer.apple.com/design/human-interface-guidelines/toolbars#Best-practices
- **No formal, numeric shadow/elevation system exists** in the HIG (nothing like Material Design's dp-tiers). Shadow usage stays qualitative and contextual — the closest first-party hook is the semantic `NSColor.shadowColor`. — https://developer.apple.com/design/human-interface-guidelines/color#macOS

### Across the comparison apps

| App | Material treatment | Source |
|---|---|---|
| Sketch | Confirmed sidebar vibrancy — "transparency, which means it ever-so-slightly takes on the background color of your wallpaper" — plus a deliberately "deeper shadow" on the app icon for a floating feel | [The new Sketch icon — Sketch Blog](https://www.sketch.com/blog/how-we-redesigned-the-sketch-icon-for-big-sur/) |
| Things 3 | 2025 redesign added restrained glass — described as "**a touch of** glass," "tastefully refreshed" — to the sidebar, plus glassy interactive buttons (glow + scale on touch) and a "liquid"-deforming Magic Plus button; Clear-style widgets let wallpaper show through | [Things for OS 26](https://culturedcode.com/things/blog/2025/09/things-for-os-26/) |
| Reeder (v5, prior release) | "The typography, semi-transparent left panel" — sidebar vibrancy; **not confirmed for the current relaunched version** — version-specific gap | [Reeder 5 — Medium](https://medium.com/macoclock/reeder-5-best-news-reader-app-for-mac-d4887f8a664f) |
| Raycast | **No blur/glass** — depth comes from hairline borders and inset "keyboard key" highlight strokes instead, deliberately tactile-via-line-work rather than material | [Raycast for designers — UX Collective](https://uxdesign.cc/raycast-for-designers-649fdad43bf1) (secondary attribution — original source 403'd on direct fetch) |
| Bear | **No documented translucency** — flat, calm surfaces, consistent with its distraction-free positioning | — |
| Craft | **No documented translucency** — "App Style" is explicitly color-only, no glass/blur | [App Style in Craft](https://support.craft.do/hc/en-us/articles/19224488955676-App-Style-in-Craft) |
| NotchNook | Transparency present but **user-toggleable** rather than one committed material choice | [How-To Geek](https://www.howtogeek.com/these-apps-turn-your-macbook-notch-into-a-dynamic-island/) |
| Ivory, Fantastical, Cardhop, Sofa | No citable material-specific detail found — gap | — |

### Counter-example, first-party critique of Apple's own material

Nick Heer's review of Liquid Glass on macOS argues the system's own default overreaches: insufficient toolbar/menu text contrast, "the continued reduction of contrast in user interface elements... to its detriment," and — specifically about the Mac — that it "does not feel ready," reading as "alien, unsuited to a multi-window keyboard-and-pointer system." — https://pxlnv.com/blog/on-liquid-glass/. This is a direct, citable case that *even Apple's own sanctioned material*, applied broadly, reads as a liability on macOS specifically — independent corroboration of the HIG's own "sparingly" language, from someone criticizing Apple for not following it closely enough itself.

### Pattern

Glass/vibrancy in this comparison set shows up specifically at **navigation/chrome surfaces** (sidebars in Sketch, Things, Reeder v5) — never as a blanket wash — and even there the apps' own language is restrained ("a touch of," "ever-so-slightly"). The apps with the most disciplined restraint on every other dimension (Bear, Craft, Raycast) **skip glass entirely** and get depth from other means instead — a custom typeface plus flat calm surfaces for Bear, hairline borders and inset strokes for Raycast. Three independent lines of evidence converge on the same conclusion: Apple's own guidance ("sparingly... limit to the most important functional elements"), the apps that do use glass (restrained, chrome-only, self-described as "a touch"), and the apps that pointedly don't (get depth from typography or line-work instead). This directly corroborates the map's own settled rule that chrome stays sober while vibrancy concentrates in content — and Nick Heer's critique of macOS's own system-wide Liquid Glass is a live warning about what happens when that restraint is abandoned even at the OS level.

---

## 7. Where they add colour the system wouldn't

### HIG grounding

Custom accent color is explicitly sanctioned to "express its unique personality" (§1), and the sidebar-icon fixed-color exception exists specifically for a color that's carrying *meaning* (Mail's VIP flag), not decoration. — https://developer.apple.com/design/human-interface-guidelines/color, https://developer.apple.com/design/human-interface-guidelines/sidebars#Best-practices

### Across the comparison apps

| App | Where color appears beyond system default | Source |
|---|---|---|
| Fantastical | Heat-map/dot day-density indicators, colorful AccuWeather forecast icons inline in the event list, per-calendar color coding throughout | [The New Fantastical Review — MacStories](https://www.macstories.net/reviews/the-new-fantastical-review/) |
| Things 3 | Distinctly colored icon per task category — more chromatic than Apple Reminders' own sidebar defaults | [Things features page](https://culturedcode.com/things/features/) |
| Bear | 260 per-tag TagCon icon glyphs — more chromatic than Apple Notes' plain folder icons | [AlternativeTo, Bear 2.7](https://alternativeto.net/news/2026/3/markdown-note-taking-app-bear-2-7-revamps-tagcons-and-adds-tag-management-option-on-macos) |
| Reeder | Per-feed favicons are the main chromatic texture running through every list row | [Reeder — MacStories](https://www.macstories.net/reviews/reeder-a-new-approach-to-following-feeds/) |
| Sofa | Poster/cover artwork as the primary chromatic element in every row, pulled from Apple Music/App Store metadata; 70+ alternate app icons | [Sofa Review — MacStories](https://www.macstories.net/reviews/sofa-review-a-simple-tool-for-tracking-movies-tv-shows-books-and-podcasts/) |
| Cardhop | Isolated yellow/gray Notes-panel treatment, visually set apart from the rest of the app | [flexibits.com/cardhop](https://flexibits.com/cardhop) |
| Craft | **Washi Tapes** (decorative digital tape strips) and hand-drawn **Doodles** as document separators, a 100+ style gallery of backdrop/text combinations | [Introducing Styling — Craft](https://www.craft.do/blog/introducing-styling) |
| Raycast, Ivory, Sketch | Comparatively minimal — Raycast's own framing is "98% achromatic"; Ivory's color lives in a user-chosen accent plus hand-drawn iconography, not spontaneous chrome color; Sketch ties highlight color to the system accent | [Inside Raycast's Design System](https://aiskill.market/blog/inside-raycasts-design-system) |

### Pattern — and the one clear counter-example

In almost every case, added color is **tied to real data**: a calendar's color, a movie's cover art, a feed's favicon, a task category's identity. Craft's Washi Tape/Doodle system is the one clear exception in the whole set — decorative, not data-driven, literal skeuomorphic ornament (fake tape, hand doodles) laid over otherwise plain UI. No external critic was found calling it out directly, but structurally it's the outlier against every other app studied, and it maps precisely onto what AppTape's map already rejected: "decorative gradients... rejected as the road to a dated skeuomorph" (#70). This gives that rejection a concrete comparison-app example, not just an abstract principle: color that decorates rather than informs is the thing to avoid, and AppTape's committed design rule — vibrancy concentrated in the waveform, Trim, and meters, all of which are real captured data — is structurally the Reeder/Sofa/Fantastical pattern (color as data), not the Craft pattern (color as ornament).

---

## Counter-examples (consolidated)

Treatments that read as dated, gaudy, or "trying too hard" — recorded so the design-language decision knows what it's avoiding, not just what to copy:

1. **Apple's own system-wide Liquid Glass, criticized for overreach on macOS specifically.** Nick Heer: insufficient toolbar/menu contrast, "the continued reduction of contrast in user interface elements... to its detriment," "alien, unsuited to a multi-window keyboard-and-pointer system," "does not feel ready" on the Mac. — https://pxlnv.com/blog/on-liquid-glass/. Direct evidence that glass restraint matters *even against Apple's own shipped default*, not just against third-party excess.
2. **Craft's Washi Tape / Doodle decoration system.** The one mechanism across all ten apps that's literal decorative ornament (fake tape strips, hand-drawn doodles) rather than restrained color or type. Not externally reviewed as bad, but structurally the outlier against every other app studied, and the closest concrete match to what AppTape's map already ruled out as "the road to a dated skeuomorph." — https://www.craft.do/blog/introducing-styling
3. **Fantastical's own pre-redesign density**, implicitly cast as the state its 2020s Mac redesign moved away from — "3-4 fewer items on screen" was the tradeoff *for* clarity, meaning the denser predecessor read as more cramped by the same team's own later judgment. — https://www.macstories.net/reviews/the-new-fantastical-review/
4. **Sketch's pre-2016 icon inconsistency** — different-colored diamonds distinguished release channels/versions before the 2016 and Big Sur redesigns unified the mark. A minor, historical, but real case of inconsistent iconography, later fixed deliberately. — https://www.sketch.com/blog/2016/11/08/an-iconic-new-look-and-more/, https://www.sketch.com/blog/how-we-redesigned-the-sketch-icon-for-big-sur/. (One hypothesis this research explicitly tested and did **not** substantiate: that Sketch went through a heavily skeuomorphic 2010–2015 era. Contrary evidence found instead — Sketch was positioned from launch as a *reaction against* Adobe's complexity, described as "sparse, utilitarian" even in 2011. — https://nira.com/sketch-history/. Recorded here so the assumption isn't silently carried forward.)
5. **NotchNook's fully user-toggleable transparency and spacing** — the opposite of one considered design point of view. It proves the app *can* look glassy and airy, but because every material/spacing decision is a user setting rather than a committed choice, it reads as less deliberate than Sketch's system-accent restraint or Reeder's "infrequent but effective" color discipline, both of which are the app's own settled position, not a slider. — https://www.howtogeek.com/these-apps-turn-your-macbook-notch-into-a-dynamic-island/
6. **The HIG's own inversion warning, worth stating as an explicit avoidance target**: "Don't use Liquid Glass in the content layer." An app that puts glass *on* its content (the waveform, the Trim region) while leaving chrome flat would be doing the literal opposite of both Apple's rule and AppTape's own already-settled "content is the colour, chrome stays sober" position — the single clearest concrete mistake this research surfaces to avoid. — https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass
7. **Notch-utility apps as a genre carry a standing "gimmick" risk** — weakly sourced (no single strong citation), but worth naming since AppTape is itself a small utility app that could tip into over-styling if the design language overcorrects toward personality. NotchNook itself was specifically *not* criticized this way (called "the most feature-rich and polished" implementation, praised for drag-and-drop that "feels integrated rather than gimmicky") — https://www.howtogeek.com/these-apps-turn-your-macbook-notch-into-a-dynamic-island/, https://raphaeljourney.com/blogs/best-notch-apps-macbook — but the category-level risk it successfully avoided is itself instructive.

---

## Recent Apple Design Award winners on macOS (2023–2025)

Scoped scan only — a full visual-treatment audit of these titles was not performed in this pass (see "what I could not verify" below). Official press releases: [2025](https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/), [2024](https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/), [2023](https://www.apple.com/newsroom/2023/06/apple-announces-winners-of-the-2023-apple-design-awards/).

Confirmed Mac-app winners: **Resident Evil Village** (2023, Visuals and Graphics/Game), **Crouton** (2024, Interaction/App), **Rooms** (2024, Visuals and Graphics/App), **Lies of P** (2024, Visuals and Graphics/Game), **djay Pro** (2024, Spatial Computing/App), **Play** (2025, Innovation/App — later pulled from the App Store following its acquisition by Apple), **DREDGE** (2025, Interaction/Game), **Neva** (2025, Social Impact/Game). Of these, **Crouton** (Interaction) and **Rooms** (Visuals and Graphics) are the categories most directly relevant to a small utility app's chrome and would be the natural next look if this line of research continues.

**Correction worth flagging**: Sofa is **not** an Apple Design Award winner or finalist in any year checked (2024/2025 rosters explicitly checked against the official lists). It has instead received an Apple Editors' Choice Award and repeated "App of the Day" placement — a real but different distinction. Its entries above should not be read as ADA-precedent. — https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/, https://9to5mac.com/2024/04/30/award-winning-sofa-downtime-organizer-major-update/

---

## Synthesis for the design-language decision

Cross-cutting conclusions, structured to support an ADR:

1. **Accent restraint is measured in coverage, not just count.** Committing to one accent (already AppTape's position) isn't sufficient on its own — the premium examples (Raycast, Bear, Reeder) hold that color to a small, deliberate fraction of the surface and explicitly withhold it from certain places (loading/progress states, more than one control at once).
2. **The clearest concrete mistake to avoid is inverting the HIG's own layering rule**: glass belongs on chrome/controls, never on content. AppTape's "content is the colour, chrome stays sober" position already gets this the right way round — this research is convergent, first-party confirmation, not a new finding.
3. **Where glass does appear in premium apps, it's chrome-only and self-consciously restrained** ("a touch of," "ever-so-slightly") — never a wash. The apps skipping glass entirely (Bear, Craft, Raycast) don't read as less premium for it; they get depth from typography or line-work instead.
4. **Typography has two legitimate paths**: stay on SF entirely (the majority, and arguably the safer default for a small utility), or depart only in a content-scoped way (Reeder's serif reading pane) — never depart in chrome without an identity claim backing it up the way Bear and Raycast do.
5. **Density should track the app's job, not a universal "premium = airy" assumption.** AppTape's task (review a handful of Recordings, trim one) resembles Things/Fantastical/Reeder's browsing-and-deciding mode more than Raycast's rapid-fire scanning — the comparison set argues for generous spacing over compression.
6. **Sidebar selection-indicator geometry has no precedent anywhere** — not in Apple's own HIG, not in any written description of these ten apps. This has to be settled empirically, in the running app, not researched further.
7. **Icon-per-sidebar-row correlates with heterogeneous row content needing fast differentiation**, not with premium-ness generally — a sidebar of same-shaped rows (like AppTape's Recordings list, mostly) has weaker grounds for icons than Things' six differently-typed categories or Bear's 260 tag types.
8. **Added color should be data, not ornament.** Every comparison app except one ties its extra chromaticism to real content (calendar color, cover art, favicon). Craft's Washi Tape/Doodle system is the sole ornamental counter-example and lines up exactly with what the map already ruled out.
9. **Empty states are a low-leverage investment.** No premium comparison app has a documented bespoke empty state; `ContentUnavailableView`, done well (real SF Symbol, on-voice copy, a real action), is a defensible default rather than a compromise.
10. **Even Apple's own Liquid Glass has been credibly criticized for overreach on macOS** — a reminder that "adopt the newest material" and "read as premium" are not the same axis, and that restraint is validated from both directions: by the apps praised for it and by criticism of the OS default for lacking it.

---

## What I could not verify

- **No screenshots were captured for any app.** Every app-level claim rests on written sources; App Store listing fetches redirected to a generic page for every app tried, across both research passes. If pixel-precise sidebar selection treatment, row height, or empty-state visuals matter for the design-language ADR, they need direct screenshot capture (App Store listing screenshots viewed in-browser, or hands-on use of the apps), not more literature search.
- **Sidebar selection-indicator geometry (fill / tint / inset capsule) is undocumented everywhere searched** — in Apple's own HIG and in every written source found for all ten comparison apps. This is a genuine gap, not an oversight in this research.
- **Empty states are undocumented in writing for all ten apps**, for the same reason.
- **Several color/spacing figures are third-party reverse-engineering, not official specs**: Raycast's `#55b3ff` secondary blue and detailed token sheet (oh-my-design.kr, itself a reconstructed document, not an official Raycast source), Bear's `#D7494C`/`#D14C3E` accent estimates and ~1.6 line-height figure (blakecrosley.com). Flagged inline at first use; treat as directionally right, not exact.
- **Sofa and NotchNook remain thinly sourced** despite real effort — no source for either gives a citable accent color, typography, row height, or empty-state treatment. This is consistent across both research passes and should be read as a genuine ceiling on what's knowable about these two apps without hands-on use.
- **2023/2024 Apple Design Award winners' Mac-platform status was not exhaustively verified** for every title in those years' rosters — only the winners explicitly confirmed as Mac apps are listed above; several category winners (Bears Gratitude, Crayola Adventures, Universe, and others) were left unconfirmed rather than guessed at.
- **A full visual-treatment audit of the confirmed ADA-winning Mac apps** (Crouton, Rooms, Lies of P, djay Pro, Resident Evil Village, Play, DREDGE, Neva) was not performed — this research only confirmed which winners are Mac apps, not how they're styled. Worth a follow-up pass, particularly Crouton (Interaction) and Rooms (Visuals and Graphics), if more precedent is needed.
- **Ivory's mascot-naming criticism** and the **"notch apps as a genre risk gimmickry"** claim are both weakly sourced (found via general search synthesis rather than one strong citation) and are flagged as lower-confidence where they appear above.
