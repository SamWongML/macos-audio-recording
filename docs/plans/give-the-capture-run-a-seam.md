---
status: proposed
source: architecture review, 12 Sep 2026 — candidate 1, "Give a Recording session a seam"
---

# Give the Capture Run a seam

`RecordingController` is 427 lines with no tests, and it cannot have any: it **creates** every
dependency it uses, so its interface is the whole of AppKit, Core Audio, the file system and the
clock. Under that sit the two facts this plan is really about — ADR-0010's generation rule is one
line hand-copied to **eight** sites with nothing verifying they agree, and the module's cadences are
four `Timer`s on `RunLoop.main`, so no end, race or threshold can be exercised without waiting in
real time for a real tap.

The change is one seam and one invariant: a `CaptureRun` module that accepts a capture adapter and
takes time as a parameter, with the generation rule expressed once as a phase transition rather than
eight guards.

---

## 0 · The name, and why it is not `RecordingSession`

The review calls the new module `RecordingSession`. `CONTEXT.md` lists `session` under _Avoid_ for
**Recording** ("_Avoid_: Take, clip, session, capture"), and `docs/agents/domain.md` says not to
drift to synonyms the glossary explicitly avoids.

This plan uses **`CaptureRun`**, borrowing the glossary's own phrase for a Recording — "captured in
one continuous run from start to stop". It names the coordination of one run of capture, which is
what the module is, without re-spending a word the glossary already spent.

If the reviewer prefers `RecordingSession`, the trade is a `CONTEXT.md` amendment striking `session`
from Recording's avoid-list. Do that deliberately or not at all.

---

## 1 · Target shape

```
                     before                                        after

RecordingController · 427 lines · 0 tests       RecordingController · ~95 lines · the shell
  Timer ×4 / RunLoop.main          created        one Timer → run.tick(now:)
  DispatchQueue.global             created        NSWorkspace observers
  DiskSpace.statfs                 created        ProcessInfo.systemUptime  ← the only clock read
  CaptureEngine → Core Audio       created        forwards for the five views
  FaultNotifier → UN centre        created                   │
  EditorPresenter.shared           created                   ▼
  NSWorkspace.shared               created        CaptureRun · @Observable · the tested tier
  ProcessInfo.systemUptime         created          start(_:now:) · stop(now:) · end(_:now:)
                                                    endForQuit() · tick(now:)
                                                               │
                                       ┌───────────────┬───────┴───────┬──────────────┐
                                 CaptureBuilding   Capturing     RunwayProbing    RunTelling
                                       │               │               │              │
                              CoreAudioCaptureBuilder  │      LibraryVolumeProbe  ShellTelling
                                 FakeCaptureBuilder  FakeCapture  StubRunway       TellingLog
```

Two conformances per interface and no more — the production adapter and the test double. That is the
bar each interface has to clear to exist, and all four clear it.

---

## 2 · The four interfaces

New file **`AppTape/AppTape/CaptureAdapters.swift`** — protocols and production adapters together, so
the seam is one file to read.

