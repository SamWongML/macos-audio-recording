#!/usr/bin/env python3
"""PROTOTYPE — four candidate AppTape app icons (#79). Throwaway; not shipped code.

Four Icon Composer .icon bundles. Each stakes a different claim about what AppTape
is, and each has a different silhouette so they can't be judged on colour alone:

  A  The lane   the app is your audio        scattered bars, indigo on pale
  B  The Trim   the app is the decision      bars inside two rails, white on indigo
  C  The reel   the app is tape, abstract    a ring, white on indigo
  D  The tape   the app is tape, concrete    a band with two reels, white on indigo
  E  The lane   same bars, saturated ground   bars, white on indigo

The bars are NOT the app's own envelope polygon. That was tried first and it
collapses into a blob below ~64 pt: WaveformShape joins 30 column midpoints, which
is right for a 700 pt lane and unreadable in a 16 pt Dock tile. Discrete bars are
the same idea at icon scale, and they are also what the status item already draws.
"""
import json, os, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SIGNAL = "#5856D6"          # Palette.signal, light
GROUND_INDIGO = "#4A48C8"
GROUND_PALE = "#E6E6F2"

# Seven bars: enough to read as audio, few enough to survive a 16 pt tile.
BARS = [0.32, 0.86, 0.50, 1.00, 0.42, 0.72, 0.28]
BAR_W, PITCH, X0, MID, MAX_HALF = 58.0, 100.0, 183.0, 512.0, 250.0
RAIL_L, RAIL_R = 262.0, 762.0   # between bar 1|2 and bar 6|7


def bar_rects(fill, keep=None):
    out = []
    for i, h in enumerate(BARS):
        cx = X0 + BAR_W / 2 + i * PITCH
        if keep is not None and (cx > RAIL_L) != keep and (cx < RAIL_R) != keep:
            pass
        inside = RAIL_L < cx < RAIL_R
        if keep is not None and inside != keep:
            continue
        half = max(h * MAX_HALF, BAR_W / 2)
        out.append('  <rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"/>'
                   % (cx - BAR_W / 2, MID - half, BAR_W, half * 2, BAR_W / 2, fill))
    return "\n".join(out)


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n%s\n</svg>\n' % body)


def circle_path(cx, cy, r):
    return ("M %.1f %.1f a %.1f %.1f 0 1 0 %.1f 0 a %.1f %.1f 0 1 0 -%.1f 0 Z"
            % (cx - r, cy, r, r, 2 * r, r, r, 2 * r))


def write(v, name, contents):
    d = os.path.join(HERE, "AppTape%s.icon" % v, "Assets")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, name), "w").write(contents)


def icon_json(v, ground_hex, layers):
    r, g, b = (int(ground_hex[i:i+2], 16) / 255.0 for i in (1, 3, 5))
    doc = {
        "fill": {"automatic-gradient": "extended-srgb:%.5f,%.5f,%.5f,1.00000" % (r, g, b)},
        "groups": [{
            "layers": layers,
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.5},
        }],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    open(os.path.join(HERE, "AppTape%s.icon" % v, "icon.json"), "w").write(
        json.dumps(doc, indent=2) + "\n")


for v in "ABCDE":
    shutil.rmtree(os.path.join(HERE, "AppTape%s.icon" % v), ignore_errors=True)

# ---------------------------------------------------------------- A · The lane
# Content is the colour, taken literally: a sober pale ground, the audio in indigo.
write("A", "1-bars.svg", svg(bar_rects(SIGNAL)))
icon_json("A", GROUND_PALE, [{"image-name": "1-bars.svg", "name": "Waveform"}])

# ---------------------------------------------------------------- B · The Trim
# The decision the app exists for. The trimmed-away bars stay present but drained —
# ADR-0019 keeps that region visible on purpose, because it is still in the master.
write("B", "1-outside.svg", svg(bar_rects("#FFFFFF", keep=False)))
write("B", "2-inside.svg", svg(bar_rects("#FFFFFF", keep=True)))
write("B", "3-rails.svg", svg("\n".join(
    '  <rect x="%.1f" y="150" width="34" height="724" rx="17" fill="#FFFFFF"/>' % (x - 17)
    for x in (RAIL_L, RAIL_R))))
icon_json("B", GROUND_INDIGO, [
    {"image-name": "1-outside.svg", "name": "Trimmed away", "opacity": 0.42},
    {"image-name": "2-inside.svg", "name": "Kept"},
    {"image-name": "3-rails.svg", "name": "Trim handles"},
])

# ---------------------------------------------------------------- C · The reel
# The name, abstracted rather than reproduced. Round 1 drew a ring with three
# spokes and it rendered as a steering wheel — a reel is a *disc with big holes*,
# so this is a solid platter, a small centre hole, three wide cutouts.
import math
cut = " ".join(circle_path(512 + 172 * math.cos(math.radians(a)),
                           512 + 172 * math.sin(math.radians(a)), 94)
               for a in (-90, 30, 150))
write("C", "1-reel.svg", svg('  <path fill-rule="evenodd" fill="#FFFFFF" d="%s %s %s"/>'
                             % (circle_path(512, 512, 300), circle_path(512, 512, 54), cut)))
icon_json("C", GROUND_INDIGO, [{"image-name": "1-reel.svg", "name": "Reel"}])

# ---------------------------------------------------------------- D · The tape
# The name, concrete: the cassette flattened to its one recognisable fact — two
# reels joined by the tape window. Round 1 used a capsule and it read as a toggle
# switch, so the shell is a rounded rectangle and the reels are joined, not adrift.
window = ('M 392 456 h 240 v 112 h -240 Z')
write("D", "1-shell.svg", svg(
    '  <path fill-rule="evenodd" fill="#FFFFFF" d="M 244 292 h 536 a 72 72 0 0 1 72 72 '
    'v 296 a 72 72 0 0 1 -72 72 h -536 a 72 72 0 0 1 -72 -72 v -296 a 72 72 0 0 1 72 -72 Z '
    '%s %s %s"/>' % (circle_path(392, 512, 92), circle_path(632, 512, 92), window)))
icon_json("D", GROUND_INDIGO, [{"image-name": "1-shell.svg", "name": "Cassette"}])

# ---------------------------------------------------------------- E · The lane, inverted
# The missing cell. In the real Dock, B's Trim rails collapse into the waveform at
# 128 pt, so the live question between A and B is not "does the Trim read" — it is
# pale ground or saturated ground. E is A on indigo with nothing else changed.
write("E", "1-bars.svg", svg(bar_rects("#FFFFFF")))
icon_json("E", GROUND_INDIGO, [{"image-name": "1-bars.svg", "name": "Waveform"}])

print("wrote", ", ".join("AppTape%s.icon" % v for v in "ABCDE"))
