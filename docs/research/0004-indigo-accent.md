# Rendering indigo as AppTape's `Signal` accent, in light and dark

Research for [#74](https://github.com/SamWongML/macos-audio-recording/issues/74) ("Decide AppTape's design language"), part of the map in [#70](https://github.com/SamWongML/macos-audio-recording/issues/70). AppTape has committed to **indigo** as its one non-system accent colour, named `Signal`, applied only to *content* — the waveform body and peak fills (the largest use: a big, saturated area fill across the detail pane, not a small accent dot), the Trim region, the playhead, and the selected rung in the export-preset list — never to chrome, which keeps following the user's own System Settings accent. This answers: what concrete indigo values best serve that role in both appearances, whether Apple's own `systemIndigo` is one of them, whether the values clear Apple's contrast floors, how a large saturated fill behaves differently from a small one, and how indigo separates from macOS system blue/purple and from AppTape's own amber (Runway warning), red (recording), and green (level meter) — under normal vision and under the three common colour-vision deficiencies.

## Method and sourcing

Primary sources consulted: Apple's HIG Color, Dark Mode, Materials, and Accessibility pages, plus the WWDC19 "Implementing Dark Mode on iOS" session. Apple's HIG site is client-rendered, so several pages were only retrievable in full via a text-extraction proxy (r.jina.ai) pointed at the real `developer.apple.com` URL — the proxy is a retrieval mechanism, not a source; every citation below points at the underlying Apple URL. Contrast ratios in §3 were computed from the WCAG relative-luminance formula (the method the WebAIM contrast checker also uses) and independently re-verified by hand for this report.

**Sourcing caveats, stated up front rather than buried:**

- **Apple does not publish numeric colour values for its system colours, and explicitly says not to hard-code them**: "Avoid hard-coding system color values in your app... The actual color values will fluctuate from release to release, based on a variety of environmental variables. Always use the API to apply system colors." — [Apple HIG, Color](https://developer.apple.com/design/human-interface-guidelines/color). Every hex/RGB figure below for `systemIndigo`, `systemBlue`, `systemPurple`, `systemOrange`, `systemRed`, `systemGreen`, and the macOS window-background semantic colours is therefore **third-party reverse-engineering** — resolving the live AppKit API and reading back the sRGB components it returns — not an Apple publication. Two independent extractions were cross-checked and agree exactly, but Apple is on record changing these values between releases (see §1), so treat every number here as *current, not guaranteed*.
- **No Display P3 component values were found anywhere** for any of these colours, from any source, primary or secondary — only sRGB. If AppTape's rendering pipeline is P3-aware, this is a real gap (see "what I could not verify").
- **No tool-verified, pixel-level colour-blindness simulation was obtained.** Attempts to run the actual hex values through a live simulator returned no extractable output (canvas-based, JS-only tools). §5b instead reasons from published CVD confusion-line literature and the Machado/Oliveira/Fernandes (2009) simulation model that most simulators implement — directionally sound, but not a rendered proof.
- **Two precedent claims are weak.** Reported dark-mode eyestrain complaints tied to Discord's 2021 "Blurple" brightening (§4, §6) is an aggregated secondary claim, not one clearly citable article. A widely-repeated claim that Linear splits its indigo into a duller large-fill token and a brighter highlight token (§6) could not be confirmed against any first-party Linear source and contradicted a third-party token-scrape — treat it as unverified community lore, not fact.

---

## 1. Concrete values: system indigo, or a custom pair?

Apple's own guidance (quoted above) rules out treating any published system-colour hex as a stable design commitment. The values below are the best available reverse-engineered numbers, cross-checked across two independent extractions that agree exactly:

| Colour | Light (hex / RGB) | Dark (hex / RGB) | Source |
|---|---|---|---|
| `systemIndigo` | `#5856D6` (88, 86, 214) | `#5E5CE6` (94, 92, 230) | [gist: andrejilderda](https://gist.github.com/andrejilderda/8677c565cddc969e6aae7df48622d47c), [sarunw.com](https://sarunw.com/posts/dark-color-cheat-sheet/) |
| `systemBlue` | `#007AFF` (0, 122, 255) | `#0A84FF` (10, 132, 255) | same two sources |
| `systemPurple` | `#AF52DE` (175, 82, 222) | `#BF5AF2` (191, 90, 242) | same two sources |
| `systemOrange` (AppTape's amber "Runway" family) | `#FF9500` (255, 149, 0) | `#FF9F0A` (255, 159, 10) | [sarunw.com](https://sarunw.com/posts/dark-color-cheat-sheet/) |
| `systemRed` (recording state) | `#FF3B30` (255, 59, 48) | `#FF453A` (255, 69, 58) | [sarunw.com](https://sarunw.com/posts/dark-color-cheat-sheet/) |
| `systemGreen` (level meter) | `#34C759` (52, 199, 89) | `#30D158` (48, 209, 88) | [sarunw.com](https://sarunw.com/posts/dark-color-cheat-sheet/) |

Apple has visibly revised indigo's exact value before: WWDC 2021 coverage of that year's system-colour refresh notes "Indigo and purple are now more consistent, and teal has been entirely redefined" — [Six Colors](https://sixcolors.com/post/2021/06/wwdc-2021-for-sf-symbols-cyan-is-the-new-teal/). Indigo is a living value Apple tunes for its own reasons, not a fixed public constant.

**`Color.indigo` / `Color(nsColor: .systemIndigo)` is already a dynamic, per-appearance colour** — SwiftUI resolves it at draw time, so "does it already switch" is not in question. The question is whether AppTape should pipe that system value straight through to `Signal`, or define its own two-stop dynamic colour. Three reasons favour a custom colour:

1. **Apple's own words say not to build on it as a stable design commitment.** A brand-defining, page-filling waveform is exactly the element an unannounced OS-level tweak (as already happened once, per Six Colors above) would visibly move.
2. **AppTape's collision constraints are narrower and harder than the ones `systemIndigo` was tuned for.** Apple's indigo is one interchangeable option among ~12 peer swatches in things like Reminders' list-colour picker (§6) — a small tag, never a 100%-coverage fill carrying the whole visual identity of the app's single strongest UI moment.
3. **A large fill and a small accent have different requirements** (§3, §4). §3 shows the stock dark value doesn't clear even the loosest HIG contrast floor against a plausible dark window background — fine for a non-text fill, but a reason not to reuse the same hex anywhere text-sized.

**Recommendation:** define `Signal` as an explicit two-stop (or more) dynamic colour AppTape owns in code — seeded from the `systemIndigo` values above so it still reads as "indigo," not invented from nothing — rather than forwarding `Color.indigo` directly. That leaves room to tune the dark-mode body-fill stop for the contrast/fatigue problem in §3–§4 while keeping a brighter, closer-to-stock value available for the peak fill, playhead, and selection highlight.

---

## 2. Why dark mode needs a different value

Apple's Dark Mode HIG page states plainly that this isn't mechanical inversion:

> "[Dark mode colors] aren't necessarily inversions of their light counterparts: while many colors are inverted, some are not." — [Apple HIG, Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)

> "If you display a content image that includes a white background, consider slightly darkening the image to prevent the background from glowing in the surrounding Dark Mode context." — same source

The same page frames the goal as legibility, not aesthetics: aim for "sufficient color contrast in all appearances," noting "dark text is less legible when it's on a dark background." WWDC19's dark-mode session makes the identical point about UI colour generally, not just text:

> "Dark mode is not just a simple inversion of light mode. It's more subtle than that." ... "The color can have a different value in Light Mode and in Dark Mode." — [WWDC19 session 214, "Implementing Dark Mode on iOS"](https://developer.apple.com/videos/play/wwdc2019/214/)

**The reasoning Apple actually gives is glow/legibility-based**, not a stated "always lighten and desaturate saturated hues" rule — that exact sentence does not appear in current HIG text (flagged below). What the shipped values themselves show is consistent with that folk rule anyway: dark `systemIndigo` (`#5E5CE6`) is measurably lighter than light `systemIndigo` (`#5856D6`) — Apple's own implementation lightens the hue for the dark appearance, even though the HIG prose only states the general legibility/glow principle, not the specific "lighten for dark" mechanism.

---

## 3. Contrast math

Apple's stated floors, confirmed via full-text fetch: **4.5:1** for text up to 17pt, **3:1** for 18pt+ and for bold text at any size — [Apple HIG, Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

Background values used (macOS semantic surfaces, reverse-engineered/secondary, cross-checked): `windowBackgroundColor` light `#ECECEC` (236,236,236) / dark `#323232` (50,50,50); `textBackgroundColor` light `#FFFFFF` / dark `#1E1E1E` (30,30,30) — [gist: andrejilderda](https://gist.github.com/andrejilderda/8677c565cddc969e6aae7df48622d47c).

Method: standard WCAG relative luminance — linearize each channel `((c+0.055)/1.055)^2.4`, then `L = 0.2126R + 0.7152G + 0.0722B`; ratio `= (L_lighter+0.05)/(L_darker+0.05)`. Recomputed independently for this report; figures match the research pass:

| Value | Computed luminance |
|---|---|
| Light indigo `#5856D6` | L ≈ 0.1359 |
| Dark indigo `#5E5CE6` | L ≈ 0.1576 |
| Light `windowBackgroundColor` `#ECECEC` | L ≈ 0.8390 |
| Light `textBackgroundColor` `#FFFFFF` | L = 1.0 |
| Dark `windowBackgroundColor` `#323232` | L ≈ 0.0319 |
| Dark `textBackgroundColor` `#1E1E1E` | L ≈ 0.0130 |

| Pairing | Ratio | Verdict |
|---|---|---|
| Light indigo on light `windowBackgroundColor` | **4.78:1** | Clears 4.5:1 (barely) |
| Light indigo on `textBackgroundColor` white | **5.65:1** | Clears 4.5:1 comfortably |
| Dark indigo on dark `windowBackgroundColor` | **2.53:1** | **Fails both 3:1 and 4.5:1** |
| Dark indigo on dark `textBackgroundColor` | **3.29:1** | Clears 3:1 (18pt/bold only); **fails 4.5:1** |

**This is the single most actionable number in this report.** Stock dark `systemIndigo`, against the lighter of the two plausible dark macOS surfaces (`windowBackgroundColor`), doesn't clear even the loosest 3:1 floor. Against the darkest plausible surface it scrapes past 3:1 but still fails 4.5:1.

**The distinction the brief asked to call out explicitly:** the waveform body is a large fill, not text, so the 4.5:1 text floor doesn't bind it directly — a big saturated shape at 2.53:1 or 3.29:1 against its surround can still read fine as a *shape*. But that same hex would visibly fail Apple's own floor if it were ever reused for anything text-sized in dark mode — a numeral, a small percentage label, a tooltip drawn in `Signal`. That argues against hard-coding one shared hex for every use: the large-fill value and any small-text use of the accent need to be allowed to diverge, which only a custom multi-stop colour (not one reused hex) can do. Note also, as a secondary/non-HIG data point: WCAG 2.1's Success Criterion 1.4.11 ("Non-text Contrast") sets a 3:1 floor for graphical objects required to understand content, a lens the waveform arguably falls under — the dark value clears that only against the darker of the two plausible surfaces, not the lighter one.

---

## 4. Large-area saturated fill: fatigue, vibration, halation

Apple's own materials guidance addresses this obliquely, through vibrancy rather than flat fills — which is exactly the gap AppTape sits in, since a 100%-opacity waveform body is not a vibrancy material:

> "When you use system-defined vibrant colors, you don't need to worry about colors seeming too dark, bright, saturated, or low contrast in different contexts." — [Apple HIG, Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

That is Apple naming the problem class (saturated colour reading wrong depending on context) and then solving it by *not* using flat colour — vibrancy dynamically blends against whatever material sits behind it. AppTape's flat waveform fill gets none of that protection for free. Apple's Color page separately counsels restraint at scale generally: "Apply color sparingly... Reserve coloring for elements truly needing emphasis" — [Apple HIG, Color](https://developer.apple.com/design/human-interface-guidelines/color).

Secondary colour-science sources name the actual mechanisms Apple doesn't spell out:

- **Simultaneous contrast / "colour vibration"**: "an optical phenomenon that occurs when two highly saturated, complementary [or strongly adjacent] colors are close to each other... the edge where they meet appears to blur, shake, or emit a strange 'glowing' distortion," mitigated by "separating areas of complementary colors with black, gray, or white outlines" and by "slightly lower saturation and higher lightness for accent colors in dark mode." — [UXmatters](https://www.uxmatters.com/mt/archives/2006/01/color-theory-for-digital-displays-a-quick-reference-part-ii.php), [CDGI](https://www.cdgi.com/2026/07/design-lesson-vibrating-color-theory/)
- **Halation**: "On dark backgrounds, your eyes adjust to lower ambient brightness. When a highly saturated color appears in that context, it seems much more intense by contrast... The color appears to 'glow' or bleed into the surrounding dark area." — same source cluster
- The underlying vision-science phenomenon (simultaneous colour contrast at saturated boundaries) has peer-reviewed backing, e.g. [Otazu et al., "Large enhancement of simultaneous color contrast by white flanking contours," PMC7674406](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7674406/) — this is a measurable perceptual effect, not just a design-blog opinion.
- **A shipped cautionary tale**: Discord's 2021 "Blurple" refresh brightened its indigo-blue brand colour (`#7289DA` → `#5865F2`); community/brand coverage around the rebrand reports the increased saturation causing eyestrain complaints against Discord's dark theme — [Discord's own blurple retrospective](https://discord.com/blog/happy-blurpthday-to-discord-a-place-for-everything-you-can-imagine) touches the rebrand, though a single authoritative citation for the eyestrain complaints specifically could not be pinned down (flagged as weak above).

**Practical read for AppTape's waveform body vs. peak fill**: the mitigations above line up with the split the brief already hypothesizes — a **duller, lower-saturation/lower-opacity indigo for the 100%-coverage body** (cuts vibration against surrounding chrome and halation against the dark canvas) with a **brighter, more saturated (or simply higher-alpha) indigo reserved for the peak fill, playhead, and Trim edges** — a saturation/lightness split, not a hue split; both stay unambiguously indigo.

---

## 5. Separability

### From macOS system blue and purple

Converting the §1 sRGB values to HSB:

| Colour | Hue | Saturation | Brightness |
|---|---|---|---|
| `systemBlue` `#007AFF` | 211.3° | 100% | 100% |
| `systemIndigo` `#5856D6` | 240.9° | 59.8% | 83.9% |
| `systemPurple` `#AF52DE` | 279.9° | 63.1% | 87.1% |

Indigo sits almost exactly midway between blue and purple (30° from each), and is much closer to purple than to blue in saturation and brightness — numerically confirming Six Colors' observation (§1) that Apple deliberately tuned indigo and purple to read as a consistent family. A user whose own System Settings accent is Blue or Purple will have that colour driving sidebar selection, focus rings, and standard controls at the same time AppTape's indigo fills the waveform. The 30° hue gap is enough to tell apart in a side-by-side swatch, but combined with near-matched saturation/brightness against purple (or the shared "blue-violet family" impression against blue), at a glance it risks reading as "the app reused my accent colour" rather than a deliberately distinct brand hue. AppTape's rule — indigo on content only, system accent on chrome only, never the same control — manages this operationally (the two colours never compete for the same pixel), but the hue itself is not maximally separable from a user's own blue/purple choice; that's a property of the rule doing the separating, not of the colour.

### Under colour-vision deficiency

Reasoned from published CVD confusion-line references — [Colour Blind Awareness](https://www.colourblindawareness.org/colour-blindness/types-of-colour-blindness/), [National Eye Institute](https://www.nei.nih.gov/eye-health-information/eye-conditions-and-diseases/color-blindness/types-color-vision-deficiency) — and the simulation model most CVD tools implement, [Machado, Oliveira & Fernandes (2009), IEEE TVCG 15(6)](https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html):

- **Protanopia**: documented confusions run "some blues with some reds, purples and dark pinks" and "dark brown with dark green, dark orange, dark red, dark blue/purple and black." Indigo and red share this cluster, so indigo-vs-red separability is *reduced but not gone* — indigo stays cool/blue-leaning while red desaturates toward brown/olive. Indigo vs. amber (`systemOrange`, warm orange-yellow) stays well separated; protanopia's confusion pairs run blue/purple/red/brown, not blue/orange.
- **Deuteranopia**: documented confusions include "light blues with lilac" and "blue-greens with grey," and the single most robustly documented cross-CVD confusion generally is blue-vs-purple itself — "a person with red-green color blindness will often describe a blue color as purple, and a purple color as blue" (NEI). Since indigo sits *between* blue and purple by construction (above), it's the worst-positioned hue for exactly this confusion — but that means indigo is more likely to blur into "some blue-purple thing" than into red or amber, which is the outcome that actually matters least, since AppTape has no other semantic blue or purple to collide with.
- **Tritanopia**: documented confusions include "dark purples with black," and blue/indigo/violet reportedly "appear greenish or black." This is the highest-risk case for AppTape's specific palette: if indigo shifts toward greenish under tritanopia it edges toward the level-meter's green, though the two occupy different UI regions (waveform vs. meter), which limits the practical risk to sequential misreading rather than simultaneous confusion on one screen.
- **Net assessment**: indigo vs. amber and indigo vs. red — the two collisions the brief explicitly rules out — hold up across all three CVD types, because amber and red sit clearly outside indigo's blue-violet family in every confusion-line model reviewed. The real residual risk is indigo losing definition *from itself* (blurring into blue/purple, marginally into green under tritanopia), which is a separate, lower-stakes problem than the one the brief was checking for.

No pixel-level simulation tool produced usable output during this research (see "what I could not verify"); the CVD analysis above is literature-grounded reasoning, not a rendered proof.

---

## 6. Precedent

**Discord — "Blurple" (`#5865F2`)** is the closest true precedent: a shipping macOS/iOS/web app with one committed, named accent nearly identical to Apple's `systemIndigo` (`#5865F2` vs. `#5856D6` — identical red channel, close green/blue) — [Discord brand page](https://discord.com/branding). Discord's own guidance is thin: it ships a lighter companion tone, "Light Blurple" `#E0E3FF`, for use on or near the colour, but doesn't publish a worked-out large-fill-vs-small-accent split or a fully specified light/dark dynamic pair on the brand page itself. The 2021 brightening of this exact colour is the cautionary tale in §4 — a real, shipped instance of a saturated indigo-family value drawing eyestrain complaints in dark mode (weakly sourced — see caveats).

**Linear** is widely cited in design blogs as splitting an indigo/violet brand colour (~`#5E6AD2`) into a duller large-fill token and a brighter interactive-highlight token — which would be a near-perfect match for §4's recommended split. This could **not** be confirmed: Linear's own engineering post about its UI redesign calls its brand colour "blue" without giving hex values or a light/dark split ([Linear, "How we redesigned the Linear UI"](https://linear.app/now/how-we-redesigned-the-linear-ui)), and a third-party design-token scrape returned a contradictory palette with no indigo/violet token at all. Treat the duller-fill/brighter-highlight Linear claim as plausible community lore, not verified fact.

**Apple's own first-party design language has no example of indigo used the way AppTape proposes** — as a single, permanent, large-area brand fill. What was confirmed instead: indigo is one of roughly twelve interchangeable named swatches in the system's multicolour palette (alongside red, orange, yellow, green, mint, teal, cyan, blue, purple, pink, brown), exposed as a peer, user-*selectable* option — e.g. Reminders' per-list colour picker offers "a choice of 12 colors" ([9to5Mac](https://9to5mac.com/2019/10/17/how-to-change-icons-colors-reminders-lists-iphone-ipad-and-mac/), [MacRumors](https://www.macrumors.com/how-to/customize-look-of-reminders-lists-ios/); no source found that names "Indigo" specifically among the twelve labels). Apple's own use treats indigo as one option a *user* picks per item, never as the one hue that defines an app's whole identity — a genuinely different role from AppTape's. Attempts to confirm indigo/purple-family branding for Reminders, Podcasts, TestFlight, or Playgrounds (candidates worth checking) did not pan out: Podcasts' icon reads closer to magenta/violet ("Heliotrope" `#D56DFB` / "Mystic Violet" `#B150E2` per a 2017-era palette extraction — [SchemeColor](https://www.schemecolor.com/apple-podcasts-app-icon-2017-colors.php), unverified against the current icon), TestFlight's icon reads as blue, and Focus's Do Not Disturb iconography is purple, not indigo. **None of Apple's own apps are a citable indigo-as-committed-accent precedent** — the real precedents are third-party, and both come with caveats (Discord: a cautionary tale as much as a model; Linear: unverified).

---

## Synthesis for the design-language decision (#74)

1. **Don't forward `Color.indigo` straight through as `Signal`.** Define a custom, explicit two-stop (or more) dynamic colour, seeded from the `systemIndigo` values (§1) so it still reads as indigo, because (a) Apple explicitly disclaims the stability of its own system-colour values, (b) AppTape's collision and large-fill requirements are narrower than what a 12-swatch peer-colour system was tuned for, and (c) a large fill and a small highlight have different needs that one fixed hex can't serve at once.
2. **The dark-mode value needs to move, and stock `systemIndigo` dark is a specific, measured failure to design away from.** §3's independently-verified math: dark `systemIndigo` (`#5E5CE6`) is 2.53:1 against `windowBackgroundColor` (`#323232`) — under even the loosest 3:1 floor — and only 3.29:1 against the darkest plausible surface, still under 4.5:1. That's tolerable for a non-text shape but is a hard "no" if that same hex is ever reused for indigo-coloured text or a numeral.
3. **The body fill and the peak/playhead highlight should diverge in saturation and lightness, not hue**, per §4's mitigation literature and the shipped Discord cautionary tale: a duller, lower-saturation/lower-alpha indigo for the 100%-coverage waveform body, a brighter, closer-to-stock indigo reserved for peaks, the playhead, and the Trim edges. This also gives §3's dark-mode contrast problem somewhere to go — the highlight tone can sit closer to (or above) stock brightness where it's small, while the body tone is freed to go duller/darker where it's large.
4. **Indigo's separability from the user's own system accent is a property of the rule, not the hue** (§5): indigo sits hue-adjacent to both system blue and system purple, deliberately tuned by Apple to read as a "consistent family" with purple specifically. AppTape's existing rule — indigo on content, system accent on chrome, never sharing a control — is load-bearing for keeping the two apart visually; the hue alone would not do it.
5. **Indigo does not collide with amber or red under any of the three common colour-vision deficiencies** (§5b) — the brief's actual constraint holds up. The one real CVD risk is indigo blurring toward blue/purple (deuteranopia/protanopia) or greenish/black (tritanopia), neither of which threatens the amber/red/green separations AppTape already depends on elsewhere (ADR-0009's Runway amber, the recording-state red, the level-meter green).
6. **There is no first-party Apple precedent for indigo as a whole-app committed accent** — only third-party ones, both imperfect (Discord: real but drew eyestrain complaints at high saturation in dark mode; Linear: an appealing pattern that could not be verified). This is a genuinely uncharted design choice for AppTape, not one with a clean model to copy — the ADR should treat §3/§4's contrast and fatigue findings as the load-bearing constraints, not precedent-matching.
7. Feeds directly into issue #70's already-flagged open question, **"Dark-mode-specific palette tuning"** — this research substantiates that exact concern with numbers rather than leaving it as a hunch.

---

## What I could not verify

- **Display P3 component values** for `systemIndigo` or any of the other system colours, light or dark — no source, primary or secondary, gave P3-space numbers; every value found was sRGB only.
- **An explicit Apple sentence stating "lighten and desaturate saturated hues for dark backgrounds" as a general rule.** Apple's actual text (§2) is legibility/glow-framed and more general; the shipped indigo values are *consistent* with a lighten-for-dark pattern, but that specific mechanism is a secondary paraphrase, not an Apple quote.
- **Apple's dedicated "Color and Contrast" accessibility sub-page at its historical URL** (`.../accessibility/overview/color-and-contrast/`) 404'd on every fetch attempt, including through the retrieval proxy. The contrast-ratio table and colour-blindness guidance used here came from the parent Accessibility overview page instead, which appears to carry the same content post-restructure — but the original page's exact wording was not directly confirmed.
- **A tool-rendered, pixel-level colour-blindness simulation** of the actual hex values (`#5856D6` indigo, `#FF9500`/`#FF9F0A` amber, `#FF3B30`/`#FF453A` red, `#34C759`/`#30D158` green). Every attempt to extract output from a live simulator (e.g. davidmathlogic.com/coblis) returned only a page shell, no renderable data. §5b is literature-grounded reasoning from the Machado et al. (2009) model, not a rendered proof — worth doing as a follow-up with an actual browser/screenshot tool if this decision needs to be pinned down further.
- **Whether Reminders' 12-colour list palette literally includes a swatch labelled "Indigo."** Sources confirm "12 colors" as the count but none enumerated the names.
- **A single, clearly citable article documenting user eyestrain complaints specifically tied to Discord's 2021 Blurple saturation increase in dark mode.** This came through as an aggregated/synthesized claim across search results rather than one strong citation — treat as directionally plausible, not confirmed.
- **Linear's actual current design-token hex values for its indigo/violet accent tiers.** One third-party scraping source directly contradicted the widely-repeated `#5E6AD2`-family figures, and Linear has no first-party brand-colour page equivalent to Discord's. The "duller fill / brighter highlight" pattern often attributed to Linear should not be relied on as verified precedent.
- **Any Apple WWDC session transcript explicitly using the words "vibration" or "halation."** Those terms and their mechanisms (§4) come entirely from secondary colour-science/design sources, not from Apple.
- **Indigo/purple-family branding for Reminders, Podcasts, TestFlight, or Playgrounds**, floated as candidates worth checking — none panned out as a citable indigo precedent (see §6).
