#!/usr/bin/env python3
"""Find the icon.json shape that declares an explicit dark variant. Throwaway."""
import json, os, shutil, subprocess, sys

IC = "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/ictool"
HERE = os.path.dirname(os.path.abspath(__file__))
SVG = open(os.path.join(HERE, "AppTapeF.icon", "Assets", "1-bars.svg")).read()
LIGHT = "extended-srgb:0.34510,0.33725,0.83922,1.00000"   # #5856D6
DARK  = "extended-srgb:0.58824,0.58039,0.94118,1.00000"   # #9694F0
GND_L = "extended-srgb:0.90196,0.90196,0.94902,1.00000"   # #E6E6F2
GND_D = "extended-srgb:0.10196,0.09804,0.16471,1.00000"   # #1A1929

CANDIDATES = {
    "a_fill_specializations_list": {
        "layer": {"fill": {"solid": LIGHT},
                  "fill-specializations": [{"appearance": "dark", "value": {"solid": DARK}}]},
        "top": {"fill-specializations": [{"appearance": "dark",
                                          "value": {"automatic-gradient": GND_D}}]},
    },
    "b_fill_specializations_dict": {
        "layer": {"fill": {"solid": LIGHT}, "fill-specializations": {"dark": {"solid": DARK}}},
        "top": {"fill-specializations": {"dark": {"automatic-gradient": GND_D}}},
    },
    "c_nested_specializations": {
        "layer": {"fill": {"solid": LIGHT,
                           "specializations": [{"appearance": "dark", "value": {"solid": DARK}}]}},
        "top": {},
    },
    "d_appearance_keyed_fill": {
        "layer": {"fill": {"solid": LIGHT}, "dark": {"fill": {"solid": DARK}}},
        "top": {"dark": {"fill": {"automatic-gradient": GND_D}}},
    },
}


def build(name, spec):
    d = os.path.join(HERE, "probe-%s.icon" % name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "Assets"))
    open(os.path.join(d, "Assets", "1-bars.svg"), "w").write(SVG)
    layer = {"image-name": "1-bars.svg", "name": "Waveform"}
    layer.update(spec["layer"])
    doc = {"fill": {"automatic-gradient": GND_L},
           "groups": [{"layers": [layer],
                       "shadow": {"kind": "neutral", "opacity": 0.5},
                       "translucency": {"enabled": True, "value": 0.5}}],
           "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}
    doc.update(spec["top"])
    open(os.path.join(d, "icon.json"), "w").write(json.dumps(doc, indent=2) + "\n")
    return d


for name, spec in CANDIDATES.items():
    d = build(name, spec)
    out = os.path.join(HERE, "probe-out", name)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    r = subprocess.run([IC, "--compile", out, "--platform", "macosx",
                        "--minimum-deployment-target", "26.0", d],
                       capture_output=True, text=True)
    errs = "com.apple.actool.errors" in r.stdout
    detail = ""
    if errs:
        import re
        detail = "; ".join(re.findall(r"<string>(.*?)</string>", r.stdout))[:180]
    colors = ""
    car = os.path.join(out, "Assets.car")
    if os.path.exists(car):
        info = subprocess.run(["xcrun", "assetutil", "--info", car],
                              capture_output=True, text=True).stdout
        try:
            cs = [x["Color components"] for x in json.loads(info)
                  if x.get("AssetType") == "Color"]
            colors = " ".join("(" + ",".join("%.2f" % c for c in x) + ")" for x in cs)
        except Exception:
            pass
    print("%-32s errors=%-5s %s" % (name, errs, detail or colors))