```swift
/// What a finalized capture hands back: the file, if a Recording was made at all (nil is
/// arm-then-never-play, ADR-0016), and the reason the Recording ended *itself*, which wins over
/// the caller's (ADR-0007).
struct CaptureOutcome {
    var result: CaptureResult?
    var selfEndReason: RecordingEndReason?
}

/// The three callbacks a capture makes while it runs. Handed over at bring-up, before the writer
/// thread starts, so a denial inferred before the capture is attached is still delivered.
struct CaptureHooks {
    var onDenialInferred: @Sendable () -> Void
    var onMasterCreated: @Sendable (URL) -> Void
    var onEnded: @Sendable (RecordingEndReason) -> Void
}

/// One live capture, as the run sees it. Exactly two conformances — `CoreAudioCapture` in the app,
/// `FakeCapture` in the suite — which is the whole reason the protocol exists.
@MainActor
protocol Capturing: AnyObject {
    /// Master duration so far; 0 through the armed window (ADR-0016).
    var elapsed: TimeInterval { get }
    /// The last chunk's linear peak. Exactly 0 for a dead tap (LevelMeter).
    var currentLevel: Float { get }
    /// The master's on-disk byte rate — the Runway divisor (ADR-0009).
    var bytesPerSecond: Double { get }
    /// Stop, drain the tail, close the file — **off the main thread**, because it blocks
    /// (ADR-0003) — then hand the outcome back on the main actor.
    func stop(then: @escaping @MainActor (CaptureOutcome) -> Void)
    /// Stop and finalize **on this thread**: the quit path, where the process is about to exit and
    /// the Seams xattr and the tail must be secured before `applicationWillTerminate` returns.
    func stopNow() -> CaptureResult?
    /// Tear down and remove any file — the denial path (ADR-0008).
    func discard()
}

/// Brings a capture up. Blocking is the point: tap creation can sit ~90 s behind the TCC prompt
/// (ADR-0008), so production builds off the main thread and calls back on the main actor.
@MainActor
protocol CaptureBuilding {
    func build(source: Source, hooks: CaptureHooks,
               then: @escaping @MainActor (Result<any Capturing, any Error>) -> Void)
}

/// The Runway's one input (ADR-0009). Nil means *cannot verify*, never *no space* — an
/// unverifiable volume neither refuses a press nor ends a Recording.
@MainActor
protocol RunwayProbing {
    func freeBytesForLibraryVolume() -> Int64?
}

/// Everything the run says to the world: the notification channel and the editor window
/// (ADR-0009/0010). One interface, so the suite reads back *what was told* instead of watching a
/// notification centre.
@MainActor
protocol RunTelling {
    func requestNotificationAuthorizationOnce()
    func tell(end reason: RecordingEndReason, recordingURL: URL)
    func tellRunwayLow()
    func openEditor(selecting url: URL)
}
```

Production adapters, in the same file, each a forwarding shell with no decisions in it:

| Adapter | Wraps | Notes |
|---|---|---|
| `CoreAudioCapture` | one `CaptureEngine` | owns the `DispatchQueue.global` hops that are inline in the controller today |
| `CoreAudioCaptureBuilder` | `CaptureEngine.init` | the off-main bring-up, and the hook plumbing |
| `LibraryVolumeProbe` | `DiskSpace.freeBytesForLibraryVolume()` | |
| `ShellTelling` | `FaultNotifier` + `EditorPresenter.shared` | the only place those two singletons are named |

---

## 3 · The generation invariant, stated once

Today ADR-0010's rule — a slow or cancelled bring-up must not attach to a later attempt — is
`generation += 1` / `guard gen == generation, isRecording` repeated across eight sites. Replace the
pair of variables (`generation`, `isRecording`) with one value that cannot disagree with itself:

```swift
/// One press's attempt at capturing. Minted at `start`, carried by every callback that press can
/// produce, and never reused.
private struct Attempt: Equatable { let id: Int }

private enum Phase {
    case idle
    /// Pressed; the capture is being built. May sit here ~90 s behind the TCC prompt (ADR-0008).
    case bringingUp(Attempt, pressedAt: TimeInterval)
    /// Built and attached. The master may or may not have begun (ADR-0016).
    case capturing(Attempt, any Capturing, pressedAt: TimeInterval)

    var attempt: Attempt? { … }
}

/// **The generation rule, stated once** (ADR-0010). Every callback a bring-up can produce — the
/// built capture, an inferred denial, the master's creation, a self-end, the wedge timeout — comes
/// through here first, and one for an attempt that is no longer live is dropped. A return to idle
/// invalidates every attempt in flight *by construction*, because `.idle` carries no attempt and a
/// later press mints a fresh id: there is no counter left to forget to bump.
private func live(_ attempt: Attempt) -> Phase? {
    guard phase.attempt == attempt else { return nil }
    return phase
}
```

`isRecording` becomes `phase != .idle` — a derived fact rather than a second source of truth the
eight guards had to keep in step with the counter.

### The eight sites, after

