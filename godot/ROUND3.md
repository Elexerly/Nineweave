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

## Follow-up pass

### 1. Owner audio

Inspected the producer's selection, lock-in, claim, spotlight, midgame and Duo screenshots at phone/tablet/Duo sizes. Wired all 13 recorded announcer IDs and seven SFX files through ResourceLoader-backed cached streams (`fx/sound.gd`). X/O claims select crystal shatter/gold clang. Export retains all resources and explicitly includes audio Oggs. Synth code remains the missing-path fallback. Place X/O are gentle 85/100 ms damped glass taps, with minimal high partials and no noise crack/long tail. Voice queue has a 100 ms gap, READY → WEAVE, synchronized comic text, and victory/defeat paired with the real fanfare/sting after the winning ladder line. Local results use NINEWEAVE/STANDOFF only. Existing duck/unlock/persisted gains remain.

Tests: added real-stream/path assertions for every voice/SFX, missing-path fallback, tap durations, start/result queue and gap checks. Targeted Round 3 PASS (319 checks). Full five-suite runner started after item 1; result recorded below. Initial headless import successfully imported the new Ogg files; only the known denied editor socket diagnostics occurred.

Item 1 full runner: PASS (rules 3,121,037; AI 2,566; layout 1,470; UI 857; Round 3 319), zero script/parser/error/warning lines.

### 2. Character art

Reworked all twelve cached vector rigs (`characters/rig.gd`): sampled smooth contours, sculpted navy shadow/curved light masses, rounded ink joins and tapered interior strokes; long tapered legs/boots, curved muscle/armour masses, mitten hands with folded thumbs and knuckle accents, smaller heads on heroic bodies. Added twelve authored asymmetrical resting gestures, opposing hip/shoulder angles, free/planted legs, tilted heads and purposeful prop holds. Hair/cloth drift sideways. Each hero now has a distinct chest garment/emblem, in addition to the existing unique helmet/hair/prop silhouettes. Heavy heroes retain broad shoulders. Faces have shaped eyes with irises/highlights, eyelids, brows, curved ears/jaw and nose/cheek marks; expression animation follows in item 6.

Added `tools/rig_proof.gd`: extracts transformed mesh triangles under headless mode for CPU-only art inspection. Inspected a rasterized twelve-hero proof; this verifies silhouettes/contours, **not** final shader/GPU output. Meshes remain cached across portraits/cinematics; no per-frame triangulation. Full runner launched after item 2; results below.

### 3. Compact claim pop

`characters/cinematic.gd` now computes a compact panel capped at 44% of board width. It prefers the free lower margin on tall phones or the nonboard HUD side on landscape/Duo/tablet. Short phones use the opposite board row when no margin exists. The claimed tile plus clearance is protected; pop hero movement stays within its panel and no pop halo spills over the board. Two short text rows preserve the one-liner. Existing 1.2 s duration, skip after 200 ms, mouse-ignore and legal input beat are unchanged.

Added 144 targeted placement assertions over all nine claimed boards at eight sizes, including 360×640/568×320. Round 3 PASS (463 checks), zero diagnostics. Full runner launched after item 3; results below.

Item 2 full runner: PASS (5/5), zero diagnostics. Item 3 full runner: PASS (5/5), zero diagnostics; Round 3 463 checks.

### 4. Section F — match corners

`ui/layout.gd` adds board-disjoint player/rival corner rects. Player is lower-left and rival upper-right; settings moves left to clear the rival. Tall phones use the space below the control row. Short portrait screens crop/shrink to the small footer strip. Height-filling phone landscape uses the lower-left of the nonboard side deck (the physical screen corner has no usable space without changing the approved board). Duo portrait's lower deck moves its minimap right to free the left corner; tall Duo/tablet use outside-board corners. Explicit folds remain clear. Scorecard portraits are frozen; live corner rigs and the Duo panel react. All overlay controls ignore mouse input and clip art to their rect, including animated props.

Targeted layout PASS (1,630 checks; 25 sizes plus hinge variants); Round 3 PASS (473). Added assertions for corner enclosure, board separation, hinge separation, and mouse-ignore. Full runner launched after item 4; results below.

Item 4 full runner: PASS (5/5), zero diagnostics (layout 1,630; UI 857; Round 3 486, including newly added highlight assertions).

### 5. Section E — last-move white highlight

`ui/board.gd` adds one cheap white overlay in the existing normal-blend Top layer: a faint wash and thin inner border, 240 ms eased fade-in, steady thereafter. Opponent moves highlight their cell; claiming moves highlight the whole small board. Own moves clear it; local pass-and-play follows either side. `main/main.gd` synchronizes from authoritative move history on label/state refresh, so save/resume, undo, online state replacement and new games need no kernel/schema changes. Active cyan glow and all R2 placement/claim/win timings remain untouched. Capture tools now include `last_move` (genuine opponent reply).

Round 3 targeted PASS (486 checks), including persistence, clear/replace, local play, claim geometry, new game, undo and saved-game restore. Full runner launched after item 5; results below.

Item 5 full runner: PASS (5/5), zero diagnostics.

### 6. Section G — expressions and reactions

