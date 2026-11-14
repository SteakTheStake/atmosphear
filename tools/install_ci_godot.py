"""Install the pinned official Godot Linux editor and Web templates for CI."""
from pathlib import Path
import argparse
import hashlib
import os
import shutil
import urllib.request
import zipfile

VERSION = "4.6.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/"
# Published official SHA512-SUMS.txt for this exact release, pinned in source.
FILES = {
    f"Godot_v{VERSION}-stable_linux.x86_64.zip": "b6e4d5a716085e9649905be2afe77f723f97853544fb33392ce3d32594c730a95d9eb4d1042ed51508904c9e1d996bd36b7c7a2bf4f93f5b1885e98d81b792e7",
    f"Godot_v{VERSION}-stable_export_templates.tpz": "ce6a91e8d86df3183452c5e40d75fa0faf94268257b1d3dc1e4538caa277ca7c0fd3d113f8104a5515c3af84d49c5cefc77d7d1e7847ba422413d5466feb49fd",
}


def download(name, destination):
    digest = hashlib.sha512()
    request = urllib.request.Request(BASE + name, headers={"User-Agent": "Atmosphear-Godot-CI"})
    print("Downloading", name, flush=True)
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != FILES[name]:
        destination.unlink()
        raise RuntimeError("Official release SHA-512 verification failed: " + name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    target.mkdir(parents=True, exist_ok=True)
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    templates = data_home / "godot/export_templates" / f"{VERSION}.stable"
    templates.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        archive_path = target / name
        download(name, archive_path)
        with zipfile.ZipFile(archive_path) as archive:
            if name.endswith(".zip"):
                member = f"Godot_v{VERSION}-stable_linux.x86_64"
                with archive.open(member) as source, (target / "godot").open("wb") as output:
                    shutil.copyfileobj(source, output)
                (target / "godot").chmod(0o755)
            else:
                for member in archive.namelist():
                    filename = Path(member).name
                    if filename in {"web_release.zip", "web_debug.zip", "version.txt"}:
                        with archive.open(member) as source, (templates / filename).open("wb") as output:
                            shutil.copyfileobj(source, output)
        archive_path.unlink()
    print("Verified Godot", VERSION, "and Web templates installed.", flush=True)


if __name__ == "__main__":
    main()