| today | after |
|---|---|
| `start(_:)` — `generation += 1; let gen = generation` | `phase = .bringingUp(mintAttempt(), pressedAt: now)` |
| `onMasterCreated` — `guard gen == …, isRecording` | `guard live(attempt) != nil` |
| `onEnded` → `finalize(reason:generation:)` | `guard live(attempt) != nil` |
| `finalize(_:_:)` — `guard gen == …, isRecording` | one funnel, one guard |
| `attach(_:generation:)` — `guard gen == …, isRecording` | `guard live(attempt) != nil else { orphan(capture) }` |
| `handleDenial(_:)` — `guard gen == …, isRecording` | `guard live(attempt) != nil` |
| `abandon(_:)` — `guard gen == …, isRecording` | `guard live(attempt) != nil` |
| `returnToIdle()` — `generation += 1` | `phase = .idle` |

Eight hand-repeated agreements become one function with one call shape, and §5's race tests are what
verifies it.

---

## 4 · Time as a parameter: four timers become one tick

`RecordingController` runs four `Timer`s (clock 4 Hz, meter 20 Hz, Runway 5 s, wedge one-shot). They
become four intervals over one `now`, the way `FaultReducer` already takes time:

```swift
/// The single clock. The shell ticks at 20 Hz — the meter's cadence — and every other cadence is
/// arithmetic over `now`, so the suite drives a 30-minute Recording in a `for` loop.
func tick(now: TimeInterval) {
    switch phase {
    case .idle:
        return
    case .bringingUp(let attempt, let pressedAt):
        // The wedge (ADR-0010): armed only *after* the first successful capture, because the first
        // bring-up may legitimately block ~90 s behind the TCC prompt and a number would murder it.
        if hasCompletedACapture, now - pressedAt >= Self.wedgeTimeout { abandon(attempt) }
    case .capturing(_, let capture, _):
        sampleLevel(from: capture)                    // every tick — 20 Hz
        publishElapsed(from: capture, now: now)       // every 0.25 s
        pollRunway(capture: capture, now: now)        // every 5 s
    }
}
```

Two cadence rules are load-bearing and must be preserved, not merely re-implemented:

- **`elapsed` publishes at 4 Hz, not 20 Hz.** `MenuBarController.trackRecorder` reads `elapsed`
  inside `withObservationTracking`, so publishing it at the meter's cadence would quintuple
  status-item churn. The meter, by contrast, is read only by the open panel and may tick at 20 Hz —
  that separation is why there are two timers today, and `now - lastElapsedPublishedAt >= 0.25` is
  what carries it over. **This becomes a test.**
- **The Runway's first poll is prompt.** Today `attach` calls `evaluateRunwayGuard()` directly so
  amber/end reflect the tap's real byte rate rather than the nominal pre-tap estimate. After the
  change, attach sets `lastRunwayPollAt = nil` and the *next* tick polls — a ≤50 ms delay, written
  down here so it is a decision rather than a drift.

`sincePress` stays a clock read, but in the shell: `CaptureRun` publishes `pressedAt` and
`RecordingController` computes `pressedAt.map { ProcessInfo.processInfo.systemUptime - $0 }`. **The
run never reads a clock.** That is the property the whole seam turns on, and it is worth stating at
the declaration so nobody re-introduces a `ProcessInfo` call inside it.

---

## 5 · Implementation phases

Each phase is one commit and leaves the app building and the suite green.

### Phase 1 — the interfaces and the production adapters
*New:* `CaptureAdapters.swift`. *Changed:* `CaptureEngine.swift` (`CaptureResult: Sendable`).

Write the four protocols and the four production adapters. Nothing consumes them yet; the app is
unchanged. `CoreAudioCapture.stop(then:)` and `.stopNow()` are lifted verbatim from
`RecordingController.finalize` and `.endForQuit` — the dispatch moves, the code does not change.

**Check:** builds; suite green; `RecordingController` untouched.

### Phase 2 — `CaptureRun`, the state machine
*New:* `CaptureRun.swift` (~250 lines).

