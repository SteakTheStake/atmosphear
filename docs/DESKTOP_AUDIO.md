# Native spatial audio

Windows desktop is the primary target. `tools/play.ps1` launches desktop by default; `-Web` selects the secondary browser build. The Windows export preset is runnable. Desktop CI runs on main-branch pushes; browser publication is manual.

## Renderer

`native/src/atmo_audio.cpp` ports the browser's shared-clock propagation and room-field design into a C++ GDExtension. `AtmoSpatialStream` feeds one stereo stream into Godot's native mixer. Geometry, material probes, source authoring, controls and settings stay in Godot. Muted Godot players retain event-timing bookkeeping; their duplicated reflection/reverb voices do not play in the new renderer.

The browser's HRTF implementation and data are internal to the browser. Native binaural convolution instead uses Steam Audio 4.8.1's built-in measured HRTF, with bilinear interpolation for direct/reflected point paths and remote room returns. The [official programmer's guide](https://valvesoftware.github.io/steam-audio/doc/capi/guide.html) describes HRTFs, interpolation and sample-rate conversion. This is a generic measured head, not a personalized HRTF or a bit-identical browser dataset.

Each emitter has one decoded sample clock and one history ring. Direct and stable-ID reflected paths read it with cubic fractional interpolation. Changing travel delay supplies Doppler; only take variation changes the source clock. Source starts, replacements, stops, virtualization, path changes, pause and headphone/speaker switching have envelopes. Three broad air-absorption EQ bands and material-dependent low-pass filtering carry over the browser model. No arbitrary diffusion copies are added.

Every authored region has a 16-line spectral Hadamard feedback network, plus a shared passage field. Local tails retain stereo diffusion. Remote tails emerge at openings with width, distance, openness, visibility and spectral loss, then HRTF spatialization. Field count follows each level's Regions nodes. This remains a bounded, one-hop room/portal approximation, not a wave solver.

## High profile

Desktop starts at High, migrating old low-quality preferences. The checkbox can still select a reduced geometry-query profile during play. Quality increases resolution and work budgets, without increasing mix volume.

| Component | Native High |
|---|---|
| HRTF | Measured binaural convolution, bilinear interpolation |
| Source and travel-delay interpolation | Cubic; one sample clock per emitter |
| Spatial updates | 60 Hz |
| Early paths | Up to 16 environmental paths; eight action/footstep paths, plus a bounded edge path |
| Surface search | 30 directions, 12 faces, 64 second-order candidates |
| Transmission | Up to six thickness-aware barriers |
| Room probes | 192 rays, up to five bounces |
| Late fields | 16 frequency-dependent delay lines per region/passage |
| Audio block | 256 frames: 5.33 ms at 48 kHz, excluding other output buffering |

The project requests 48 kHz. Native DSP follows Godot's actual device mix rate and rescales delays/HRTFs; the local WASAPI device used 44.1 kHz. No Windows device settings are changed. The existing buffer target remains 30 ms; `--audio-output-latency 60` is available for troubleshooting.

Decoding, effect creation and allocation happen on the control thread. The mixer uses fixed buffers and tries the control mutex without waiting, retaining the last state when an update is busy. Denormal flushing protects long, nearly silent reverb tails. Immutable library paths allow rebuilding while an editor holds an older DLL. Restart an open editor before F5 to load the new extension; a newly launched executable loads the current release.

## Measurements

`tests/native_hrtf.gd` measures native DSP PCM independently of game telemetry or output hardware:

- Lateral sources have the correct ear advantage. Front/back correlation was about 0.329 and elevation correlation 0.567 for the deterministic probe; speaker front/back correlation was 1.0. This distinguishes HRTF cues from pan alone.
- One impulse arrives near 90 ms directly and 100 ms by reflection for 3.43 m and 6.86 m paths. No fixed 3/11/19 ms copies appear.
- A 1 kHz tone with a receding travel-delay slope of 1.715 m/s measured about 995.04 Hz, versus 995 Hz predicted.
- Sixteen-line T30 measurements extrapolated to RT60 were 0.299, 0.998 and 1.995 seconds for 0.3, 1 and 2 second targets. This checks equal-band calibration at 48 kHz, not every mixed-band/material estimate.
- Pause fades the combined output to silence.

`tests/controller_ui.gd -- --native` passed 57 assertions, including High quality and reversible headphone/speaker switching. Portable geometry/mixer regressions explicitly disable the extension and remain separate from HRTF validation.

`tests/desktop_smoke.gd` loads the release's embedded resources and walks/turns through the current main forest world and four legacy levels. The local WASAPI run passed all five environments: nonzero stereo PCM, no capture overflow or short-run clipping, all room fields present, no path-slot exhaustion, and complete private-bus cleanup. In the final combined run, mean DSP work ranged roughly 0.55–1.45 ms per block, below the device's 5.8 ms block interval. There were 66 over-budget blocks across 3,720 measured blocks, with a maximum of 14.52 ms; maximum-quality processing still has occasional spikes. `over_budget_blocks` measures wall-clock processing intervals, not hardware underruns; this is not a guarantee of click-free playback on all devices.

Official export templates disable script/path overrides. The pack test uses the editor runtime with the release pack:

```powershell
godot_console --headless --max-fps 60 --audio-driver WASAPI --main-pack build/windows/Atmosphear.exe --script C:/absolute/path/to/tests/desktop_smoke.gd -- C:/absolute/path/to/report.json
```

The portable ZIP contains `Atmosphear.exe`, `atmo_audio.dll`, `phonon.dll`, and project/engine/SDK/recording notices. Extract the whole folder. Building needs CMake and a Visual Studio C++ toolchain; playing does not. SDK and binding downloads are pinned and SHA-256 checked. Physical headphone listening remains a separate validation step.
