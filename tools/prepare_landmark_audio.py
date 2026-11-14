"""Derive fixed, recognizable landmarks only from the user's local audio library.

Run after prepare_library.py and prepare_detail_audio.py. Requires FFmpeg and
NumPy. Source recordings remain untouched; the manifest is replaced by filename
only for the twelve assets owned by this script. No sound is synthesized.
"""
from pathlib import Path
import hashlib
import json
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/library"
SR = 44100

# filename, exact library filename, start, duration, looping, application
ASSETS = [
    ("landmark_waterfall.ogg", "Ambience Waterfall Exterior 03.wav", 12, 24, True,
     "Forest waterfall: continuous broad water roar, distinct from the small stream."),
    ("landmark_frog.wav", "Animal Frog Gray Tree Frog Hi Pitched Chirp 01.wav", 0, 2, False,
     "Fixed wetland frog call; schedule intermittently, not as a mobile source."),
    ("landmark_fountain.ogg", "Liquid Water Pouring Into Water In Plastic Bucket Steady Long Fast 04.wav", 1.2, 8.6, True,
     "Courtyard fountain stand-in: recorded steady water pouring/splashing, not a recording of a fountain."),
    ("landmark_bell.ogg", "04 Church Bells, Near Distance, In Church Tower-3 Different Bell 02.wav", 12, 20, True,
     "Fixed tower bells; actual near-distance church-tower recording, distinct from the existing handbell."),
    ("landmark_horse.wav", "Animal Horse Snort 01.wav", 0, 2, False,
     "Stable horse breath/snort; animal vocalization, no human voice; schedule intermittently."),
    ("landmark_pump.ogg", "Industry Hydraulic Pump Run 01.wav", 3, 16, True,
     "Cistern pump machinery; hydraulic pump Foley stand-in for the fixed pump station."),
    ("landmark_chain.wav", "Industry Chain Pull 01.wav", 0, 5, False,
     "Fixed chain mechanism or well winch; recorded chain pull, schedule intermittently."),
    ("landmark_air.ogg", "Industry Tool Air Escaping From Air Compressor Blower Nozzle 24.wav", 2, 10, True,
     "Fixed air valve/pressure leak; recorded escaping compressed air."),
    ("landmark_water_resonance.ogg", "Liquid Water Bubbling Shallow In Metal Bowl Steady 06.wav", .25, 3.2, True,
     "Resonant well stand-in: shallow bubbling water in a metal bowl, with natural container resonance."),
    ("landmark_electric.ogg", "MACHAppl_Deep Fridge Hum, Buzz, Electric Tone, Deep_Jake Fielding_Fridge Hums Pt2.wav", 25, 20, True,
     "Fixed electrical bay: real deep appliance motor hum/buzz, not radio speech or an alarm."),
    ("landmark_servo.ogg", "Technology Electronic Servo Motor Pulsing 08.wav", .6, 7.8, True,
     "Fixed servo/automation bay: recorded pulsing servo motor, not a navigation beep."),
    ("landmark_cargo.wav", "Foley Cargo Shakes And Rattles Long 0.wav", .1, 5.5, False,
     "Fixed loose cargo rack: recorded cargo shaking/rattling, schedule intermittently."),
]


def source_path(name):
    matches = [p for p in (ROOT / "audio").rglob("*.wav") if p.name == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one source for {name!r}, found {len(matches)}")
    return matches[0]


def decode(path, start, duration):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(start), "-i", str(path),
        "-t", str(duration), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-",
    ])
    samples = np.frombuffer(data, dtype="<f4").copy()
    if len(samples) < SR * .08 or not np.isfinite(samples).all():
        raise ValueError(f"Invalid or empty recording: {path}")
    return samples


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for name, source, start, duration, loop, application in ASSETS:
        path = source_path(source)
        samples = decode(path, start, duration)
        samples -= float(np.mean(samples))
        crossfade = min(.4, len(samples) / SR * .12) if loop else 0
        if loop:
            n = int(crossfade * SR)
            phase = np.linspace(0, np.pi / 2, n)
            samples = np.concatenate([
                samples[n:-n], samples[-n:] * np.cos(phase) + samples[:n] * np.sin(phase)
            ])
        else:
            # Keep natural event duration; trim only low-level leading/trailing silence.
            active = np.flatnonzero(np.abs(samples) > max(float(np.max(np.abs(samples))) * .006, .00002))
            if not len(active):
                raise ValueError(f"Silent source: {source}")
            begin = max(0, int(active[0]) - int(.012 * SR))
            end = min(len(samples), int(active[-1]) + int(.045 * SR))
            samples = samples[begin:end]
            start += begin / SR
            n = min(int(.005 * SR), len(samples) // 4)
            samples[:n] *= np.linspace(0, 1, n)
            samples[-n:] *= np.linspace(1, 0, n)
        peak = float(np.max(np.abs(samples)))
        rms = float(np.sqrt(np.mean(samples * samples)))
        gain = min(10 ** (18 / 20), .78 / peak, .10 / rms if loop else .65 / peak)
        samples = np.asarray(samples * gain, dtype="<f4")
        output = OUT / name
        codec = ["-c:a", "libvorbis", "-q:a", "4"] if loop else ["-c:a", "pcm_s16le"]
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
            *codec, str(output)
        ], input=samples.tobytes(), check=True)
        # Check the encoded result too, including any lossy-encoding peak overshoot.
        decoded = decode(output, 0, len(samples) / SR + .2)
        encoded_peak = float(np.max(np.abs(decoded)))
        if encoded_peak >= .99 or np.sqrt(np.mean(decoded * decoded)) < .0001:
            raise ValueError(f"Encoded output failed peak/signal validation: {name}")
        entries.append({
            "file": output.relative_to(ROOT).as_posix(),
            "sources": [{"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}],
            "source_start_seconds": round(start, 5), "duration_seconds": round(len(samples) / SR, 5),
            "sample_rate": SR, "channels": 1, "loop": loop,
            "gain_db": round(float(20 * np.log10(gain)), 3),
            "peak_dbfs": round(float(20 * np.log10(encoded_peak)), 3),
            "rms_dbfs": round(float(20 * np.log10(np.sqrt(np.mean(decoded * decoded)))), 3),
            "processing": f"Mono 44.1 kHz; DC removal; {'equal-power wrap crossfade ' + str(round(crossfade * 1000)) + ' ms' if loop else 'silence trim and 5 ms edge fades'}; bounded gain; {'Vorbis q4' if loop else 'PCM16'}; no added reverb or synthesized signal.",
            "application": application,
            "selection": "Non-human-voice source labels and signal inspection. Original unchanged. No speech, crowd, radio dialogue, or synthesized replacement selected.",
        })
        print(f"{name}: {len(samples)/SR:.2f}s, peak {entries[-1]['peak_dbfs']} dBFS, RMS {entries[-1]['rms_dbfs']} dBFS", flush=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf8"))
    owned = {e["file"] for e in entries}
    manifest["assets"] = [e for e in manifest["assets"] if e["file"] not in owned] + entries
    manifest["landmark_notes"] = "Twelve fixed landmark recordings added for expanded environments. Loop recordings have wrap crossfades; animal, chain and cargo calls remain one-shots. Application fields identify Foley stand-ins honestly. Source recordings remain untouched. Regenerate base library, detail library, then landmarks in that order."
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf8")
    total = sum(p.stat().st_size for p in OUT.iterdir() if p.suffix in (".wav", ".ogg"))
    print(f"{len(manifest['assets'])} assets, {total / 1e6:.3f} MB total")


if __name__ == "__main__":
    main()