Move, verbatim where possible, from `RecordingController`: the published state, `start`, the disk
start-decision, the hook closures, `attach`, `finalize`/`didFinalize`, `handleDenial`, `abandon`,
`returnToIdle`, `sampleLevel`, `resetMeter`, `evaluateRunwayGuard`, `elapsedText`, `isCapturing`,
`isStillArriving`, `hasFirstSound`. Then apply §3 (phase enum, one guard) and §4 (tick).

Keep every doc comment. They carry the ADR citations and they are why the module is readable; a move
that drops them costs more than the move gains.

Two things do **not** move — they are the shell's: `installLifecycleObservers` (NSWorkspace) and the
`Timer`/`RunLoop` plumbing.

**Check:** builds; nothing references `CaptureRun` yet.

### Phase 3 — `RecordingController` becomes the shell
*Changed:* `RecordingController.swift` (427 → ~95 lines).

```swift
@MainActor @Observable
final class RecordingController {
    static let shared = RecordingController()
    let run: CaptureRun
    private var clock: Timer?

    init(run: CaptureRun = CaptureRun(capture: CoreAudioCaptureBuilder(),
                                      runway: LibraryVolumeProbe(),
                                      telling: ShellTelling())) { self.run = run }

    // The five views' surface, forwarded. Observation tracks through a computed property, so a view
    // reading `recorder.isRecording` registers on the run's stored property and nothing re-renders
    // more often than it did.
    var isRecording: Bool { run.isRecording }
    var elapsed: TimeInterval { run.elapsed }
    …
    var sincePress: TimeInterval? { run.pressedAt.map { ProcessInfo.processInfo.systemUptime - $0 } }

    func start(_ source: Source) { run.start(source, now: uptime); if run.isRecording { startClock() } }
    func stop()        { run.stop(now: uptime) }
    func endForSleep() { run.end(.sleep, now: uptime) }
    func endForQuit()  { run.endForQuit() }
    func installLifecycleObservers() { … }   // unchanged

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func startClock() {
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.run.tick(now: self.uptime)
                // The run may have ended itself — a fault, the guard, a denial — so the clock
                // follows the run's state rather than being stopped by each end's own path.
                if !self.run.isRecording { self.stopClock() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }
}
```

**No view changes.** The five views keep reading `RecordingController.shared`; review candidate 3 is
what moves them onto an injected interface, and reviewing the two together helps neither.

**Check:** builds; suite green; **and one real recording end to end** — press record, make a sound,
stop, the editor opens. The suite cannot yet cover this tier, which is the whole point of the change,
so this phase is verified by hand exactly once.

### Phase 4 — the test doubles
*New:* `AppTape/AppTapeTests/CaptureDoubles.swift`.

```swift
/// A capture that never touches Core Audio: the test sets what it reports and reads back what was
/// asked of it. The bring-up is the interesting half — it completes when the test says so, which is
/// what makes ADR-0010's races expressible at all.
@MainActor final class FakeCapture: Capturing {
    var elapsed: TimeInterval = 0
    var currentLevel: Float = 0
    var bytesPerSecond: Double = 8 * 48_000
    var outcome = CaptureOutcome(result: nil, selfEndReason: nil)
    private(set) var stopCount = 0, stopNowCount = 0, discardCount = 0
    …
}

@MainActor final class FakeCaptureBuilder: CaptureBuilding {
    private(set) var builds: [(source: Source, hooks: CaptureHooks)] = []
    /// Hand back a capture now — the ordinary bring-up.
    func finish(with capture: FakeCapture = FakeCapture())
    /// Fail the bring-up — `ProcessTap` threw.
    func fail(_ error: any Error = TapError.failed)
    /// Hand nothing back at all — the wedge.
    func stall()
}

@MainActor struct StubRunway: RunwayProbing    // a settable Int64?, nil included
@MainActor final class TellingLog: RunTelling  // appends an enum per call; tests assert on the array
```

### Phase 5 — the tests
*New:* `AppTape/AppTapeTests/CaptureRunTests.swift`. In the suite's existing idiom: Swift Testing, a
doc comment naming the ADRs, `#expect`, no real file unless the case needs one.

