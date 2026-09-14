---
status: accepted
---

# 0047. The lane maps points to seconds in one place

The 12 Sep 2026 architecture review found two pixel↔time mappings in `TrimTimeline.swift` and called
them a duplication. Mapping the file found **five**, plus the range they all derive from written out
in two files, plus four re-derivations of the divisor:

| | site | direction | clamp |
|---|---|---|---|
| A | `time(_ px:)` | points → seconds | `min(max(0, …), duration)` |
| B | `x(_ t:)` | seconds → points | none |
| C | the ruler's own `let x:` closure | seconds → points | none |
| D | the loupe, inlined | seconds → points | `min(max(106, …), width - 106)` |
| E | `loupeDropouts` | seconds → fraction | `max(0, min(1, …))` |
| F | `Envelope.columns(over:count:)` | index → seconds | none |

None of it was tested. There is no `TrimTimelineTests.swift`, and `tickTimes` / `tickInterval` had
been made `static` and pure **for** testing without a test ever naming them.

## The mappings differed because one of them was carrying a feature the app does not have

`visible` was `0...max(duration, 0.001)`, and its lower bound is **provably `0`** at all seven sites
that subtracted it. [ADR-0023](0023-detail-pane-layout.md) closed the question
in as many words — *"the Recording always fits the width and there is no zoom, so the interval is a
function of duration and width alone"* — and rejected an overview strip on the same ground, *"an
overview strip is a zoom-navigation aid and there is no zoom."* The file's own header repeats it.
There is no zoom or scroll state anywhere in it.

So four of the five conversions carried a scroll offset that could not be non-zero. That is most of
why they did not look like each other, and it is why C was written fresh rather than reusing B four
lines above: `(t - visible.lowerBound) / span * width` reads like something with a moving origin, and
nobody rereading it could see that the origin never moves.

## The decision

**One `TimelineGeometry` value over `(width, duration)`, and every conversion, bound and ladder
derived from it.**

This is `Trim`'s shape one domain up, and deliberately so. `Trim`'s own header states the argument:

> The fix is not a better pair of clamps: it is to clamp **once**, into an interval that is provably
> non-empty, and to have exactly one place that knows how.

`Trim` owns clamping in seconds. Nothing owned the conversion into seconds, so every clamp in the
lane was a hand-written nested `min`/`max` — the exact idiom `Trim` exists to have ended — and none
of them called the `Double.clamped(to:)` `Trim` publishes.

`Trim` also names the hazard the lane manufactured: *"`NaN` is reachable: the lane converts a pixel
to a time with `px / width * span`, and a zero-width lane during a layout pass makes that
`inf * 0`."* That was defended by a `max(geo.size.width, 1)` written at each `GeometryReader` and by
`Trim`'s own `isFinite` guard three files away. It is an invariant of one initialiser now.

## The clamp that inverted, which is the expensive half

```swift
let x = min(max(boxWidth / 2, position), width - boxWidth / 2)   // boxWidth = 212
```

The intent is `clamp(position, to: 106...(width - 106))`. **That interval is empty whenever the lane
is narrower than the box**, and because the lower bound is applied first and the upper bound last,
the upper bound wins unconditionally when it is the smaller of the two:

| lane width | what the loupe did |
|---|---|
| ≥ 213 pt | tracked the handle, as intended |
| 212 pt | pinned at 106 and stopped tracking |
| < 212 pt | sat at a fixed `width - 106` regardless of the drag; the inner `max` was dead code |
| < 106 pt | that number is **negative** — at 100 pt the box offset −119, fully off the leading edge of the lane it is drawn inside |

`EditorView` gives the lane a height floor and a height cap and **no width constraint**, so those
widths are reachable by narrowing the window.

**The box now centres when the lane cannot hold it.** On a lane too narrow to avoid both edges there
is no position that satisfies the constraint, so it overhangs symmetrically rather than choosing an
edge to fall off — and the interval it clamps into is non-empty by construction, which is the part
that matters. This is the one behaviour change in the work.

## The two directions disagree about clamping, and that is correct

The review read the asymmetry — A clamps, B and C do not — as the defect. It is not, and the reason
had simply never been written down anywhere.