Added `characters/reactions.gd`: all ten requested game-event categories resolve weighted reaction choices; deterministic presentation-only sequence, priority-aware cooldown, higher-priority claim/danger/result interruptions, 0.5 s Reduced Motion reaction cap. Eight short clips (nod, smirk, startle/double-take, eye-roll, cheer, panic, pout, relief) use eased anticipation/recovery and retain the underlying contrapposto. Main routes actual moves, unblocked two-in-row threats, claims, match point, comeback, win and loss to both corners/the Duo panel. No input or game-state changes.

All twelve heroes have all seven expressions, each with a per-hero face dialect: neutral, smug grin, panic, double-take, eye-roll, celebration, sulking. Separate cached face parts for sclera/lids, pupils/highlights, brows, mouths and comic symbols (sweat, ?!, anger ticks, sparkle, sulk lines). Bust faces are enlarged. Narrow authored rim strips use cyan/gold side colour in the Compatibility shader. Expression meshes are shared/cached; transitions do no triangulation. Selection, board-pop, power/stagger and spotlight poses also resolve expressions. `reaction` capture scenario and CPU `rig_proof.gd -- --faces` mode added. Inspected the seven-face proof for Vesper/Rex/Quill/Gilt; all other heroes have the same complete face vocabulary with their own dialect/silhouette.

Tests cover every event and weighted choice, every hero/reaction expression mapping, cooldown/priority/release/reduced motion, all 84 drawable hero expressions, cache reuse, real game-event routing, deterministic captures, and player/local result voice integration. A new result test initially assumed NINEWEAVE for a zero-opponent-board fixture; corrected it to accept the required CLEAN SWEEP ladder. Targeted Round 3 final result recorded below. Full runner launched after item 6.


Item 6 full runner: PASS (5/5), Round 3 720 checks; zero SCRIPT ERROR/Parse Error/ERROR:/WARNING: in all six numbered full-run logs. Initial web export PASS. A final source audit found alpha tagging on the rim shader could be confused by parent fades: changed it to a cached UV.x vertex flag, independent of opacity. Re-running final checks/export after this narrow shader fix.


### Follow-up final validation and remaining review

All six numbered steps ran `sh godot/tools/run_tests.sh` successfully; the additional final run after the UV rim fix also passed. All seven full-run logs have zero SCRIPT ERROR, Parse Error, ERROR: or WARNING: lines. Final results:

```
NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
NINEWEAVE_AI PASS checks=2566 failures=0
NINEWEAVE_LAYOUT PASS checks=1630 failures=0 sizes=25
NINEWEAVE_UI PASS checks=857 failures=0
NINEWEAVE_ROUND3 PASS checks=720 failures=0
NINEWEAVE ROUND3 TEST SUMMARY: PASS (5/5 suites; rules, AI, layout, UI, Round 3)
```

Final AI diagnostic: Medium vs Easy 29 wins/1 draw; Hard vs Easy 30 wins; native Hard 140.52 ms mean / 207.12 ms max, incremental slice max 2.85 ms. These are headless CPU measurements, not phone frame-rate measurements.

Headless Compatibility `--import` completed with exit 0, imported all 20 Oggs plus new scripts/UIDs, and has no script/resource/shader parse errors. The known denied editor `_inet_open` / `TCPServer.listen` socket diagnostic pairs remain in editor import/export infrastructure logs; they are preserved, not claimed clean. Test suites have zero diagnostics.

Final `tools/export_web.sh` PASS after the UV fix (a second export was necessary because the final source audit corrected the rim marker after the first successful export). Single-threaded Compatibility Web release, BUILD_INFO first line **Nineweave Round 3**. Output is under `godot/.godot/web-build/` to honor this pass's write scope. Checked all 20 owner audio source paths are represented in `index.pck` (20/20, missing 0); real-stream tests separately verify every source resolves to AudioStreamOggVorbis. `git diff --check -- godot` is clean. No git mutation, install, network access or display session was performed; all authored edits are under `godot/`.

Files: `fx/sound.gd`, `fx/announcer.gd`, `export_presets.cfg`; `characters/rig.gd`, new `characters/reactions.gd`, `characters/cinematic.gd`; `assets/shaders/comic.gdshader`; `main/main.gd`, `ui/layout.gd`, `ui/board.gd`; layout/Round 3 tests; capture tools, new headless `tools/rig_proof.gd`, and this log. Godot generated imports and UID files for the new assets/scripts. Approved board art, thin large emblems, rules/AI/online protocol and R2 animation timings remain as before this follow-up, with only the requested white highlight added to board presentation.

All twelve characters use the complete expression/reaction vocabulary; there is no unfinished roster subset. Further bespoke narrative acting (falling crown, unraveling sleeve, bird story, etc.) is still optional future polish, as in the main pass. Very short phones necessarily get a small/cropped lower-corner bust because the approved board/control geometry is retained. A height-filling landscape board uses the nearest safe lower corner in the side deck.

Remaining: producer's fresh Xvfb captures (especially all corner positions, compact pop typography, rim/clip/fade appearance), listening to the real mix on speakers/headphones, Web/iOS unlock/resume checks, and actual device frame pacing/GPU cost. Inspected the supplied main-pass screenshots and new headless CPU mesh/face proofs; no new GPU screenshot or audible playback is claimed. `last_move` and `reaction` join the existing deterministic capture scenarios. The mesh proof verifies shapes and facial distinctions only, not the final shader/rendered UI or a high-end art approval.
