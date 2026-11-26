# Surtaal - Architecture & Roadmap

Godot 4.x (verified on 4.7.2), GDScript, GL Compatibility renderer (widest Android/iOS reach).

## A. Technical architecture

Layers, each talking to the one below through signals and Resources only:

```
UI (scenes/, scripts/ui)         studio_root, instrument_browser, piano_keys, waveform_view, level_meter
  |  signals
Domain (scripts/music, timeline, instruments)   InstrumentManager, [TrackManager, TimelineManager, MidiManager ...]
  |
Audio (scripts/audio)            AudioEngine (voices+buses), SampleManager (bake cache), SynthBaker (DSP)
  |
Native boundary                  Godot AudioServer  ->  [future GDExtension / platform plugins]
Services (services/)             [ai, storage, export]  - backend-facing, provider-independent
```

Autoloads (Phase 1): `SampleManager`, `AudioEngine`, `InstrumentManager`.
Planned autoloads: `ProjectManager`, `TrackManager`, `TimelineManager`, `MidiManager`, `MixerManager`,
`EffectsManager`, `RecordingManager`, `PitchDetectionManager`, `ExportManager`, `AIComposer`.

Data-driven: instruments live in `data/instruments/instruments.json` and load into `InstrumentDef` Resources.
Adding an instrument = adding a JSON entry (no code) if it fits an existing synth engine.

### What Godot cannot do alone (external dependencies)
| Feature | Requirement |
|---|---|
| Low-latency mic capture / monitoring | Native Android (Oboe/AAudio) + iOS (AVAudioEngine) plugin; Godot's `AudioEffectCapture` adds latency |
| Real-time DSP at scale (EQ, comp, pitch tracking, time-stretch) | C++ GDExtension (YIN/pYIN, biquads, Rubber Band or Signalsmith Stretch) |
| MP3 / AAC export | LAME (LGPL) / platform encoders (MediaCodec, AVAssetWriter) |
| AI planning (Claude Haiku) | Backend proxy holding API keys; app only calls your backend. **No keys in the app.** |
| Voice-to-instrument *timbre* conversion | Separate ML service/model - out of scope until pitch transcription ships |

## B. Audio architecture

* **Bake-and-play:** `SynthBaker` renders each (instrument, note) once into an `AudioStreamWAV` (16-bit mono, 44.1 kHz).
  Playback is then native `AudioStreamPlayer` mixing - no per-sample GDScript in the audio callback, so no underruns.
  Baking happens on `WorkerThreadPool` (prebake the visible keys on instrument/octave change), with a synchronous fallback so a tap is never silent.
* **Engines:** `pluck` (Karplus-Strong + fractional-delay tuning + bridge buzz), `wavetable` (additive cycle, ADSR, vibrato, scoop, breath, detune, bright->dark morph),
  `membrane` (pitch-dropping drum + inharmonic partials + noise).
* **Buses:** voices (24, round-robin stealing) -> `Instruments` (reverb) -> `Master` (limiter).
* **Later phases:** sequenced playback uses the same note path with sample-accurate scheduling from an audio-clock-driven transport;
  mixer = one bus per track with effect chains; export = offline render through the same engine; sustained notes need looped samples
  or a streaming synth (AudioStreamGenerator / GDExtension).

## C. Responsive UI

Scaling: `content_scale_factor = clamp(shortSide/400, 1, 4)` so the logical short side is ~400 px on every device; layouts then work in logical px.

**Portrait - Easy Creation Studio** (one-handed): top bar / stage (instrument + live waveform + meter) / controls / instrument browser / keys / bottom nav (thumb zone).

**Landscape - Pro Studio:** top bar with nav / browser column | stage + keys | controls + diagnostics. Phases 2-5 add timeline, piano roll, mixer and effects rack here.

Components are created once and re-parented on orientation change (`studio_root._apply_layout`), so state survives rotation.
Safe-area insets are applied on mobile. Unimplemented destinations (Create/Record/Arrange/Mix, Undo/Redo/Save/Export) are visibly **disabled** with a "Phase N" tooltip - not fake buttons.

## D. Folder structure
```
Surtaal/
  project.godot
  data/instruments/instruments.json     (loops/, presets/, templates/ planned)
  scenes/studio/studio.tscn             (home/ instruments/ recording/ piano_roll/ mixer/ timeline/ export/ planned)
  scripts/audio/                        synth_baker, sample_manager, audio_engine
  scripts/instruments/                  instrument_def, instrument_manager
  scripts/ui/                           studio_root, studio_theme, instrument_browser, piano_keys, waveform_view, level_meter
  scripts/{core,music,ai,recording,timeline}/   planned
  services/{ai,storage,export}/         planned
  tools/                                screenshot.gd, audio_selftest.gd
  docs/                                 this file, LICENSING.md
```

