---
status: accepted
---

# The reason is not part of the control

[ADR-0015](0015-an-adopted-file-is-faithful-or-refused.md) makes the Export inspector promise that
*every* unusable Quality Preset rung says why, not just the effective one. `rung()` kept that promise
in the source and broke it in the render. The reason was the second `Text` of the button's label:

```swift
Text(encodability.reason ?? preset.codecLabel)
    .font(.caption)
    .foregroundStyle(encodability.isAvailable ? AnyShapeStyle(.secondary)
                                              : AnyShapeStyle(Color.orange))
    .lineLimit(2)
```

on a row carrying both `.disabled(true)` and an explicit `.opacity(0.5)`. Measured for the first time
in [#119](https://github.com/SamWongML/macos-audio-recording/issues/119), against `ZZ Probe 96k` — a
96 kHz Recording that renders three unencodable rungs at once — it came out at **1.58 : 1 in Dark and
1.22 : 1 in Light**, the worst figures this app has recorded, for the one sentence on the row that
has to be read. [ADR-0037](0037-a-warnings-colour-belongs-to-its-mark-not-its-sentence.md) named this
site and declined to fix it blind, on
[ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md)'s rule. It was right to: the
fix it would have applied is not the fix.

**The rule: a control's explanation lives outside the control, because the system dims the control
and the explanation still has to be read.**

| | before | after |
|---|---|---|
| unencodable rung, reason, Dark | **1.58 : 1** | **11.71 : 1** |
| unencodable rung, reason, Light | **1.22 : 1** | **13.02 : 1** |

Identical at `1200 × 680` and at the `960 × 656` floor, in the Release build, both appearances
(ADR-0032). The preset's name and its checkmark slot keep the dimming — they *are* the control.

## Three dimmings were stacked, and only two were in the source

The colour was the smallest of them.

1. **`Color.orange` as words.** ADR-0037's finding, unchanged: an alarm colour is unreadable as a
   sentence in Light. On its own this took the reason to 2.33 : 1 in the dock.
2. **The explicit `.opacity(0.5)`** on the rung.
3. **`.disabled()`'s own dimming of its subtree's text** — which appears nowhere in `ExportInspector`
   and is the reason this took a ticket rather than a line. Exempting the sentence from (2) alone,
   with the colour dropped for ink, recovers only **4.03 : 1 Dark / 3.01 : 1 Light**: the system's
   half is still being applied, because the text is still inside a disabled `Button`. Nothing done
   *within* the button reaches ADR-0037's band. Moving the text out reaches it immediately.

This is the same family as the mechanisms the map already records — `.secondary` is a vibrancy style,
two system colours may not differ by value, `Color.primary` is 85% ink, an authored asset renders ~10
levels dark. Each is a place where the render is not what the source says. **`.disabled()` is the
first one that is not a colour at all**: it is a *scope*, and the fix is to change what is in the
scope rather than what it is painted with.

## No fourth mark, and the test is why

ADR-0037 hands the alarm to a mark and the meaning to the words. Here there is no mark to hand it to,
and one was measured rather than assumed: with an `exclamationmark.triangle.fill` before the sentence,
the reason reached only 2.00 : 1 (the whole row still being halved) **and truncated further** — the
glyph's width pushed `this file is 96 kHz.` off the end in a 276 pt pane where all three reasons were
already truncating at `1200 × 680`. ADR-0037 asks for a *test* before a fourth mark rather than a
habit: *a mark may sit under 3 : 1 only where the text beside it carries the whole meaning at full
strength.* A mark that costs the text its ending fails that test on both halves.

What distinguishes a refusal from a codec label instead costs no width at all. **The name above it is
dimmed and the sentence is not** — an inversion that exists on no other row — and the rung states no
size.

## An unencodable rung states no size, which is ADR-0031's rule reaching a second cause

[ADR-0031](0031-a-growing-recording-states-the-engines-figures-or-nothing.md) already refuses a
confident size for an export that cannot happen, for a Recording still arriving. A rung that cannot
encode is the same category one row up: `≈ 457 KB` beside `AAC can't encode above 48 kHz` is the
inspector disagreeing with itself on a single row.

Dropping it is also what makes the sentence fit. The estimate reserved the trailing width that forced
every reason to wrap and truncate; with it gone, all three of `ZZ Probe 96k`'s reasons finish, at both
window sizes. The accessibility value still folds `size not yet known` / the estimate in for the
arriving case and is otherwise unchanged; the reason itself is `.accessibilityHidden` outside the
button, because the button already speaks it (ADR-0025 — the rung speaks once).

## Considered options

**Darkening the orange to an owned stop was rejected**, for ADR-0037's reason: it adds a colour to a
palette [ADR-0019](0019-content-is-the-colour.md) holds at two, and here it would not have worked
anyway — the `.disabled()` scope dims an owned colour exactly as it dims a system one.

**Leaving the reason inside the button at `.secondary`, full strength (5.72 / 3.81), was rejected.**
It is the codec label's own treatment, which is precisely the confusion ADR-0015 exists to prevent,
and 3.81 : 1 in Light is below the 4.5 : 1 a caption-size sentence wants when that sentence is the
only actionable thing in the pane.

## Consequences

**A disabled `.borderedProminent` Export button reads at 3.00 : 1 in Dark and 1.75 : 1 in Light**
against its own fill, measured in this same state (enabled: 4.54 : 1). That is the system's disabled
rendering of a prominent button, not anything AppTape authors, and it is reachable in three states —
a zero-length Trim, an export already running, and this one. Ticketed rather than folded in:
whether the app overrides a system control's disabled treatment is its own decision and is not about
the rungs.

**The state is now photographable and the harness records how.** `ZZ Probe 96k` is the only Recording
in the Library that renders it; a tick on a rung that cannot encode needs `defaults write
com.samwongml.AppTape com.apptape.exportPreset -string high` before launch, which makes the *sticky*
preset unavailable for this file. Both are on
[`prototype/unencodable-rung`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/unencodable-rung/tools/unencodable-rung).
