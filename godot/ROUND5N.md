# Round 5n: readability and rematch polish

Based on tested/published Round 5m. Independent hero soundtrack playback and -8 dB video gain are preserved; no source clips are regenerated, replaced or re-encoded.

- Computer rematches now alternate human X/O, so the players alternate who opens while X remains first. Local pass-and-play still swaps. Online remains authoritative and does not receive an extra local swap. Legacy result Play Again uses the same rematch path. Tests exercise four repeated rematches, hero identity and AI scheduling after the versus reveal.
- Recovery WELCOME BACK has a nearly opaque white-to-blue gradient form, dark readable text, readable locked email and solid fields. Small Edit email corrects a mistyped address, retaining its draft while retiring the prior challenge. Back no longer misleadingly says Create screen name. Request failures no longer claim an unrequested code is invalid.
- Comic-book single versus prelude: gold/cyan plates, ink rays, halftone, cream title burst. Existing wording and owner voice, timing, reduced motion, skip and reveal remain.
- Beth-only tail fade uses video completion position when Godot web sample-position reporting lags. Jack/Ryan are not faded. See ROUND5N_AUDIO.md if present for detailed evidence.

Ryan sync: media start timestamps are both zero and native clocks remain within about60ms in diagnostic playback. Source lip alignment and real browser drift remain unverified. No speculative audio seeks, offsets or media substitution were made.

Aggregate runner covers29 suites. Headless geometry/lifecycle tests do not establish actual rendered polish, audible fade or browser lip sync. Target-device visual/audio check remains required.
