"""Build a verified Pages release using existing assets; no raw audio or FFmpeg."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot") or "godot")
    parser.add_argument("--output", type=Path, default=ROOT / "build/pages")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    commands = [
        [args.godot, "--headless", "--editor", "--path", str(ROOT), "--import"],
        [sys.executable, "tools/package_used_audio.py", "--check", "--godot", args.godot],
        [sys.executable, "tools/prepare_pages_export.py"],
        [args.godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(output / "index.html")],
        [sys.executable, "tools/stage_browser_audio.py", str(output)],
        [sys.executable, "tools/package_pages.py", str(output)],
    ]
    for command in commands:
        print("Running:", " ".join(command), flush=True)
        subprocess.run(command, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
