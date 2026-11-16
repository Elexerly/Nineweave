# Round 5k: arena entrance, hero audio and account switching

Based on published Round 5j source 6facacf26945e04a1d0e4cd06d1466353daba2d0.

- One procedural gold/cyan arena-entry corridor behind the existing “TWO HAVE STEPPED FORWARD” title. Preserves owner voice, bounded wait, one flash, skip/reduced-motion and both intro videos. No new scenes or texture download.
- Hero intro/victory soundtracks demultiplexed losslessly into dedicated AudioStreamPlayer; silent Theora video decoding is independent. Source OGVs unchanged. See ROUND5K_AUDIO.md for evidence and limitations.
- Options > Account > Sign out: confirmation explains local state loss, recovery-email risk and active match loss. Server account is not deleted. New signed-out state persists and stops automatic registration; explicit Sign in or New account follows. Late callbacks retired, uncertain deletion cannot be bypassed, recovered identity replaces marker.
- Options screen-name action is now “Change”; atomic server validation/save unchanged.
- Bot game/tournament results remain local. Only finished authoritative online rooms update online match statistics. No backend, database, admin or production changes.

## QA
Aggregate runner now includes signout and hero_audio_playback (25 suites). Individual feature suites cover malformed Ogg, all 64 real soundtrack loads, decoder/player lifecycle, confirmation bounds in portrait/landscape, cancellation, stale callback retirement, distinct-account recovery and deletion guards.

No actual graphical capture or browser listening was possible in this worker: display socket creation is denied. Headless tests cannot establish appearance, audible distortion removal or audiovisual sync on target devices. Offline graphical capture helper: `godot/tools/capture_arena_prelude.gd`. Target-device review remains required before claiming those outcomes.
