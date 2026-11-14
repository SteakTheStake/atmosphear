"""Validate a PWA export and scope Godot's offline cache to this Pages project.

Run after export, never edit generated engine/audio files. Godot's official
worker supplies COOP/COEP; cache identity and document aliases are scoped here.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path, nargs="?", default=Path("build/pages"))
    args = parser.parse_args()
    directory = args.directory.resolve()
    html = (directory / "index.html").read_text(encoding="utf8")
    assert "$GODOT_" not in html, "Unexpanded HTML export placeholder"
    mobile = 'const ATMO_MOBILE_BUILD=true;' in html
    assert re.search(r'"ensureCrossOriginIsolationHeaders"\s*:\s*' + ('false' if mobile else 'true'), html), "Isolation setting disagrees with build variant"
    assert "prepareAudioHost" in html, "Custom shell must install the worker before the threaded engine"
    workers = list(directory.glob("*.service.worker.js"))
    assert len(workers) == 1, "Expected Godot's generated service worker"
    worker = workers[0]
    assert (directory / "index.wasm").is_file() and (directory / "index.pck").is_file()
    inventory = json.loads((ROOT / "assets/library/used_audio.json").read_text(encoding="utf8"))
    expected_audio = {asset["file"] for asset in inventory["files"]}
    packed_audio = {value.decode().removeprefix("res://").removesuffix(".import") for value in re.findall(
        rb"(?:res://)?assets/library/[A-Za-z0-9_ ./-]+?\.(?:wav|ogg|mp3|flac|aiff?)\.import", (directory / "index.pck").read_bytes())}
    assert packed_audio == expected_audio, f"PCK audio closure mismatch; missing={sorted(expected_audio-packed_audio)}, extra={sorted(packed_audio-expected_audio)}"
    staged_audio = {p.name for p in (directory / "sound").iterdir() if p.is_file()}
    assert staged_audio == {Path(p).name for p in expected_audio}, "Browser audio closure mismatch"
    for path in expected_audio:
        assert hashlib.sha256((directory / "sound" / Path(path).name).read_bytes()).digest() == hashlib.sha256((ROOT / path).read_bytes()).digest(), "Staged audio bytes differ: " + path
    fingerprint = hashlib.sha256()
    assets = []
    for path in sorted(directory.rglob("*")):
        if path.relative_to(directory).parts[0] == "mobile" or not path.is_file() or path == worker or path.name in {".nojekyll", "pages-build.json"}:
            continue
        data = path.read_bytes()
        fingerprint.update(path.relative_to(directory).as_posix().encode() + b"\0" + data)
        assets.append({"file": path.relative_to(directory).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    revision = fingerprint.hexdigest()[:24]
    source = worker.read_text(encoding="utf8")
    source, version_count = re.subn(r"const CACHE_VERSION = .*?;", f"const CACHE_VERSION = 'atmosphear-{revision}';", source, count=1)
    source, prefix_count = re.subn(r"const CACHE_PREFIX = .*?;", "const CACHE_PREFIX = 'atmosphear-' + new URL(self.registration.scope).pathname + '-cache-';", source, count=1)
    assert version_count == 1 and prefix_count == 1, "Godot service-worker format changed; review cache patch"
    assert "ENSURE_CROSSORIGIN_ISOLATION_HEADERS = " + ("false" if mobile else "true") in source
    # Firefox can expose an empty stream for204/205/304. Fetch forbids attaching
    # any body to those statuses when reconstructing a response with headers.
    source = source.replace("new Response(response.body, {", "new Response([204, 205, 304].includes(response.status) ? null : response.body, {")
    cached_match = re.search(r"const CACHED_FILES = (\[.*?\]);", source)
    assert cached_match, "Godot precache format changed"
    cached = json.loads(cached_match.group(1))
    cached += [asset["file"] for asset in assets if asset["file"].endswith((".png", ".manifest.json", ".wav", ".ogg")) and asset["file"] not in cached]
    source = source[:cached_match.start(1)] + json.dumps(cached, separators=(",", ":")) + source[cached_match.end(1):]
    # Project-root and ?debug navigation must use the same cached HTML offline.
    # Other paths retain the stock worker's normal request handling.
    if "Atmosphear scoped navigation alias" not in source:
        anchor = "let cached = await cache.match(event.request);"
        assert anchor in source, "Godot navigation-cache format changed; review alias patch"
        source = source.replace(anchor, anchor + """
                // Atmosphear scoped navigation alias (HTML only).
                if (cached == null && isNavigate) {
                    const navigation = new URL(event.request.url);
                    const scope = new URL(self.registration.scope);
                    if (navigation.origin === scope.origin &&
                            [scope.pathname, scope.pathname + CACHED_FILES[0]].includes(navigation.pathname)) {
                        cached = await cache.match(CACHED_FILES[0]);
                    }
                }
""", 1)
    worker.write_text(source, encoding="utf8", newline="\n")
    (directory / ".nojekyll").write_text("", encoding="utf8")
    (directory / "pages-build.json").write_text(json.dumps({"godot": "4.6.2", "revision": revision, "worker": worker.name, "used_audio_count": len(packed_audio), "assets": assets}, indent=2), encoding="utf8")
    print(f"Pages bundle ready: {sum(asset['bytes'] for asset in assets)/1e6:.2f} MB, revision {revision}")


if __name__ == "__main__":
    main()
