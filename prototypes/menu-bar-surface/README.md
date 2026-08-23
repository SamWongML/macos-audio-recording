# PROTOTYPE — Menu bar surface (issue #8)

Throwaway. Four answers to "what happens when you click the menu bar item", on the real
menu bar. Not production code.

```sh
./run.sh   # builds, signs, launches. Waveform icon in the menu bar. ⌘Q quits.
```

- **← / →** switch the panel variant (I J K L)
- **↑ / ↓** switch the menu bar **icon** treatment, independently of the panel
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

## Four findings before any layout question

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
| glyph swap | 32pt | 32pt |
| tint only | 32pt | 32pt |
| **glyph + time** | **74pt** | 78pt |
| **time only** | **56pt** | 60pt |

**So elapsed-time-in-the-menu-bar is not a reason to leave `MenuBarExtra`.** K is now
justified by *click-to-stop alone*, which is a much narrower claim than it looked.

The table is also the honest price of the two time treatments: **74pt against 32pt, 2.3×
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
- **Cycle ↑ / ↓ through the four icon treatments while recording**, ideally with a busy
  menu bar. `tint only` is the accessibility question (colour as the sole channel);
  `glyph + time` and `time only` are the width question — see the table above.
- **Reduce Motion.** All the pulses are `.symbolEffectsRemoved(reduceMotion)`. Check the
  recording state is still obvious with motion off, especially in I where the pulse is
  doing a lot of the work.

## Deliberately left out

- **Pause and resume** — still fog on the map, and it would change every variant's
  recording state.
- **A global keyboard shortcut**, also still fog. It is the other way to make stop one
  click, and it would weaken K's case considerably. Worth saying out loud before choosing.
- **What happens when the Source quits mid-Recording** — that is
  [#13](https://github.com/SamWongML/macos-audio-recording/issues/13), and
  [#18](https://github.com/SamWongML/macos-audio-recording/issues/18) owns what a degraded
  Recording looks like. Neither variant shows an error state yet.
- **The first-run permission prompt's timing** —
  [#14](https://github.com/SamWongML/macos-audio-recording/issues/14). These variants all
  open taps to draw the idle list, exactly as variant H did.
