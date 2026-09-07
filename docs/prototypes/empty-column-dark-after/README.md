# The after-picture for issue #111 — the column reaching the top edge

Release build, `1200 × 680`, fresh launch at the saved frame, both appearances × empty and
populated column. The empty shots used #106's Library-aside method, **39 files → 39 files** each
run.

| appearance | state | detail | column | step | fill top edge |
|---|---|---|---|---|---|
| Dark | empty | `(40,40,40)` | `(27,27,27)` | 1.168 : 1 | **y = 0** (was 52) |
| Dark | populated | `(40,40,40)` | `(27,27,27)` | 1.168 : 1 | **y = 0** |
| Light | empty | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 | **y = 0** |
| Light | populated | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 | **y = 0** |

**Every colour is byte-identical to `main`.** The only thing that moved is where the fill starts —
which is the point of [ADR-0035](../../adr/0035-the-trailing-column-reaches-the-windows-top-edge.md).
