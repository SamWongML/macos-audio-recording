---
status: accepted
---

# A warning's colour belongs to its mark, not to its sentence

The Export dock's failed phase is the one place in the editor whose **text is the payload**: it names
how much space the encode needs and how much is free, and
[#104](https://github.com/SamWongML/macos-audio-recording/issues/104) spent a ticket shortening
`Try Again…` to `Retry…` so both figures would survive the line. It rendered like this:

```swift
Label(message, systemImage: "exclamationmark.triangle.fill")
    .font(.caption)
    .foregroundStyle(.orange)
```

One `foregroundStyle` over a `Label` colours the glyph **and** the title. So the sentence was orange,
at caption size, on the trailing column's scrim, and it measured **2.33 : 1 in Light** — and that
figure is from `1200 × 680` with nothing scrolled beneath the dock. #104 verified this phase at
exactly that size and checked that both figures *fit*; nobody checked whether they could be *read*.
It was found by [#114](https://github.com/SamWongML/macos-audio-recording/issues/114), which went
looking for a scrolling defect and found a colour one underneath it.

**The rule: an alarm colour applies to the mark that raises the alarm, never to the words that
explain it.** The ⚠ carries the alarm; the sentence carries the information and takes ink.

| | before | after |
|---|---|---|
| failed phase, message, Dark | 3.94 : 1 *(worst spot)* | **11.39 : 1** |
| failed phase, message, Light | 2.08 : 1 *(worst spot)* | **14.32 : 1** |
| succeeded phase, `Exported`, Dark | 7.33 : 1 | **11.68 : 1** |
| succeeded phase, `Exported`, Light | 2.13 : 1 | **14.50 : 1** |

The succeeded phase had the identical fault one function up — `.foregroundStyle(.green)` over
`Label("Exported", systemImage: "checkmark.circle.fill")` — and was only measured because #114 went
looking for it after the orange one. It takes the same split: green check, ink word.

## The marks stay under 3 : 1, and that is the bounded part of the trade

After the split, both glyphs measure below the 3 : 1 floor for a non-text mark in Light: the ⚠ at
**2.46 : 1**, the checkmark at **2.31 : 1**. They are left alone.

**The standard, so this is a rule and not three separate shrugs:** *a mark may sit under 3 : 1 only
where the text beside it carries the whole meaning at full strength.* Both qualify — the sentence
they annotate now measures 11–14 : 1 and states the entire fact, so a reader who cannot see the
colour loses emphasis and nothing else. This is the same shape as
[ADR-0009](0009-the-disk-guard-is-a-runway-clock.md)'s amber Runway trade, and it is deliberately
written as a *test* rather than a precedent, because the app now has three such marks and a fourth
added without one would be a habit.

What made the old code fail this test was not the glyph. It was that the sentence was orange too, so
the colour **was** the message; killing that is what makes leaving the glyph defensible.

## Considered options

**Darkening orange and green to custom stops clearing 3 : 1 was rejected.** It is correct by the
letter, and it would add two owned colours to a palette [ADR-0019](0019-content-is-the-colour.md)
deliberately holds at two, for marks that duplicate text already at full strength.

**Dropping the glyphs entirely was rejected**, though it would buy back width in a 276 pt pane where
#103 already lost both figures to wrapping. A `Label` with no icon in a phase that shares one
declared height with three others is a change to the dock's shape, and the shape is not what was
wrong.

## Consequences

**A third site of this fault is left in place, and ticketed rather than fixed.** `rung()` renders an
unencodable preset's plain reason ([ADR-0015](0015-an-adopted-file-is-faithful-or-refused.md)) as a
**sentence** in `Color.orange` on a row the system is simultaneously dimming. It is not fixed here
for two reasons. It could not be **measured**: every one of the 39 Recordings in the real Library is
2 ch / 48 kHz / Float32, so all four presets encode all of them and no rung ever renders its reason —
and a treatment changed at a site nobody rendered is how #104 produced the defect this ADR is
cleaning up. And unlike the two phases above, that text has **no glyph** to hand the alarm to, so
applying this rule there is not a one-line split: it is a choice between giving the rung a mark
(risking the wrap defect #103 found in this pane at this width) and letting it give up its colour and
read like the codec label beside it. That decision needs a real unencodable file on screen.

**`.tertiary` is gone from `ExportInspector`** in the same change, on
[ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md)'s rule rather than this one:
`sourceFormatLine` measured 2.27 : 1 Dark and 1.86 : 1 Light and now measures 6.46 and 5.27 as
`Color.primary.opacity(0.7)`. Measured against the rungs' own captions it reads *dimmer* than they
do, so it is still subordinate — which is what `.tertiary` was reaching for and failing to get.

Every figure here is sampled from `screencapture -x -o -l` of the Release build in both appearances
(ADR-0032).
