"""Build the Windows x64 HRTF GDExtension from pinned, verified dependencies."""
from pathlib import Path
import argparse
import hashlib
import os
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / "build/native_deps"
CPP_COMMIT = "27d9dd23c83871e0619fca5dc2cddfbfd69e926a"
ARCHIVES = {
    "godot-cpp-27d9dd23.zip": (
        f"https://codeload.github.com/godotengine/godot-cpp/zip/{CPP_COMMIT}",
        "20856bc47c726fc139e7226e1b07d753f0a59c660ffdd31e333c80ae793db2f9",
    ),
    "steamaudio_4.8.1.zip": (
        "https://github.com/ValveSoftware/steam-audio/releases/download/v4.8.1/steamaudio_4.8.1.zip",
        "4a0aa5ec1176f38f0b0993a37c2259d9e86f27e22d5e24f83ec4c3cb9a1d5449",
    ),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 2))
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("This native build currently targets Windows x64.")
    DEPS.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    for name, (url, digest) in ARCHIVES.items():
        archive = DEPS / name
        if not archive.exists():
            print("Downloading", name, flush=True)
            urllib.request.urlretrieve(url, archive)
        with archive.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                raise SystemExit("Dependency checksum mismatch: " + str(archive))
        with zipfile.ZipFile(archive) as bundle:
            if name.startswith("godot-cpp"):
                marker = DEPS / "godot-cpp/.atmo-version"
                if marker.exists() and marker.read_text() == CPP_COMMIT:
                    continue
                for info in bundle.infolist():
                    relative = Path("godot-cpp", *Path(info.filename).parts[1:])
                    if not info.is_dir():
                        target = DEPS / relative
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(bundle.read(info))
                marker.write_text(CPP_COMMIT)
            else:
                for info in bundle.infolist():
                    needed = info.filename.endswith(("/phonon.h", "/phonon_version.h", "/phonon.lib", "/phonon.dll")) and ("/include/" in info.filename or "/windows-x64/" in info.filename)
                    if needed and not info.is_dir():
                        target = DEPS / info.filename
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(bundle.read(info))
    build = ROOT / "build/native_audio"
    subprocess.run(["cmake", "-S", str(ROOT / "native"), "-B", str(build), "-A", "x64", f"-DATMO_DEPS={DEPS.as_posix()}"], check=True)
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--parallel", str(args.jobs)], check=True)
    binary = build / "bin/atmo_audio.dll"
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()[:16]
    target = ROOT / "native/bin" / digest
    target.mkdir(parents=True, exist_ok=True)
    # Immutable library paths allow rebuilding while an editor has an older DLL
    # loaded. An open editor must be restarted to use the newly built extension.
    for source in (binary, DEPS / "steamaudio/lib/windows-x64/phonon.dll"):
        destination = target / source.name
        if not destination.exists():
            shutil.copy2(source, destination)
    descriptor = ROOT / "native/atmo_audio.gdextension"
    descriptor.write_text(
        '[configuration]\nentry_symbol = "atmo_audio_init"\ncompatibility_minimum = "4.5"\nreloadable = false\n\n'
        f'[libraries]\nwindows.x86_64 = "res://native/bin/{digest}/atmo_audio.dll"\n\n'
        f'[dependencies]\nwindows.x86_64 = {{"res://native/bin/{digest}/phonon.dll": ""}}\n',
        encoding="utf8", newline="\n",
    )
    print("Native HRTF renderer ready:", target / "atmo_audio.dll", flush=True)


if __name__ == "__main__":
    main()
