"""Prepare very soft, short physical-button clicks from the user's recordings.

Writes a manifest patch for the library owner to merge, never manifest.json.
No synthesis, pitch shifting, overlays, bells, knocks, or electronic UI tones.
Validation is provenance and signal analysis; this script does not claim an
auditory audition. Original library recordings remain untouched.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import wave

import numpy as np
from scipy.signal import butter, sosfiltfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/library"
SR = 44100
ATTACK = 0.008
RELEASE = 0.010
FAMILY = {
    "a": "Technology Electronic Button Push Sound System 01.wav",
    "b": "Technology Electronic Button Push Sound System 03.wav",
}
# Separate physical press/release transients of the same button mechanism family.
# Accept is slightly longer; back uses a quieter release. No pitch modification.
CLIPS = [
    ("ui_soft_move0", "a", 0.000, 0.052, -25.0, "first mechanism press"),
    ("ui_soft_move1", "b", 0.001, 0.052, -25.0, "second recorded mechanism press"),
    ("ui_soft_move2", "a", 0.142, 0.044, -25.0, "first mechanism release"),
    ("ui_soft_accept", "a", 0.000, 0.068, -24.0, "slightly longer first press"),
    ("ui_soft_back", "b", 0.137, 0.046, -26.0, "quieter second mechanism release"),
]


def decode(path):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"
    ])
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def metrics(x):
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x * x)))
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    frequencies = np.fft.rfftfreq(len(x), 1 / SR)
    total = float(spectrum.sum())
    return {
        "peak_dbfs": round(20 * np.log10(max(peak, 1e-12)), 3),
        "rms_dbfs": round(20 * np.log10(max(rms, 1e-12)), 3),
        "crest_db": round(20 * np.log10(peak / max(rms, 1e-12)), 3),
        "spectral_centroid_hz": round(float((frequencies * spectrum).sum() / total), 1),
        "energy_above_5khz_fraction": round(float(spectrum[frequencies > 5000].sum() / total), 6),
        "largest_fft_bin_energy_fraction": round(float(spectrum.max() / total), 5),
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    paths = {}
    decoded = {}
    hashes = {}
    # Band-limit the whole recording before cropping to avoid artificial filter
    # startup transients. This removes bass thumps and brittle high-end clicks.
    band = butter(2, [300, 3200], btype="bandpass", fs=SR, output="sos")
    for key, name in FAMILY.items():
        matches = list((ROOT / "audio").rglob(name))
        if len(matches) != 1:
            raise ValueError(f"Expected one unambiguous source for {name}: {matches}")
        paths[key] = matches[0]
        decoded[key] = sosfiltfilt(band, decode(paths[key]))
        hashes[key] = hashlib.sha256(paths[key].read_bytes()).hexdigest()
    entries = []
    for name, key, start, seconds, target_peak, selection in CLIPS:
        begin = round(start * SR)
        x = decoded[key][begin:begin + round(seconds * SR)].copy()
        x -= x.mean()
        attack = round(ATTACK * SR)
        release = round(RELEASE * SR)
        x[:attack] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, attack))
        x[-release:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, release))
        source_peak = float(np.abs(x).max())
        assert source_peak > 1e-5 and np.isfinite(x).all(), name
        gain = 10 ** (target_peak / 20) / source_peak
        pcm = np.clip(np.rint(x * gain * 32767), -32767, 32767).astype("<i2")
        output = OUT / (name + ".wav")
        with wave.open(str(output), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes(pcm.tobytes())
        measured = metrics(pcm.astype(np.float64) / 32768)
        assert 0.035 <= len(pcm) / SR <= 0.080
        assert measured["peak_dbfs"] <= -23.99
        assert pcm[0] == 0 and pcm[-1] == 0
        entry = {
            "file": output.relative_to(ROOT).as_posix(),
            "sources": [{"path": paths[key].relative_to(ROOT).as_posix(), "sha256": hashes[key]}],
            "source_start_seconds": start,
            "duration_seconds": round(len(pcm) / SR, 5),
            "sample_rate": SR, "channels": 1, "loop": False,
            "gain_db": round(float(20 * np.log10(gain)), 3),
            **measured,
            "processing": "Physical button press/release excerpt; mono PCM16 at44.1kHz;300–3200Hz second-order bandpass on source;DC removal;8ms raised-cosine attack and10ms release;peak normalization to a quiet bounded level;no synthesis or pitch/time changes.",
            "selection": selection + "; same sound-system physical button family. Provenance and waveform/spectrum checked; no listening audition claimed.",
        }
        entries.append(entry)
        print(name, json.dumps({"duration_ms": round(len(pcm) / SR * 1000, 2), **measured}), flush=True)
    patch = {
        "assets": entries,
        "menu_notes": "Short soft mechanical button feedback replaces the previous sci-fi terminal sounds. Runtime menu volume is independent. Preserve previous entries as historical library provenance; runtime palette selects the new ui_soft clips.",
        "supersedes_runtime_menu_files": ["ui_move.wav", "ui_accept.wav", "ui_back.wav"],
    }
    (OUT / "menu_manifest_patch.json").write_text(json.dumps(patch, indent=2), encoding="utf8")


if __name__ == "__main__":
    main()
