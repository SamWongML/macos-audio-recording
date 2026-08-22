# What's the native macOS 26/27 idiom for a primary record affordance in a compact menu bar panel?

Research for the AppTape `MenuBarExtra` panel — a `.menuBarExtraStyle(.window)` popover (~320pt wide) that lists running apps (the domain glossary's **Source**) and lets someone start a **Recording**. The prototype's first pass at "start recording" was `Button(...).buttonStyle(.glassProminent).controlSize(.large)` — a full-width, accent-tinted capsule. The designer's verdict: *"those newly added big blue buttons are too awkward and too standing out, I don't like them."* This research asks what Apple itself does instead, and ranks concrete SwiftUI alternatives.

**SDK used**: same machine/build as `docs/research/capture-api.md` — Xcode 27.0 (build 27A5237l) at `/Applications/Xcode-beta.app`, SDK root `.../MacOSX.sdk`, running macOS 27.0 (build 26A5416b). `.swiftinterface` files used: `SwiftUI.framework/.../arm64e-apple-macos.swiftinterface`, `SwiftUICore.framework/.../arm64e-apple-macos.swiftinterface`, `Symbols.framework/.../arm64e-apple-macos.swiftinterface`. All are the `arm64e-apple-macos` (not `-macabi` or `-ios`) slice, so what's cited below is the real macOS surface, not an iOS API riding along via Catalyst/iPad-on-Mac. Per the prior research pass in this repo, macOS 26 shipped Liquid Glass and macOS 27 did not add new Liquid Glass surface area — that pattern holds again here: essentially everything relevant to this question that carries a `26.0` availability tag was introduced with Liquid Glass in macOS 26, and I found nothing genuinely new to macOS 27 for this specific problem (noted per-API below).

## Recommendation

**Don't add a separate button at all for the common case. Make the list row itself the record affordance, with a small circular glyph — not a filled capsule — as the only color-bearing element, living in a fixed trailing lane the row's live waveform background is never allowed to draw into, and reserve red for exactly the moment a Recording is active.** This is ranked #1 below (Alternative A), and it's a direct answer to the panel's current shape: rows already paint a real, per-Source amplitude waveform, so the record affordance has to coexist with motion and color rather than being the only colorful thing on the panel — see Q4 for why "the row is the subject, and the affordance is a protected lane within it" beats moving the control to a separate zone. Ship it paired with Alternative B (a `.bordered` button carrying `.keyboardShortcut(.defaultAction)`) for whenever nothing is selected yet, or as a keyboard-accessible fallback — `.defaultAction` is the actual macOS mechanism for marking "the button people are most likely to choose," and it does so with system-drawn coloration at normal control size, not a hand-picked accent capsule.

The designer's specific complaint — "too big/awkward/standing out" — is best explained by two separable failures, both fixable without abandoning tint or prominence outright: (1) `.controlSize(.large)` plus an unconstrained-width capsule inside a ~320pt popover breaks the HIG's own rule to **use style, not size, to distinguish a preferred action** (quoted in full below), and (2) a full-width bordered/glass button is not a documented macOS idiom — SwiftUI didn't even have an API to *ask* for full-width button stretching until macOS 26's `ButtonSizing.flexible`, whose sibling `.fitted`/`.automatic` cases imply content-hugging is still the platform default. Fixing size and width alone (Alternative E below) would technically satisfy the letter of the HIG, but it keeps the "isolated colored pill" silhouette the designer already rejected on sight — which is why the row-native and default-action options are ranked above it.

## 1. First-party precedent

What I could actually verify (SDK/documentation) versus what's described from memory of long-standing, stable OS behavior is called out per item — none of these system surfaces ship SwiftUI source, so "verified" here means confirmed via Apple's own support documentation or a third-party description I could cite, not a screenshot I personally captured this session.

| Surface | Primary-action affordance | Verified how |
|---|---|---|
| Screenshot/Screen Recording capture bar (⇧⌘5) | A small, capsule-shaped floating toolbar; the record control is a **circular icon button** inside it, not a wide tinted bar. Once recording starts, the capture bar disappears and is replaced by a **small icon in the menu bar** — Apple's own support page confirms a record/stop control appears there: "You'll see a small record button appear up in the menu bar" and a circular stop glyph once recording is underway. | [Apple Support: "How to record the screen on Mac"](https://support.apple.com/en-us/102618); corroborated by [Macworld](https://www.macworld.com/article/226469/how-to-take-screenshots-on-your-mac.html). Not independently screenshotted this session. |
| Voice Memos (macOS) | A **large red circular button**, centered, on a plain (non-glass, non-list) background — but it lives in its own dedicated recording pane, not inside a compact popover stacked on a list. It is the single, unambiguous piece of UI on that screen. | Description from memory of stable, long-standing OS behavior, corroborated by third-party how-to sources (e.g. [iDownloadBlog](https://www.idownloadblog.com/2018/08/14/howto-voice-memos-mac/)). Not Apple-documentation-verified; not screenshotted this session. |
| Now Playing menu bar module / Control Center modules | Playback transport (play/pause, skip) renders as **borderless/plain glyph buttons** in a compact strip — no filled capsule. `ControlWidgetButton`/`ControlWidgetToggle` (WidgetKit) are the actual API Apple ships for Control Center–shaped primary actions elsewhere in the system, confirming the "toggle/button as a compact glyph, not a pill" idiom is a real, first-party pattern for exactly this class of surface — but this is a **separate extension point** (a Control Widget extension target), not something embeddable inside a `MenuBarExtra` scene, so it's precedent, not a directly reusable API for this app. | `ControlWidgetButton`/`ControlWidgetToggle` confirmed via `mcp__xcode__DocumentationSearch` ("Controls: Setup and configuration", `/documentation/WidgetKit/Controls-Collection#Setup-and-configuration`). Visual description of Now Playing/Control Center from memory of OS behavior, not screenshotted. |
| Podcasts/Music mini players | Transport controls are small glyph-only buttons (play/pause as a filled circle glyph, not a bordered/prominent button style) inside a compact bar. | Description from memory of OS behavior; not documentation-verified this session. |
| Shazam menu bar app | Single circular Shazam-glyph button; no list is involved (it's a single-purpose menu bar item, not a panel with a list + separate action). Least directly comparable of the surfaces checked. | Description from memory; not documentation- or screenshot-verified this session. |
| Time Machine / Wi-Fi menu bar extras | Present a **list of rows** (backup destinations; Wi-Fi networks) where **selecting a row performs the action** (join that network) rather than populating a separate "Connect" button elsewhere in the menu. No filled/tinted button anywhere in either menu. | Description from memory of long-standing, stable OS behavior; this is the strongest first-party precedent for Q4 ("does the action live in the row") but I could not find an Apple HIG or API document that states this design rule explicitly — flagged again under "What I could not verify." |
| System recording/capture-in-progress indicator | **Not a button at all.** A single small colored dot rendered next to the Control Center icon in the menu bar: orange = microphone in use, green = camera in use, purple = system audio being recorded; only one dot shows at a time even if multiple are active. | [MacRumors: "macOS Monterey: What Does a Green or Orange Dot in the Menu Bar Mean?"](https://www.macrumors.com/how-to/menu-bar-dot-explanation/); this is Apple's own system-level privacy-indicator feature, not a public API third-party apps can draw into — see Q5 below. |

The consistent shape across every verified/well-attested surface: **no full-width tinted capsule anywhere.** Every primary "start/stop" affordance in first-party macOS surfaces is either a small circular glyph button, a borderless/plain transport glyph, or — where a list is already the whole UI (Wi-Fi, Time Machine) — the row itself.

**Directly relevant to AppTape's specific situation**, since its rows are now confirmed to paint a real, moving amplitude waveform as a background (Core Audio taps, per-app isolated): the Now Playing module and Control Center's media card both already solve "small monochrome control glyph legible over a busy, colorful, *moving* background" — album artwork there is not static wallpaper, it can be animated (Apple Music's animated covers) and is always arbitrary color content the system doesn't control. Apple's own solution, as long observed on macOS/iOS, is not to make the transport glyphs bigger or more colorful to compete — it's a **scrim/material treatment behind the control layer**, keeping the glyphs small, monochrome (white/template), and legible regardless of what's animating underneath. I could not find an Apple document that names this technique explicitly for Now Playing (flagged below), but the mechanism it implies is a stable, well-documented SwiftUI primitive — `ShapeStyle`'s `Material` cases (`SwiftUICore.swiftinterface:7987-7992`, struct `@available(iOS 15.0, macOS 12.0, ...)`; `.regularMaterial`/`.thinMaterial`/`.ultraThinMaterial`/etc. at `L7995-8008`, same `macOS 12.0+` window) — see Q4/Q6 for how this applies directly to AppTape's waveform rows.

## 2. What the HIG actually says

**Prominence and when a filled/tinted button is warranted.** The HIG does not forbid a tinted primary button; it constrains it:

> "In general, use a button that has a prominent visual style for the most likely action in a view. To draw people's attention to a specific button, use a prominent button style so the system can apply an accent color to the button's background... Keep the number of prominent buttons to one or two per view."
> — [Buttons: Style](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)

> "**Use style — not size — to visually distinguish the preferred choice among multiple options.** When you use buttons of the same size to offer two or more options, you signal that the options form a coherent set of choices. By contrast, placing two buttons of different sizes near each other can make the interface look confusing and inconsistent."
> — same page

This second quote is the most directly diagnostic sentence found in this whole research pass: it says the *size* mismatch — a `.controlSize(.large)` capsule sitting over/under a list of `.regular`-sized rows — is itself a documented anti-pattern, independent of whether tint is used at all.

**Color, sparingly.** From the Liquid Glass–era color guidance:

> "Apply color sparingly to the Liquid Glass material, and to symbols or text on the material. If you apply color, reserve it for elements that truly benefit from emphasis, such as status indicators or primary actions. To emphasize primary actions, apply color to the background rather than to symbols or text... Refrain from adding color to the background of multiple controls."
> — [Color: Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color)

This licenses tinting *one* primary action's background — it does not forbid what the prototype did. Combined with the "style, not size" rule above, the HIG reading is: a small, single, content-hugging tinted control is fine; a large, full-width one is what it warns against.

**Buttons inside popovers/menus.** The HIG's menu-bar-extra-specific guidance is the single most load-bearing citation for this whole document, because it questions the container, not just the button:

> "**Display a menu — not a popover — when people click your menu bar extra.** Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a [Popovers]."
> — [The menu bar: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)

AppTape's `.menuBarExtraStyle(.window)` produces a borderless floating panel that is popover-*shaped* even though it is technically a SwiftUI `Scene`, not an `NSPopover`. I cannot claim the HIG's popover rule applies verbatim to `.window`-style `MenuBarExtra` — Apple's own SwiftUI sample code uses exactly this pattern (`MenuBarExtra(..., isInserted:) { List { ... } }` per the SwiftUI "Building and customizing the menu bar" material referenced by `DocumentationSearch`), so `.window` style is clearly sanctioned for "functionality too complex for a menu." What the quote *does* support is treating the panel's content with popover discipline generally — see [Popovers: Best practices](https://developer.apple.com/design/human-interface-guidelines/popovers#Best-practices): "Use a popover to expose a small amount of information or functionality," "Avoid making a popover too big." A full-width, large, standalone CTA button reads as importing a sheet/full-screen mobile pattern into a surface the HIG wants kept small and list-like.

**Red and destructive actions.** The HIG does explicitly reserve red for destructive/warning semantics:

> "The system can display a destructive menu item using a red text color."
> — [Context menus: Best practices](https://developer.apple.com/design/human-interface-guidelines/context-menus#Best-practices)

> "Menus use red text to highlight actions that you identify as potentially destructive."
> — [Pull-down buttons: Best practices](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons#Best-practices)

> "A destructive button... uses the system red color."
> — [Buttons: Role](https://developer.apple.com/design/human-interface-guidelines/buttons#Role)

None of these say "don't use red for a record indicator" — a persistent record dot is a *status* signal, not a *destructive-action* label, and Apple's own system privacy indicator uses purple/orange/green dots for exactly that status-signal purpose (Q1/Q5), not red. But it does mean a **permanently red** record glyph (red even at rest, not just while recording) risks reading as "this will destroy something" by the system's own color grammar. The fix used in Alternatives A/C below is to keep the glyph a neutral/secondary color at rest and apply red only while a Recording is actually in progress — mirroring the "only one indicator dot, only while active" system pattern.

**Full-width buttons: not found as an explicit macOS rule, but circumstantial API evidence points the same way.** I searched specifically for HIG text stating whether a full-width button is or isn't idiomatic on macOS and found none — this is a genuine gap (see "What I could not verify"). What I did find, from the SDK rather than the HIG: SwiftUI didn't ship a way to explicitly request a stretched-to-fill button until macOS 26.0's `ButtonSizing` (`SwiftUICore.swiftinterface:4316`, `@available(iOS 26.0, macOS 26.0, ...)`), with cases `.automatic`, `.flexible`, and `.fitted`. The existence of an explicit opt-in `.flexible` case, with `.fitted`/`.automatic` as siblings, is consistent with "content-hugging is the platform default and full-width must be requested" — but Apple's own doc stub for `ButtonSizing` and its cases carries no discussion text beyond the one-line type/case description, so I'm stating this as an inference from the shape of the API, not a documented rule. Separately, `NSButton.BezelStyle` on AppKit exposes a `flexiblePush` variant whose *entire* purpose is variable **height** for multi-line text — the HIG text for it never mentions width-stretching: "Use this style of button when you need to accommodate tall or variable height content" ([NSButton.BezelStyle.flexiblePush](https://developer.apple.com/documentation/AppKit/NSButton/BezelStyle-swift.enum/flexiblePush)). Nowhere in AppKit or SwiftUI button documentation did I find a "stretch to container width" pattern presented as an idiomatic default — full-width buttons appear to be, as the research question suspected, an iOS-shaped import.

**Primary action via role, concretely.** The HIG's own vocabulary for "the button people are most likely to choose" is not `ButtonRole` (whose actual SwiftUI cases are `.destructive`, `.cancel`, `.confirm`, `.close` — see Q3) but a *design* role called **Primary**:

> "**Primary.** The button is the default button — the button people are most likely to choose... A button's role can have additional effects on its appearance. For example, a primary button uses an app's accent color, whereas a destructive button uses the system red color... **Assign the primary role to the button people are most likely to choose.** When a primary button responds to the Return key, it makes it easy for people to quickly confirm their choice."
> — [Buttons: Role](https://developer.apple.com/design/human-interface-guidelines/buttons#Role)

The SwiftUI mechanism that actually implements this "primary/default button, Return-key-bound, system-colored" concept is `KeyboardShortcut.defaultAction`, covered under Q3/Alternative B — not a manually chosen `.borderedProminent`/`.glassProminent` style. That's a real gap between HIG vocabulary (a "Primary" role) and the `ButtonRole` enum (no `.primary` case exists in the SDK — confirmed by grep, see Q3) worth knowing before reaching for role-based styling to solve this.

## 3. The API menu, ranked

Every entry below is grepped directly from the macOS 27.0 SDK `.swiftinterface` files; availability is quoted verbatim. None of the styles below are new to macOS 27 — everything either predates Liquid Glass or shipped with it in macOS 26.

**Button styles** (`SwiftUI.framework/.../arm64e-apple-macos.swiftinterface`):

| Style | Declaration | Availability |
|---|---|---|
| `.plain` | `L11250-11253`, `extension PrimitiveButtonStyle where Self == PlainButtonStyle` | `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)` |
| `.borderless` | `L1724-1727` | `@available(iOS 13.0, macOS 10.15, tvOS 17.0, watchOS 8.0, *)` |
| `.bordered` | `L22489-22492` | `@available(iOS 15.0, macOS 10.15, tvOS 13.0, watchOS 7.0, *)` |
| `.borderedProminent` | `L28158-28161` | `@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)` |
| `.glass` | `L1469-1474` | `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)`, `visionOS unavailable` |
| `.glass(_:)` (configurable, takes a `Glass`) | `L1476` | same struct-level `26.0` availability; the `Glass.tint(_:)` case (`SwiftUICore.swiftinterface:7245-7259`, `@available(iOS 26.0, macOS 26.0, ...)`) is what a custom-tinted glass button would use |
| `.glassProminent` | `L4455-4459` | `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)`, `visionOS unavailable` — this is what the rejected prototype used |
| `.accessoryBar` | `L11974-11980` | `@available(macOS 14.0, *)`, **`iOS/tvOS/watchOS unavailable`** — a genuinely macOS-only style |
| `.accessoryBarAction` | `L12013-12019` | `@available(macOS 14.0, *)`, **`iOS/tvOS/watchOS unavailable`** |
| `.card` | `L23590-23625` | `@available(tvOS 14.0, *)`, **`macOS unavailable`** — not usable here at all, listed only because it's easy to confuse with a "card-shaped" idea |

`AccessoryBarButtonStyle`/`AccessoryBarActionButtonStyle` are documented (`mcp__xcode__DocumentationSearch`, `/documentation/SwiftUI/PrimitiveButtonStyle/accessoryBar` and `.../accessoryBarAction`) as: `accessoryBar` — "typically used in the context of an accessory toolbar (sometimes referred to as a 'scope bar'), for buttons that narrow the focus of a search or other operation... the default button style for views in accessory toolbars, created with `ToolbarItemPlacement.init(id:_)`, and for searchable scopes"; `accessoryBarAction` — "for extra actions in an accessory toolbar... like adding or editing filters." Both also affect `Toggle`/`Picker`/`Menu` instances styled the same way. Neither is documented as a "primary CTA" style — their designed job is narrow-focus/secondary actions in a compact strip — which is why Alternative D (below) ranks below the row-native and default-action options despite being the most visually restrained API in the whole list.

**Control size** (`SwiftUICore.swiftinterface:7771-7789`): `ControlSize` is `CaseIterable`/`Sendable`, `@available(iOS 15.0, macOS 10.15, ...)`, cases `.mini`, `.small`, `.regular` (always available), `.large` (`@available(macOS 11.0, *)`), `.extraLarge` (`@available(iOS 17.0, macOS 14.0, ...)`). `ControlSize : Comparable` conformance is `@available(..., macOS 26.0, ...)` — genuinely 26-new, letting code compare sizes (`if controlSize < .large`) but not affecting the styling question directly.

**`.tint(_:)` vs. a prominent style.** `.tint(_:)` on a `.bordered` button recolors the *border/fill accent* without adopting the heavier prominent silhouette; on a `.glass(_:)` button, tinting goes through `Glass.tint(_:)` (`SwiftUICore.swiftinterface:7250`) instead of the view-level `.tint(_:)` modifier. Practically: `.bordered` + `.tint(.red)` gives a small, red-accented, non-full-bleed control — closer to what a "this row is recording" glyph should look like than `.glassProminent`'s heavier fill.

**`ButtonRole` — the full enum, grepped** (`SwiftUI.swiftinterface:12057-12063`):
```swift
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 9.0, *)
public struct ButtonRole : Swift.Equatable, Swift.Sendable {
  public static let destructive: SwiftUI.ButtonRole
  public static let cancel: SwiftUI.ButtonRole
  @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
  public static let confirm: SwiftUI.ButtonRole
  @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
  public static let close: SwiftUI.ButtonRole
}
```
So yes — **`.confirm` and `.close` are real, and both are macOS-26-new**, not 27-new. There is still no `.primary` role (see the HIG-vs-API gap noted in Q2) and nothing role-wise for "record/start" specifically. Per Apple's own `Button` documentation (`DocumentationSearch`, `/documentation/SwiftUI/Button#Assigning-a-role`): "The system uses the button's role to style the button appropriately in every context. For example, a destructive button in a contextual menu appears with a red foreground color." `.confirm`/`.close` visual mapping on macOS specifically wasn't stated beyond that generic sentence — flagged under "could not verify."

**Symbol-only circular buttons / `ButtonBorderShape`** (`SwiftUI.swiftinterface:19692-19710`): `.automatic` (always), `.capsule` (`@available(macOS 14.0, tvOS 17.0, *)`), `.roundedRectangle`/`.roundedRectangle(radius:)` (roundedRectangle base case always available, the `radius:` overload `macOS 14.0+`), **`.circle`** (`@available(iOS 17.0, macOS 14.0, tvOS 16.4, watchOS 10.0, *)`). `.buttonBorderShape(.circle)` on a `.bordered`/`.glass` button, at `.controlSize(.regular)` or `.small`, is the direct SwiftUI route to a small round icon button matching the Voice-Memos/capture-bar precedent from Q1 — none of it is macOS-27-new.

**`.contentTransition(.symbolEffect(...))` and live-record symbol effects** — all from `Symbols.framework/.../arm64e-apple-macos.swiftinterface`, none 27-new:
- `.replace` (content-transition swap, e.g. `record.circle` ↔ `stop.circle.fill`): `L220-229`, `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)`.
- `.pulse` (discrete/indefinite effect, good for "recording is live"): `L21-24`, `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)`.
- `.breathe`: `L362-368`, `@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)`.
- `.variableColor`: `L81-84`, same `14.0` family. `.bounce`: `L48-51`, same `14.0` family.
- The generic modifiers themselves — `View.symbolEffect(_:options:isActive:)` and `ContentTransition.symbolEffect(_:options:)` — live in `SwiftUICore.swiftinterface:16513` and `16735` respectively, both under the umbrella `@available(iOS 17.0, macOS 14.0, ...)` window for the symbol-effects feature as a whole.

**Hover-revealed row actions.** I found no macOS-specific, documented "hover reveals a button in this `List` row" API or HIG idiom distinct from what iOS calls swipe actions — SwiftUI's `swipeActions(...)` family is the searchable/relevant modifier, but nothing in the swiftinterface or `DocumentationSearch` results ties it to a *hover* (pointer-only, no swipe gesture) trigger on macOS specifically. This is a real gap; see "What I could not verify."

**`.keyboardShortcut`/default-action button.** `KeyboardShortcut` itself: `SwiftUI.swiftinterface:27386-27389`, `@available(iOS 14.0, macOS 11.0, *)`. `.defaultAction`: `L27399`, inherits the struct's `macOS 11.0+` availability — an old, stable API, not new to 26 or 27. Apple's own doc for it (`DocumentationSearch`, `/documentation/SwiftUI/KeyboardShortcut/defaultAction`): "The standard keyboard shortcut for the default button, consisting of the Return (↩) key and no modifiers... **On macOS, the default button is designated with special coloration.** If more than one control is assigned this shortcut, only the first one is emphasized." This is the literal, first-party API for "mark this as the primary/preferred action" on macOS, independent of button style or control size — see Alternative B.

## 4. The "action lives in the row" question

**Answer: yes, the affordance belongs in the row — but in a fixed, protected lane that the waveform background is never allowed to draw into, not floated directly on top of the freely-animating fill.** This is the load-bearing question for the current prototype (rows already paint a live, per-Source amplitude waveform as background), so the reasoning is laid out in full below rather than just asserted.

**Row-as-action precedent.** Wi-Fi and Time Machine menu-bar extras both present a flat list of destinations/networks where clicking a row *is* the action (join, mount) — there is no separate "Connect" button elsewhere in the menu that a row merely arms. I could not find this stated as a design rule anywhere in the HIG (searched "menu bar extras," "lists and tables," "selection and input," "menus") — it's inference from long-standing, widely-observed OS behavior, not a documented pattern, so treat it as **plausible precedent, not confirmed guidance**. What "selected" vs. "acted upon" looks like in that precedent: there generally isn't a separate *selected* state at all — highlighting on hover/keyboard-focus is the only intermediate state, and a click commits directly. That maps cleanly onto AppTape if starting a Recording is treated as cheap/reversible (consistent with the domain model — Trim/Export happen later, as separate, undoable steps), the same way joining a Wi-Fi network is a one-click, reversible action.

**Why a separate zone (a button below/beside the list) is the weaker answer now.** Before the waveform-background detail, "put a small control below the list" (Alternative B/D) was a defensible fallback because it doesn't have to fight for space or contrast against anything. Now that every row already carries motion and color, moving the record affordance *out* of the row creates a worse problem than it solves: the person's eye is on the row (that's where the amplitude motion draws attention), and a control living in a different zone of the panel asks them to look away from the thing that just told them "this is the app making noise" to find the control that acts on it. Keeping the affordance in the row keeps the locus of attention and the locus of action the same place — which is the actual reason Wi-Fi/Time-Machine rows work as single-click targets: the row *is* the option, so acting where you're already looking is the natural gesture, not a shortcut around something.

**How to keep the affordance from fighting the waveform, concretely.** Two complementary techniques, both inferred/engineering judgment rather than documented Apple rules:

1. **Reserve a lane the waveform drawing never enters.** Inset the waveform's rendering region so it stops short of a fixed trailing width (e.g. the last ~32–36pt of the row), the same way a standard `List` row keeps trailing accessories (a checkmark, a chevron, an SF Symbol accessory) outside of any custom row-background content — the accessory lane is structurally exempt from whatever the row draws, rather than being drawn *over*. This is the more robust of the two techniques because it guarantees contrast by construction: the record glyph is never actually composited against arbitrary waveform color/opacity, in any theme, at any amplitude.
2. **Back the glyph with a `Material` puck as a second line of defense** — e.g. `Circle().fill(.thinMaterial)` behind the glyph (`Material`, `SwiftUICore.swiftinterface:7987`, `@available(iOS 15.0, macOS 12.0, ...)`; case statics at `L7995-8008`, same availability — a decade-old, stable API, not new to 26/27). This is the same mechanism implied by Now Playing's glyph-over-album-art treatment (Q1) and covers the edges the inset lane doesn't — hover/hit-target affordance, a crisper separation when the waveform amplitude briefly spikes near the lane boundary, and consistent legibility across light/dark and the selected-row highlight color.

Combining both means the glyph's contrast never depends on what the waveform happens to be doing at that instant — which is the actual, concrete version of "sit on top of a moving, tinted background without fighting it." See Alternative A in Q6 for the code shape.

The remaining state question — once a Source is being recorded, the list needs to show which row is "hot" and let a second click on that *same* row mean "stop" rather than "start a second, concurrent recording" — is handled by the same state-aware glyph (idle vs. recording) rather than by removing click-to-act on the row; see Alternative A.

## 5. The record-state problem

No API found for tinting or animating a `MenuBarExtra`'s label as a distinct capability. Grepping `MenuBarExtra` across `SwiftUI.swiftinterface` (`L2092-2230`, `L5952-5980`, `L21384-21420`, `L21753-21790`) turns up: the `MenuBarExtra<Label, Content>` scene type itself (`@available(macOS 13.0, *)`), plain `Text`/`Label<Text, Image>`/`ImageResource` label initializers (`macOS 13.0`–`14.0`), and three `MenuBarExtraStyle`s — `.window` (`L5952-5980`, `@available(macOS 13.0, *)`), `.menu` (`PullDownMenuBarExtraStyle`, `L8055-8090`, `@available` not fully captured but co-located with the 13.0-era styles), and `.automatic` (`L21384-21420`). None of these expose a tint, badge, or animation hook — the label is just whatever `View` you hand it (`Text`, `Label`, `Image`), and per the HIG's own menu-bar-extras guidance quoted in Q1/Q2, **the system treats that content as a template image regardless**: "Both interface icons and symbols use black and clear colors to define their shapes; the system can apply other colors to the black areas in each image so it looks good on both dark and light menu bars, and when your menu bar extra is selected" ([The menu bar: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)). That sentence is a real constraint: it means AppTape's menu bar glyph can't reliably carry a persistent custom color (e.g., staying red while recording) the way the system's own privacy dot does — the system dot is drawn by the OS itself, next to the Control Center icon, not by the third-party app whose mic/camera/system-audio is active, and there is no public API surfaced in this SDK for a third-party `MenuBarExtra` to opt into that same chrome.

Practical options within the actual API surface, in order of how well-attested they are:
1. **Swap the icon glyph itself** between an idle and a recording variant (e.g. `systemImage: "waveform"` idle → `systemImage: "record.circle.fill"` recording) via the `isInserted`/state-driven `MenuBarExtra` label closure — fully supported by the plain `Label`/`systemImage` initializers already covered above, no special API needed, but still subject to the template-image monochrome treatment the HIG describes.
2. **Animate the glyph** with `.symbolEffect(.pulse, isActive:)` (macOS 14.0+, cited in Q3) while recording — SwiftUI does document `symbolEffect` as usable on menu-bar-hosted content in general, though I found no example specifically inside a `MenuBarExtra` label to confirm the animation actually plays in the real menu bar chrome (versus being suppressed like custom color might be) — flagged under "could not verify."
3. **Don't try to replicate the system's colored-dot chrome.** That's OS-owned UI for its own privacy subsystem, not a documented extension point for third-party menu bar items.

## 6. Concrete recommendation, ranked

All five are real APIs at their stated availability; none require anything newer than macOS 26, and most predate Liquid Glass entirely.

**A. (Ship this) The row is the action; a small stateful glyph in a protected trailing lane is the only affordance — no separate button, and the lane is structurally exempt from the row's own waveform background.**

```swift
List(runningApps) { app in
    Button {
        recordingController.toggle(app)          // click = start; click again on the
    } label: {                                     // active row = stop
        HStack(spacing: 8) {
            SourceRow(app: app)                    // background: live amplitude waveform,
                                                     // inset to stop short of the trailing lane
            Spacer(minLength: 0)

            Image(systemName: recordingController.isRecording(app)
                  ? "record.circle.fill" : "circle")
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(recordingController.isRecording(app) ? .red : .secondary)
                .symbolEffect(.pulse, options: .repeating,
                              isActive: recordingController.isRecording(app))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: Circle())   // 2nd line of defense: legible
                .padding(.trailing, 6)                       // regardless of waveform state
        }
    }
    .buttonStyle(.plain)   // row keeps normal list-row appearance, not a bordered button
}
```
Rationale: matches the Wi-Fi/Time-Machine row-is-the-action precedent (Q4), needs zero additional panel real estate, and keeps red reserved for the live/recording moment only — satisfying the HIG's destructive-red concern (Q2) by construction rather than by discipline. The trailing lane is reserved by layout (the waveform's own drawing is inset to stop before it, per Q4) rather than by z-order, so the glyph's contrast never depends on the waveform's instantaneous color/amplitude; the `.thinMaterial` circle (`macOS 12.0+`, Q1) is the belt-and-suspenders fallback for hover/highlight states. `.symbolEffect(.pulse)`/`.contentTransition(.symbolEffect(.replace))` are both macOS 14.0+ (Q3). Biggest honest caveat: I could not find a documented HIG rule validating one-click-commits-immediately for a *recording* action specifically (only inferred from Wi-Fi/Time Machine's observed behavior), so usability-test the "click a row and it just starts recording" gesture before shipping — a `.help()` tooltip and/or a first-run affordance may be warranted.

**B. `.keyboardShortcut(.defaultAction)` on a normally-sized bordered button — the literal "primary action" API.**

```swift
Button {
    recordingController.toggle(selectedSource)
} label: {
    Label(recordingController.isRecording ? "Stop Recording" : "Start Recording",
          systemImage: recordingController.isRecording ? "stop.circle.fill" : "record.circle")
        .contentTransition(.symbolEffect(.replace))
}
.buttonStyle(.bordered)            // NOT .glassProminent / .borderedProminent
.controlSize(.regular)             // NOT .large; content-hugging, not full-width
.keyboardShortcut(.defaultAction)  // macOS 11.0+ — Return key + system-drawn "default button" coloration
```
Rationale: this is what the HIG's "Primary" role (Q2) actually maps to on macOS — a Return-key-bound, system-colored default button, sized like every other control, not a manually chosen accent capsule. `KeyboardShortcut.defaultAction` is a decade-old, stable API (macOS 11.0+), so this is close to "as native as it gets." Good as the fallback control before any Source is selected, or paired with A as a keyboard-reachable equivalent of the row click.

**C. A circular `Toggle` styled `.button`, tinted only while on.**

```swift
Toggle(isOn: $recordingController.isRecording) {
    Label("Record", systemImage: "record.circle")
}
.toggleStyle(.button)              // macOS 12.0+
.buttonBorderShape(.circle)        // macOS 14.0+
.controlSize(.regular)
.tint(.red)
.labelStyle(.iconOnly)
.contentTransition(.symbolEffect(.replace))
```
Rationale: `ToggleStyle.button`'s own documentation states the mechanism directly — "The button indicates the `on` state by filling in the background with its tint color" (`DocumentationSearch`, `/documentation/SwiftUI/ToggleStyle/button`) — which is a first-party, off/on-native way to get exactly the "same control becomes Stop" behavior Q5 asks for, without hand-rolling role-swapping logic. Circular + regular-sized keeps it closer to Voice Memos' small red control than to a stretched pill. Ranked below A/B because on its own it still doesn't communicate *which* Source is being recorded — it wants to be paired with row selection, which makes it partly redundant with A unless used as a single global control.

**D. `.accessoryBar`/`.accessoryBarAction` — the flattest, most restrained macOS-only style — for a secondary Stop/settings strip, not the primary action.**

```swift
HStack {
    Button("Record", systemImage: "record.circle", action: start)
    Spacer()
    Button("Settings", systemImage: "gearshape", action: openSettings)
}
.buttonStyle(.accessoryBarAction)   // macOS 14.0+, iOS/tvOS/watchOS unavailable
```
Rationale: genuinely macOS-only (Q3), visually the opposite of a filled capsule — no border, no fill at rest. But its documented purpose is "extra actions... like adding or editing filters" / "narrow the focus of a search" in an accessory toolbar (scope bar), not carrying a sole primary CTA — using it for "the" record action stretches past its designed intent, so it's ranked below A–C for that role, while remaining a good fit for a persistent Stop/settings strip once a Recording is already running.

**E. (Not recommended, but the minimal fix to the literal complaint) Keep `.glassProminent`, shrink it, and stop stretching it.**

```swift
Button("Record", systemImage: "record.circle", action: start)
    .buttonStyle(.glassProminent)   // macOS 26.0+
    .controlSize(.small)            // not .large
    .fixedSize()                    // don't stretch to fill row/panel width
```
Rationale: technically HIG-compliant — the "Color: Liquid Glass color" quote (Q2) explicitly sanctions a tinted background for the one primary action, and shrinking + `.fixedSize()` fixes the "style, not size" violation directly. Ranked last anyway because it keeps the "isolated colored pill sitting apart from the list" silhouette the designer already reacted against on sight, just at a smaller scale — the row-native and default-action options above integrate the affordance into the panel instead of placing a discrete colored object next to it.

## What I could not verify

- **Whether a `.window`-style `MenuBarExtra` is governed by the HIG's popover rules verbatim.** It is popover-*shaped* (borderless floating panel) but is a SwiftUI `Scene`, not a literal `NSPopover`, and Apple's own sample material uses `.window` with list content — so the "avoid popovers for menu bar extras" quote (Q2) is suggestive, not a confirmed direct rule for this exact case.
- **Whether `.confirm`/`.close` `ButtonRole` cases (macOS 26.0+) have any distinct visual mapping on macOS specifically**, beyond the generic "the system styles the button appropriately... e.g. a destructive button appears with red foreground" sentence in the `Button` documentation. No macOS-specific example or screenshot found for these two roles.
- **Whether `.symbolEffect(.pulse, isActive:)` actually animates when applied inside a live `MenuBarExtra` label**, versus being suppressed the way custom color apparently is per the HIG's template-image guidance. No first-party example or third-party report found confirming this either way — would need an on-device prototype spike to settle (this repo's `prototype/source-picker` and `research/waveform-rows` branches, both currently in use by other sessions, may end up touching this same question).
- **Any HIG sentence explicitly addressing full-width buttons on macOS**, pro or con. Absence inferred circumstantially from `ButtonSizing`'s macOS-26 `.flexible`/`.fitted`/`.automatic` cases and from `NSButton.BezelStyle.flexiblePush`'s height-only (not width) framing — not a documented rule.
- **Whether Apple explicitly documents "click a row = commit the action" as a menu-bar-extra or list design pattern anywhere.** Everything in Q4 is inferred from stable, widely-observed Wi-Fi/Time-Machine menu behavior, not from an HIG page or API doc that states the rule.
- **Whether Now Playing/Control Center's transport-glyph-over-album-art actually uses a `Material`-style scrim specifically**, versus a plain dimming gradient, a fixed-opacity overlay, or something else entirely. The visual effect (small monochrome control staying legible over arbitrary, moving artwork) is confidently remembered; the exact implementation technique is not documentation-confirmed — `Material` is offered in Q1/Q4/Alternative A as the concrete, available SwiftUI mechanism that would produce a comparable effect, not as a claim about what Apple's own (non-SwiftUI, system-owned) Now Playing UI literally uses under the hood.
- **Real-time performance/visual correctness of a `Material`-backed circle sitting over a per-frame-updating `Canvas`/`TimelineView`-driven waveform**, specifically — i.e. whether the material's blur/vibrancy sampling looks right against fast-changing custom-drawn content at typical list-row scale. Not tested; this is exactly the kind of thing worth spiking in `prototype/source-picker` before committing to the material-puck half of Alternative A (the inset-lane half does not have this risk, since it never composites the two layers at all).
- **Live screenshots of Voice Memos, the Podcasts/Music mini player, the Now Playing module, Control Center transport controls, or the Shazam menu bar app for macOS 27 specifically.** All described from memory of long-standing, stable OS behavior and corroborated where possible with third-party how-to sources (cited inline); none were captured or confirmed against the actual installed OS this session. This tool session has no general screenshot/UI-inspection capability for arbitrary running macOS apps, only for building/previewing this repo's own Xcode project.
- **Whether SwiftUI's `swipeActions` family has any macOS hover-triggered equivalent.** No such API or HIG page found; flagged as a real gap rather than confirmed absent.
- Did not build or run any code against this SDK — this is a documentation/header-research ticket, matching the scope of `docs/research/capture-api.md`. The ranked recommendations in Q6 are real, available APIs but untested in AppTape's actual panel; the parent task plans to prototype the top two.

## Sources

- SDK `.swiftinterface` files, macOS 27.0 SDK at `/Applications/Xcode-beta.app/.../MacOSX.sdk`:
  - `System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
  - `System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`
  - `System/Library/Frameworks/Symbols.framework/Versions/A/Modules/Symbols.swiftmodule/arm64e-apple-macos.swiftinterface`
- Apple Developer Documentation (via `mcp__xcode__DocumentationSearch`): `PrimitiveButtonStyle`, `AccessoryBarButtonStyle`, `AccessoryBarActionButtonStyle`, `ButtonToggleStyle`/`ToggleStyle.button`, `ButtonSizing`, `Button` ("Assigning a role", "Styling buttons"), `KeyboardShortcut.defaultAction`, `NSButton.BezelStyle.accessoryBar`/`.accessoryBarAction`/`.flexiblePush`, `ControlWidgetButton`/`ControlWidgetToggle` (WidgetKit), "Configuring a multiplatform app target" (MenuBarExtra sample).
- Human Interface Guidelines (via `mcp__xcode__DocumentationSearch`, URLs also given inline above):
  - [Buttons: Style](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)
  - [Buttons: Role](https://developer.apple.com/design/human-interface-guidelines/buttons#Role)
  - [Buttons: Push buttons](https://developer.apple.com/design/human-interface-guidelines/buttons#Push-buttons)
  - [Color: Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color)
  - [The menu bar: Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)
  - [Popovers: Best practices](https://developer.apple.com/design/human-interface-guidelines/popovers#Best-practices)
  - [Context menus: Best practices](https://developer.apple.com/design/human-interface-guidelines/context-menus#Best-practices)
  - [Pull-down buttons: Best practices](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons#Best-practices)
- [Apple Support: "How to record the screen on Mac"](https://support.apple.com/en-us/102618)
- [Macworld: "How to take screenshots and record video on your Mac"](https://www.macworld.com/article/226469/how-to-take-screenshots-on-your-mac.html)
- [MacRumors: "macOS Monterey: What Does a Green or Orange Dot in the Menu Bar Mean?"](https://www.macrumors.com/how-to/menu-bar-dot-explanation/)
- [iDownloadBlog: "How to use Apple's Voice Memos app on Mac"](https://www.idownloadblog.com/2018/08/14/howto-voice-memos-mac/)
- This repo: `CONTEXT.md` (domain glossary — Source/Recording/Library terminology used throughout this document), `docs/research/capture-api.md` (fetched from `origin/research/capture-api` for tone/citation-density reference; not otherwise cited for content).
