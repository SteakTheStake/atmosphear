# Coastal forest & river

`scenes/levels/forest_river.tscn` is the default main level. The original editable
starter and all four legacy levels remain intact. The Blender source and backups
are not modified by game import.

The scene contains the authored 600 terrain/water/tree mesh objects, 39 Bezier
flight/escape paths, 14 proximity takeoff definitions, and 153 sound anchors.
Geometry is saved in `assets/worlds/forest/terrain.scn` and is loaded as an ordinary
Godot scene, not rebuilt procedurally during play. Terrain vertices remain in
metres. Blender `(x,y,z)` maps to Godot `(x,z,-y)`; Bezier handle offsets are preserved.

Terrain bodies have editable three-band acoustic profiles. Footsteps raycast the
actual ground collider, so height and slopes determine the material instead of
overlapping 2D rectangles. Grass, dirt, forest litter, sand, wet dirt, wet sand,
marsh and water have eight replaceable footfall slots each in the sound palette.
Stone and gravel use the existing varied recordings. Sand is a documented filtered
granular-footstep approximation; wet surfaces blend recorded soil/granular steps
with real water footsteps. No synthetic Foley is introduced.
Physical outer map limits occupy a separate collision layer and do not create
artificial acoustic reflections around the ocean.

Birds use the imported curves at metres-per-second speed. Takeoffs trigger on
proximity entry, select an escape directed away from the player, and rearm only
after leaving the larger radius and completing the cooldown. They do not fire
every frame. A short, irregular sequence of two or three follow-up calls makes
the flight away audible after the initial startled call. One-way ambient routes
finish silently and return after a randomized rest, avoiding audible teleports.
Both bird motion and event cooldowns freeze while paused. There is
no fabricated wingbeat recording: takeoff currently uses the assigned bird call
moving along the escape path. Replace these sound slots in the Inspector when a
suitable supplied recording becomes available.

Local source groups distinguish oak, birch and spruce pockets, freshwater marsh,
river reaches, estuary, surf, and exposed ridges. Individual trees have their own
leaf-wind anchors placed in air beside the solid trunks. To keep the scene scalable, `forest_world.gd` instantiates at
most 18 selected environment voices plus four releasing voices, with group caps
and hysteresis. Continuous beds fade over 0.7/1.1 seconds; close takeoffs retain
their attack. Moving sound sources retain velocity for propagation/Doppler.

The water surface has a separate physics layer. Submersion detection crossfades
external-source filtering toward 850 Hz with 7 dB attenuation, without playing a
generic underwater drone. This is medium acoustics, not a swimming simulation.
Sound travels through the existing bounded geometric-acoustics renderer; it is
not a full wave solver. The 24 m sampled coastline and estimated seabed remain
first-pass bathymetry. A static plan shows terrain and landmarks only, never the
player, heading or trail; ordinary play can hide it for black-screen listening.

## Mix direction

The mix uses a clear direct signal, restrained geometry-dependent reflections,
and distance falloff. No global chorus, doubled dry layer, modulation or extra
master reverb is added. Footsteps and nearby takeoffs provide foreground detail;
water is a continuous navigational landmark; foliage, wind, insects and occasional
calls provide a quieter background. Raw water beds have rumble reduction and
loop-wrap crossfades. The mix keeps transient headroom rather than forcing every
source to the same loudness. Menu clicks retain their existing soft feedback.

Doppler defaults to moving emitters and bird paths. Wind, leaf rustle, water beds,
stationary landmarks and self-generated footsteps keep stable pitch while their
distance, panning, filtering and reverb continue to update. Ambient early paths
retain fixed excess-delay taps to avoid pitch glides. Each sound emitter exposes
an Automatic / Disabled / Enabled Doppler override in the Inspector.

Audio files come only from the supplied library. New derivatives and source
hashes are recorded in the local catalog; `package_used_audio.py --write` publishes
only the dependency closure of playable scenes and their actual sound slots.
No raw library folder is required by exported builds.

## Rebuild after approved Blender edits

Reimporting replaces the generated Godot forest scene and its geometry; save a
separate copy before hand-editing them. Shared palette edits outside the forest
terrain slots are preserved.

1. Run Blender headlessly on `Blender/Authoring/Forest_River_Audio_Authored.blend`
   with `--python Blender/Authoring/export_game_map.py`.
2. Run `python tools/create_forest_plan.py`.
3. If preparing recordings again, run `python tools/prepare_forest_audio.py`
   (local raw library, FFmpeg and NumPy required).
4. Run `godot_console --headless --editor --path . --import`.
5. Run `godot_console --headless --path . --script tools/import_forest_map.gd`.
6. Import once more, then run `python tools/package_used_audio.py --write`.
7. Build with `python tools/build_pages.py --output build/web`; add
   `--mobile --output build/web/mobile` for the phone build.

## Validation

`tests/forest_world.gd` checks default assignment, spawn collision, geometry,
terrain-dependent footsteps, bounded voices, natural proximity entry, animated
takeoff movement, pause, submersion filtering, and legacy cleanup. Existing audio
authoring and acoustic integration tests cover live sound replacement and bus
cleanup. Browser captures audit actual mixed stereo output in all seven regions;
automated audio-input review is an additional audition aid, not a human headphone
listening session. Synthetic controller/device tests do not certify a physical
8BitDo controller on iPhone Chrome.

The final local release audit recorded seven regional samples, a proximity
takeoff, and a walking/turning sample. The mixed output had zero clipped samples;
the highest measured true peak was -13.3 dBFS. The takeoff capture contained four
separate calls, starting near the player and following the escape route. Short
audio-input reviews described clear foreground footsteps, leaf rustle, water and
bird calls without obvious looping or distortion; receding bird motion still
benefits from a human headphone check. The stereo captures and full measurements
are under `test-results/`, with `forest-integration-report.json` as the index.

Controller-only browser routing passed on desktop and an iPhone 13-sized Chromium
setup, including the default forest, all menus/settings, legacy levels, rotation,
reconnects and audio-interruption recovery. Physical iPhone/8BitDo testing remains
separate. The exported Windows pack passed the existing WASAPI smoke checks for
continuous stereo PCM, collision, pause, DSP path capacity and bus cleanup across
the default map and all four legacy levels. The initial Dummy-driver timing run
did not meet its realtime frame-count assertion; the WASAPI run passed it.

Local builds are `build/web/`, `build/web/mobile/`, and
`build/forest-release/windows/`; the separate Windows ZIP is under
`build/forest-release/`. The Pages workflow builds both browser variants, checks
controller routing and the forest integration, and deploys updates to `main`.
Windows-only native audio is excluded from the browser build.
