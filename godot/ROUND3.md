# Nineweave — Round 3

Working incrementally; only `godot/` is edited. No network, installs, git mutations, display or speakers. Approved Round 2 board art/mechanics/animation timing are preserved. Compatibility renderer remains in use.

## A — Sound (implementation)

Replaced `fx/sound.gd` with original cached PCM synthesis (22.05 kHz, signed 16-bit), fixed player pool, Master/SFX/Music/Announcer buses, five fixed pan sends and smooth manual −4.5 dB announcer ducking (35 ms attack / 160 ms release). No music bed is added. SFX and Announcer sliders persist; Music bus/gain is reserved. Silent unlock playback happens in the first mouse/touch/key input callback, with explicit web detection; no playback before the gesture. Legacy settings without audio_version 3 repair the old mute once; intentional Round 3 mutes persist.

Cue layers: X = inharmonic icy partials; O = lower metallic partials; both share high-pass noise crystal set + short body transient. UI = tight high gold tick. Invalid = noise knock and descending low resonance. Route = noise whoosh and two delayed glass partials, panned to the destination column. Claim = high-pass crack, falling sub, rising chirp, intermittent high sparkles. Victory = four newly composed major brass-like additive chords over 2.65 s; defeat/draw use a darker descending progression. Announcer uses an original gritty formant choir/stinger, **not intelligible recorded speech**, paired with bold gold/ink burst text (`fx/comic_callout.gd`). Ladder weight increases gain/duration/particle accents. Pure `fx/announcer.gd` detects all requested events, with specific events taking priority and a full qualifying event list available to tests. Only one callout per transition prevents a spoken queue. Original 12-key character stinger generator is prepared for C.

Startup generates only 25 ms of near-silent unlock PCM. Other cues prewarm in 1.8 ms work slices or cache on first request. `main/main.gd` now routes move/claim/result/reject/buttons and announcer events. `settings/store.gd`, `tools/run_tests.sh`, `tests/run_round3_tests.gd` updated. Headless validation pending below.

A validation: all five suites PASS, rules 3,121,037; AI 2,566; layout 1,470; UI 682; Round 3 53, with zero error/warning lines. Full cue-bank synthesis took ~745 ms when deliberately forced in one test; production startup generates only unlock and prewarms the rest incrementally. Headless mode exercises stream generation/routing/duck state without starting Dummy-driver playback (Godot retains playback objects without a real mixer).

## B — Thin large emblems

`ui/paint.gd` adds separately cached X/O emblem meshes at 60% stroke weight, including scaled bevel rims/ridges. `ui/board.gd` uses them only for claimed-board stamps; `main/main.gd` uses them for the result-panel emblem. Normal cell/player/turn marks retain their original meshes. Halo, colours, radius and every Round 2 animation duration/phase are unchanged. Full regression queued.

B validation: five-suite full regression PASS with zero error/warning lines. Extra mesh-cache checks also pass (Round 3 now 55 checks).

## C — Character layer (in progress)

Added the twelve original roster records and a separate versioned local profile with replaceable identity envelope. Character art is authored procedural cutout geometry, not downloaded/generated images. Further integration and validation follow below.

C implementation: `characters/roster.gd`, `profile.gd`, `rig.gd`, `select.gd`, `cinematic.gd`, `assets/shaders/comic.gdshader`; integrated in `main/main.gd`, `ui/layout.gd`. Each rig has 15–20 articulated mesh parts (limbs, head/face/eyes, cape/hair/helmet, costume and signature prop). Polygon geometry is triangulated once, merged per part with ink expansion, clipped navy shadows, lit facets and sparse shadow halftone. Portrait head/cape edges have ±1.2-unit cyan/rose doubles; one cheap canvas shader adds rim/impact colour. No screen sampling, render-target ping-pong, HDR or glow environment. Frozen portraits reuse draw commands; only live heroes animate. Seamless 5.2 s idle includes breathing, weight transfer, blink and delayed prop/cloth motion. Clips: idle, idle_power, idle_stagger, hover_react, lock_in, board_pop, victory, defeat, score_flash, mark_push. Pose changes blend over 220 ms; attacks anticipate/recover with phase-offset follow-through. Defeats vary head/arm/prop angles by hero, with kneeling/settling for heavy characters; these are procedural reactions rather than full hand-animated narrative sequences.

