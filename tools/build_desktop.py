"""Build a native Windows release with the same verified runtime assets as Web."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot") or "godot")
    parser.add_argument("--output", type=Path, default=ROOT / "build/windows")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Keep build products out of Godot's resource scan, including on clean clones.
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    commands = [
        [sys.executable, "tools/build_native_audio.py"],
        [args.godot, "--headless", "--editor", "--path", str(ROOT), "--import"],
        [sys.executable, "tools/package_used_audio.py", "--check", "--godot", args.godot],
        [sys.executable, "tools/prepare_pages_export.py"],
        [args.godot, "--headless", "--path", str(ROOT), "--script", "tools/export_engine_licenses.gd", "--", str(output / "licenses/GODOT.txt")],
        [args.godot, "--headless", "--path", str(ROOT), "--export-release", "Windows Desktop", str(output / "Atmosphear.exe")],
    ]
    for command in commands:
        print("Running:", " ".join(command), flush=True)
        subprocess.run(command, cwd=ROOT, check=True)
    # Audio terms must accompany the portable release, just as they do the site.
    files = [output / "Atmosphear.exe", output / "licenses/GODOT.txt"]
    for name in ("LICENSE", "THIRD_PARTY_AUDIO.md"):
        files.append(Path(shutil.copy2(ROOT / name, output / name)))
    for source in (ROOT / "licenses").rglob("*"):
        if source.is_file():
            target = output / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            files.append(Path(shutil.copy2(source, target)))
    # GDExtension and Steam Audio are native DLLs beside the embedded game pack.
    for name in ("atmo_audio.dll", "phonon.dll"):
        library = output / name
        if not library.is_file():
            raise SystemExit("Native export is missing a required library: " + str(library))
        files.append(library)
    instructions = output / "README.txt"
    instructions.write_text(
        "Atmosphear - Windows x64\n\n"
        "Double-click Atmosphear.exe. No browser, server, Python or Godot install is needed.\n"
        "Use headphones. WASD: walk; arrows: turn; Shift: run; Space: jump; E: punch; Esc: pause.\n"
        "Standard controllers are supported. Start/Menu pauses; bottom face button selects.\n\n"
        "High-quality native HRTF, shared-clock propagation and 16-line room fields are enabled.\n"
        "Keep the whole extracted folder together, including both native DLLs.\n"
        "Settings includes Headphone binaural audio; turn it off for speakers.\n"
        "If playback crackles, try launching with: Atmosphear.exe --audio-output-latency 60\n"
        "That increases buffering and response delay; it is a troubleshooting option.\n\n"
        "See THIRD_PARTY_AUDIO.md and licenses/ for recording terms.\n",
        encoding="utf8",
    )
    files.append(instructions)
    archive = output.parent / "Atmosphear-windows-x64.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for file in files:
            bundle.write(file, "Atmosphear/" + file.relative_to(output).as_posix())
    print("Native executable:", output / "Atmosphear.exe", flush=True)
    print("Portable download:", archive, flush=True)


if __name__ == "__main__":
    main()
