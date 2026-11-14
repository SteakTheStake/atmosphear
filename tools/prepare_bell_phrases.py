"""Make two finite church-bell phrases from the unchanged local recording.

Requires FFmpeg and NumPy. Updates only the local provenance catalog; run
package_used_audio.py --write after assigning the new streams to a scene.
"""
from pathlib import Path
import hashlib
import json
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/library"
SR = 44100
PASSAGES = [("bell_phrase0.ogg", 1.0, 12.0), ("bell_phrase1.ogg", 29.0, 12.0)]
PEAK_LIMIT = 10 ** (-9.0 / 20)


def decode(path, start=0, duration=None):
    command = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", str(path)]
    if duration is not None:
        command += ["-t", str(duration)]
    command += ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    result = np.frombuffer(subprocess.check_output(command), dtype="<f4").copy()
    if not len(result) or not np.isfinite(result).all():
        raise ValueError(f"Invalid audio in {path}")
    return result


def encode(path, samples):
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR),
        "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "4", str(path),
    ], input=np.asarray(samples, dtype="<f4").tobytes(), check=True)


def db(value):
    return round(float(20 * np.log10(max(1e-10, value))), 3)


def main():
    catalog_path = OUT / "manifest.local.json"
    source_catalog = catalog_path if catalog_path.exists() else OUT / "manifest.json"
    catalog = json.loads(source_catalog.read_text(encoding="utf8"))
    bell = next(entry for entry in catalog["assets"] if entry["file"] in (
        "assets/library/landmark_bell.ogg", "assets/library/bell_phrase0.ogg",
    ))
    provenance = bell["sources"][0]
    source = ROOT / provenance["path"]
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if source_hash != provenance["sha256"]:
        raise ValueError("Church-bell source differs from its recorded provenance")
    duration = float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(source),
    ]))
    print(f"Original duration: {duration:.6f}s", flush=True)
    assert PASSAGES[0][1] + PASSAGES[0][2] <= PASSAGES[1][1]
    clips = []
    for name, start, length in PASSAGES:
        if start + length > duration:
            raise ValueError(f"Passage exceeds original duration: {name}")
        samples = decode(source, start, length)
        if len(samples) != round(length * SR):
            raise ValueError(f"Unexpected passage duration: {name}")
        samples -= float(np.mean(samples))
        attack = round(.05 * SR)
        release = round(3.0 * SR)
        samples[:attack] *= .5 - .5 * np.cos(np.linspace(0, np.pi, attack))
        samples[-release:] *= .5 + .5 * np.cos(np.linspace(0, np.pi, release))
        clips.append(samples)
    # One multiplier preserves the recording's relative dynamics across both
    # passages. Reserve a small margin for Vorbis reconstruction overshoot.
    gain = 10 ** (-9.15 / 20) / max(float(np.max(np.abs(clip))) for clip in clips)
    for attempt in range(4):
        encoded = []
        for (name, _, _), samples in zip(PASSAGES, clips):
            encode(OUT / name, samples * gain)
            encoded.append(decode(OUT / name))
        peak = max(float(np.max(np.abs(clip))) for clip in encoded)
        if peak <= PEAK_LIMIT:
            break
        gain *= PEAK_LIMIT / peak * .99
    else:
        raise ValueError("Encoded shared-gain bell phrases exceed the peak limit")
    entries = []
    for (name, start, length), samples in zip(PASSAGES, encoded):
        rms = float(np.sqrt(np.mean(samples * samples)))
        if rms <= .0001 or len(samples) != round(length * SR):
            raise ValueError(f"Encoded phrase failed signal validation: {name}")
        entry = {
            "file": f"assets/library/{name}",
            "sources": [{"path": provenance["path"], "sha256": source_hash}],
            "source_duration_seconds": duration,
            "source_start_seconds": start,
            "source_end_seconds": start + length,
            "duration_seconds": length,
            "sample_rate": SR, "channels": 1, "loop": False,
            "gain_db": db(gain), "shared_gain_group": "church_bell_phrases",
            "peak_dbfs": db(float(np.max(np.abs(samples)))),
            "rms_dbfs": db(rms),
            "processing": "Mono 44.1 kHz; DC removal; 50 ms raised-cosine attack and 3 s raised-cosine release; shared gain for both passages; decoded sample peaks limited to -9 dBFS; Vorbis q4; no looping, synthesized signal, time/pitch copies, or added reverb.",
            "application": "Finite church-bell phrase for an intermittent fixed bell landmark with substantial silence between events. Separate nonoverlapping passages of the same actual church-tower recording, not independent takes.",
            "selection": "Source provenance, duration, and signal measurements only. No listening audition claimed by this preparation script.",
            "asset_sha256": hashlib.sha256((OUT / name).read_bytes()).hexdigest(),
        }
        entries.append(entry)
        print(f"{name}: {length:.1f}s, peak {entry['peak_dbfs']} dBFS, RMS {entry['rms_dbfs']} dBFS, shared gain {entry['gain_db']} dB", flush=True)
    replaced = {entry["file"] for entry in entries}
    catalog["assets"] = [entry for entry in catalog["assets"] if entry["file"] not in replaced] + entries
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print("Updated local provenance catalog only; assign scenes before packaging.")


if __name__ == "__main__":
    main()