All 12 are visible at once on the selection grid. Title Hero button, screen-name field, focus reaction/line/mark preview and 950 ms lock-in (350 ms Reduced Motion) are integrated. First game routes through selection; local identity and choice persist independently of game state. Rival is a different random hero; resume retains it. Character mark signatures are previews/held sigils; the normal in-cell X/O remain the approved R2 art as requested.

Claim pop lasts 1.2 s (550 ms reduced), remains mouse-transparent, and retains only R2's original 160/50 ms move beat. Game-win spotlight begins at R2's result beat: board FX pause at that point, a 3 s (1 s reduced) winner/loser scene plays, then the original result entrance resumes. Every new cinematic skips after 200 ms. Reduced Motion removes punch/edge doubles, limits speed strokes and reduces rig amplitudes. No new random particles: posed speed lines/halftone are deterministic and capped.

Duo landscape replaces the lower chronicle area with a live character panel and reflows the existing mini-map/info; Duo portrait uses the lower middle deck. Board geometry is unchanged. Tablet tall cards contain full figures; phone cards contain busts. Ahead/behind board counts drive power/stagger; claims flash/push a sigil. Explicit hinge layouts keep art/controls on their own side.

Capture tools now accept character_select, lock_in, claim_pop, win_spotlight, duo_panel at 390×844, 844×390, 867×553, 669×787, 1366×1024, preserving existing scenarios. OUT defaults to `/workspace/nineweave-r3-shots`. `debug_refresh()` pins all rig/cinematic clocks and does not depend on running particles.

C targeted validation: Round 3 197 checks PASS, including all roster/identity/clip/selection/input/skip/stance/scenario cases. Full five-suite regression is running. No visual/audio output is claimed from headless checks.

C full regression: rules 3,121,037; AI 2,566; layout 1,470; UI 722; Round 3 197 — all PASS, zero error/warning lines.

## D — Local theme scaffold

`themes/registry.gd` defines independent background and board collections with Crystal defaults. `settings/store.gd` persists/validates their IDs. Settings → Cosmetics cycles choices or restores Crystal. The crystal draw branch, meshes, colours and timing remain the original code path. Optional Sandstone Marble uses cached recoloured piece meshes and warm stone tile interiors with faint procedural veins; heavy gold frames/layout remain. Tidal Ocean uses four low-frequency wave strips and a pearl moon; Western Dusk uses three static mesa silhouettes and a copper sun. `ui/backdrop.gd` skips the old sky/art only for those explicit optional choices. No downloaded art or generated samples.

`net/net_transport.gd`, `loopback_transport.gd`, `http_polling_transport.gd`, `main/main.gd`, `ONLINE_PROTOCOL.md` now share only validated starter IDs at create/join and in a seat map. Moves/state authority are unchanged. Theme registry/settings are not imported into net/. Character maps are validated before delivery. No theme/background field enters a payload. Protocol remains compatible with v1 responses without character metadata. Validation follows.

## Final polish and validation

Character meshes are now cached by hero and reused across focus, field cards and cinematics; repeated selection/layout rebuilds do not triangulate the same art again. Twelve distinct six-note motifs with independent roots and harmonic colours replace the initial generic motif. The selected/rival tags, claim stabs and full 2.3 s motifs prewarm through the same bounded synthesis queue. Full-bank tests deliberately force every core/announcer cue and all 36 hero variants: ~2.35 s total in one diagnostic run, **not startup cost**. Production startup only builds the 25 ms unlock cue; other generation is incremental (or lazy on an early first request). No claim of measured Safari audio latency is made.

The screen name in Settings and the local profile now stay in sync. Online and Resume first-match paths also route through initial character selection. A top fold mask keeps even effect halos out of an explicitly reserved gutter. The 568×320 selector uses a shared footer row so all twelve portrait targets remain at least 44×44. Reduced Motion, profile/name persistence and theme reset remain available without an account.

