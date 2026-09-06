#!/usr/bin/env python3
"""PROTOTYPE round 2 — refinements of the picked mark (#79). Throwaway.

Round 1 picked A: indigo bars on a pale ground. Round 2 varies one thing at a time.

  A  as picked            7 bars, w58/gap42, max half 250   (baseline, unchanged)
  F  refined              7 bars, w66/gap36, max half 236, steadier rhythm
  G  F + the Trim, again  outer bar each side in Signal Muted, no rails
  H  F at five bars       fewest bars that still say audio, for the 16 pt tile

G is the trimmed-away idea's second attempt. Round 1 said it with rails and the
rails collapsed into the waveform. Here it is said with colour instead, using
ADR-0019's own two stops — Signal for the kept bars, Signal Muted for the
trimmed-away ones — which is also the desaturate-don't-dim rule the ADR settles.
"""
import json, os, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SIGNAL = "#5856D6"          # Palette.signal, light
SIGNAL_MUTED = "#6C6BC9"    # Palette.signalMuted, light
GROUND_PALE = "#E6E6F2"


def bars_svg(heights, bar_w, pitch, max_half, muted_ends=False):
    total = len(heights) * pitch - (pitch - bar_w)
    x0 = (1024.0 - total) / 2.0
    out = []
    for i, h in enumerate(heights):
        cx = x0 + bar_w / 2 + i * pitch
        half = max(h * max_half, bar_w / 2)
        fill = SIGNAL_MUTED if (muted_ends and i in (0, len(heights) - 1)) else SIGNAL
        out.append('  <rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s"/>'
                   % (cx - bar_w / 2, 512 - half, bar_w, half * 2, bar_w / 2, fill))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n%s\n</svg>\n' % "\n".join(out))


def emit(v, svg_text):
    d = os.path.join(HERE, "AppTape%s.icon" % v)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "Assets"))
    open(os.path.join(d, "Assets", "1-bars.svg"), "w").write(svg_text)
    r, g, b = (int(GROUND_PALE[i:i+2], 16) / 255.0 for i in (1, 3, 5))
    open(os.path.join(d, "icon.json"), "w").write(json.dumps({
        "fill": {"automatic-gradient": "extended-srgb:%.5f,%.5f,%.5f,1.00000" % (r, g, b)},
        "groups": [{
            "layers": [{"image-name": "1-bars.svg", "name": "Waveform"}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.5},
        }],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }, indent=2) + "\n")


R1 = [0.32, 0.86, 0.50, 1.00, 0.42, 0.72, 0.28]     # round 1's rhythm: noisy on purpose
R2 = [0.34, 0.72, 1.00, 0.56, 0.92, 0.64, 0.30]     # steadier: one clear peak, one echo
FIVE = [0.44, 0.92, 1.00, 0.62, 0.34]

emit("A", bars_svg(R1, 58, 100, 250))
emit("F", bars_svg(R2, 66, 102, 236))
emit("G", bars_svg(R2, 66, 102, 236, muted_ends=True))
emit("H", bars_svg(FIVE, 78, 124, 236))
print("wrote A, F, G, H")
