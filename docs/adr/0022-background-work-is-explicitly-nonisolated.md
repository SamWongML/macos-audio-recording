# Background work is explicitly `nonisolated`

The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which is the right default for an
app that is almost entirely UI: views, the panel, the store, the editor's models and the capture
controller are all main-actor by nature, and having to write `@MainActor` on each of them would be
noise. The cost is invisible and lands on the small minority of types that are *not* UI: **an
unannotated type is main-actor isolated, so long-running computation written to run in the background
silently comes back to the main thread.**

`LoudnessCorrectionModel` dispatched its BS.1770 loudness pass with `Task.detached(priority: .utility)`
and the detached task genuinely did detach — but `LoudnessMeter` was a plain unannotated `enum`,
therefore implicitly `@MainActor`, so the very first call out of that task hopped straight back. The
whole pass then ran on `com.apple.main-thread`: selecting a 20-minute master froze the editor for over
fifteen minutes, with clicks ignored, the playhead stopped and the accessibility tree gone (issue #80).

**The decision: every type doing work that must not run on the main actor is marked `nonisolated`
explicitly, and that annotation is load-bearing rather than decorative.** `LoudnessMeter`,
`LoudnessAnalyzer`, `Biquad`/`BiquadState`, the `LoudnessCorrection` value types that cross the
boundary, and `AudioStreamBasicDescription.interleavedFloat` all carry it. Each says why at the
declaration, so the next reader does not take it for redundancy and delete it.

The alternative was to turn `SWIFT_DEFAULT_ACTOR_ISOLATION` off for the target. Rejected: the setting
earns its keep across dozens of UI types, and paying for it with an explicit opt-out on the handful of
genuinely-background ones is the cheaper side of the trade — provided the opt-out is written down,
which is what this record is for.

## Consequences

- **The compiler finds every instance of the hop, and there was exactly one.** In Swift 5 language
  mode a nonisolated context calling a main-actor member is the warning *"main actor-isolated … cannot
  be called from outside of the actor"*. A clean build of the whole target reports each one, which is
  how the audit this ADR came from was run: `CAFMasterWriter`, `ExportEncoder`, `Envelope`/
  `EnvelopeLoader` and `SeamReconciler` all came back clean. Treat that warning as an error in review.
- **The build setting hides the size of the win.** Debug measures 120 s of stereo 48 kHz audio in
  69.3 s; Release does it in 0.84 s — **82× faster**, because Release specialises the generics the
  inner filter loop pays for. Extrapolated to a 20-minute master that is ~11.5 minutes against 8.4 s,
  so a Debug measurement of anything in this file is not evidence about shipping behaviour.
- **`Measuring…` is left as it is, with no progress bar.** The inspector's Loudness preview resolves in
  ~8 s on the longest Recording anyone realistically has and in well under a second on a typical one,
  now that it is off the main thread and the window stays live throughout. `LoudnessMeter.onProgress`
  stays — it is not unused, it drives Export's one continuous measure-then-encode bar
  ([ADR-0013](0013-loudness-is-one-clamped-gain-not-a-limiter.md)) — but the preview does not pass it.
- **A test pins it.** `theBS1770PassNeverRunsOnTheMainThread` runs the pass from a detached task and
  samples the thread from inside the read loop, so dropping `nonisolated` fails the suite rather than
  waiting to be found by someone selecting a long Recording.
- **The inverse hazard exists and is *not* addressed here.** `CaptureEngine` is unannotated, and so
  main-actor isolated, yet it runs its writer loop on a real `Thread`. Nothing hops, because same-actor
  calls need no hop, so it is silent and harmless to responsiveness — but the annotations describe the
  opposite of what happens. Correcting it means marking the capture spine `nonisolated` throughout,
  which is its own change.
