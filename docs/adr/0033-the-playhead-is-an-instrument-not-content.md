---
status: accepted
supersedes: "ADR-0019's playhead entry on the exhaustive `Signal` site list"
amends: "ADR-0019's *nothing gets a custom shadow*"
---

# The playhead is an instrument, not content

[ADR-0019](0019-content-is-the-colour.md) put the playhead on the exhaustive list of places
`Signal` may appear, beside the waveform peaks. [#79](https://github.com/SamWongML/macos-audio-recording/issues/79)
then chose `Signal` and `Signal Muted` to be *"deliberately close enough not to fight across a
lane"*. Eleven tickets later the after-picture measured what those two decisions produce where they
meet ([#103](https://github.com/SamWongML/macos-audio-recording/issues/103), finding 7): the
playhead and the peaks are **the identical RGB triple**, and nowhere in the lane does the playhead
reach the 3 : 1 floor for a non-text component.

Re-measured on a fresh Release build over loud continuous material — the 1:30 Spotify Recording, at
`1200 × 680`, in **both** appearances, which finding 7 had not done:

| lane fill | Dark | Light |
|---|---|---|
| peaks (`Signal`) | **1.00 : 1** | **1.00 : 1** |
| body (`Signal Muted`) | 1.49 : 1 | **1.23 : 1** |
| lane ground | 2.22 : 1 | 6.12 : 1 |

Light was never looked at and is the worse half: its body contrast is 1.23 where Dark's is 1.49.
Of 311 rows sampled down the playhead in Dark, 143 sat on peaks of exactly its own colour.

## The decision

**The playhead leaves `Signal`. It is a transport readout drawn *over* the audio, not audio.**

This **corrects ADR-0019 rather than excepting it.** That ADR's own prose says *"The system accent
marks what the user has selected; indigo marks the audio and the Trim."* The peaks are the audio.
The Trim handle is the Trim. The playhead is neither — it sat on the exhaustive site list without
ever matching the principle the list was enumerating. `Palette.swift` states the test as *"is this
pixel captured audio?"*, and the playhead has always failed it.

The app already contained the finished proof: **the loupe's crosshair is the same object** — a
1.5 pt "you are here" line over the same `WaveformShape` in the same two stops — and it has been
`.primary` and legible from the start.

Two consequences follow, and both are worth stating because both were nearly missed:

- **#79's "deliberately close enough not to fight" stops being a liability.** After this, nothing
  indigo is ever asked to show against something else indigo.
- **The active Trim handle keeps `Signal`.** The broader rule — *instruments leave `Signal`* —
  was rejected: the Trim is the other half of what indigo is *for*, and the handle has never had
  the contrast problem, being under the cursor, 5 pt rather than 3, and carrying a
  `.background`-coloured chevron.

## The ink is the appearance's ink, not `.primary` — and that is the expensive half

Built first as `Color.primary` at an opacity, exactly as the decision was written, and **measured
on the running app, where it failed in both appearances**: 3.13 : 1 against the peaks in Dark and
2.93 : 1 in Light, against predictions of 3.74 and 3.17.

`Color.primary` is `labelColor`, which is **85% ink, not ink**. That last 15% is the entire margin.
This is [ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md) repeating one level
down: `.primary` reads like a physical value and is still a name off the palette, and the thing
that ate it was again a property of the destination — how the token resolves — not of the choice.

So the stops are white and black outright, at measured opacities, and **they are asymmetric because
the lane is**:

| | ink | peaks | body | ground |
|---|---|---|---|---|
| **Dark** | white @ **0.75** | 4.07 : 1 | 5.71 : 1 | 8.02 : 1 |
| **Light** | black @ **1.0** | 3.17 : 1 | 3.92 : 1 | 19.43 : 1 |

- **Dark is subordinated, because it can afford to be.** Full strength measures 13.0 : 1 against the
  lane ground, which makes the playhead the brightest thing in a lane whose whole premise is that
  the *audio* is the loud thing. 0.75 buys that back to 8.0 and still clears the binding fill — the
  peaks — at 4.07.
- **Light is not subordinated, because no subordination exists to spend.** The light `Signal` peaks
  render dark, `(77, 75, 202)`, so black over them is **3.16 : 1 at full strength and there is
  nothing better**: solving the three fills together admits only inks below L 0.003, and 0.9 alpha
  already drops the peaks to 3.02. White is not the escape — 6.6 : 1 on the peaks, but **1.10 : 1
  on the near-white lane ground**.

**Light therefore ships with 5% of margin and no more available.** If the light `Signal` stop ever
darkens, the playhead fails and it is `Signal` that has to move, not this.

The disc at the lane's top follows the line to the same ink. It sits above the lane, where peaks —
capped at 88% of half-height — never reach, so it never had the line's problem; but a `Signal` disc
on a `.primary` line would read as two marks rather than one.

## Also decided here

**The floor is 3 : 1 and no colour-only trade is booked.** [ADR-0009](0009-the-disk-guard-is-a-runway-clock.md)
books one, for the amber Runway glyph, and it is affordable there **because a textual follow-up is
guaranteed at 30 minutes**. A playhead the user cannot find has no follow-up anywhere: the
transport's clock says *when*, never *where*.

**The active Trim handle's `shadow(radius: 3)` is permitted, and ADR-0019 is amended rather than
reversed** — the same shape as ADR-0025's amendment under ADR-0032. It predates the token set and
was a live contradiction of *"Nothing gets a custom shadow"* on `main`. It does real work: it lifts
the handle off the waveform for the one moment the handle is `Signal` over `Signal`. The ADR's rule
is about inventing an elevation *system*; a single mark separating itself from the field it is
dragged across is not one. Deleting it silently would have been the tidy-up-retires-a-decision
mistake [#77](https://github.com/SamWongML/macos-audio-recording/issues/77) already caught once.

**The loupe's crosshair is deliberately left at full-strength `.primary`.** It appears only while a
handle is under the hand, over its own material and its own *normalised* window — a different
surface, which is the whole point of ADR-0032. It is not covered by the stops above.

## What is not verified

The Increase Contrast branch — Dark giving its 0.75 back — is **stated, not measured.**
`NSAppearance(named: .accessibilityHighContrastDarkAqua)` assigned to `NSApp.appearance` does not
move `effectiveAppearance`, and `\.colorSchemeContrast` is get-only in `EnvironmentValues`, so the
setting cannot be forced on this machine ([#103](https://github.com/SamWongML/macos-audio-recording/issues/103)).
`colorSchemeContrast` is *read* correctly; what is unproven is the rendered result.
