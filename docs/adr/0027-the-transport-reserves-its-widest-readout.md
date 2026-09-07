---
status: accepted
---

# The transport reserves its widest readout

The transport's two figures — the playhead clock and the Trim readout — are laid out in the width
their **widest possible content** would need, not the width the Recording in front of them happens
to need. A hidden reference string is rendered in the same font and `fixedSize`d, and the live text
is drawn as an overlay inside it. The window's width floor is then that reservation plus the two
columns beside it, and it is a **layout number rather than a crash guard** — a change of reason,
not of value: it stays at 960.

## The loop this replaces is gone

[Issue #85](https://github.com/SamWongML/macos-audio-recording/issues/85) existed because the editor
**aborted** below roughly 920 pt wide: `NavigationSplitView` and a permanently presented
`.inspector` re-triggered each other's layout until AppKit threw `NSGenericException` ("more Update
Constraints in Window passes than there are views in the window"). The 960 floor was set wider than
any layout reasoning wanted, and commented as a guard, to make the crash unreachable.

[ADR-0024](0024-the-trailing-pane-is-a-column-not-an-inspector.md) deleted the `.inspector`, and the
loop went with it. Re-measured against that code, the editor was stepped from 1120 pt down to
**400 pt in 10 pt increments with no abort at any width**. Two other shapes that used to abort were
re-measured too and no longer do: **opening the editor window during launch**
(`.defaultLaunchBehavior(.presented)`), and a **bottom safe-area bar** on the detail pane.

So nothing in this window is protecting against a crash any more, and the floor had to be re-derived
from what the layout needs. That turned out to be the harder half.

## The floor could not be one number while the readouts sized to their content

`Format.time(_, precise: true)` is `m:ss.ff` below an hour and `h:mm:ss` at or above one, and
`trimRangeText` is two of those figures around an en dash. Both grow with the Recording, so the
width the transport needed changed with the file the window happened to be showing — and a floor
derived from one Recording was wrong for another. Measured with an eight-second Recording the
playhead clock wrapped into a **vertical stack of digits** at 880 pt; with a twenty-minute one it
wrapped higher, because the clock is a glyph wider.

Two smaller faults came from the same root, and both are visible without touching the window:

- **The bar reflowed under the pointer.** Arrowing down the Library moved `Reset` by the difference
  between `0:07` and `20:00`.
- **It reflowed mid-playback.** Playing anything past ten minutes moved `Reset` again the moment the
  clock gained a digit.

## Considered options

**Reserve the widest form (chosen).** Both figures are laid out at the width of a reference string
covering the widest case, and the live text is overlaid on it. The bar is then the same shape for
every Recording and at every playhead position, and the floor is one number. This is not a new idea
in this app: the same bar already keeps `Reset` in the layout when there is nothing to reset so the
row does not reflow the moment a Trim is set, and
[ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md) made the sidebar's glyph rail
fixed-width and the Export dock's four phases one height for exactly this reason.

**Keep them content-sized and set the floor to the worst case.** Honest, and it needs no code — but
the number goes *up* rather than down, and it leaves both reflows in place. Rejected: the floor was
the smaller of the two problems.

**Lower the floor to what today's Library needs and defer the rest.** Rejected as knowingly shipping
a wrong number: a trimmed twenty-minute Recording already breaks it.

## Consequences

**The reference is a string, not a point value.** The widths stay in the font, so a face change moves
them and nothing has to be re-measured by hand. This matters because the reference has to be rendered
in *exactly* the clock's face — hence `EditorView.clockFont`, named rather than inlined twice, since a
reference that drifted from the face beside it would reserve the wrong width silently.

**The reservation only holds with `fixedSize`.** A bare `Text` is compressible: without it an `HStack`
short of room shrinks the hidden reference and then truncates the overlay inside the width it was
shrunk to. Measured — the clock rendered `0:00.…` at 940 pt with the reservation in place but
compressible, which looks like the reservation working and is the opposite.

**Below the floor the transport overflows rather than wraps.** Fixed-size content cannot compress, so
a window forced narrower than the floor (a saved frame, an odd display) clips the sidebar's names on
the left and the trailing column on the right instead of stacking digits. Both are wrong; the clipped
one is the one you can see is wrong.

**The floor is 960 and the sidebar is why it is not smaller.** With the reservation the three columns
want the sidebar's resolved 268 pt rather than its 232 pt minimum, the trailing column's fixed 276,
and about 405 for the transport. Measured with the longest Recording in the Library selected: **940
overflows, 960 is clean.** Lowering it further means letting the sidebar compress toward its minimum,
which changes the editor's default proportions and belongs to whoever decides those.

**A Recording past ten hours is one glyph wider than the reservation.** Disclosed, not overlooked:
reserving for a capture nobody will make would spend the bar's width on air.

**The idiomatic bottom bar is still not available, for a new reason.** `safeAreaBar(edge: .bottom)`
and `safeAreaInset(edge: .bottom)` no longer abort, but a bottom safe area is resolved against the
**window**, not the view it is attached to. Applied to the detail pane, the pane lays out at the full
window width, runs under the trailing column, and the column draws on top of it. The sidebar's own
`.safeAreaInset` works only because a split-view column *is* the window's width there. So the
transport stays hand-laid: not because the sanctioned route crashes, but because it docks to the
wrong box.

**The height floor stays 500, and it is now comfort rather than a boundary.** 960 × 460 was measured
aborting when the `.inspector` was present; against this code it does not abort, and the detail pane
still resolves ruler, lane, brief and transport at that height. It was left where it was rather than
lowered on one screenshot.
