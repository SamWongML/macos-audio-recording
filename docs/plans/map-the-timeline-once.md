---
status: delivered
source: architecture review, 12 Sep 2026 — candidate 5, "One timeline, two pixel↔time mappings"
issue: https://github.com/SamWongML/macos-audio-recording/issues/133
record: docs/adr/0047-the-lane-maps-points-to-seconds-in-one-place.md
---

# Map the timeline once

## Context

The review found two pixel↔time mappings in `TrimTimeline.swift`. The map found **five**, plus the
range they all derive from written out twice in two files, plus four re-derivations of the divisor.
None of it is tested: there is no `TrimTimelineTests.swift`, and `tickTimes` / `tickInterval` were
made `static` and pure *for* testing and no test names them.

| # | site | direction | clamp |
|---|---|---|---|
| A | `TrimTimeline.swift:77-79` — `func time(_ px:)` | px → time | `min(max(0, …), duration)` |
| B | `TrimTimeline.swift:76` — `func x(_ t:)` | time → px | none |
| C | `TrimTimeline.swift:478` — `let x: (Double) -> Double` | time → px | none — the ruler's own copy, *"a `ViewBuilder` closure cannot contain a declaration"* |
| D | `TrimTimeline.swift:375-377` | time → px | `min(max(212/2, …), width - 212/2)` — **inverts below 212 pt** |
| E | `TrimTimeline.swift:254-255` — `loupeSeams` | time → fraction | `max(0, min(1, …))`, over the loupe's own span |
| F | `Envelope.swift:46-47` — `columns(over:count:)` | index → time | none |

The divisor, four times: `:75`, `:212`, `:476`, and inlined at `:376`. The range, twice, in two
files:

```
TrimTimeline.swift:44    private var visible: ClosedRange<Double> { 0...max(recording.duration, 0.001) }
EditorView.swift:930-931 columns(over: 0...max(recording.duration, 0.001), count: 120)
```

### `visible` is a zoom abstraction for a timeline that has no zoom

`visible.lowerBound` is **provably `0`** at all seven sites that subtract it. ADR-0023 closed the
question outright — *"the Recording always fits the width and there is no zoom, so the interval is a
function of duration and width alone"* — and rejected overview strips on the same ground
(*"an overview strip is a zoom-navigation aid and there is no zoom"*). `TrimTimeline.swift:16`
repeats it. There is no zoom or scroll `@State` anywhere in the file.

So four of the five mappings carry a scroll offset that cannot be non-zero. That is most of why they
look unlike each other while doing the same thing — and it is why C was written as a fresh closure
rather than reusing B.

### The precedent is `Trim`, and it is exact

`Trim.swift:20-29` is this plan's argument, one level down:

> the ad-hoc version — clamping written out by hand at five separate call sites … held *none* of
> them … The fix is not a better pair of clamps: it is to clamp **once**, into an interval that is
> provably non-empty, and to have exactly one place that knows how.

And `Trim.swift:79-81` names the hazard the lane manufactures:

> `NaN` is reachable: the lane converts a pixel to a time with `px / width * span`, and a zero-width
> lane during a layout pass makes that `inf * 0`.

That is defended today by a `max(geo.size.width, 1)` floor written at two call sites (`:67`, `:475`)
and by `Trim`'s own `isFinite` guard. `TrimTimeline` never calls the `Double.clamped(to:)` that
`Trim.swift:104-108` already publishes — every clamp in the view is a hand-written nested
`min`/`max`, which is the exact bug class `Trim` was built to end.

### The live defect: the loupe's clamp inverts

```swift
// TrimTimeline.swift:375-377, boxWidth = 212
let x = min(max(boxWidth / 2, (centre - visible.lowerBound)
                / (visible.upperBound - visible.lowerBound) * width),
            width - boxWidth / 2)
```

The intent is `clamp(pos, to: 106...(width - 106))`. That interval is non-empty only when
`width >= 212`. Because the lower bound is applied first and the upper bound last, **the upper bound
wins unconditionally whenever it is the smaller of the two**:

