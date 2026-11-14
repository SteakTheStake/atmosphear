# Publishing only used audio

The playable scenes and their assigned `AudioStream` resources are authoritative. The legacy metadata filenames are retained for editor compatibility and do not decide what gets published.

After importing the Godot project, run:

```powershell
python tools/package_used_audio.py --write
python tools/package_used_audio.py --check
```

Set `GODOT_BIN` or pass `--godot` if the Godot executable is not named `godot_console` or `godot`.

The utility instantiates the main scene and each playable level without running their `_ready` methods. It traverses stored resource properties, including emitter variants, footstep arrays, and menu variants, and inspects GDScript preload constants. It independently checks Godot's selected-root dependency closure and the actual Web preset. Both audio sets must match, so an orphaned audio declaration cannot silently enter the export.

`--write` updates:

- `assets/library/manifest.json`: provenance and output hashes for used recordings only.
- `assets/library/used_audio.json`: used files, sizes, hashes, references, and export roots.
- The marked audio allowlist block in `.gitignore`: used audio and their import settings are allowed; raw recordings, local reports/builds, and unused derivatives remain excluded.
- Each Web preset's explicit resource selection: current runtime roots, used recordings, and acoustic material resources. This removes stale selections after sound swaps while preserving selected-resource mode and every unrelated export option. `--check` rejects stale selections without changing them.

The full provenance catalog is preserved locally in ignored `assets/library/manifest.local.json`. No recording or raw archive is deleted, moved, staged, committed, or pushed. The checker also reports any raw/unused audio already in the Git index because an ignore rule cannot untrack existing files.

`export_presets.cfg` uses **selected resources and dependencies**, with the main scene, all four playable levels, the shared sound palette, and runtime scripts reached only through GDScript preloads selected. Its root list must cover `used_audio.json`. This excludes unused recordings from builds even while they remain available locally. Run Godot's editor import before exporting so its dependency cache reflects scene/resource edits.

A clean clone includes every sound needed to run, test, and export the game. It does not need the original stock library or `manifest.local.json`. The optional audio preparation scripts require the user's original local recordings; after regenerating them or swapping a scene recording, run the packager again. New recordings need a provenance entry before publication. Audio rights remain separate from the code license; see [THIRD_PARTY_AUDIO.md](../THIRD_PARTY_AUDIO.md).

The optional `audit_library_audio.py` measures the published audio by default. It verifies original hashes when the local originals are available. Use `--require-sources` for a strict source audit or `--all-local` to audit the preserved full local catalog. Neither mode is a listening audition.
