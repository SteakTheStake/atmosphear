"""Review incremental browser captures with the optional audio API.

Example: python tools/review_mix_batch.py after --wait --expected 28
Uses the same OPENAI_API_KEY and opt-in upload behavior as review_mix_audio.py.
"""
import argparse
import json
from pathlib import Path
import time
from review_mix_audio import review

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("phase", choices=["before", "after", "final-bells"])
parser.add_argument("--wait", action="store_true")
parser.add_argument("--expected", type=int, default=28)
args = parser.parse_args()
report = Path("test-results") / f"mix-audit-{args.phase}.json"
seen = set()
deadline = time.monotonic() + 1500
while time.monotonic() < deadline:
    if not report.exists():
        if not args.wait: raise SystemExit("No capture report: " + str(report))
        time.sleep(3)
        continue
    try:
        captured = json.loads(report.read_text(encoding="utf8"))
    except json.JSONDecodeError:
        time.sleep(1)
        continue
    for item in captured.get("areas", []) + captured.get("walks", []) + captured.get("longs", []):
        source = item["raw_capture"]
        if source in seen: continue
        # Blind review: do not tell the model what scene or species it should hear.
        result = review(source)
        print(json.dumps({"capture": source, "observations": result["observations"]}), flush=True)
        seen.add(source)
    if not args.wait or len(seen) >= args.expected: break
    if captured.get("failure"): raise SystemExit(captured["failure"])
    time.sleep(3)
print("AUDIO REVIEWS COMPLETE", len(seen), flush=True)
