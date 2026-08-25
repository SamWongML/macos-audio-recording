---
status: accepted
---

# The menu bar item is an NSStatusItem, and it is the transport

AppTape's menu bar item is a hand-built **`NSStatusItem`**, not a SwiftUI `MenuBarExtra`. While a Recording is running the item reads **`● 01:23`** in red, and a **left-click stops the Recording** — it does not open anything. A **right-click** opens the panel; while idle, either click opens it. The panel itself stays SwiftUI, hosted in an `NSPopover` the app manages.

The constraint this serves is that starting and stopping a Recording each cost **one click**. Issue #6 settled the start half: the panel is a list of applications and the row *is* the record control, so starting is one click on a row. The stop half is what forces this decision.

## Considered options

Three alternatives kept the SwiftUI `MenuBarExtra` and paid two clicks to stop — one to open the panel, one to hit the control.

**The panel never changes shape** (the recording row flips its glyph and grows a small clock, every other row goes inert) is the most conservative reading of #6: stopping is the same gesture in the same pixel that started it. It was rejected because the running Recording is then only ever legible at list-row size, and never legible at all without opening the panel.

**The panel becomes a recording view** (Source, a large clock, full-width signal, one Stop) makes the running Recording unmissable, at the cost of moving the stop target away from the start target and giving the panel two shapes.

**Two decks, Record over Library** keeps a Library list visible so a Recording visibly lands when you stop. Rejected here as the busiest surface at rest, and because it answers a different question — the Library's place — which issue #10 owns.

**The deciding fact is that `MenuBarExtra` cannot intercept its own click.** The macOS 27 SwiftUI interface exposes exactly two initialiser shapes, `init(content:label:)` and `init(isInserted:content:label:)`. There is no action closure, no `isPresented` binding, no click hook: the panel always opens. One-click stop is therefore not reachable from `MenuBarExtra` at any price, and the choice is a straight trade of framework support for a click.

A **global start/stop shortcut** would have bought one-gesture stop without leaving `MenuBarExtra`, and was the strongest surviving argument against this decision. It is **out of scope for v1**, ruled out with issue #21, so it is no longer an alternative to weigh: in v1 this status item is the only thing that makes stop one gesture.

## Consequences

**The app loses what `MenuBarExtra` did for free**, and must hand-roll each piece: the `NSPopover` and its lifecycle, `.transient` dismissal, and `NSApp.activate(ignoringOtherApps:)` — without which the panel's controls come up inactive, because an `LSUIElement` app is not frontmost. This is the whole cost of the decision and it is paid once, in the app shell.

**Which implementation owns the menu bar is fixed at launch.** An `App`'s scene body does not re-evaluate when an `@Observable` it reads changes, so `MenuBarExtra(isInserted:)` is read once when the scene is built and never again. Measured three ways — inside the `isInserted` getter, directly in the body, and with the model held in `@State` — all identical. There is no runtime toggle between the two implementations.

**A left-click destroys rather than reveals**, which nothing else in the menu bar does. A misclick during a Recording stops it, and there is no confirmation — deliberately, because a confirmation would put the second click back. This raises the value of pause-and-resume, which is not yet scoped, and which is now the only mitigation left on the map.

**The panel is reachable during a Recording only by right-click**, a gesture with no visible affordance. That gap is real, and it is now an **accepted cost of v1 rather than an open risk**: issue #21 ruled a keyboard and assistive path to the item out of scope, so nothing is coming to close it.

**Colour must be pre-rendered.** `NSStatusBarButton` **ignores `contentTintColor`** and draws template images in the menu bar's own appearance — measured, template or not, the glyph came out black. `foregroundStyle(.red)` in a SwiftUI `MenuBarExtra` label is discarded the same way. Red arrives only as an explicitly non-template `NSImage`, and the clock as an `attributedTitle` carrying `.foregroundColor`.

**One thing this decision buys back:** a `MenuBarExtra` label renders exactly one image — two `Image`s and the second is silently dropped — so a red glyph beside a red clock is impossible there. A status bar button carries an image *and* an attributed title, so `● 01:23` is red in full.

**The item is 78pt wide while recording, against 32pt idle.** Monospaced digits keep it from jittering second to second; it steps once more at one hour, when `59:59` becomes `1:00:00`.

Settled in issue #8. Prototype: branch `prototype/menu-bar-surface`.
