# PROTOTYPE — Level controls: normalization, Gain, and the readout (issue #25)

Throwaway. How the Loudness correction and the manual Gain appear in the editor, and what
adjusting the level *feels* like — with real audition, because [#25](https://github.com/SamWongML/macos-audio-recording/issues/25)
says the check is playback: what you hear must be what you Export. Not production code.

```sh
./run.sh   # builds, signs, launches. ⌘Q quits.
```

Two windows: the **editor** (waveform + Trim on the left, the permanent Export inspector on
the right — the #7 frame) and a small floating **switcher**.

- The switcher's **A / B** segmented control swaps the one thing this prototype is about: the
  **Level section treatment**.
- The switcher's **Recording** popup jumps between the five fixtures.
- **space** plays the Trim, looping — *auditioning Loudness + Gain*. **[** / **]** pick a Trim
  handle, **← / →** nudge it (**⇧** = 1 s). Or just drag the handles.
- The **Normalize loudness** toggle is in both the switcher and the inspector (it's app-wide).

**First run writes ~45 MB of fixtures into `~/Music/AppTape-LevelControls`** — a folder of its
own, so it never mixes with the editor-window prototype's 28 in `~/Music/AppTape`. Delete with:

```sh
rm -rf ~/Music/AppTape-LevelControls
```

## The five fixtures are the five outcomes

Each is engineered so the ADR-0013 correction lands on a different case. Turn **Normalize
loudness** on and watch the readout; the switcher's bottom line prints the raw
`measured LUFS, peak dBTP → correction` so you can see the machinery.

| fixture | measured | true peak | correction | the case |
|---|---|---|---|---|
| **Quiet podcast** | −22 LUFS | −13 dBTP | **+6.2 dB** | clean amplify — the happy path, no caption |
| **Loud master** | −10 LUFS | −2 dBTP | **−5.9 dB** | clean attenuate — uncapped, no caption |
| **Phone call** | −41 LUFS | −27 dBTP | **+12.0 dB** | hits the **+12 cap** · *noise floor* caption |
| **Peaky mix** | −20 LUFS | −3 dBTP | **+0.2 dB** | wants +6, the **−3 dBTP ceiling** stops it short |
| **Silent room** | — | — | **—** | **undefined** — 0 dB, and Export still completes |

Trimming changes the reading live: the Quiet podcast has a louder phrase 12–20 s in, so
trimming onto it needs less boost. That live update is real — the whole file is measured once
(a background pass, hence the brief *Measuring…*), then a moved Trim re-runs only the gating
arithmetic over cached blocks. This is ADR-0013's closing note, made real.

## What is inherited, and what #25 actually decides

**Inherited — not re-opened here** (ADR-0013 / #7): the section lives in the permanent trailing
inspector between Quality Preset and the size estimate; the target is −16 LUFS / −3 dBTP;
amplify is capped at +12, attenuate is uncapped; the correction is a **clamp, not a limiter** —
a pure scalar multiply, which is why the audition is one wideband gain node; the correction
shows as a **dB figure, never LUFS**, with a caption only when it falls short; Loudness and Gain
are **two separate figures**; the toggle is app-wide, sticky, off by default.

**Resolved without a prototype — trigger timing → live-on-drag.** ADR-0013's own implementation
note mandates caching each block's K-weighted power so a moved Trim is cheap to re-measure,
"what makes the previewed figure cheap to update as a handle moves." So the figure tracks the
handle continuously; only the first measure of a Recording shows *Measuring…*.

**What #25 settles, and what these two treatments make concrete:**

- **The resting state (normalization off).** The Level section shows only the toggle and the
  Gain control — no correction readout until you turn it on. The default UI has nothing
  measured in it.
- **The measuring state.** No progress bar (the pass is single-digit CPU-seconds/hour): the
  readout just reads *Measuring…* and resolves to the number.
- **How the two figures coexist**, and **what a clamped correction looks like** — the caption
  naming *why* it fell short (cap vs. ceiling vs. undefined are three different messages).
- **Gain's affordances**: range ±12 dB, a soft detent at 0, a numeric figure, and a **Reset**
  that appears only when it's off zero.
- **Does any of this need custom drawing?** — the A/B axis:
  - **A · Stock components.** `Toggle` + `LabeledContent` + `Slider`. No custom drawing at all.
  - **B · Custom meter.** A drawn LUFS scale showing where the Recording sits, where −16 is, how
    far the correction pushes it, where it lands short, and Gain as a draggable offset on top.
    Buys a picture; costs the one custom control [#4](https://github.com/SamWongML/macos-audio-recording/issues/4) didn't already sign up for.

The recommendation going in is **A** — if the stock read-out is clear enough, the meter is scope
we don't take on, and "official components first" holds. B exists to be compared against, not
assumed. **That's the call this prototype is here to settle.**

## Honest shortcuts

- The K-weighting coefficients are the standard BS.1770 pair for **48 kHz only** (every fixture
  is 48 kHz). A shipping build recomputes them per rate.
- True peak is a compact 4×-oversampling polyphase filter — enough to surface inter-sample
  peaks, not a reference implementation.
- The fixtures are synthesised, and their levels are tuned to reach each case, not to a
  reference LUFS. The point is the UI, not the meter's calibration.
