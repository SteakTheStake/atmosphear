# Browser mix review — 2026-11-14

The review used actual mixed stereo output from the Godot browser build, rather than previewing source recordings in isolation. All 24 authored regions were captured at matched positions with identical volume settings. The baseline also includes four walking/turning recordings; the first revised mix includes four longer stationary recordings to expose loop repetition.

Short samples are approximately 15 seconds, and long samples approximately 60 seconds. Audio-thread sample counts determine the measured duration; browser scheduling makes wall-clock recordings somewhat longer. The output was not normalized before measurement or audio-model review.

## Listening and measurement

OpenAI's `gpt-audio-1.5` received the actual recordings for audio-input review, including blind reviews without scene labels. Its comments were treated as fallible suggestions. Uncorroborated sound identities, impossible timestamps, and generic requests for more variety were not treated as measurements. Numeric changes were supported by captured levels, source identity/event telemetry, or a verified repeating waveform.

This is an automated audio-model review, not a human headphone audition. It cannot guarantee identical subjective balance across headphones, speakers, hearing profiles, or every location in the levels.

| Region | Observed sample peak before | Observed sample peak after first mix | Change made |
|---|---:|---:|---|
| Bird grove | −6.1 dBFS | −20.2 dBFS | Softer focal bird, two actual goldfinch takes, more leaf-bed context, longer variable rests |
| Frog wetland | −5.9 dBFS | −10.5 dBFS | Softer calls and stronger insect/water context |
| Timber pump room | −2.6 dBFS | −6.4 dBFS | Reduced pump level and supported its water background |
| Engine hall | −7.7 dBFS | −11.7 dBFS | Reduced sustained engine level by 4 dB |
| Timber stable | −5.9 dBFS | −11.1 dBFS | Softer horse snorts with more space between calls |

These are outcomes of randomized takes and event timing, not isolated gain-transfer measurements. Across the 24-region first comparison, the highest measured true peak changed from −2.1 to −6.4 dBTP. No clipped samples occurred. Quiet areas retain their contrast; there is no per-room loudness normalization.

## Repetition findings

The long bird-grove capture contained 17 regional bird events. Combined inter-event gaps had a coefficient of variation of 0.81, supporting an irregular, clustered texture despite individual birds repeating recognizable calls. The mix retains those species identities. Source clocks now continue independently, and approaching an area spreads incidental arrivals rather than starting all details together.

The cistern's original continuous bell bed repeated with an envelope correlation of 0.996 at its exact 19.6-second asset period. This matched the audio review's concern about an intrusive repeated peal. Both bell landmarks now use two distinct 12-second passages of the original church-bell recording, with gentle releases and randomized 20–45-second rests after each peal. The courtyard's active level remains comparable to its previous quiet, geometry-muffled bell.

Targeted short and long browser captures verified both revised bell landmarks. Correlation near the old period fell to −0.156 in the cistern and −0.048 in the courtyard; the old repeating envelope is absent. Both recorded phrases were selected across the tests. Each approximately 66-second long capture contains only one new peal onset, so these recordings do not establish an inter-event-gap distribution. The final long peaks were −17.38 and −31.88 dBFS, with no clipping; the audio review described clear bell tones without overpowering the ambience.

The servo's pulsing motor is also periodic, as expected for that mechanism. Its longer audio review did not identify an objectionable loop boundary or harsh transient after the level reduction, so its mechanical character was preserved.

## Reproduce

Build and serve the project, then run `tests/mix_capture_browser.cjs`. It uses localhost-only QA positioning, captures actual output as PCM WAV plus an Ogg preview, and records source event timelines. `ATMO_MIX_PHASE`, `ATMO_LEVELS`, `ATMO_REGION_MATCH`, and `ATMO_LONG_LOOPS=1` select comparison sets. `tools/analyze_mix_captures.py` measures the captures. The optional `tools/review_mix_batch.py` performs audio-model review using an environment API key.

Captures, raw model responses, and detailed measurements remain in ignored `test-results/`. They are not distributed as extra audio in the repository or game. Publication and export verify the exact live audio-resource inventory independently.

Final verification: 24 selected region results, including the two final bell revisions, have a highest sample peak of −6.38 dBFS and zero clipping. Final browser export SHA-256: `051122cf9d6f1bc8de747fde38a3c35cf2c7f000e1b9924d491faf7fbc15ac1b`. Pages build revision: `7612745553e7fb295af27f07`.
