---
status: accepted
---

# Content is the colour

AppTape's editor read as a scaffold: sober everywhere, with `.tint` sprinkled at two opacities
across the waveform and whatever else wanted emphasis, and an **empty `AccentColor.colorset`** — so
the app had no colour of its own at all, only the user's System Settings accent wearing the app's
layout. The rule this ADR settles is one line: **content is the colour.** Chrome stays on system
materials and the user's own accent; all chromatic weight concentrates in the captured audio and
the Trim decision, in **one committed non-system accent** that never appears anywhere else. Every
view built after this ADR inherits the values below.

The accent is **indigo**, named **`Signal`**, in two stops.

## Considered options

**Filling `AccentColor.colorset` was rejected, and this is the most surprising line in the
decision.** The obvious mechanism for "one committed accent" is the asset-catalog global accent, and
it does not work: Apple's own guidance is that a custom app accent renders **only when the person
has set System Settings → General → Accent color to Multicolor**, and any other choice overrides it
app-wide. A committed accent shipped that way is committed only on machines that happen not to have
an opinion. The alternative reading — fight the override — has no API and would be wrong anyway,
because the user's accent is the user's. So the accent asset stays deliberately empty and `Signal`
is applied explicitly at each content site. This dissolves the conflict rather than losing to it:
we never contest the user's accent, we simply stop using it for content.

**A warm gold in the Fission tradition was rejected on collision grounds.** Fission's 2.9 refresh
leaned its light theme into the app's gold, and a tape recorder wants to be warm. But ADR-0009 spends
amber on the Runway advisory and ADR-0007's recording state spends red, so the warm half of the wheel
is already carrying meaning. An accent that reads as a quieter warning is worse than no accent.
Green reads as level-meter and success. That left the cool half, and indigo over teal was the
human's call.

**Forwarding `Color.indigo` was rejected.** Apple declines to publish stable values for the system
colours and warns against hard-coding them — which cuts both ways: it also means the value can move
under us, and indigo has moved before. A committed brand accent that shifts on an OS update is not
committed. `Signal` is therefore a custom colour set *seeded* from the best cross-checked values for
`systemIndigo` (light `#5856D6`, dark `#5E5CE6`) and owned by us thereafter.

**One indigo stop varied by opacity was rejected in favour of two named stops.** The waveform body is
a large saturated field; the peaks, the playhead and the Trimmed-glyph are small bright marks. A
single value cannot serve both: simultaneous-contrast vibration and dark-canvas halation punish a
large fill at the saturation a small mark needs, and dropping the fill's alpha instead muddies it
toward grey rather than keeping it indigo. So `Signal` (marks) and `Signal Muted` (fields) are
separate values, and the existing two-layer peak/RMS waveform already has exactly the two slots.

**Tinting the Export button with `Signal` was rejected**, though the HIG explicitly sanctions
tinting a prominent button's background for the primary action. One exception is all it takes to
make the rule unenforceable in review: "is this pixel captured audio?" has to have one answer per
site. Export is already the most prominent thing in the inspector by shape and position. It keeps
the user's accent, like every other control the system draws.

**A rectified waveform, and any change to the geometry, was rejected.** Fission's release notes treat
the zero-dB centre line as load-bearing enough that losing it was a bug, and the mirrored two-layer
peak-and-RMS drawing AppTape already has is the peer norm. Only the colours change.

**Raising the dark-mode dim opacity on the trimmed-away region was rejected in favour of
desaturating it.** The current `.background.opacity(0.62)` overlay barely moves in Dark Mode, which
undercuts the one thing AppTape does better than its peers: every peer's treatment of the
trimmed-away region reads *this is gone*, contradicting ADR-0003, where a translucent dim reads
*still there, just not Exported*. Two per-appearance magic numbers would patch the symptom.
Desaturating states the meaning directly — what changes outside the Trim is **colour, not
brightness** — it needs no per-appearance tuning, and it survives Increase Contrast, which an alpha
overlay does not. It also leaves the Trim as the only indigo on the lane, which is the whole point.

**A custom typeface was rejected**, and **a dense layout was rejected.** The premium research found
both departures legitimate but both tied to a specific identity claim — Bear's distraction-free
writing, Raycast's developer tool — that AppTape does not make. The apps closest to AppTape's job of
browsing and deciding (Things, Fantastical, Reeder) all moved *toward* more air in a named redesign.

**Showing the selection checkmark only under Differentiate Without Color was rejected.** The HIG's
"convey information with more than colour alone" is stated unconditionally, not gated on the setting.
A conditional-only affordance is a second layout that nobody looks at and that rots.

## Consequences

**`Signal` and `Signal Muted` are colour sets, six values in total.** `Signal` carries light, dark
and a **High Contrast variant of each**; `Signal Muted` carries light and dark only. The muted stop
gets no High Contrast variant because it is a field, not a mark — raising its contrast makes the lane
louder without making anything more legible, and fights the anti-halation reasoning that made it a
separate stop.

