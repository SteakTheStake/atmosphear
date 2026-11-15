"""Select the proven runtime closure explicitly, including every used recording.

Godot's editor dependency cache can lag headlessly authored scenes. Explicit
selection prevents a valid scene from being packed without its current clips.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def main():
    inventory = json.loads((ROOT / "assets/library/used_audio.json").read_text(encoding="utf8"))
    selected = set(inventory["export_roots"])
    selected.update("res://" + asset["file"] for asset in inventory["files"])
    selected.update("res://" + path.relative_to(ROOT).as_posix() for path in (ROOT / "assets/acoustics").glob("*.tres"))
    for resource in selected:
        assert resource.startswith("res://") and (ROOT / resource[6:]).is_file(), resource
    preset = ROOT / "export_presets.cfg"
    text = preset.read_text(encoding="utf8")
    count = 0
    def selection(match):
        nonlocal count
        header, body = match.groups()
        resources = selected.copy()
        if 'platform="Windows Desktop"' in body:
            resources.add("res://native/atmo_audio.gdextension")
        line = "export_files=PackedStringArray(" + ", ".join(json.dumps(resource) for resource in sorted(resources)) + ")"
        body, changed = re.subn(r"^export_files=PackedStringArray\(.*\)$", lambda _: line, body, flags=re.MULTILINE)
        count += changed
        return header + body
    updated = re.sub(r"(^\[preset\.\d+\]\n)(.*?)(?=^\[|\Z)", selection, text, flags=re.MULTILINE | re.S)
    assert count == 3, "Expected two Web presets and one Windows Desktop preset"
    preset.write_text(updated, encoding="utf8", newline="\n")
    print(f"Explicit runtime selection: {len(selected)} resources, {len(inventory['files'])} used recordings")


if __name__ == "__main__":
    main()