**The generation rule (§3) — five races nothing verifies today**

1. A second press during bring-up returns to idle, and the first attempt's capture, arriving late, is
   **orphan-stopped and never attached** (`stopCount == 1`, `run.isRecording == false`).
2. A denial arriving *before* attach still raises `permissionRecovery`; the later attach orphan-stops
   its capture. (The gap ADR-0008's 3 s window leaves open, and why `handleDenial` may not depend on
   `attach` having run.)
3. A denial for a stale attempt changes nothing.
4. `onMasterCreated` for a stale attempt does not set `capturingURL`.
5. A self-end (`onEnded`) for a stale attempt does not finalize a second time.

**The wedge (ADR-0008/0010)**

6. Before any successful capture, ticking 90 s past the press does **not** abandon — bring-up is
   cancellable, not timed, so a human at the TCC prompt is never murdered by a number.
7. After a completed capture, ticking past 10 s abandons and returns to idle.
8. A capture attaching at 9.9 s disarms the wedge; ticking on to 60 s does nothing.

**The six ends (ADR-0007/0010)**

9. `.userStopped` → authorization requested once, editor opened, nothing told.
10. `.quit` → `stopNow()` called (synchronously), nothing told, nothing opened.
11. `.diskGuard`, `.recoveryExhausted`, `.formatMismatch`, `.sleep` → `tell(end:recordingURL:)` with
    that reason, and the editor **not** opened directly.
12. The capture's own reason wins over the caller's: a `.sleep` stop on a capture that already ended
    itself `.diskGuard` tells `.diskGuard`.
13. Arm-then-never-play (`result == nil`) tells nothing, opens nothing, and leaves
    `hasCompletedACapture` false.
14. A completed Recording sets `hasCompletedACapture` — including one a *fault* ended, which is what
    arms the wedge for the next press.

**The Runway guard, composed (ADR-0009) — the math stays in `RunwayGuardTests`**

15. A press below the 2 GB floor is refused: `startRefusal` set, `permissionRecovery` cleared, and
    **no bring-up started**.
16. A press inside the 3-hour tier begins amber rather than flashing nominal first.
17. The guard polls every 5 s of ticks and not on every tick.
18. Crossing 30 minutes tells `runwayLow` exactly once.
19. Reaching the floor ends the Recording as `.diskGuard`.
20. An unverifiable volume (`nil`) neither refuses a press nor ends a running Recording.

**Cadence and meter**

