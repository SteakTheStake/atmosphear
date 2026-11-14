"""Optional audio-model audition of actual browser captures, never used by the game.

Reads OPENAI_API_KEY from the environment; recordings go to OpenAI for analysis.
Usage: python tools/review_mix_audio.py capture.webm --environment "Forest bird grove"
Outputs a local JSON report beside the capture. Requires requests and FFmpeg.
"""
import argparse
import base64
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import wave
import requests


def review(path, environment="", model="gpt-audio-1.5"):
    path = Path(path)
    output = path.with_suffix(".review.json")
    source_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    if output.exists():
        previous = json.loads(output.read_text(encoding="utf8"))
        if previous.get("review_version") == 2 and previous.get("environment") == environment and previous.get("capture_sha256") == source_hash and previous.get("requested_model", previous.get("model")) == model:
            return previous
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("Set OPENAI_API_KEY to run this optional audio review.")
    # Preserve actual captured level and stereo. Do not normalize before judging balance.
    pcm = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-ar", "24000", "-ac", "2", "-f", "s16le", "-"])
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as encoded:
        encoded.setnchannels(2)
        encoded.setsampwidth(2)
        encoded.setframerate(24000)
        encoded.writeframes(pcm)
    wav = buffer.getvalue()
    duration = len(pcm) / (24000 * 4)
    prompt = (
        f"Listen carefully to this {duration:.1f}-second actual browser-game audio capture. First describe only sounds you hear; "
        "do not infer unheard sounds from the environment label. Then assess the mix for a quiet, speech-free "
        "exploration game: foreground/background balance, harsh or startling transients, masking of landmarks, "
        "unconvincing sound context, obvious loop repetition or metronomic events, and noticeable artifacts. "
        "Distinguish concrete audible observations from uncertainty; do not invent exact dB values. "
        "If none needs changing say so. Provide concise actionable observations, referring to audible sound "
        "types. Do not invent timestamps or sounds not clearly present. The audio is unnormalized: don't assume playback gain. "
        + ("Intended environment (context only): " + environment + ". " if environment else "")
        + "Return JSON with keys heard, balance, repetition, context_fit, artifacts, suggested_changes, confidence. "
        "Do not include markdown fences."
    )
    payload = {"model": model, "modalities": ["text"], "store": False, "max_completion_tokens": 950,
               "messages": [{"role": "system", "content": "Analyze the attached audio signal. Treat environment labels as context, not evidence. If sounds cannot be identified, report uncertainty rather than inventing events or timestamps. Return a JSON object."}, {"role": "user", "content": [
                   {"type": "text", "text": prompt},
                   {"type": "input_audio", "input_audio": {"data": base64.b64encode(wav).decode("ascii"), "format": "wav"}}
               ]}]}
    response = requests.post("https://api.openai.com/v1/chat/completions", json=payload,
                             headers={"Authorization": "Bearer " + key}, timeout=120)
    if not response.ok:
        error = response.json().get("error", {})
        # Never print request headers or payloads containing credentials/audio bytes.
        raise RuntimeError(f"Audio review failed: HTTP {response.status_code}, {error.get('code')}: {error.get('message', '')}")
    data = response.json()
    content = data["choices"][0]["message"]["content"]
    try:
        observations = json.loads(content)
    except json.JSONDecodeError:
        observations = {"text": content}
    report = {"review_version": 2, "duration_seconds": duration, "capture": path.name, "capture_sha256": source_hash, "model": data.get("model", model),
              "requested_model": model, "environment": environment,
              "reviewed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "method": "Audio-input model review of actual unnormalized browser output; not a human headphone audition.",
              "observations": observations, "usage": data.get("usage", {})}
    output.write_text(json.dumps(report, indent=2), encoding="utf8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture")
    parser.add_argument("--environment", default="")
    parser.add_argument("--model", default="gpt-audio-1.5")
    args = parser.parse_args()
    result = review(args.capture, args.environment, args.model)
    print(json.dumps(result, indent=2))
