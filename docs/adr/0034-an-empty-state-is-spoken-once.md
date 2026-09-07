---
status: accepted
supersedes: "ADR-0024's *the pane's own empty state*; issue #73 finding 16's placement of the Library's empty state in the sidebar"
amends: "ADR-0023's *the empty state stays a `ContentUnavailableView` and gains a second line*"
---

# An empty state is spoken once, by the pane that owns the fact

On a first run the editor rendered **three empty states at once**, and two of them gave an
instruction the user could not follow:

| pane | said |
|---|---|
| sidebar | **No Recordings** · *Recordings you make from the menu bar appear here.* |
| detail | **No Recording selected** · *Choose one in the Library to play it, set its Trim, and Export it.* |
| trailing column | **Nothing to export** · *Select a Recording in the Library.* |

Each line arrived correctly and separately. [ADR-0023](0023-the-detail-pane-is-ruler-lane-brief-dock.md)
gave the detail its second line on report 0002's grounding — *say what to do next*.
[ADR-0024](0024-the-trailing-pane-is-a-column-not-an-inspector.md) kept the column's own empty state
so that deselecting did not make the column disappear, fixing issue #73's finding 24. Issue #73's
finding 16 gave the sidebar its line so an empty Library was not a blank grey column. Every one of
the three was right about its own pane, and nobody had photographed them together: #73 declined to
move the human's Library aside, so its finding 16 was only ever settled from source.

Photographed, the sum is not what the parts intended. Apple's guidance is *say what to do next*; said
three times, twice about something impossible, it stops being that. And this is the **first** thing
a new user sees, which is the one screenshot where "premium" is decided.

## The decision

**One sentence per state, in the pane that owns the fact.**

**The detail owns the Library's silence**, because it is the surface the eye lands on. It tells
*nothing exists* from *nothing is picked* — genuinely different states the app could not previously
distinguish, which is why on a first run it told the user to choose from a Library that was empty:

| state | detail says |
|---|---|
| Library empty | **No Recordings** · *Record from the AppTape icon in the menu bar.* |
| Library has rows, nothing picked | **No Recording selected** · *Choose one in the Library to play it, set its Trim, and Export it.* |

The condition is `store.recordings`, deliberately **not** `matches`: a query that hides every row
leaves the Library full, and claiming otherwise would be a third wrong sentence. It stays one
`ContentUnavailableView` with ternary text rather than an `if`/`else`, so the view keeps its
structural identity when the first Recording arrives and the sentence changes under it.

**The sidebar keeps only the query's silence.** Its `No Recordings` overlay goes. This *supersedes*
finding 16's placement rather than reverting its fix: the footer below states `0 Recordings` in the
same column, so the overlay was the sidebar's second statement, not its only one — and the sentence
that replaces it is a few hundred points to the right, in the same window. A query that matches
nothing keeps `ContentUnavailableView.search`, because the field is in the sidebar and no other pane
could name it.

**The trailing column holds the Export ladder or nothing, and never explains itself.** Both of its
sentences repeated the pane beside them — `Select a Recording in the Library` next to the detail's
own `No Recording selected`, and `AppTape can't decode this file` next to `cantOpenDetail`'s. Every
state without a ladder already has the detail speaking, so nothing goes unexplained.

**Nothing invites the first capture.** [ADR-0017](0017-accessory-at-rest-regular-while-editing.md)
keeps the app a menu-bar item at rest, so on an empty Library the real next action is outside this
window entirely; issue #77's rule — a control invented to fill a hole is not a decision — is
strongest here. The sentence names the menu bar, and the sidebar footer's `Reveal` already offers the
only in-window action that works on an empty Library, opening the folder ADR-0006 makes the truth.

## What this does not change

**ADR-0024's structure stands, and so does #73's finding 24.** The column is still attached above
all three detail branches, still `inspectorWidth` wide, still painting `controlBackgroundColor` plus
its scrim to the full height. It does not disappear when nothing is selected; it holds `Color.clear`.
Measured on this build at `1200 × 680`, the fill is **byte-identical before and after** in both
appearances:

| appearance | detail | column | step |
|---|---|---|---|
| Dark | `(42, 42, 42)` | `(27, 27, 27)` | 1.20 : 1 |
| Light | `(255, 255, 255)` | `(242, 242, 242)` | 1.12 : 1 |

This decision moves no chrome. It removes three strings and adds one.

## Consequences

**The empty column is now bare, and Dark is where that shows.** The same fill that carried a glyph
and two lines of text now carries nothing, and Dark's step is roughly seven times Light's in relative
terms — 36% darker against 5% lighter. ADR-0032's note in `EditorView` already says the scrim *"in
Dark moves the column two units it does not need"*. Whether an empty column should be flatter in Dark
is a treatment question about the column, not about which pane speaks, so it is filed separately
rather than settled here.

**A fourth pane could re-open this.** The rule is *one sentence per state*, not *the detail always
speaks*. If a state ever arises that the detail cannot describe — as the query already is for the
sidebar — the pane that owns that fact speaks for it, and the detail stays quiet.
