# atmosphear
Puzzle game based on an original concept Take 5 from Chuck Sutton

The current prototype is a speech-free, sound-led walking simulator made in Godot 4.6.2. Explore four low-poly environments using a controller or keyboard. There are no spoken directions or objectives. Geometry, distance, surface materials, footsteps, and fixed sound landmarks provide orientation.

**[Play in your browser](https://SteakTheStake.github.io/atmosphear/)** · Headphones recommended.

## Environments

Each environment has six connected areas, routes that loop back, and local sound details:

| Environment | Areas | Size |
|---|---|---|
| Forest & lake | Clearing, bird grove, boardwalk, waterfall cove, timber hut, frog wetland | 108 × 108 m |
| Stone cistern | Bell vault, reservoir, drip gallery, pump room, overflow passage, airshaft | 90 × 110 m |
| Deep-space freighter | Engine hall, electrical gallery, cargo hold, servo workshop, ventilation, airlock | 90 × 110 m |
| Rain courtyard | Bell gate, rain square, cloister, fountain, stable, wind tower | 108 × 108 m |

The optional map is a fixed plan of objects and landmarks. It never shows the player, heading, or trail. Hide it for black-screen listening. Developer mode can separately reveal geometry, sources, and acoustic paths.

## Controls

| Action | Keyboard | Standard controller |
|---|---|---|
| Enter the browser game | Enter | A / bottom face button, or Start / Menu |
| Walk / strafe | WASD | Left stick |
| Turn | Left/right arrows | Right stick |
| Run | Hold Shift; Ctrl toggles | Hold LB; left-stick click toggles |
| Jump | Space | A / bottom face button |
| Punch / brush a surface | E | X / left face button, or RT |
| Map | M | Y / top face button |
| Pause | Escape | Start / Menu, or B / right face button |
| Acoustic debug | F3 | Right-stick click |
| Navigate menus | Arrows, Enter; Escape goes back | D-pad or left stick, A; B goes back |

Menus and settings are native Godot controls. Very soft, short recorded clicks have an independent **Menu feedback volume** control. Gameplay map toggles make no menu sound. Settings persist when browser storage is available.

The browser launch screen polls connected controllers and resumes the actual audio engine on A / bottom face button or Start / Menu. Release the launch button, then choose an environment with a second press. The launch press is consumed so it cannot also select a level or jump. Settings, restarting, changing environments, and returning to the menu are accessible from the controller.

Keep the browser tab visible and focused. Current Chromium browsers grant audio activation for a real controller button press; Firefox added that behavior in version 155. Older browsers or restrictive audio permissions may still require allowing sound or one click / Enter. The launch screen detects a suspended audio engine and explains this instead of entering a silent game. Browser policies cannot be overridden by the game. See the [Chromium gamepad implementation](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/gamepad/navigator_gamepad.cc) and [Firefox implementation issue](https://bugzilla.mozilla.org/show_bug.cgi?id=1679817).

## Phones and controllers

The main URL automatically selects the dedicated [mobile build](https://steakthestake.github.io/atmosphear/mobile/) on Android, iPhone and iPad. Pair a standard dual-stick Bluetooth/USB controller in device settings, then open the game in the system browser. Press the bottom face button to begin. Some browsers require one tap on the launch button to allow audio; menus, settings, level selection and gameplay then use the controller. The right face button also pauses during gameplay if the phone reserves Menu/Start.

For an iPhone with an Xbox-style 8BitDo controller, use its iOS-supported pairing mode and check that it appears connected in iPhone Bluetooth settings. Open the link directly in Chrome; if Chrome does not expose the controller, compare the same link in Safari. Exact pairing combinations depend on the 8BitDo model. The game uses the browser's standard mapping rather than assuming an 8BitDo-specific button numbering scheme.

The mobile export uses single-threaded Godot and retains the separate AudioWorklet spatial renderer. It needs WebGL 2 and AudioWorklet but does not require SharedArrayBuffer or cross-origin isolation. Its cache is scoped separately from the desktop build. Phone-sized menus scroll to keep controller focus visible, support both orientations, and account for safe areas. Canvas resolution is capped at CSS pixels to limit rendering cost.

If a call, screen lock or app switch interrupts audio, the game pauses and shows Resume sound. Press the bottom face button, release it, then resume the walk. A tap may be required again by the browser. The game does not request fullscreen, which can interfere with controller buttons on some iPad browser versions.

Automated phone profiles test the actual single-thread export with simulated standard controllers, real stereo output, portrait/landscape rotation, all menus/settings/levels, reconnects and suspended-audio recovery. Device emulation runs desktop Chromium: it does not establish physical Bluetooth/USB behavior or Chrome/Safari on actual iOS hardware. Physical phone/controller validation remains necessary. Godot documents the [mobile and single-thread export considerations](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html).

## Run and edit locally

Open `project.godot` in Godot **4.6.2** and run the main scene. All playable worlds are saved scenes under `scenes/levels/`; they are not reconstructed by runtime geometry generators.

For a browser build, install matching Web export templates and run:

```powershell
python tools/build_pages.py --output build/web
python tools/build_pages.py --mobile --output build/web/mobile
python tools/serve.py
```

Open `http://127.0.0.1:8060/`. The build helper detects `godot_console` or `godot`; use `--godot /path/to/godot` to choose one. Opening `index.html` directly from disk does not work.

Select a node under a level's **Sources** group to change its **Sound**, gain, range, intervals, or **Sound Variants** in the Inspector. Intermittent events shuffle the primary and alternative recordings without immediate repeats. Looping beds retain their primary recording; neighboring trees use different wind passages. Clearing the primary silences the source. Editor preview buttons audition the dry recording. Remote Inspector changes rebuild the active emitter without moving the player; save corresponding local edits to retain them.

`resources/audio/default_palette.tres` holds the 48 footstep recordings, actions, and menu cues. Ground-material arrays and menu variants are editable. Empty slots are ignored. Source samples remain swappable without changing a filename table.

Each geometry body has an editable **Acoustic Material**. Low/mid/high absorption and transmission, scattering, and roughness affect obstruction, reflections, and reverberation. Keep collision geometry aligned with meshes when editing the world.

## Audio and mix

All game recordings come from the supplied local audio library. Sixteen local forest canopy emitters use four long passages of wind through trees. Wood creaks belong to timber structures; bird variant pools preserve species. Fifty-six environmental emitters have multiple recordings. Footsteps use grounded distance, shuffled takes, and varied stride/force rather than a fixed clock. Running, jumping, landing, and material-sensitive punches have distinct behavior.

The mix pass captures actual browser output in all 24 areas, with walking/turning examples and longer repetition checks. It combines sample/true-peak and loudness measurements with an audio-input model's observations. Model descriptions are fallible: uncertain identities and unsupported timestamps are not measurements or grounds for changes on their own. This is automated audio review, not a human headphone audition or a guarantee for every playback device.

See [the mix review](docs/MIX_REVIEW.md) for measured changes, listening limits, and the final bell-repetition checks.

The authored mix softens prominent bird/frog/horse calls, enclosed drips, pump transients, and sustained engine/servo levels. The grove uses two actual goldfinch takes; local leaf and wetland beds provide context between calls. Cistern and courtyard bells use two finite recorded peals with gentle releases and randomized quiet gaps instead of a continuous short loop. The courtyard keeps its muffled balance through the gate geometry. Environmental events have independent clocks, and entering an area no longer restarts all nearby details together. Quiet spaces keep their intended contrast.

The browser renderer uses one AudioBufferSource clock per audible emitter. Direct sound and persistent first/second-order reflections share that signal, with fractional propagation delays, pressure-distance loss, material absorption, and smooth path gains. Travel-delay changes supply Doppler; a second pitch Doppler effect is not applied. Native duplicated reflection/reverb voices are silent in Web builds. Short fixed diffusion taps are disabled.

Headphone mode uses the browser's HRTF panner; **Headphone binaural audio** can be disabled in Settings for speakers. Direct air absorption uses broad-band EQ fitted from ISO 9613-1 coefficients at 20°C, 50% humidity and standard pressure, rather than the previous blanket distance/rear low-pass. Materials have an editable transmission reference thickness; bounded multi-barrier tracing scales transmission by geometry thickness and incidence. A bounded visibility search supplies filtered edge paths.

Six authored regions have separate eight-line frequency-dependent feedback delay networks. Their decay targets come from geometric/material probes. Existing door lintels define openings into the connecting passage field; remote room tails emerge toward these openings and weaken when geometry blocks them. This is a one-hop room/passage approximation. Local room tails retain stereo diffusion; they are not collapsed into a single HRTF point. Forest canopies retain separate recordings/offsets on individual trees, and extended water/rain features retain their authored distributed anchors.

See [the renderer validation](docs/ACOUSTICS_V2.md) for measurements and limitations. This remains a bounded acoustic model, not a full wave solver, personalized HRTF, structural-vibration simulation, or measured room convolution. Desktop Godot playback retains the existing native fallback; the new shared-clock/HRTF/FDN renderer targets the browser build.

## Publish only used audio

The repository contains **118 referenced audio files, approximately 9.74 MB**. The Web Audio renderer stages those same used files under the exported `sound/` directory; the Godot pack retains their resource imports for scene compatibility. No extra library recordings are shipped. `assets/library/manifest.json` provides source provenance and output hashes; `used_audio.json` lists actual scene/resource references. Audio has separate terms: see [THIRD_PARTY_AUDIO.md](THIRD_PARTY_AUDIO.md). It is excluded from the code's MIT license.

The original downloads, unused derivatives, render captures, build output, and import caches stay local and are ignored by Git. Audio files are denied by default, with generated exceptions for actual runtime references. Web export uses selected scene, palette, and script roots and their dependencies.

After adding or removing an Inspector recording, import and refresh the publication set:

```powershell
godot_console --headless --editor --path . --import
python tools/package_used_audio.py --write
python tools/package_used_audio.py --check
```

The full preparation catalog is retained locally in ignored `assets/library/manifest.local.json`. Raw-library preparation scripts require the original downloads and are not needed to build a clean clone. Their intentional regeneration order is `prepare_library.py`, `prepare_detail_audio.py`, `prepare_landmark_audio.py`, `prepare_menu_audio.py`, `prepare_context_audio.py`, then `prepare_bell_phrases.py`. After import, `tools/curate_soundscapes.gd` applies the curated assignments and `tools/tune_soundscape_mix.gd` applies the measured mix choices. These utilities overwrite those authored audio choices; normal startup and CI never run them over your edits.

## GitHub Pages

Pushes to `main` run [the Pages workflow](.github/workflows/pages.yml). It installs official Godot 4.6.2 with pinned SHA-512 checks, imports resources, verifies the used-audio inventory, exports the game, checks a project subpath on a plain server, and tests controller menus, navigation, and blocked-audio handling before deployment. Generated WebAssembly and build output are deployment artifacts, not committed source files.

The desktop threaded audio engine needs cross-origin isolation; the mobile export does not. Godot's PWA service worker supplies the necessary headers on GitHub Pages, where custom response headers are unavailable. First use may reload once to activate it. Caches are scoped to this project and versioned by build content. If service workers are blocked, the launch screen explains how to retry; it does not reload indefinitely. Chromium and Firefox were tested with actual audio on a header-free server. Real macOS Safari was not available for playback verification. The game itself uses no external API, account, or microphone.

## Checks

```powershell
godot_console --headless --path . --script tests/context_audio.gd
godot_console --headless --path . --script tests/audio_authoring.gd
godot_console --headless --path . --script tests/acoustics.gd
godot_console --headless --path . --script tests/acoustic_materials.gd
godot_console --headless --path . --script tests/room_acoustics.gd
godot_console --headless --path . --script tests/expanded_worlds.gd
godot_console --headless --path . --script tests/locomotion.gd
godot_console --headless --path . --script tests/controller_ui.gd
npm ci --prefix tests
npx --prefix tests playwright install chromium
node tests/pages_browser.cjs build/web
node tests/controller_browser.cjs build/web
node tests/propagation_dsp.cjs
$env:ATMO_DEVICE="iPhone 13"; node tests/controller_browser.cjs build/web
```

Additional browser suites cover controllers, menu audio, debug geometry, movement, and long walks. `tests/mix_capture_browser.cjs` records actual output; its region-positioning hooks are enabled only on localhost with `?qa=1`. Captures and reports remain in ignored `test-results/`.

The controller browser suite drives only a simulated standard Gamepad API through launch, every menu/setting, all four environments, disconnect/reconnect, and reload persistence. It measures real audio output. Synthetic pads cannot grant native browser activation, so this routing suite explicitly permits autoplay and asserts no keyboard, mouse, touch, or automation user gesture was used. With the local server running, `node tests/controller_audio_policy.cjs` separately checks the default and strict audio policies without granting activation: blocked audio retains the launch screen, and an explicit keyboard fallback unlocks it. Physical controller audio activation is not established by these simulated tests.

Optional `tools/review_mix_audio.py` sends a selected capture to OpenAI's audio-input API using `OPENAI_API_KEY` from the environment. It is a development review utility only; never put API credentials in the project or exported game. Its use is separate from ordinary offline/local playback.