## E. Scene hierarchy (Phase 1)
```
Studio (Control, studio_root.gd)
  TextureRect                    gradient background
  MarginContainer               <- rebuilt on orientation change
    VBoxContainer
      Topbar (HBox): logo, project, [nav in landscape], Undo/Redo/Save/Export (disabled)
      portrait:  Stage, Controls, InstrumentBrowser, PianoKeys, Nav
      landscape: HBox[ InstrumentBrowser | VBox[Stage, PianoKeys] | Controls ]
Stage (PanelContainer): name, description, WaveformView, LevelMeter
```

## F. Roadmap
1. **Phase 1 (done)** responsive shell, browser, synth instruments, real playback.
2. **Phase 2 (done, see notes)** sustain loops + release + live vibrato, presets, microtonal tuning (raga/just/pentatonic), meend glide, transport, 16-step drum sequencer, 1-bar piano roll. Not yet: multi-bar patterns, articulations, chord suggestions, beginner/advanced roll modes, sample-accurate scheduling.
3. **Phase 3 (in progress)** DONE: tracks + arrangement view, multi-bar songs, project save/load/rename/duplicate/delete, autosave + crash recovery, undo/redo (`ProjectManager`, JSON v1 in `user://projects/`). TODO: multitrack timeline, loop browser with tempo metadata, multi-bar patterns, audio-asset management.
4. Phase 4: mic capture (native plugin), YIN -> pYIN pitch tracking, onset/segmentation, MIDI-note generation, hum-to-instrument.
5. Phase 5: mixer, effect chains, automation, audio clip editing.
6. Phase 6: AI composer (backend + Haiku planning -> editable layers), cinematic templates.
7. Phase 7: export (WAV/stems/MIDI, MP3/AAC via encoders), profiling, Android/iOS device passes.

## G. Mobile audio risks
| Risk | Impact | Mitigation |
|---|---|---|
| **Bake CPU cost in GDScript** - measured 15-770 ms/note on a desktop (piano worst); expect 3-5x slower on phones | First-hit stutter on uncached notes | Background prebake (done); reduce harmonics/duration; move SynthBaker to a C++ GDExtension; ship pre-rendered packs |
| Output latency (Android 20-100+ ms on some devices) | Laggy feel | `audio/driver/output_latency` tuned; native Oboe plugin; expose latency calibration |
| Mic latency & permissions | Hum-to-music, overdubs | Native capture plugin; calibration tone loopback |
| Memory: 16-bit mono 44.1k = ~88 KB/s/note | Large caches | LRU cap (400 notes); share/stream long samples |
| Thermal throttling | Glitches in long sessions | Diagnostics panel; cap voices; offline-render heavy FX |
| Sustained notes (hold-to-sustain) | Current notes are fixed-length | Loop-point samples or streaming synth |
| 12-TET only today | Indian microtonal expression | Phase 2: per-note cents offset & tuning tables (pitch_scale on players is available) |
| Velocity = volume only | Less expressive | Multi-velocity layers (bake brightness variants) |
| Touch on iOS/Android not yet device-tested | Multitouch keys | `PianoKeys` handles ScreenTouch/Drag directly; verify on hardware |
| Key leakage | Security | AI via backend proxy only |


## H. App flow (redesign, current)

```
Arrangement (home)            tracks over a bar timeline, Play/BPM/bars, Project menu, Undo/Redo
  + Add track  ->  Instrument picker (or Drum machine)
                     ->  Track editor
                           melodic: note view (bar pager) + Record voice + piano keys
                           drums:   16-step grid
```

**Hum to instrument** (`TrackEditor` -> `RecordingManager` -> `PitchTracker` -> `HumTranscriber`):
Record -> 4-beat count-in -> hum/sing/whistle -> Stop -> YIN pitch tracking (75-900 Hz, 15 ms hops, runs on a worker thread)
-> segmentation (pitch jumps, outlier rejection, energy re-articulation, min 70 ms) -> quantised to 16ths at the project tempo
(optionally snapped to the current scale/raga) -> notes appear on the track and play through the track's instrument.
The original recording is kept as `user://assets/<project>_track<N>.wav` ("Voice" button plays it).

Scripts: `scripts/music/{track,track_manager,transport,tuning_manager}.gd`, `scripts/recording/{pitch_tracker,hum_transcriber,recording_manager}.gd`,
`scripts/ui/{studio_root,arrangement_view,track_lane,timeline_ruler,instrument_picker,track_editor,sound_panel,piano_roll,drum_grid,peak_strip}.gd`.

**Mic requirements:** `audio/driver/enable_input=true` (set). Android export: enable `RECORD_AUDIO`. iOS export: add `NSMicrophoneUsageDescription`.
Use headphones when overdubbing (the app does not cancel speaker bleed). Not yet implemented: latency calibration, pitch bends/vibrato capture,
harmony/variation generation, AI voice-to-timbre conversion.

**Tests (tools/):** `hum_test.gd` (synthetic melodies -> exact notes + quantisation), `audio_selftest.gd` (synth pitch, loops, tuning, tracks, save/load, undo, sequencer),
`recovery_test.gd` (crash recovery across launches), `mic_test.gd` (real input device; needs audio hardware), `screenshot.gd`.

