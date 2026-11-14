"""Read-only provenance/signal audit of authored audio references.

Never claims audition: waveform metrics cannot prove semantic suitability,
the absence of voices, or the perceptual quality of a loop.
"""
import concurrent.futures
import datetime
import json
import math
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from scipy.signal import welch

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "assets/library/manifest.json").read_text())
entries = {x["file"]: x for x in manifest["assets"]}

def references(text):
    result = {}
    for line in text.splitlines():
        if line.startswith("[ext_resource"):
            path = re.search(r'path="([^"]+)"', line)
            identifier = re.search(r'id="([^"]+)"', line)
            if path and identifier:
                result[identifier[1]] = path[1].removeprefix("res://")
    return result

def scalar(block, name, default):
    match = re.search(r"(?m)^" + re.escape(name) + r" = (.+)$", block)
    if not match: return default
    value = match[1]
    if value in ("true", "false"): return value == "true"
    try: return float(value)
    except ValueError: return value.strip('"')

emitters = []
for path in (ROOT / "scenes/levels").glob("*.tscn"):
    text = path.read_text()
    refs = references(text)
    for block in re.split(r"(?m)^\[node ", text)[1:]:
        header = block.splitlines()[0]
        if 'parent="Sources"' not in header: continue
        sound = re.search(r'(?m)^sound = ExtResource\("([^"]+)"\)', block)
        if not sound: continue
        emitters.append({"level": path.stem, "anchor": re.search(r'name="([^"]+)"', header)[1],
            "file": refs[sound[1]], "loop":scalar(block,"looped",True),
            "gain_db":scalar(block,"gain_db",-8), "landmark":scalar(block,"landmark",False),
            "interval_seconds":[scalar(block,"interval_min",8),scalar(block,"interval_max",22)]})

palette_text = (ROOT / "resources/audio/default_palette.tres").read_text()
palette_refs = references(palette_text)
palette = {}
for line in palette_text.split("[resource]")[-1].splitlines():
    if " = " not in line or line.startswith("script"): continue
    key = line.split(" = ")[0]
    ids = re.findall(r'ExtResource\("([^"]+)"\)',line)
    if ids: palette[key] = [palette_refs[x] for x in ids]

used = sorted(set(e["file"] for e in emitters) | {f for files in palette.values() for f in files})

def db(value): return round(20 * math.log10(max(float(value), 1e-9)), 3)

def measure(file):
    raw = subprocess.check_output(["ffmpeg","-v","error","-i",str(ROOT/file),"-ac","1","-ar","22050","-f","f32le","-"])
    x = np.frombuffer(raw,dtype="<f4")
    rms = float(np.sqrt(np.mean(x*x)))
    peak = float(np.max(np.abs(x)))
    f, power = welch(x,22050,nperseg=min(4096,len(x)))
    total = float(power.sum())
    n = 2205
    env = np.array([np.sqrt(np.mean(x[i:i+n]**2)) for i in range(0,len(x)-n+1,n)])
    nonzero = env[env>1e-6]
    diff95 = np.percentile(np.abs(np.diff(x)),95)
    jump = abs(float(x[0]-x[-1]))
    return file, {"duration_seconds":round(len(x)/22050,3),"decoded_peak_dbfs":db(peak),"rms_dbfs":db(rms),
        "crest_db":round(db(peak)-db(rms),3),"samples_ge_099":int(np.count_nonzero(np.abs(x)>=.99)),
        "spectral_centroid_hz":round(float((f*power).sum())/max(total,1e-16),1),
        "energy_above_4khz_fraction":round(float(power[f>=4000].sum())/max(total,1e-16),4),
        "wrap_jump_dbfs":db(jump),"wrap_jump_over_internal_diff_p95":round(jump/max(float(diff95),1e-9),3),
        "rms_100ms_p95_to_p05_db":round(db(np.percentile(nonzero,95))-db(np.percentile(nonzero,5)),2) if len(nonzero)>1 else 0}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    metrics = dict(pool.map(measure,used))

usage = defaultdict(list)
for emitter in emitters: usage[emitter["file"]].append(emitter)
assets = []
for file in used:
    entry = entries.get(file,{})
    roles = [k for k,v in palette.items() if file in v]
    assets.append({"file":file,"sources":[s["path"] for s in entry.get("sources",[])],
        "declared_application":entry.get("application",""),"manifest_loop":entry.get("loop"),
        "processing":entry.get("processing",""),"palette_roles":roles,"emitter_count":len(usage[file]),
        "levels":dict(Counter(e["level"] for e in usage[file])),"metrics":metrics[file]})

