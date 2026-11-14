# Shared-clock browser acoustics

The previous renderer used separate Godot players for direct sound, early reflections and three spectral reverb sends. It continuously changed integer-offset delay taps and reassigned reflection slots by strength, then added fixed 11/19 ms diffusion taps. Those features were plausible causes of the reported doubled/chorused sound. A previous volume-only review did not test these timing defects.

## Rendering

Godot remains the geometry/material/controller/scene authority. `web/acoustics.js` renders browser gameplay audio through one AudioBufferSource per emitter; Web Audio fans that same sample clock into direct propagation, persistent geometric paths and room sends. Native gameplay outputs are muted in Web builds; native menu clicks remain active. Native reflection/late players do not start in Web builds. Failed decodes are exposed in renderer telemetry and checked by the browser suite.

The direct path uses total distance/c latency and pressure falloff. DelayNode fractional interpolation and time-continuous parameter ramps supply propagation Doppler; only authored take variation affects source playbackRate. Reflection identities include surfaces and normals, with 15% selection hysteresis. Valid paths retain their delay line. Newly appearing/disappearing paths fade for 60 ms; arbitrary wall identities are never morphed through a shared slot. Physical early reflections can still produce natural interference; the objective is removing artificial regular taps and unstable transitions, not eliminating real acoustic coloration.

Browser HRTF data are supplied by the browser implementation; no third-party HRTF asset is redistributed. Speaker mode uses equal-power panning. Fixed environmental assumptions for air absorption are 20°C, 50% RH and 101.325 kPa. The three broad EQ sections approximate the frequency curve; they do not implement an exact arbitrary-frequency atmospheric filter. Formula reference: [python-acoustics ISO 9613-1 implementation](https://python-acoustics.github.io/python-acoustics/_modules/acoustics/standards/iso_9613_1_1993.html).

Transmission traces up to four barriers, using each authored material and geometry thickness/incidence relative to an editable reference thickness. Edge diffraction is a bounded horizontal visibility search with frequency loss; it is not UTD. Door lintels are actual scene geometry, not arbitrary portals punched through walls. Their metadata `acoustic_open_fraction` controls the authored opening fraction. Each lintel is associated with the nearest authored region and the connecting passage field. This does not solve arbitrary multi-room portal chains, coupled feedback, low-frequency modes or moving-door aperture geometry.

Each region owns an eight-line orthogonal Hadamard feedback network, with fixed unequal delays and low/mid/high feedback losses calculated from requested RT60. No pitch modulation creates artificial width. Region tails are stereo locally; remote tails are positioned at door openings, attenuated by width, distance, openness and a visibility ray. Disposed room processors are explicitly stopped on level changes. Outdoor wet levels remain governed by enclosure and escape probes.

## Verification

`tests/propagation_dsp.cjs` measures the actual renderer graph in Chromium OfflineAudioContext and runs the exact worklet processor against an impulse. A diagnostic impulse at 80 ms arrives at 90 ms for a 3.43 m direct path and 100 ms for a 6.86 m reflection. Direct-only has one arrival, early-only one reflection, and the combined render exactly those two arrivals. No fixed 3/11/19 ms copies appear.

Measured broadband T30 estimates, extrapolated to RT60: target 0.3 s -> 0.30175 s; target 1 s -> 1.00858 s; target 2 s -> 2.00667 s. These establish equal-band decay calibration at 48 kHz, not universal accuracy of every geometry estimate or mixed-band setting.

Browser integration checks exercise real stereo output, six region fields, zero renderer errors, every controller action/menu/setting, reconnects, all four levels and saved preferences. Header-free subpath tests cover Chromium and Firefox, service-worker isolation, offline reload and bounded failure messages. Audio-model capture reviews are fallible observations, not a human headphone audition. Earlier prototype captures are distinguished from final captures in ignored test-results. Raw diagnostics and review audio are not published.

The first shared-clock prototype pass captured all 24 areas (about 10 seconds each) plus four walking/turning samples. The final room/transmission pass captured all 24 areas again (about 5 seconds each). Short final clips check balance and artifacts, not long-term repetition. Final highest sample peak was -5.92 dBFS, with no clipped samples or browser errors. All 28 prototype and 24 final recordings received fallible audio-input model review. Unsupported sound identities and generic requests for additional layers were not used as evidence of faults.

The existing isolated air-punch test also passed: the cistern late tail outlasted the dry clip/early echoes, exceeded a silent baseline, and was substantially stronger than the outdoor tail. Pause-silence/native UI feedback and actual stereo output at all four spawns passed. Eight native Godot suites passed, including 53 controller assertions.

## Practical limits

A source audit found 118 distinct mono recordings (591.0 seconds total), with no byte-identical duplicates. Stock recordings can contain their own room tone or reverberation. The supplied mono preparations and independently offset tree beds are retained; the new renderer cannot reverse acoustics baked into a recording. Materials, emitter extents and room probes are approximations. Generic HRTF localization varies between listeners. Browser scheduling, device latency and headphone response remain external variables. No claim of indistinguishability from reality or comprehensive physical simulation is made.
