---
status: accepted
---

# A Recording begins at the first sound, not the first press

The tap's IOProc is not called at all until the Source produces audio (issue #12),
so the stretch between pressing record and the first sound has no frames. The policy
is that **the master's clock begins at the first sound**: the head is elided, not
padded; the timer reads master duration and sits at `00:00` until audio arrives; and
a Recording that never hears a sound is never saved. This is the one place the master
is deliberately *not* wall-clock true — the opposite of ADR-0007, and for a reason
ADR-0007 itself supplies.

## Considered options

**Padding the head with silence to the moment of `AudioDeviceStart`** would make the
master wall-clock true and consistent with ADR-0007's mid-Recording seams. It was
rejected because the head pad is unbounded in a way a seam never is: arming the
recorder and walking away, then playing something an hour later, writes ~1.4 GB of
leading zeros before the first real sample — the exact unbounded-gap failure ADR-0007
refused to pad for sleep. It also has no callbacks to drive the writer, so the silence
would have to be synthesized. And a head pad buys nothing a recorder wants: leading
silence is only ever something to Trim away.

**Refusing to start until the Source is audible** removes the ambiguity between a
silent head and a failed start, but breaks the primary gesture — arming *before*
pressing play so the intro is not clipped. Refusing guarantees a clipped start, which
is the one thing a recorder must not do.

## Consequences

**Elide only the head; never an internal gap.** ADR-0007 pads mid-Recording gaps
because Trim points are stored against the master and eliding would shift every point
after the gap. The head has no "before" for a Trim point to shift against, so anchoring
t=0 at the first sound violates nothing that rule protects. Internal silence still lands
as real zero-frames — issue #12 proved callbacks continue through a pause, even after
the tapped process is killed — and a full callback stop is still ADR-0007's padded seam.
The asymmetry (head elided, interior padded) is the wall-clock rule read correctly, not
an exception to it.

**The armed-waiting state is not a failure, and is not mistaken for one.** Before the
first callback the app is live but the file is empty. Issue #14 already gates its denial
inference on `isRunningOutput`, and "no callbacks yet" is physically distinct from a
denial's "all-zero callbacks," so the armed-waiting window never trips the denial
(ADR-0008) or degraded-Recording (ADR-0010) machinery.

**The timer reads master duration.** The menu-bar `● MM:SS` (ADR-0004) counts frames
written, not wall-clock, so it sits at `● 00:00` through the armed window and only
advances at the first sound — an honest reading against the file that doubles as the
"waiting for audio" signal when audio *should* be playing but is not. It stays
continuous through seams, which are padded into the master. No app-owned "waiting"
chrome is added: the frozen zero and issue #6's flat level meter are the signal,
consistent with issue #14 declining an explainer.

**The CAF is created lazily at the first frame.** This resolves ADR-0006 / issue #10's
"written from the first sample" as literal lazy creation: an arm-then-never-play stop is
a **no-op** — no file, no Library entry, and no editor opens (ADR-0011's
user-stop-opens-editor rule is conditioned on the Recording having content). It is
distinct from issue #14's discard of an all-zero file: that file's callbacks fired and
it is removed as a probable denial; this one never had a callback and never became a
file.

Settled in issue #33.