## I. Sound engine (v3) and the realism ceiling

Engines in `SynthBaker`: `pluck` (Karplus-Strong), `wavetable`, `membrane` (drums: click, low-passed rumble, saturation) and **`super`**
(cinematic subtractive: up to 7 detuned unison oscillators spread across the stereo field, octave/fifth `stack` layers, sub oscillator,
resonant filter with its own envelope, drive, formant-shaped spectra for choir, custom harmonics for organ/reed).
Stereo samples, RMS loudness balancing (every instrument ~ -15 dBFS), sample **zones** (bake every 3rd note, repitch neighbours) and
half-rate rendering for dark instruments keep bake cost bounded. Bus chain: voices -> Instruments (hall reverb with pre-delay + stereo enhance) -> Master (glue compressor -> limiter).
Baking is queued with bounded parallelism (cores-2) so it can never starve the UI/recording thread; urgent requests jump the queue.

Cinematic set: Epic Strings, Ostinato Strings, Epic Brass, Braam, Choir Aah, Pipe Organ, Dark Pad, Taiko, Epic Hit.
Electronic: Hybrid Lead, Pluck Synth, 808 Bass. Indian percussion: Dhol, Parai, Thavil, Mridangam, Kanjira, Ghatam; plus Nadaswaram.

**Honest ceiling:** this is synthesis. It gives big, wide, layered, usable cinematic and electronic textures, but it cannot match
recorded orchestral libraries for realism (bow noise, breath, room, true legato). The route to Hans-Zimmer/Anirudh-grade realism is a
*sampled* engine (multi-sampled recordings with loops, velocity layers and round-robins). Candidates: your own recordings, or properly licensed
libraries (e.g. CC0 orchestral sets such as VSCO 2 Community Edition - verify the licence per pack). Trade-off: app size (hundreds of MB) and
streaming/memory on phones. `InstrumentDef`/`SampleManager` are already keyed by zone/preset, so a `sampler` engine slots in beside `super`.

## J. Recording sources

Voice (mic -> YIN -> notes) and Keys (timed key presses -> notes, overdub). Keys recording pre-bakes every visible key before the count-in,
because a key whose sound is not rendered would block the main thread and corrupt the timing. `hum_hard_test.gd` scores the transcriber on
realistic singing (vibrato, scoops, flat singers, octave glitches, repeated notes): mean F1 0.99.

## K. Home screen = mixer + export (current)

* **No bars.** Song length is automatic: it follows the last note (rounded up to whole bars internally), 2 bars minimum, **10 minutes maximum**
  (`TrackManager.song_steps`, `MAX_SONG_SEC`). The timeline shows a time ruler (m:ss), scrolls horizontally and zooms (`TrackLane.px_per_step`).
  The piano roll pages through the song in 16-step windows labelled by time.
* **Mixer.** Every track has its own bus (`T<id>`) -> `Instruments` (reverb) -> `Master` (compressor, limiter). Per track: volume, pan, mute, solo,
  and a play-this-track-alone button (`TrackManager.play_only`). Master volume on the transport row. Settings are saved with the project.
* **Export.** `ExportManager.export_song()` bounces the song once in real time through an `AudioEffectRecord` on the Master bus (so the file is what you hear),
  then writes WAV (always) and converts to MP3 when an encoder exists. **MP3 requires `ffmpeg` (libmp3lame) or `lame` on the PATH** (desktop). Godot has no MP3 encoder.
  Phones need a native encoder plugin (Android MediaCodec/LAME, iOS AVAssetWriter) - until then phones save WAV. Output: `Music/Surtaal/` on desktop.
* **Voice accuracy check.** After a voice recording the raw per-frame pitch is drawn as a white line over the notes in the piano roll.
  `Voice` plays your original recording; the play button plays the detected notes with the instrument.

Tests: `mix_export_test.gd` (auto length + 10-min cap, mixer, play-one, real WAV bounce).

## L. Sampler engine (real recordings)
`synth: "sampler"` instruments list recorded zones (`params.samples: [{midi, file}]`). `SynthBaker._bake_sampler` loads the nearest zone,
builds a seamless sustain loop from the steady middle of the note (crossfaded), trims the unused tail and stores a loudness-balancing
`gain_db` in the stream metadata; `AudioEngine` repitches neighbouring notes and applies the gain. `fixed: true` = unpitched hits
(drums, cymbals). Samples are imported as **uncompressed 16-bit PCM** (`importer_defaults/wav compress/mode=0`) because loop building needs raw PCM.
Bake cost is 10-40 ms per note (vs 100-900 ms for synthesis). The recorded subset is ~50 MB; add zones/velocity layers/instruments by extending
`tools/fetch_samples.ps1` or `sampled.json`. Licence + gaps: `docs/LICENSING.md`.