| Token | Light | Dark | Rule for any future change |
| --- | --- | --- | --- |
| `Signal` | `#5856D6` | `#5E5CE6` | Seeded from `systemIndigo`; ours to own thereafter |
| `Signal` High Contrast | starting point `#403FA0` | starting point `#9694F0` | Must **measure** ≥ 4.5:1 on the appearance's window background |
| `Signal Muted` | starting point `#6C6BC9` | starting point `#4A48A8` | Always lower saturation than `Signal`, and on dark also lower lightness |

The four starting points are starting points, not measurements. They are settled by running the real
app and screenshotting it, per this map's own rule, during the detail-pane work — not by picking a
number here.

**Indigo is never a text colour in Dark Mode.** Measured, `Signal` dark is **2.53:1** on the dark
window background and 3.29:1 on the darker text background — it fails both the 4.5:1 small-text floor
and, on one of the two, the 3:1 large-and-bold floor. It is legitimate as a large fill and as a small
non-text mark; it is not legitimate as a glyph carrying words. This immediately condemns the `.tint`
Trim readout in `TrimTimeline.swift`, which becomes `.primary`.

**Where `Signal` may appear, exhaustively.** The waveform peaks; the playhead; the Trim drag handle
while it is under the hand; the "is Trimmed" scissors glyph in the Library sidebar (the HIG's
Mail-VIP carve-out — a sidebar glyph with a fixed, meaning-carrying colour is left alone). The
waveform body takes `Signal Muted`. **Nowhere else.** In particular: not the Export button, not the
selected Quality Preset rung, not focus rings, not the sidebar selection, and not any text in Dark
Mode. The system accent marks *what the user has selected*; indigo marks *the audio and the Trim*.

**Seam bands stay neutral, and this is now a rule rather than a comment.** `SeamBand.swift` already
says "Neutral, not tinted — it is absence, not alarm." A Seam is audio that never arrived, so the
absence of `Signal` **is** the meaning; tinting it would say the opposite.

**Typography is wholly SF, four rungs, no light weights.** Recording name at Body/13 semibold;
metadata and secondary lines at Subheadline/11 in `.secondary`; inspector section headers at
Headline/13 bold; the transport position and Trim readouts at Body with monospaced digits. That
monospacing is the single content-scoped departure, and it is there so digits do not jitter as they
tick, not for flavour. Nothing goes below 11pt, though macOS permits 10.

**Spacing is a 4pt base — 4/8/12/16/24 — on the generous side**, with one deliberate break in the
uniformity: the waveform lane is the only element allowed to take all remaining height. Sidebar rows
go to 40pt so the name and its metadata are two real lines.

**Liquid Glass is limited to exactly two controls, and the number two is the rule**: the transport
play/pause and the Export button. Not the lane, not the inspector rungs, not the sidebar. This
condemns the third glass control now in the tree — the "Try Again…" button after a failed Export
(`ExportInspector.swift`), which drops to plain `.glass` because a recovery is not the primary path.
Separators are the system `Divider`. **Nothing gets a custom shadow**: the HIG publishes no elevation
system, and inventing one is how an app arrives at a dated skeuomorph.

**Reduce Transparency and Increase Contrast need no code for the glass controls** — the material
handles both automatically, "across the board". But Apple's own implementation of this shipped
**broken in Tahoe 26.1 and 26.2** and was fixed in 26.3, so the automatic behaviour is a contract to
**verify empirically each OS cycle**, not one to trust.

**Reduce Motion is the app's job and gets one helper, not four call sites.** Only Liquid Glass's own
morph is automatic; every `withAnimation` and `.animation` the app writes is ours. Apple's stated
preferred replacement is a **fade, not an instant cut**. The helper lives in the token set and returns
the intended animation normally and an opacity fade when the setting is on, so the next animation
anyone adds inherits the behaviour instead of forgetting it. Four unconditional `.animation` calls in
`ExportInspector.swift` route through it.

**The selected Quality Preset rung gains a leading checkmark, always.** It is currently marked by
colour and opacity alone. The checkmark is unconditional so the accessible path and the default path
are the same path — the only version that stays correct.

**The values live in one named token set (`Palette` and `Metrics`), not inline.** The visual sweep
filed 38 findings, many of them values that quietly disagree with each other, and four more tickets on
this map build views after this ADR. A named set is how those tickets inherit the decision instead of
copying it, and how disagreement becomes visible.

**ADR-0009 is untouched, deliberately.** Its amber Runway tier is signalled by colour alone, which by
the letter of the HIG's "more than colour alone" is a gap — re-examined here against Differentiate
Without Color and left as it stands, because it is a bounded, disclosed trade with a guaranteed
textual follow-up at 30 minutes, and because the menu bar status item is out of scope for this
effort. Adding a `⚠` to the amber glyph under that setting is a reasonable future change and belongs
to a separate effort, not to this one. Inside the editor the question does not arise: both amber uses
already pair the colour with a warning triangle and words.

**`AccentColor.colorset` stays empty on purpose**, and carries a comment saying why, so that nobody
"fixes" it by filling it in.
