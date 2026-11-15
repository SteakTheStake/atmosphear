"""Install the project's pinned Windows Godot editor for desktop CI."""
from pathlib import Path
import argparse
import hashlib
import urllib.request
import zipfile

VERSION = "4.6.2"
DIGEST = "01c3bc0ede0f8771e810832fb92ce52a3a4352af7b7ac32a81a8edf05bb30760f56a6ab7e17cebc80b81c4f609a95c24c2fdbbe6929ac4e0285cb8f654b56d78"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    target.mkdir(parents=True, exist_ok=True)
    archive = target / "godot.zip"
    urllib.request.urlretrieve(f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_win64.exe.zip", archive)
    with archive.open("rb") as stream:
        if hashlib.file_digest(stream, "sha512").hexdigest() != DIGEST:
            raise SystemExit("Official Godot Windows SHA-512 mismatch")
    with zipfile.ZipFile(archive) as bundle:
        for name in bundle.namelist():
            if name.endswith(".exe"):
                (target / Path(name).name).write_bytes(bundle.read(name))
    print(target / f"Godot_v{VERSION}-stable_win64_console.exe")


if __name__ == "__main__":
    main()
