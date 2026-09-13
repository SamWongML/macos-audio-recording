---
status: accepted
---

# One run of capture accepts its world, and takes time as a parameter

`RecordingController` had grown to 427 lines and zero tests, and the second number followed from the
first: it **created** every dependency it used — four `Timer`s on `RunLoop.main`, `DispatchQueue`,
`DiskSpace`'s `statfs`, `CaptureEngine`, `FaultNotifier`, `EditorPresenter.shared`,
`NSWorkspace.shared`, `ProcessInfo` — so its interface was the whole of AppKit, Core Audio, the file
system and the clock. There was no seam anywhere, and so no test could stand anywhere. It held
ADR-0007's six ends, ADR-0008's denial inference, ADR-0009's Runway guard and ADR-0010's generation
rule, none of them verified by anything.

**The decision: the coordination of one run of capture is its own module, `CaptureRun`, which
accepts a capture builder, a free-space probe and the telling as interfaces, and takes time as
`tick(now:)`.** What is left in `RecordingController` is the shell: the presses, the `NSWorkspace`
notifications, one timer, and the single `ProcessInfo` read those need.

## Considered options

**Testing the controller as it stood** is what the missing tests would have cost, and the price is
not the test code. Every end would need a real tap, a real disk and real elapsed time: the 30-minute
Runway warning would take thirty minutes, the wedge ten seconds, and the three bring-up races cannot
be reached at all, because they turn on *when* a blocked Core Audio call returns relative to a later
press — which no amount of waiting makes deterministic.

**A reducer returning effect values**, in the shape `FaultReducer` and `RunwayGuard` already have,
was the obvious thing to reach for given they are the deep modules of this codebase. Rejected here:
a run holds a live capture for minutes and the effects are calls with return values that feed the
next decision (`stop` hands back the file *and* the reason). Turning that into a value stream means
inventing an effect language and an interpreter for it — more machinery than the four one-method
interfaces it replaces, and less readable at the call site.

**Injecting a clock protocol** rather than passing `now` was considered and is strictly worse. A
clock the run can call is a clock a test has to program; `tick(now:)` makes a thirty-minute Recording
a `for` loop and, more importantly, means there is nothing to program. It is also the shape
`FaultReducer`, `SeamReconciler` and `DenialDetector` already take, so it needed no new idea.

**Naming it `RecordingSession`** was the first instinct and is wrong on this project's own terms:
`CONTEXT.md` lists *session* under _Avoid_ for **Recording**. `CaptureRun` borrows the glossary's own
phrase — a Recording is "captured in one continuous run from start to stop" — and names the
coordination of one such run.

## Consequences

**Four interfaces, and two conformances each is the bar for one to exist.** `Capturing` and
`CaptureBuilding` over `CaptureEngine`; `RunwayProbing` over `DiskSpace`; `RunTelling` over
`FaultNotifier` and `EditorPresenter`. Each has exactly one production adapter and one test double,
and none of them carries a decision — they are forwarding shells, so the policy stays in one place
and the untestable part stays thin. An interface here that ever acquires a second production
conformance, or a branch of its own, has stopped being a seam and become a layer.

**The generation rule is one phase transition, not eight guards.** ADR-0010 requires that a slow or
cancelled bring-up never attach to a later attempt. That was `generation += 1` and `guard gen ==
generation, isRecording` hand-copied to eight sites, with nothing verifying the eight agreed — and
two variables, `generation` and `isRecording`, that had to be kept in step by hand. It is now one
`Phase` enum carrying the `Attempt` that owns it, and one `isLive(_:)`. A return to idle invalidates
every in-flight attempt *by construction*: `.idle` carries no attempt and a later press mints a fresh
id, so there is no counter left to forget to bump. `isRecording` is read off the phase, so it cannot
drift from it. Verified by mutation: making `isLive(_:)` return `true` unconditionally fails four of
the five race tests.

**The run reads no clock.** `ProcessInfo.systemUptime` appears once, in the shell, and `sincePress`
is computed there from the `pressedAt` the run publishes. This is the property the seam turns on: a
`ProcessInfo` call put back inside `CaptureRun` silently removes a test's ability to drive it, and
nothing would fail to say so. It is worth defending in review.

**Four timers became one tick, and the cadences became arithmetic.** The shell ticks at 20 Hz — the
meter's rate, the fastest thing the run does — and the menu bar's 4 Hz clock, the Runway's 5 s poll
and the wedge timeout are all `now - last >= interval` inside the run. **The 4 Hz clock is a
decision, not a detail**: `MenuBarController` reads `elapsed` inside `withObservationTracking`, so
publishing it at the meter's cadence would quintuple status-item churn, while the meter is read only
by the open panel. That is why there were two timers, and it is now a test rather than a comment.

**One behaviour changed, deliberately.** The Runway's first poll used to happen synchronously inside
`attach`; it now happens on the next tick, within 50 ms. The reason it was immediate — so amber
reflects the tap's real byte rate rather than the pre-tap nominal estimate before anyone reads it —
survives a 50 ms delay intact.

**The capture spine is now honestly `nonisolated`, which closes ADR-0022's open item.** That ADR
recorded the inverse hazard and deferred it: `CaptureEngine` was unannotated, and so main-actor
isolated, yet its whole life is a real `Thread`. Marking it `nonisolated` made the compiler name
every callee it drives — `ProcessTap`, `CAFMasterWriter`, `AudioRingBuffer`, `TimestampRing`,
`CAProperty`, `LibraryLocation`, `RecordingMetadata`, `LevelMeter`, `CaptureReducer`,
`DenialDetector`, `Trim`, and the `Double.clamped` extension `Trim` reaches for — each of which now
says why at its declaration. The seam is what made this natural rather than merely possible:
`CoreAudioCapture` is the main-actor adapter that stands between the engine and the rest of the app,
so the boundary is a line in the type system instead of a convention.

**The hop belongs to the adapter, not the run.** `CaptureHooks` carries main-actor calls;
`CoreAudioCaptureBuilder` wraps each in a `Task` before handing them to the engine, exactly as it
already owns the teardown dispatch. The run does not know the writer thread is a different thread —
which is both the right layering and what lets a test play the writer thread's part in a straight
line, with no `await` and no yielding.

**The views were left alone.** All five still read `RecordingController.shared`; observation tracks
through the shell's computed forwards onto the run's own stored properties, so nothing re-renders
more often than it did. Moving them onto an injected interface is a separate change with a separate
argument.

**31 tests where there were none**, covering the five bring-up races, the wedge's two halves, the six
ends and what each tells the user, the Runway guard composed against a settable `statfs`, and the
cadence split. Eleven coordinating modules still have no seam and no tests; the argument for each of
them is this one.

Prompted by the architecture review of 12 September 2026, candidate 1.