findings = [
 {"severity":"high","file":"assets/library/tree_rustle.ogg","evidence":"source filename Foley Tree Shaking 01.wav; reused at many tree anchors","interpretation":"Manual tree-shaking Foley is a poor semantic basis for sustained wind-through-leaves; transient character requires audition, not inferred certainty.","recommendation":"Replace with wind-through-trees canopy sections and distribute independent regions; keep creaks sparse."},
 {"severity":"high","files":["assets/library/ui_move.wav","assets/library/ui_accept.wav","assets/library/ui_back.wav"],"evidence":"All three source labels are Sci-Fi Electronic Computer Terminal Button","interpretation":"Electronic terminal character is supported by provenance and may clash with quiet organic environments. User explicitly rejected current UI audio.","recommendation":"Quiet, brief nonvocal tactile recordings; separate navigation/confirm/back roles and enforce menu-only playback."},
 {"severity":"medium","file":"assets/library/pipe_tick.wav","evidence":"Source is Industry Tool Hammer Small Metal Hammer Tapping Nail 01.wav","interpretation":"Impact-on-nail recording does not establish thermal pipe ticking.","recommendation":"Use actual pipe resonances/strain and name their roles honestly."},
 {"severity":"medium","file":"assets/library/landmark_water_resonance.ogg","evidence":"Source is shallow water bubbling steadily in a metal bowl; current role is a reservoir landmark","interpretation":"Small-container resonance may imply a much smaller object than the surrounding reservoir.","recommendation":"Use larger water-space recording or explicitly author a small bubbling outlet as the landmark."},
 {"severity":"medium","file":"assets/library/landmark_fountain.ogg","evidence":"Source is steady water pouring into a plastic bucket, declared fountain stand-in","interpretation":"Container resonance and pour character may be incongruous with a large stone fountain; actual percept requires audition.","recommendation":"Prefer true fountain or free-running cascade recording; otherwise constrain modeled object to a small water outlet."},
 {"severity":"medium","files":["assets/library/cistern_air.ogg","assets/library/courtyard_wind.ogg"],"evidence":"Source labels are blizzard whistle gust and hurricane storm strong gusts","interpretation":"Extreme-weather recordings may overstate atmosphere or imply storm conditions in calm areas.","recommendation":"Reduce/change calm-area use, preserve only where strong drafts or storm weather are authored."},
 {"severity":"review","files":["assets/library/landmark_bell.ogg","assets/library/freighter_engine.ogg","assets/library/freighter_vent.ogg"],"evidence":"Recordings are church-tower bells, boiler room ambience, factory fan ambience","interpretation":"Real environments may already contain room acoustics; additional simulated reverb can exaggerate it. Filename alone cannot quantify baked reverberation.","recommendation":"Audition dry and processed; keep reflected/late gain conservative if original ambience has long tails."},
 {"severity":"info","files":["assets/library/landmark_pump.ogg","assets/library/landmark_electric.ogg","assets/library/distant_bell.wav"],"evidence":"Sources are hydraulic pump, refrigerator hum, brass handbell","interpretation":"First two are disclosed machinery stand-ins; handbell is suitable only for a local small-bell role, not the main tower landmark.","recommendation":"Retain clear contextual roles and avoid replacing tower bells with handbell."}
]
report={"generated_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"phase":"before changes",
    "method":"Static resource/provenance inspection plus decoded mono22.05kHz signal statistics; no listening performed.",
    "limitations":["No claim of voice-free content based solely on filenames.","Signal metrics flag risks, not perceptual defects.","Loop wrap delta is compared to normal adjacent-sample differences; a large envelope variation may be natural motion, not a bad edit.","No true-peak measurement; decoded peak is a sample-peak screening statistic."],
    "counts":{"emitters":len(emitters),"unique_used_recordings":len(used),"palette_roles":len(palette)},
    "findings":findings,"repeated_assets":[{"file":f,"count":len(v),"by_level":dict(Counter(e["level"] for e in v))} for f,v in sorted(usage.items(),key=lambda item:-len(item[1])) if len(v)>=4],
    "assets":assets,"emitters":emitters,"palette":palette}
out=ROOT/"test-results/context-audit-before.json"
out.write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report["counts"]))
print("UI",json.dumps([x for x in assets if any(r.startswith("ui_") for r in x["palette_roles"])]))
print("REPEATS",json.dumps(report["repeated_assets"][:10]))
print("LOOP_RISKS",json.dumps([{"file":a["file"],"metric":a["metrics"]} for a in assets if a["manifest_loop"] and (a["metrics"]["wrap_jump_over_internal_diff_p95"]>4 or a["metrics"]["rms_100ms_p95_to_p05_db"]>15)]))
