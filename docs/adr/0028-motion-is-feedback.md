---
status: accepted
---

# Motion is feedback

Issue [#88](https://github.com/SamWongML/macos-audio-recording/issues/88) asked what moves in the
editor and how. AppTape had a colour language ([ADR-0019](0019-content-is-the-colour.md)), a layout
language ([ADR-0023](0023-the-detail-pane-is-ruler-lane-brief-dock.md),
[ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md)) and a type scale, but no
stated position on motion — two written animations and a pile of framework defaults nobody chose.

**Motion is feedback: something moves only to confirm an action the user just took, or to mark a
state change they must notice. No entrances, no ambient motion.**

The rejected alternative was the rhyme with the colour rule — *motion belongs to content, chrome
never moves*. It reads well and it forbids the wrong thing: the Export control is chrome by any
reading, and its phase arriving is the single state in this window most worth noticing.

## Two stops, and no default

`Metrics.motionQuick` (`.easeOut`, 0.12 s) is direct manipulation — the thing under the cursor
answering the cursor. `Metrics.motionState` (`.easeInOut`, 0.25 s) is a change the user should notice
but did not directly cause. One duration gets one of the two wrong: 0.25 s on a Trim handle feels
like drag, and 0.12 s on an Export phase is a flicker you miss.

`motion(_:value:)` takes **no default animation**. It used to default to `.default` — a framework
spring — and four call sites took it without choosing it.

## Motion attaches to the smallest view that contains the change, never to a container

This is the operative clause, and it is not a style preference. `.animation(_:value:)` animates every
property of its subtree **including that subtree's own resolved geometry**. On a view whose position
is *derived* rather than stated, that means "animate where this view is".

The editor's open animation was this bug, and it had been read as a missing design decision. Four
`.animation(.default, value:)` sat on the Export inspector's whole `Form`
(`ExportInspector.swift`), inside a column whose x-position is not stated anywhere — it is whatever
`detailContent.frame(maxWidth: .infinity)` leaves over (`EditorView.swift`). Two of the four tracked
values changed while the window was still resolving its first layout: `editor.correction.state` goes
`.off → .measuring` on an `initial: true` onChange, and on the stop-click path
`recording.trimmedDuration` changes again when `.task { model.activate() }` re-lists the folder and
rebinds a fresh `Recording`. So the subtree interpolated from its previously-recorded geometry, which
on the first pass is the unresolved origin of the enclosing `HStack` — the top-left of the detail
pane, exactly where the column was seen to fly in from. The *seconds* were the re-trigger: `.default`
is ~0.35 s, but the fourth value fires again when the BS.1770 pass lands, each restart resuming from
the in-flight position, while `EnvelopeLoader`'s streamed main-actor publishes keep layout churning.

The animations are not the defect and neither are their durations. The scope is. Each now sits on the
smallest view containing its change: the size estimate `Text`, the correction readout, the Export
control.

One case falls out of the rule rather than being decided separately. **The normalize toggle no longer
animates anything.** What it changes is the *presence* of the Correction row, and an insertion can
only be animated from the parent — here the `Section`, whose height is derived exactly as the
column's position was. The toggle is already its own feedback.

## What must never move

An allow-list was rejected. ADR-0019 carried an exhaustive where-`Signal`-may-appear list, and
[#79](https://github.com/SamWongML/macos-audio-recording/issues/79) then made the app icon a new
`Signal` site, so the list stopped holding as written and `Palette`'s comment had to say so. A
forbid-list is the opposite shape: small, stable, and genuinely worth amending if it grows. A new
animation is legal without touching this ADR; a new forbidden case is not.

- **The waveform cuts, never cross-fades, on a selection change.** Interpolating one Recording's
  peaks into another's animates a relationship between two files that does not exist — the same
  class of untruth as the 0.5 px silence floor [#76](https://github.com/SamWongML/macos-audio-recording/issues/76)
  deleted. No `.motion` may be attached at or above the lane keyed on the selection.
- **The window's open.** An entrance is never feedback: the user has done nothing yet.
- **The ruler's labels.**
- **A Recording arriving in, leaving, or re-sorting within the Library.** The Library is a view of a
  folder ([ADR-0006](0006-the-library-is-a-folder.md)); a row animating its own arrival claims the
  app did something when the folder merely changed.

**The playhead is exempt** — a data readout, not an animation. It is a 30 Hz `Timer` publishing a
position, unanimated, and it must stay that way: a spring on a playhead lags the audio it claims to
represent. Reduce Motion governs interface motion, not media, so suppressing it would break the
feature rather than accommodate anyone. Stated because the next reader will otherwise "fix" it by
wrapping it in `.motion`.

## Two helpers, one contract each

**This supersedes ADR-0019's "Reduce Motion is the app's job and gets one helper, not four call
sites."** Its principle is untouched, and is why both helpers exist: only Liquid Glass's own morph
honours Reduce Motion automatically, so every animation the app writes must honour it itself, and a
contract that has to be remembered at each call site will be forgotten. Only the *count* changes.

One helper owned two contracts — which animation plays, and how changing text redraws — and bundling
them is what let a wrong content transition sit unnoticed at all five sites in the app.
`.motion` applied `.contentTransition(.interpolate)` unconditionally, and documented itself as
rolling digits under normal settings. **`.interpolate` does not roll digits**; it interpolates
between symbol and shape states. `.numericText()` rolls digits. The behaviour the token set was
written to provide had therefore never once happened, and it took splitting the helpers to see it.

`motion(_:value:)` swaps the animation. `textTransition(_:)` swaps the content transition and
resolves to `.opacity` under Reduce Motion, because rolling digits are motion too. What a row's text
does when it changes is an editorial choice per row; honouring Reduce Motion is one rule for the app.

## Consequences

- Nothing is added. Every state change in the editor already had the feedback it needed, so this ADR
  is a rule, two tokens, a rescoping and a helper split — and zero new animations. That is the
  correct outcome of *motion is feedback*, not a shortfall against "premium".
- The two durations are starting points measured in the running app, not derived. They are the
  numbers the ticket watched and kept.
- `.interpolate` appears nowhere in the app any more. `.numericText()` is on the size estimate, the
  one figure in the inspector that ticks rather than swaps.