Final source validation:

```
NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
NINEWEAVE_AI PASS checks=2566 failures=0
NINEWEAVE_LAYOUT PASS checks=1470 failures=0 sizes=25
NINEWEAVE_UI PASS checks=857 failures=0
NINEWEAVE_ROUND3 PASS checks=299 failures=0
NINEWEAVE ROUND3 TEST SUMMARY: PASS (5/5 suites; rules, AI, layout, UI, Round 3)
```

Every lettered section ran the full shell runner before proceeding; final run includes all changes. Test/runtime logs contain **zero** SCRIPT ERROR, Parse Error, ERROR: or WARNING: lines. Hard vs Easy: 30/30 wins; Medium vs Easy: 29 wins/1 draw. Final native Hard timing: 145.74 ms mean, 220.84 ms max; requested 2.5 ms incremental slices peaked at 2.90 ms in that run. These are CPU/headless measurements, not a device FPS claim.

`tools/export_web.sh` produced a single-threaded Compatibility release successfully; BUILD_INFO begins **Nineweave Round 3**, source HEAD remains 64d6916 on godot-game, and the build explicitly records uncommitted changes. `git diff --check` is clean. New UID files were created by the headless editor import. README/protocol/test runner/capture tools are updated. No source outside godot/ was changed; no git mutation, install, network fetch, display session, screenshot capture or publishing was performed.

### Import limitation

Headless `--import` completed with exit 0 and imported all scripts/shader resources; there are no resource/parser diagnostics. This sandbox denies editor debug/listener sockets. The editor nevertheless emits `_inet_open` / `TCPServer.listen` ERROR diagnostics while starting those built-in listeners (also during staged export). Recovery mode reduces this to one diagnostic pair but does not eliminate it. Those diagnostics are **not silently filtered or claimed clean**. The five executable test suites have zero error/warning lines. Consequently the requested zero-error condition is achieved for application/runtime/tests, **not for the editor's import/export infrastructure logs**. The final import is retained as a completed import with this explicit limitation.

### Not verified and known gaps

- No display or speakers: new characters, shader colour/edge treatment, typographic balance, clipping and mix are reasoned and structurally tested, not visually/listening approved. The owner's Xvfb/Mesa capture pass remains essential. New deterministic scenarios are ready in the capture scripts; no screenshots were produced here.
- Actual first-gesture Web/iOS AudioContext behaviour, speaker mix, touch/keyboard behaviour on device and 60 fps/GPU cost cannot be proved by native headless tests. Procedural PCM and routing/ducks are tested. Initial lazy requests may still cost a frame before warming on a slower phone.
- Announcer audio is a theatrical synth/formant **stinger**, not intelligible spoken English; the exact original words are always on screen. There is no music bed. Original recorded speech may improve personality later.
- The rig library has all required clips, authored silhouettes/faces/props and per-hero reaction variations. Elaborate story-specific defeat business (individual falling crowns, unraveling cloth, flying bird narrative) is represented by poses/props rather than a complete bespoke animation short for every hero.
- Character mark styles appear in selection previews/score sigils. In-cell marks intentionally retain Round 2 geometry; a future opt-in piece-style system can expand signatures without changing the default board.
- Side panel is on the unfolded inner display only. No cover-screen accessory, camera workaround, native plugin, account system or production online backend was added. The existing online abstraction remains loopback + future HTTP client.

### Suggested Round 4

1. Review the five new capture scenarios and the original title/claim/win_end at every requested size, then tune facial readability, crops and panel typography from actual rendering.
2. Listen and tune transients, voice-like stingers and gain hierarchy on phone speakers/headphones; verify unlock/background resume in Safari and the iOS export. Add original recorded speech only if wanted.
3. Profile real device GPU/CPU/frame pacing. Atlas or pre-render frozen portrait cutouts if necessary; retain the current vector rigs for live poses.
4. Expand hero-specific lock-in/victory/defeat acting and optional signature-piece cosmetics. Implement the documented authoritative backend with verified accounts/reconnect separately.