- **`time(atX:)` must clamp.** Its result leaves the view: it reaches `Trim.setStart`/`setEnd` and
  `AudioPlayer.seek`. A drag that runs past the lane's edge has to land on the Recording's end.
- **`x(atTime:)` must not.** A Trim handle at the very end draws at exactly `width`; a Dropout band's
  width is the difference of two of these, and clamping either end would collapse a band that runs
  off an edge instead of letting it clip. Callers that want a bounded answer ask for one by name —
  `centredBoxX(at:boxWidth:)` for the loupe, `labelX(at:reserving:)` for the ruler's last label.

Both are now stated on the members and pinned by tests, including a round-trip property the two
hand-written copies could have broken silently.

## ADR-0031's rule stops being expressed as a lie about the length

The ruler said:

```swift
ForEach(Self.tickTimes(duration: isStillArriving ? 0 : recording.duration, width: width), …)
```

[ADR-0031](0031-growing-recording-figures.md)'s rule is *no duration
means no ticks, not one tick at zero* — but what the code was doing is misreporting the Recording's
length to the arithmetic in order to get a policy out of it. The geometry answers honestly for
whatever duration it is given; **whether that duration is trustworthy yet is the ruler's judgement**,
and it is made where the ADR comment already was. The rule is unchanged; only where it is stated.

## Also decided here

**Two `GeometryReader`s stay two, and this is the option that was hardest to leave alone.** Hoisting
one around the `VStack` would give the ruler and the lane a single measurement rather than two that
happen to agree. It was rejected because ADR-0023 fought a greedy `GeometryReader` in this exact pane
— the whole reason the lane's height is pinned by a `minHeight`/`maxHeight` frame at the call site —
and re-wrapping the stack risks that layout for a duplication that is not the one causing harm. One
*type*, two instances. What was duplicated was the formula, not the measurement.

**The geometry must never become `Animatable`.** ADR-0028's first forbid-list entry is that the lane
cuts rather than cross-fades when the selection changes, *"a correctness matter rather than a taste
one"* — interpolating one Recording's peaks into another animates a relationship that does not exist.
A geometry value that carried `animatableData` would reintroduce that through the back door.

**The layout numbers that are not part of the mapping were left where they are.** `Metrics` is scoped
by its own docstring to *"the spacing, type and motion half of the token set"* and has no corner
radius, opacity or shadow stop; `cornerRadius` appears in no file but this one, so there is no
cross-file disagreement to fix. Only numbers that participate in points↔seconds moved. The rest is
the review's candidate 6.

**Three comments were corrected rather than obeyed.** `Recording.trimmedFrameRange` called itself
*"the one place the seconds→frames rounding lives"* and there are three — `AudioPlayer` truncates its
start frame, `loupeWindow` rounds outward to cover its window — and the one it actually owns is the
Export's. `loupeWindow` promised *"seconds-per-pixel is always `span / columns`"*, which is its
seconds-per-**column**: the box is 212 points wide and asks for 220, so the picture is slightly
oversampled and only the centre is exact. And `TrimTimeline`'s hit-test claimed a tolerance *"from a
fixed fraction of the visible span"* when the span is the whole Recording and the fraction is of the
lane.

## What is not verified

**The loupe still cannot be previewed, and the narrow-lane preview added here does not show it.**
It renders only while `draggingHandle` is set, which is `@State` with no dropout to set it from outside;
giving it one would mean a debug-only initialiser on a production view. The clamp is covered by
`TimelineGeometryTests` instead, which is the point of moving it out of the view — but the *picture*
of a loupe on a 180 pt lane has been reasoned, not seen. ADR-0018 has no UI test layer, so this stays
a review-by-hand item.

**ADR-0023's 64 pt label spacing does not hold at the top of the ladder, and now says so.** The ladder
stops at one hour, so a Recording longer than about 56 seconds per point of lane — roughly 3 h 20 at
a 212 pt lane — gets ticks closer together than the ADR asks for. The behaviour is carried over
unchanged and is pinned by a test that will fail if it ever silently changes. No file the app
produces has reached it; an adopted one could.
