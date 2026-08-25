# PROTOTYPE — Menu bar surface (issue #8)

Throwaway. Four answers to "what happens when you click the menu bar item", on the real
menu bar. Not production code.

```sh
./run.sh   # builds, signs, launches. Waveform icon in the menu bar. ⌘Q quits.
```

- **← / →** switch the panel variant (I J K L)
- **↑ / ↓** switch the menu bar **icon** treatment, independently of the panel — the
  switcher previews all four side by side, and they are clickable
- **⏺** starts a Recording against a fake Source, so the recording state and the menu bar
  icon are reachable with nothing playing
- **▤** opens the raw Core Audio process table (evidence, not part of any variant)

**Crossing into or out of K relaunches the app** (about a second, and K's popover opens
itself so the switcher stays reachable). I ↔ J ↔ L are instant. See finding 3 for why —
it is a `MenuBarExtra` constraint, not a choice.

First launch will prompt for **System Audio Recording** — this is a new bundle ID
(`com.samwongml.AppTape.MenuBarSurfacePrototype`), so it does not inherit the
source-picker prototype's grant. Without it the waveforms are flat but every layout
question is still answerable.

## What is *not* being decided here

The idle panel is settled. [Issue #6](https://github.com/SamWongML/macos-audio-recording/issues/6)
chose variant H — the list is the panel, the row is the record control, no button chrome —
and all four variants inherit it unchanged from `Baseline.swift`. What varies is only what
**recording** does to that panel, what the **menu bar item** becomes, and how the
**editor** is reached. The editor window itself is a deliberate stub; issue #7 designs it.

## Six findings before any layout question

### 1. `MenuBarExtra` cannot intercept its own click

Grepped the macOS 27 SwiftUI interface. `MenuBarExtra` has exactly two initialiser shapes,
`init(content:label:)` and `init(isInserted:content:label:)`. **No action closure, no
`isPresented` binding, no way to see the click** — the panel always opens.

The ticket's shaping constraint is that start and stop stay one click. I, J and L all
spend *two* to stop: one to open the panel, one to hit the control. Only variant K spends
one, and buying that means dropping to `NSStatusItem` and hand-rolling the popover,
its lifecycle, and `NSApp.activate` — all of which `MenuBarExtra` does for free.

`isInserted: false` does genuinely remove the SwiftUI item — when it is false *as the
scene is built*. K's own item then takes the exact slot the SwiftUI one had, so exactly one
item is in the bar:

```
variant=I  ownItem=none            NSStatusBarWindow(x=1273 w=32)  NSStatusBarWindow(x=0 w=32)
variant=K  ownItem=x=1273 w=32     NSStatusBarWindow(x=1273 w=32)  NSStatusBarWindow(x=0 w=32) …
```

Flipping it *after* launch is a different story, and it is finding 3.

### 2. A SwiftUI menu bar label *does* stay live while the panel is closed — and it renders a stack

This was the open risk. The source-picker prototype's `Canvas` froze because SwiftUI could
not observe the ring the audio thread was mutating, and a menu bar clock is the same shape
of problem: nothing is on screen, so nothing obviously forces a rebuild.

It holds. With `Session.elapsed` on an `@Observable` and the label reading `elapsedText`,
the label rebuilds locked 1:1 with the tick, panel closed:

```
DIAG menuBarLabel=1/s sessionTick=1/s     <- sustained, panel never opened
```

And an `HStack { Image; Text }` genuinely renders — the item **grows**, so the `Text` is
really there rather than being dropped:

| icon treatment | `MenuBarExtra` item | K's `NSStatusItem` |
|---|---|---|
| glyph swap | 34pt | 32pt |
| tint only | 34pt | 32pt |
| **glyph + time** | **77pt** | 78pt |
| **time only** | **53pt** | 60pt |

**So elapsed-time-in-the-menu-bar is not a reason to leave `MenuBarExtra`.** K is now
justified by *click-to-stop alone*, which is a much narrower claim than it looked.

The table is also the honest price of the two time treatments: **77pt against 34pt, 2.3×
wider, held for the whole Recording** on a bar that is already contested. Digits are
monospaced so the width does not jitter second to second, but it will step once more at
one hour, when `59:59` becomes `1:00:00`.

### 3. An `App`'s scene body does not re-evaluate when an `@Observable` changes

Found by switching variants rather than launching into them, which is how the first pass
missed it: the menu bar button stuck, because **two items were sitting on the same
coordinate** and clicks went to whichever was on top.

```
CENSUS variant=I  inBar=1  ownItem=none            <- MenuBarExtra's item
SWITCH -> K
CENSUS variant=K  inBar=2  ownItem=x=1306 w=32     <- K's item, and MenuBarExtra's still there
```

`MenuBarExtra(isInserted:)` was bound to `!shell.variant.usesStatusItem`, and the scene was
simply never rebuilt, so `isInserted` was never read again. Three placements were measured
and all behaved identically — inside the `isInserted` getter closure, directly in the body,
and with `Shell` held in `@State`. **A scene reads its inputs once and keeps them.**

So which menu bar implementation owns the bar is a **launch-time** decision, and crossing
the K boundary relaunches the app instead of trying to swap live.

Second trap inside the fix: relaunching with `NSWorkspace.openApplication` +
`createsNewApplicationInstance` and *then* terminating left the new instance with **no
menu bar item at all** (`x=0`, never placed) — two instances of the same `LSUIElement`
bundle overlap and the one still holding the slot wins. Quitting first and handing the
relaunch to a detached `sh` fixes it. Verified in both directions:

```
I -> K   inBar=1  ownItem=x=1344 w=32   <- K's item, and only K's
K -> L   inBar=1  ownItem=none          <- MenuBarExtra's item back
```

### 4. `withObservationTracking` keeps an `NSStatusButton` live, but only if it re-arms

For K, the AppKit side. `withObservationTracking`'s `onChange` fires **once** — the
obvious one-shot call leaves the title frozen after the first second. Re-registering
inside the callback fixes it, verified sustained:

```
DIAG menuBarLabel=1/s sessionTick=1/s statusItemRefresh=1/s
```

A second bug hid behind it: `remove()` did not reset the `observing` flag, so after
K → L → K the re-installed item's title was frozen at whatever second it was removed on —
the tracking chain bails on `item == nil` without re-arming, and `install()` then
short-circuits `startObserving()`. Both now verified to survive a round trip.

### 5. Colour does not survive into a menu bar label

Reported as "no difference when I cycle the icon". Two causes, and this is the interesting
one: **`foregroundStyle(.red)` inside a `MenuBarExtra` label renders black.** SwiftUI hands
the menu bar a template image and the colour is dropped. It applies to `Text` as well as
`Image`.

That made **`tint only` literally identical to idle** — its entire design is "keep the
glyph, change the colour", and the colour never arrived. Not a subtle difference to squint
at: the same black waveform, before and after.

Seen by **snapshotting the real status bar window from inside the app**
(`cacheDisplay(in:to:)` on its content view). `screencapture` from a shell without the
Screen Recording grant silently returns a desktop-picture-only image and cannot see the
menu bar at all, which is why the first pass never looked. Control run first, because an
instrument that renders everything black would have produced exactly these results: a
hand-drawn non-template red disc snapshots **red**, so the black was real.

The same bug bit variant K from the opposite side. K set `isTemplate = false` while
recording so that `contentTintColor` could "win" — but an SF Symbol is a monochrome glyph,
so turning off template mode does not give it colour, it just opts out of the one mechanism
that would have coloured it. `contentTintColor` tints **template** images only. Keeping
`isTemplate = true` fixes it.

Fix on the SwiftUI side: pre-render the symbol into an explicitly non-template `NSImage`
and hand *that* to `Image(nsImage:)`. All four treatments now read correctly — red
`record.circle.fill`, red `waveform`, red glyph + clock, red clock.

### 6. A menu bar label renders exactly one image

Found while making the clock red too. Two `Image`s in the label and **the second is
silently dropped** — the item measured 34pt where it should have been 77pt, i.e. the glyph
rendered and the clock vanished. `Image` + `Text` renders both (that is how the 77pt
measurement in finding 2 happened).

So **a red glyph beside a red clock is not available.** With a glyph, the clock has to stay
a `Text` and takes the menu bar's own colour; a red clock is only possible when it is
alone. Which is probably the better end of the trade anyway — a rasterised clock stops
adapting to the bar's appearance, and has to be re-rendered every second.

### And the other half of "no difference": idle is identical on purpose

Every branch in `IconTreatment` is gated on `recording`, so **all four treatments are
byte-identical when nothing is being recorded** — correctly, since they exist to convey the
*active* state. But it means ↑ / ↓ did nothing visible unless a Recording happened to be
running, and starting one needs an app actually playing audio, which is not always true
when you sit down to judge this.

Two bits of scaffolding fix that:

- the switcher now shows **all four treatments at once**, drawn as the menu bar would draw
  them while recording, with the current one boxed — so ↑ / ↓ always moves something, and
  the comparison is direct instead of from memory (they are clickable too);
- a **⏺ demo button** starts a Recording against a fake Source, so every variant's
  recording state and every icon treatment is reachable with nothing playing.

## The four variants

| | While recording, the panel… | Stop is… | Route to older Recordings |
|---|---|---|---|
| **I** No modes | keeps exactly its idle shape; the row flips glyph and grows a small clock, every other row goes inert | the same row, same pixel | `Recordings` footer, always present |
| **J** Mode swap | is replaced entirely — Source, a 42pt clock, full-width signal, one Stop | a `.glassProminent` Stop button | footer, but only while idle |
| **K** Transport | is not involved; the *menu bar item* reads `● 01:23` | **one click on the menu bar item**, from anywhere | right-click for the panel |
| **L** Two decks | collapses the list to a strip; a Library deck stays visible underneath | a `.glass` stop button in the strip | it is on screen the whole time |

Each disagrees with the others about something real:

- **I vs J** is *does recording deserve a mode?* I says the panel should never change shape,
  so stopping is the same gesture in the same place — at the cost of a clock the size of a
  list row. J says a running Recording is the only thing that matters and should be
  readable across a desk — at the cost of moving the stop target away from the start
  target, and a panel with two shapes.
- **K** is the only one that satisfies "one click" literally. Price: `NSStatusItem`, a
  hand-rolled popover, and a **left-click that destroys rather than reveals** — which is
  not what a menu bar item does anywhere else on the system. Watch whether it feels fast
  or feels dangerous.
- **L** is the only one that treats the Library as half the product rather than a link out.
  Price: it is the busiest panel at rest, and the tallest.

## What to watch while flipping

- **Start something in Chrome, record it, then stop.** All four auto-save and open the
  editor stub (the map's standing preference). Does that feel right in I, where nothing
  else about the panel moved — or does the window appearing out of a list feel abrupt?
- **In J, catch the transition.** The panel changes shape under the cursor. Is it
  disorienting, or is it the clearest possible confirmation that recording started?
- **In K, stop a Recording.** One click, nothing opens, the editor appears. Then try
  right-clicking for the panel and notice you had to *know* that. Is one saved click worth
  a hidden gesture and leaving `MenuBarExtra` behind?
- **In L, stop and watch the Recording land** in the deck below. That visible landing is
  the whole argument for the variant.
- **Hit ⏺ in the switcher, then cycle ↑ / ↓ through the four icon treatments**, ideally
  with a busy menu bar. `tint only` is the accessibility question — it is now genuinely
  red, but colour is its *only* channel, and it is the one treatment that says nothing at
  all to someone who cannot see it. `glyph + time` and `time only` are the width question:
  77pt and 53pt against 34pt idle.
- **Reduce Motion.** All the pulses are `.symbolEffectsRemoved(reduceMotion)`. Check the
  recording state is still obvious with motion off, especially in I where the pulse is
  doing a lot of the work.

## Deliberately left out

- **Pause and resume** — still fog on the map, and it would change every variant's
  recording state.
- **A global start/stop shortcut** — the other way to make stop one click, and the one that
  would have weakened K's case considerably. It was fog on the map when this probe was
  written; it is now **out of scope**, ruled out with
  [#21](https://github.com/SamWongML/macos-audio-recording/issues/21) along with every other
  keyboard route to the item, so K's case no longer has a rival.
- **What happens when the Source quits mid-Recording** — that is
  [#13](https://github.com/SamWongML/macos-audio-recording/issues/13), and
  [#18](https://github.com/SamWongML/macos-audio-recording/issues/18) owns what a degraded
  Recording looks like. Neither variant shows an error state yet.
- **The first-run permission prompt's timing** —
  [#14](https://github.com/SamWongML/macos-audio-recording/issues/14). These variants all
  open taps to draw the idle list, exactly as variant H did.
