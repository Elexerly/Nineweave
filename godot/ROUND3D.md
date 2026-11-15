# Nineweave Round 3d: web audio fix

## Symptom
The web build made no sound on any browser, not even the placement tap.

## Root cause
Single-threaded web builds play audio in **Sample mode**. In this mode Godot mirrors every
audio bus in JS (`GodotAudio.buses`, made of Web Audio GainNodes). `fx/sound.gd::ensure_buses()`
created 8 buses at runtime with `AudioServer.add_bus()`, which defaults to `at_position=-1`.
In Godot 4.7, `GodotAudio.Bus.addAt(-1)` calls `move(id,-1)`, which runs `splice(-2,0,bus)`
and inserts each new bus *before* Master. After that the JS bus order no longer matches
the engine's. Every later `set_bus_send(index)` rewires the wrong JS bus, Master ends up
in a loop (0→7→8→1→0), and its connection to `ctx.destination` is dropped. Godot still
called `sample_start` for every cue, but the measured peak at the destination was exactly 0.
Settings, mute, ducking, the .ogg packing and the gesture unlock were all checked and
ruled out (see `/workspace/nineweave-sound-diagnosis.md`).

## Changes
- **`default_bus_layout.tres`** (new): Master; SFX, Music and Announcer → Master at 0 dB;
  CrystalPan0..4 → SFX, each with an `AudioEffectPanner` at -0.7/-0.35/0/0.35/0.7. Godot
  loads this layout at startup with `set_count`, which keeps the JS order correct, so
  `ensure_buses()` finds every bus and creates none.
- **`fx/sound.gd`**: the `ensure_buses()` fallback appends with
  `AudioServer.bus_count = bus_count + 1` (`_append_bus()`) and never calls `add_bus()`.
  A comment there explains why.
- **`export_presets.cfg`**: `html/head_include` sets `navigator.audioSession.type="playback"`
  when the API exists (Safari 16.4+), wrapped in try/catch, so iOS treats the game as
  media playback.
- Audio path review: the first-gesture unlock (silent play inside both the first press and
  the first release), the `enabled`/`unlocked` gates in `cue()` and `_drain_voice()`, the
  settings defaults, ducking and mute were all correct. No other changes were needed.
- Known limitation: bus effects are ignored in web Sample mode, so the CrystalPan panners
  have no effect on web. Native builds still pan.

## Tests
New file `tests/run_audio_tests.gd` (`NINEWEAVE_AUDIO PASS checks=270 failures=0`) covers:
- the layout file exists and has all 8 named buses with the correct sends, 0 dB, unmuted,
  and the correct panners; the project setting points to it;
- the engine bus count and order match the layout at startup, after `Sound._ready()`, and
  after repeated `ensure_buses()`, with no duplicates and Master unmuted at index 0;
- the `ensure_buses()` fallback, run from Master only, rebuilds the same order, sends and
  panners;
- a static guard: `fx/sound.gd` contains no `add_bus(`, and the web preset includes the
  audioSession head script;
- every REAL_SFX and VOICES `.ogg` loads as a non-empty AudioStream;
- before unlock, cues are skipped; press and release each run the silent unlock; after that,
  `cue()` for place/ui/claim/route at several pans assigns its stream to a player on a
  CrystalPan bus whose send chain reaches an unmuted Master; announcer lines do the same;
- default settings give sound=true and non-zero volumes, with audible bus gains; mute and
  unmute work.

The suite fails against the round3b `sound.gd` (static guard). All suites pass headless:
rules, ai, ui, layout, round3 (720/0), round3b (585/0) and audio (270/0).