21. `elapsed` publishes at 4 Hz when ticked at 20 Hz (the menu-bar churn rule, §4).
22. `elapsedText` is `00:00` / `01:23` / `1:02:03`. *(Deliberately **not** `Format.time` — ADR-0027
    reserves the transport's widest readout; the two formatters differ on purpose.)*
23. The meter resets at each start, so a new Recording inherits no tail.
24. A dead tap (level 0) flattens the meter rather than freezing it at its last live value.
25. `elapsed` sits at 0 through the armed window (ADR-0016), so the clock reads `00:00`.

**The two `Recording`-shaped cases**

26. `isCapturing` / `isStillArriving` are true for the growing master and false for another
    Recording. These need a real `Recording`, so they need a real CAF via `AudioFixtures` — the one
    expensive corner of the new file, and exactly what review candidate 2 removes. Write them; delete
    the fixture when `Recording` gains a memberwise init.

### Phase 6 — the capture spine becomes honestly `nonisolated` (ADR-0022's open item)
*Changed:* `CaptureEngine.swift`, and whatever the compiler names.

ADR-0022 records the inverse hazard and defers it: "`CaptureEngine` is unannotated, and so
main-actor isolated, yet it runs its writer loop on a real `Thread` … Correcting it means marking the
capture spine `nonisolated` throughout, which is its own change." This is that change's natural home,
because Phase 1 puts a `@MainActor` adapter in front of the engine and the boundary is now explicit.

Method, which is ADR-0022's own: mark `CaptureEngine` `nonisolated`, build the target clean, and fix
every *"main actor-isolated … cannot be called from outside of the actor"* the compiler reports —
likely `ProcessTap`, `CAFMasterWriter`, `AudioRingBuffer`, `TimestampRing`, `CAProperty`,
`LibraryLocation`, `RecordingMetadata` and the reducers it drives, several of which
(`RunwayGuard`, `RecordingEndReason`) already carry the annotation. The target builds clean today —
verified, zero Swift warnings — so every warning this phase produces is one it caused, which is what
makes the audit tractable.

**This phase is deliberately last and separately revertable.** If the cascade runs wider than the
capture spine, drop it and keep the seam; the seam does not depend on it.

### Phase 7 — the record
*New:* `docs/adr/0043-….md`. *Changed:* `docs/adr/0022-…` (amendment), `CONTEXT.md` (only if §0 is
reopened).

One ADR covering what is genuinely a decision rather than a refactor:

- the run takes its world as four adapters, and two conformances each is the bar for one to exist;
- **time arrives as `tick(now:)`** — the run reads no clock, and the shell owns `ProcessInfo`;
- the generation rule is a phase transition, not a counter plus a flag;
- the 4 Hz / 20 Hz split is a menu-bar churn decision, not an implementation detail;
- ADR-0022's open item is closed by Phase 6 — or explicitly left open, if Phase 6 is dropped.

---

## 6 · Behaviour that must not change

The suite cannot yet catch a regression in this tier — that is the condition being fixed — so this
list is the review checklist for Phases 2 and 3.

| Behaviour | Why it is fragile |
|---|---|
| `elapsed` publishes at 4 Hz | 20 Hz would quintuple `MenuBarController`'s status-item churn |
| The meter publishes at 20 Hz and the menu bar does not observe it | the reason there are two timers today |
| `endForQuit` finalizes **synchronously** | `applicationWillTerminate` must not return before the CAF closes and the Seams xattr is written |
| A denial before `attach` still raises recovery | the gap ADR-0008's 3 s window leaves open |
| A refused press (below the floor) starts no bring-up and clears `permissionRecovery` | the panel carries at most one blocking reason (ADR-0009) |
| A denial clears `startRefusal` | the same rule, other direction |
| An orphaned capture is stopped **off-main** | teardown blocks (ADR-0003) |
| Amber is pre-seeded at start from the nominal rate | ADR-0009: no green flash before the first real poll |
| `hasCompletedACapture` is set by a capture a *fault* ended, not only a clean stop | it is what arms the wedge next time |
| Nothing about permission is persisted | ADR-0008 — `hasCompletedACapture` is in memory only |

## 7 · Verification

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```

Plus, once, by hand after Phase 3: record → sound → stop → the editor opens on the new Recording;
record → stop with no sound → nothing opens; record → press again during bring-up → returns to idle.

The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so new files under `AppTape/AppTape/`
and `AppTape/AppTapeTests/` join their targets with no project-file edit.

## 8 · Out of scope

- **Views reaching through to singletons** (review candidate 3). Phase 3 deliberately leaves the five
  views on `RecordingController.shared`.
- **`Recording` as a plain value** (candidate 2). It would delete the one fixture-dependent corner of
  the new test file (§5, test 26) and is the better *first* change overall — but it blocks nothing
  here.
- Anything inside `CaptureEngine`'s writer loop. The seam goes **under** the controller and **over**
  the engine; the realtime and writer halves are untouched but for Phase 6's annotations.

## 9 · Size

| Phase | Files | Net lines |
|---|---|---|
| 1 · interfaces + production adapters | +1 | +180 |
| 2 · `CaptureRun` | +1 | +250 |
| 3 · shell | ~1 | −330 |
| 4 · doubles | +1 | +120 |
| 5 · tests | +1 | +450 |
| 6 · `nonisolated` spine | ~8 | ~±20 |
| 7 · ADR | +1 ~2 | +90 |

Roughly +780 lines, of which 570 are tests and doubles, against a 427-line module that has none — and
12 coordinating modules that between them have none either. This is the first one to get a seam; the
argument for the other eleven is the same argument.