- `width == 212` — `x == 106` always; the loupe stops tracking the drag and pins to centre.
- `width < 212` — the outer `min` always selects `width - 106` regardless of where the handle is.
  The inner `max` becomes dead code.
- `width < 106` — that value is **negative**. Feeding `:457`'s `.offset(x: x - 113)`, a 100 pt lane
  offsets the loupe by −119 pt: fully off the leading edge, which is the one thing the clamp exists
  to prevent.

`EditorView.swift:383-390` constrains the lane's height and gives it no width floor, so sub-212 pt
widths are reachable on a narrow window.

### What was checked and found **not** duplicated

- **`Trim`** — already the one place that clamps in the time domain. This restates none of it.
- **`Double.clamped(to:)`** (`Trim.swift:104`) — already exists. Reused; no second primitive.
- **`Envelope.drawnHeadroom`** and **`Envelope.Column.reduce`** — each already one definition with a
  doc comment saying why. The model to copy, not to fix.
- **`WaveformShape` vs `WaveformPath`** — a documented framework workaround (`Canvas` draws nothing
  inside a `List` row on macOS 27), not an accident. Only the curve expression is folded.
- **`Format.time` vs `CaptureRun.elapsedText`** — `CaptureRun.swift:164-165` says the divergence is
  deliberate (ADR-0027 reserves the transport's widest readout; the menu bar does not pad).
- **`Metrics.sectionHeader`** — dead *by decision*; ADR-0025 owns it.
- **`isStillArriving`** — derived once at `CaptureState.swift:59`; the view-side reads are forwards.
  ADR-0045 settled it.
- **Corner radii, opacities, shadows in `TrimTimeline`** — `Metrics` is scoped to *"the spacing, type
  and motion half of the token set"* and has no radius or opacity stop, and `cornerRadius` appears in
  no other file, so there is no cross-file disagreement to fix. **Candidate 6's business.** This
  module takes only numbers that participate in the px↔time mapping.

---

## As built

Green at every step, zero failures. **19 new cases**, and `TrimTimeline.swift` went from 577 lines to
612 — it gained a preview and lost every arithmetic expression it had.

The suite total is quoted as a range on purpose: it reports **331 or 332** depending on the run, and
**312 or 313** on `main`, because `xcodebuild`'s parallel reporter intermittently drops one `passed`
line. See the last bullet below.

Isolation is unchanged. The 42 `#IsolatedConformances` warnings all name `LibraryLocation.RenameOutcome`,
`RowRecordGlyph.State` and `PanelAnchor` — three pre-existing types this work does not touch.
`TimelineGeometry` is `nonisolated` and raises none.

| file | change |
|---|---|
| `TimelineGeometry.swift` | **+173, new**: the value, both directions, the range, the ladder, the two bounded placements |
| `TimelineGeometryTests.swift` | **+267, new**: 19 cases over geometry that had none, including a round-trip property and a deterministic fuzz |
| `TrimTimeline.swift` | +105/−70: `visible` and both statics gone; the lane, the loupe and the ruler each ask one value; the loupe's numbers named; a fourth preview |
| `Envelope.swift` | +9/−7: four dead members out, the loupe's seconds-per-pixel contract corrected |
| `WaveformView.swift` | +16/−10: one amplitude curve for two renderers, the reason stated once |
| `Recording.swift` | +9/−3: a locality claim that was not true |
| `Seam.swift` | +6: `endSeconds(sampleRate:)`, which two call sites were doing by hand |
| `EditorView.swift`, `AudioPlayer.swift` | +2/−2: the sidebar's range and the player's clamp stop being copies |

Six things differ from the plan below, each because writing the code showed the plan was wrong.

- **The mapping was five, and the plan's own table was already the correction.** The review said two.
  What the plan did not predict is that the ruler's copy existed *because* of `visible`: with a
  moving origin in the expression, nobody rereading `(t - visible.lowerBound) / span * width` could
  see that the origin never moves, so it read as a different calculation rather than the same one.
- **`secondsPerPoint` was designed and then not built.** It is the file header's own phrasing for the
  central quantity and no caller wanted it once `grabTolerance` and `columnCount` existed. Adding
  unused API while removing unused API is the wrong trade; it can be added when something asks.
- **`tickInterval` is an instance member, not the `static func(duration:width:)` the plan sketched.**
  Once the value exists, a static taking the same two scalars is the value with extra steps.
- **The width floor moved off the call sites entirely.** The plan kept `max(geo.size.width, 1)` at
  both `GeometryReader`s and had the module floor defensively. Both is one too many: the initialiser
  is the invariant, so the views now pass `geo.size.width` straight in.
- **ADR-0023's 64 pt label rule does not hold at the top of the ladder, and the test says so rather
  than asserting a falsehood.** The ladder stops at an hour, so a Recording longer than roughly
  56 seconds per point of lane crowds its ticks. Found by writing the assertion the ADR implies and
  watching it fail. Carried over unchanged, pinned by a test that fails if it silently changes.
- **The narrow-lane preview cannot show the loupe.** It renders only while `draggingHandle` is set,
  which is `@State` with no seam; giving it one means a debug-only initialiser on a production view.
  The clamp is covered by a test instead — which is the point — but the picture is reasoned, not seen.

### What bit us, so it does not bite you again

- **`min`/`max` and `.clamped(to:)` disagree about `NaN`, in opposite directions.** Swift's
  `max(0, .nan)` returns `0` (the comparison is false, so it keeps `x`), while
  `Double.clamped(to: 0...d)` returns `.nan` — the same two operations, composed the other way round.
  So porting a hand-written clamp to the shared helper silently changes what a bad layout pass
  produces. `time(atX:)` keeps an explicit `isFinite` guard for exactly this, and it is a test case.
- **A local `let` shadowing a method of the same name does not compile.** `let geometry =
  geometry(width: width)` is *"used before being initialized"* — the binding is in scope inside its
  own initialiser. `self.geometry(width:)`.
- **The suite count is not stable to ±1, and it is the reporter, not the tests.** Two consecutive
  full runs of an unchanged tree gave 332 and 331; the difference was a single missing `passed` line
  for `EditorModelTests/theOpenRecordingVanishingClosesTheEditorAndCancelsTheExport()`, which passes
  3/3 under `-only-testing` and never fails. Both runs said `** TEST SUCCEEDED **` with zero
  failures. This also explains the previous plan's "313" against this one's "312" — the same suite,
  the same flake, two runs. **Quote failures, not totals**, and count new `@Test func`s by hand when
  a delta matters.

## 0 · Decisions taken before any code

### The name is `TimelineGeometry`, a `nonisolated struct` over two scalars

`CONTEXT.md` has no term for *timeline*, *lane*, *ruler* or *playhead*, and this coins none —
exactly as ADR-0046's plan declined to coin *refusal* and reused **Export**. The shape is `Trim`'s: a
small `nonisolated struct` whose initialiser establishes invariants so no call site clamps.
`nonisolated` is load-bearing under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (ADR-0022).

### `visible` is deleted, not parameterised

Storing `(width, duration)` rather than `(width, visibleRange)` is the whole point: it makes *"the
Recording always fits the width"* (ADR-0023) a property of the type instead of a comment. If zoom is
ever wanted, adding it is one change to one type — the argument *for* this shape, not against it.

### `x(atTime:)` stays unclamped, and that is now written down

The review reads the two mappings disagreeing about clamping as a defect. It is not: `time(atX:)`
must clamp because it produces a time that reaches `Trim` and `AudioPlayer`, while `x(atTime:)` must
be free to return values outside `0...width` so a handle at the very end draws at `width` and so
seam-band widths subtract correctly. The asymmetry is right and has simply never been stated.

### Two `GeometryReader`s stay two

Hoisting one around the `VStack` would give ruler and lane a single measurement, but ADR-0023 fought
a greedy `GeometryReader` in exactly this pane and pinned the lane's height with a
`minHeight`/`maxHeight` frame at the call site. One *type*, two instances, is the low-risk shape; the
duplication that mattered was the formula, not the measurement.

### ADR-0031's policy becomes visible instead of encoded as a fake duration

Today the ruler writes `tickTimes(duration: isStillArriving ? 0 : recording.duration, …)` — it lies
about the length to suppress the ticks. After, `ticks` returns `[]` for a non-positive duration as
arithmetic, and the view states the policy where the ADR comment already is.

---

## 1 · Target shape

```
                 before                                       after

TrimTimeline.swift                             TrimTimeline — gestures & drawing only
  :75  span                                      lane   → TimelineGeometry(width:duration:)
  :76  func x(_:)            time → px           ruler  → TimelineGeometry(width:duration:)
  :77  func time(_:)         px → time                        │
  :212 span (again)                                           ▼
  :375 inline x + broken clamp                        TimelineGeometry
  :476 span (again)                          ┌─────────────────────────────────┐
  :478 closure x             time → px       │ time(atX:) · x(atTime:)         │
  :518 tickTimes  ← 0 tests                  │ secondsPerPoint · visibleRange  │
  :524 tickInterval ← 0 tests                │ ticks · tickInterval            │
                                             │ centredBoxX(at:boxWidth:)       │
Envelope.swift                               │ labelX(at:reserving:)           │
  :46  index → time                          │ grabTolerance                   │
                                             │ width(from:to:minimum:)         │
EditorView.swift                             └─────────────────────────────────┘
  :930 0...max(duration, 0.001)                  ↑ EditorView.silhouette reads
                                                   TimelineGeometry.wholeRange(duration:)
```

## 2 · The module

`AppTape/AppTape/TimelineGeometry.swift`. New files under `AppTape/AppTape/` and
`AppTape/AppTapeTests/` join their targets automatically (`PBXFileSystemSynchronizedRootGroup`); no
pbxproj edit.

`init` establishes the invariants that today are spread across two `max(geo.size.width, 1)` floors,
a `max(duration, 0.001)`, a second `max(duration, 0.001)` inside `tickInterval`, and `Trim`'s
`isFinite` guard:

```swift
init(width: Double, duration: Double) {
    self.width = width.isFinite ? Swift.max(1, width) : 1
    self.duration = duration.isFinite ? Swift.max(0, duration) : 0
}
```

Every clamp goes through `Double.clamped(to:)` (`Trim.swift:104`). No new clamp primitive.

## 3 · The call sites

| was | becomes |
|---|---|
| `TrimTimeline:75-79` local `span`, `x`, `time` | one `TimelineGeometry` per `GeometryReader` |
| `:96`, `:100` `x:` closure params | pass `geometry` to `waveform` / `seamBands` |
| `:111` `scrub(time:)` | `scrub(geometry:)` |
| `:164` `columns(over: visible, count: Int(width))` | `columns(over: geometry.visibleRange, count: geometry.columnCount)` |
| `:212-213` `span * 0.02` | `geometry.grabTolerance` |
| `:236-238` `max(3, x1 - x0)` | `geometry.width(from:to:minimum:)`, with `Seam.endSeconds` |
| `:375-377` the inverted clamp | `geometry.centredBoxX(at:boxWidth:)` |
| `:476-478` the ruler's own `span` + `x` | the ruler's own `TimelineGeometry` |
| `:488-489` `tickTimes(duration: isStillArriving ? 0 : …)` | `isStillArriving ? [] : geometry.ticks` |
| `:498` `min(x(t), width - 30)` | `geometry.labelX(at:reserving:)` |
| `:518-529` the two statics | deleted — they live on the module |

Blast radius: `EditorView.swift:930` reads `TimelineGeometry.wholeRange(duration:)`;
`AudioPlayer.swift:116` uses `Double.clamped(to:)`; `Envelope.swift` loses four dead members and
gains a corrected loupe contract; `Seam.swift` gains `endSeconds(sampleRate:)`; `WaveformView.swift`
folds its amplitude curve; `Recording.swift:253`'s untrue locality claim is corrected.

## 4 · Phases

0. **Repo hygiene**: 60 branches already merged into `main` deleted; the two stale worktrees under
   `.claude/worktrees` removed — both held pre-ADR-0043 copies of this very file that polluted every
   repo-wide `grep`.
1. The plan and the ticket.
2. **The module and its tests, with nothing calling it** — green on its own, so the decision gets
   tested before it gets moved.
3. The lane reads it.
4. The loupe and the ruler read it — the clamp fix lands here.
5. Blast radius.
6. The record: ADR-0047, plus an issue for the loupe's synchronous read.

## 5 · Behaviour that must not change

ADR-0018 has no UI test layer, so the lane's render is a review checklist, not a test.

| behaviour | why it is fragile |
|---|---|
| the lane cuts, never cross-fades, on selection change | ADR-0028's first forbid-list entry, *"a correctness matter rather than a taste one"*. **No `.motion` at or above the waveform keyed on the selection** — so `TimelineGeometry` must not become `Animatable`. |
| the ruler draws no ticks while arriving, and never rescales continuously | ADR-0031 |
| the Trim xattr is written once, at gesture end | `:205` — never per drag frame (ADR-0006) |
| the handle grab area stays the same physical size | `grabTolerance` stays 2 % of the lane, not a fixed number of seconds |
| a sub-pixel Seam draws ≥ 3 pt in the lane and at **true width** in the loupe | ADR-0010 — two rules, and `laneSeams` vs `seams` are two collections |
| the loupe crosshair is exactly `centre` | `Envelope.swift:165-170`'s contract |
| the playhead stays 1.5 pt with a 7 pt disc at the measured stops | ADR-0033 — Light ships with 5 % of margin and none spare |
| the Trimmed-away half stays `Palette.signalQuiet` | ADR-0040 — not `.grayscale` |
| the lane keeps its 168/340 pt height bounds | ADR-0023, `EditorView.swift:431-432` |

**One intentional change**: on a lane narrower than 212 pt the loupe now centres on the lane instead
of pinning to `width - 106`, which is off the leading edge below 106 pt.

## 6 · Verification

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```

**The acceptance criterion that is a grep, because it cannot be a test** — one mapping, one place:

```
grep -rn "/ width \* \|/ span \* \|visible\.lowerBound\|max(recording.duration, 0.001)" AppTape/AppTape
```

Every surviving hit is inside `TimelineGeometry.swift`.

**By hand, once**: drag both handles end to end and confirm the loupe tracks and never clips; narrow
the editor to its 960 pt floor and drag again; check the ruler's last label still sits inside the
lane; scrub the playhead to both extremes; confirm a capturing Recording still shows no ticks and no
waveform.

## 7 · Out of scope

- **The loupe's synchronous `AVAudioFile.read` per drag frame** — filed as
  [#134](https://github.com/SamWongML/macos-audio-recording/issues/134). `Envelope.swift:153-154` documents
  the held-open file cache as a deliberate design so that read stays cheap, and making it async means
  the loupe lags the handle it magnifies. This module fixes *where the box sits*; *what it shows* is
  a separate change with a real latency trade-off.
- **Unifying seconds→frames rounding** across `Recording.trimmedFrameRange` (`.rounded()`),
  `AudioPlayer` (truncation) and `loupeWindow` (`.rounded(.down)`/`.up`) — a behaviour question about
  playback and export boundaries, not a mapping duplication.
- **`Seam.swift:46-70`** — the 250 ms threshold converted to frames three times. `SeamSurfacing`'s.
- **Candidate 6** — `SourceFormat`'s four renderers, the `"—"` literals, the layout tokens.
- **Zoom.** ADR-0023 rejected it and nothing here reopens that; the module simply stops pretending
  the code has it.
