# Nineweave Round 4b — 32 heroes and moving comic cinematics

Implemented in `godot/` only, with Godot 4.7.2. No git commands, network,
installs, audio changes, or source-image edits. Read `ROUND4.md` first and used
only the timing/composition guidance in the reference guide, without copying
reference art, characters, wording or assets.

## Roster, art and selection

- Appended the requested 16 IDs after the original 16, in the exact requested
  order. Each has original concept, victory, defeat and action copy, the supplied
  palette and pop line, and cosmetic body/prop/mark metadata. All 16 existing IDs,
  positions and audio mappings are retained. Every new hero explicitly maps to
  an existing motif through `Roster.audio_index`; the sound system is untouched.
- All 320 WebP import sidecars use Lossy mode 1, quality **0.85**, mipmaps off.
  Only splash/victory imports have `process/size_limit=640`; all 224 registered
  head canvases remain 256×256, and versus imports retain their source size.
  The source WebPs and `PLACEHOLDER.txt` files were never edited or deleted.
- Phone portrait has four pages of eight (4 columns × 2 rows), two arrows, four
  font-safe dots, swipes in both directions and wrapping in both directions.
- Other layouts compute fit: 32 at once means 8 columns × 4 rows and both tile
  dimensions at least 56px. Otherwise, two pages of 16 use 8×2 or 4×4. Eight
  columns on a paged screen also need room for readable first-word labels.
  Very short landscape moves the name/confirm controls beneath the splash so
  the right-hand 4×4 grid still has touchable rows. Explicit Duo hinges are
  excluded from both detail and roster panels.
- Representative tile sizes: 360×640 → four pages, 78×85px; 390×844/664 → four
  pages, 85.5×85px; 867×553 → all 32, about 57.4×76.8px; 1366×1024 → all 32,
  about 93.5×123.8px; 1920×1080 → all 32, about 133.7×176px. The 568×320
  fallback has two 4×4 pages with about 69.7×48.5px tiles.
- Selection loads only visible-page neutral heads and the selected splash.
  Hidden tile nodes do not load their art during `_ready`; visiting a page
  loads that page's heads. No versus, victory or reaction textures are
  preloaded by the select screen. Computer rivals use all 31 other heroes.
- Screen-name entry now sits on a slanted dark-navy plate with gold ornament,
  cyan focus edge, SCREEN NAME caption, light text and readable placeholder.
  The LineEdit's `normal`, `focus` **and `read_only`** backgrounds are empty, so
  local PLAYER 1/2 fields keep their behavior without the default grey box.

## Cinematic motion

One analytic `age` clock drives live poses and arbitrary-time captures. Back-out
and cubic easing functions provide the requested overshoot without unseekable
fire-and-forget tweens. There is no wall-clock shader TIME, random particle RNG,
physics integration or texture allocation on each frame.

**Versus, 3.0 seconds:** diagonal background panels wipe in; both bodies dash
from opposite offscreen sides, with three fading texture afterimages per actor
and moving directional streaks. Portrait uses bottom-left/top-right travel;
landscape uses left/right and a reflected rival. At 0.35s, the VS starburst slams
from 2.2 to 0.9 to 1.0, a three-frame white/ink/white graphic impact lands, and a
10px shake decays to zero by 0.60s. There are 44 seeded cyan shards and 44 gold
sparks, emitted from their respective X/O sides. Plates sweep in at 0.45/0.53s
and catch a traveling glint. A slow 1.00→1.06 camera push, opposite-phase 3.5px
bobs, 1.5% breathing, drifting lines and gently pulsing batched halftone keep the
readable hold alive. From 2.65–3.0s the heroes and diagonal panels dash apart,
revealing the board. Skip remains guarded until 0.6s. Clock, input and AI wait
until completion or an accepted skip.

**Winner, 5 seconds:** the victory pose leaps in with overshoot and a landing
squash. Rays rotate slowly and 112 deterministic confetti/shard particles follow
ballistic arcs with gravity. The screen name and then WINS! slam letter by
letter at 45ms intervals. Hero name and score slide/fade in. A small vertex-only
shader sways the shoulders/cape while keeping the feet anchored; its time is
explicitly set from the cinematic clock. A quiet 3.5px bob accompanies the
breathing hold. The small loser head shakes, panics,
droops and settles into a pout. Existing slanted actions fade/slide up at 3.0s;
skip after 0.8s reveals them immediately. The final pose remains behind usable
actions after the five-second beat. Draw uses two sliding/bumping heads, a DRAW
letter slam and the same action timing.

Winner hero-name colour now uses the actual winning X/O side, including the
computer and P2. The score scales with the card and is at least 16px (27px at
1366×1024). Move history uses ASCII `>`; the suite checks `Font.has_char` on the
actual bundled Rajdhani font, including all paging glyphs.

**Reduced motion:** only short fades, no traveling bodies/plates, shake,
flashes, particles, breathing, rotating rays, shader sway or loser motion.
Versus settles in 0.65s; results settle in 1s with actions fading in at 0.25s.
The optional additional board bounce was omitted; existing board win effects
and their timing remain intact.

## Deterministic captures

`capture_shots.gd` accepts `versus_t`, `winner_t`, `winner_cpu_t` and `draw_t`,
with `--time SECONDS` or `--time=SECONDS`. Time can move forward or backward,
including across the actions appearing and the versus card disappearing.
Cinematic `seek` poses only; it never emits match/AI transition callbacks.

Examples, under a working real display:

```sh
ROUND4B_ONLY=1 xvfb-run -a sh godot/tools/capture_shots.sh /tmp/nineweave-r4b-shots
xvfb-run -a sh godot/tools/capture_sequence.sh 390x844 versus_t 60 3 /tmp/nineweave-r4b-versus
xvfb-run -a sh godot/tools/capture_sequence.sh 867x553 winner_cpu_t 30 5 /tmp/nineweave-r4b-winner
```

The sequence helper renders **all frames in one launch** at `frame/FPS`,
including the final frame, to `frame_%04d.png`. It waits for redraws after each
seek. The Round 4b capture section covers all four requested sizes, four select
pages (the full grid on fitting layouts), versus at 0.2/0.4/1.5s, winner at
0.5/1.5/3.5s, CPU winner at 3.5s and draw at 3.5s.

### Capture limitation — visual QA is incomplete

Both the original capture command and the finished Round 4b command were run.
Xvfb cannot bind its local display sockets in this sandbox:

```text
_XSERVTransSocketUNIXCreateListener: ...SocketCreateListener() failed
Fatal server error:
Cannot establish any listening sockets
ERROR: X11 Display is not available
ERROR: Unable to create DisplayServer, all display drivers failed.
```

No rendered PNGs were produced, so no rendered screenshots were visually or
numerically inspected. Native/Web rendering, GPU shader compilation and phone
frame-rate remain producer review items. Headless tests do not substitute for
that visual review. The new suite checks the **actual Art draw path's positive
texture rect, reflection transform and clipped visible area**, across real
hero nodes; when run with a display, it also enables a SubViewport pixel probe
using an asymmetric synthetic alpha texture, avoiding any dependency on art
that the producer is replacing. That real-pixel probe could not run here.

## Files

| Files | Changes |
|---|---|
| `characters/roster.gd` | 32 heroes, appended IDs, copy, palettes and stable audio mapping |
| `characters/select.gd` | Computed grids, four-page phone, lazy heads and slanted name entry |
| `characters/cinematic.gd` | Moving layered cards, cached lettering/halftone, seek, result timing |
| `characters/cinematic_motion.gd` + `.uid` | Pure timing, easing, shake, seeded ballistic particles |
| `characters/victory_sway.gdshader` + `.uid` | Feet-anchored, explicitly timed upper-body sway |
| `characters/art.gd` | Shared positive texture-rect/reflection helpers used by draw and tests |
| `main/main.gd` | Result-action fade/slide, font-safe move history, capture seeks/pages |
| `assets/heroes/*/*.webp.import` | 320 lossy imports, 64 import-only size limits |
| `tools/capture_shots.gd`, `tools/capture_shots.sh` | Exact-time scenarios and four-size Round 4b capture section |
| `tools/capture_sequence.sh` | Single-launch deterministic frame sequences |
| `tools/check_pack.gd`, `tools/export_web.sh` | 320-resource audit, preserved import settings, enforced <20 MB budget |
| `tests/run_round4b_tests.gd`, `tools/run_tests.sh` | New suite and 11-suite Round 4b summary |
| `tests/run_ui_tests.gd`, `tests/run_round3_tests.gd`, `tests/run_round3b_tests.gd`, `tests/run_round3c_tests.gd`, `tests/run_round4_tests.gd` | Explicitly superseded presentation assertions below |
| `tests/LAST_RUN.txt` | Complete passing regression output |

## Existing assertion changes

No assertions were removed or relaxed to hide a failure. In particular, short
landscape label/plaque failures were fixed in layout, preserving the fit checks.

1. **UI:** both completion waits changed from 2.81s to 3.01s for the requested
   three-second intro. Input, online sender and gameplay assertions remain.
2. **Round 3:** six unique roster-field counts changed from 16 to 32, and the
   first-match portrait-node count changed from 16 to 32. All per-hero art and
   expression checks still run, now over the larger roster.
3. **Round 3b:** the online-highlight fixture's versus completion wait changed
   from 2.81s to 3.01s. Leak, audio, highlight and other checks are unchanged.
4. **Round 3c:** the former `not c.loser.visible` assertion now requires a
   visible **bust** alongside the unchanged winner victory pose. This one
   presentation expectation is necessarily superseded by the explicitly
   requested loser-head stagger; retaining it would forbid that feature.
   Winner rect, viewport/action separation and all legacy inset geometry,
   caption-fit and board-safety assertions remain.
5. **Round 4 roster:** total/unique count becomes 32. The exact original 16-ID
   prefix remains checked; the new suite separately checks all 16 appended IDs
   in order. All texture, head-registration and exact 0.85 import checks remain.
6. **Round 4 selection:** phone now requires 4 pages of 8; non-phone requires
   either 32 at once or 2 pages of 16. Visible counts, arrow/dot counts and page
   traversal use that contract. Every page is visited; wrap expects the final
   page. All tile touch/viewport and local duplicate-selection checks remain.
7. **Round 4 timing:** versus waits become 3.01s and the protected-duration
   check samples 2.99s rather than 2.79s. Winner actions are checked at 3.01s
   instead of 1.81s (the existing fixture starts at 1.25s). Winner identity,
   guarded skip, navigation, persistent art, rotation and online agreement
   assertions are retained.

`kernel/rules.gd`, `ui/board.gd`, `ui/layout.gd`, `fx/sound.gd`, audio assets/buses,
title art, `tests/layout_snapshot_r3c.json` and the complete
`tests/run_round3e_tests.gd` were not edited. Gold last-move behavior is unchanged.

## Tests and export

The new suite covers 320 loadable textures and lossy imports; unique/appended
IDs and original motif mappings; truly lazy select loads; all requested screen
sizes plus short landscape and an explicit hinge; every page, arrow, dot,
swipe, label, touch target and detail bounds; all 31 random rival alternatives;
versus offscreen/arrived poses, slam, flash, shake decay, exit, skip and match
clock/input/AI gating; winner letters, buttons, skips, player/CPU/P2/online
identity and colour; draw; repeatable forward/backward capture seeks; reduced
motion; all 32 corner/scorecard/Duo/pop surfaces; reflection visibility and
font glyphs. All 11 suites pass, including unchanged audio and Round 3e suites.

Exported with:

```sh
sh godot/tools/export_web.sh /tmp/nineweave-r4b-export
```

Final measured `index.pck`: **16,590,328 bytes — 16.590328 MB / 15.822 MiB**.
This is below both the 18 MB target and the strict 20 MB limit. Export preserves
all hero import parameters, checks all 20 packed Ogg recordings, and now fails
if the PCK reaches 20,000,000 bytes. Staging snapshot:
`/tmp/nineweave-export.RKxUze/project`.

The producer is replacing art concurrently. This measurement belongs to that
export snapshot (5 new-hero folders still carried PLACEHOLDER markers there),
not to the eventual completed art set. Replacing the images requires re-import
and re-export; the sidecar settings and export budget guard remain in effect.
No generated replacement artwork was used.

The release PCK was opened directly with the engine and external pack audit:

```text
NINEWEAVE_PACK PASS hero_textures=320 select/versus/winner=PASS
```

Editor import/export logs include sandbox TCP-listener failures (`_sock == -1`
/ `ERR_CANT_CREATE`), as in Round 4, but no script parse/resource-export errors.
The regression runner itself has no SCRIPT ERROR, ERROR or WARNING lines.
The pre-existing external online backend gap is unchanged.

Full output of `sh godot/tools/run_tests.sh`:

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

AI incremental slices=77 max_slice_ms=2.84
AI_STRENGTH Medium vs Easy N=30 wins=29 draws=1 losses=0 rate=96.6666666666667% moves=1194 node_limit=700
AI_STRENGTH Hard vs Easy N=30 wins=30 draws=0 losses=0 rate=100.0% moves=1091 node_limit=700
AI_TIMING Hard samples=45 mean_ms=161.3 max_ms=311.88 hard_ceiling_ms=450
NINEWEAVE_AI PASS checks=2566 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_LAYOUT PASS checks=1948 failures=0 sizes=25
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_UI PASS checks=867 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

AUDIO synthesis_all_ms=2084.736 (lazy; startup only unlock)
NINEWEAVE_ROUND3 PASS checks=912 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

LEAK games=56 nodes_after_6=37.0 nodes_after_56=37.0 orphans=0.0→0.0
NINEWEAVE_ROUND3B PASS checks=597 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

TURNAROUND_RATE { "turnaround": 197, "first_claim": 120, "old": 394 }
NINEWEAVE_ROUND3C PASS checks=6734 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_AUDIO PASS checks=270 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_ROUND3E PASS checks=965 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_ROUND4 PASS checks=2023 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

FLIP_VISIBILITY transform/clip=PASS; real-pixel probe requires a display
NINEWEAVE_ROUND4B PASS checks=4282 failures=0
NINEWEAVE ROUND4B TEST SUMMARY: PASS (11/11 suites; rules, AI, layout, UI, Round 3, Round 3b, Round 3c, audio, Round 3e, Round 4, Round 4b)
```

## Pass 2 — roster renames and animation polish

Implemented under `godot/` only, using the existing Godot 4.7.2 binary. No git,
network, installs, audio-system edits, or source-art edits were performed.

### Roster and compatibility

- Applied the owner's five ID/display-name renames, Jack Sovereign replacement,
  Sara redesign, Ethan's silver-white/sapphire styling, Aiden's original
  robotics/spinning-top concept, and Dylan's gold-token copy and palette.
- The original 16 slots remain stable. The appended order is James II, Sara,
  Daphne, Jason Danger, Dylan Volt, Max Granite, Kellen Byte, Simon Shade,
  Alex Wilder, Rose Valor, Grayson Quake, Erick Comet, Devin Torque, Pope Slam,
  Ethan Ricochet, Aiden Vortex. `shard_jack` remains the ninth protocol ID.
- `Roster.ALIASES` maps all five old IDs to canonical IDs. `valid`, `index_of`,
  `get_hero`, and `audio_index` accept aliases. Profile load and selection store
  canonical IDs. Online incoming seat maps canonicalize before signals/state;
  outgoing character/lobby payloads send canonical IDs. Every renamed hero
  retains its exact prior audio index. The protocol document records the map.
- Select labels use the first word, with the explicit `JAMES II` exception.
- Regenerated all 50 missing import sidecars under the five renamed folders.
  All 320 hero imports use mode 1, **quality 0.85**, mipmaps off, and correct
  canonical source paths. Splash/victory retain the import-only 640px limit;
  registered head canvases remain 256px. The isolated export's 320 sidecars
  were independently checked for those same settings.

### Cinematics

- Versus draws an opaque full-viewport navy cover **at t=0**, beneath the two
  diagonal wipes. The cover stays until the exit begins, including in reduced
  motion. The controller remains opaque, so its entry fade cannot expose the
  board. Geometry assertions check the actual transformed draw-cover rect and
  opacity at 0 and 0.05 seconds.
- At 2.65 seconds, heroes continue along their incoming dash headings with three
  afterimages each. Background halves slide apart. VS shrinks and the foreground
  fades completely in **0.12s**, including name plates and foreground particles.
  The entire versus subtree is hidden at 3.0 seconds, with tests at 3.0, 3.05
  and 3.2 seconds and a reverse-seek check retaining deterministic behavior.
- Winner lands at **0.35s** after a visible short leap arc, then squashes by up
  to 12%. Its landing emits **108** bright particles over 45ms. A separate
  **32**-particle burst follows the last WINS! letter settling. The maximum is
  **140** particles, each analytically posed with gravity, spin and a 1.5–2s
  lifetime. Sizes are 6–14px at 390px card width. Shards use the winner's cyan
  or gold; confetti mixes that colour with white. All 108 landing particles
  are live and bright at 0.5s; reduced motion emits zero particles.
- Loser is a circular framed badge: **88px at 390×844**, 84px at 360×640,
  scaled up for larger cards, and at least 80px in short landscape. A shader
  masks the displayed head without changing its source texture. The loser-side
  cyan/gold ring sits over the winner's lower cape lane, clear of the head and
  lettering. It hits/shakes at 0.4s, droops into a pout, panics at 1.0s, then
  settles back into a pout; a small cross punctuation appears beside the ring.
- Winner letter fitting includes the sheared ink, heavy outline and the full
  2× per-letter bounce, rather than only string advance width. Every sampled
  animated letter stays at least **18px** from both screen sides, including
  PATRICK and a 24-letter wide-name stress case. The leap, bounce and stagger
  remain analytic and seekable; reduced motion keeps short fades only.

### Regression and release verification

`sh godot/tools/run_tests.sh` **passes all 11 suites** on the final source.
Round 4b now reports **57,940 checks, zero failures**; complete output is in
`tests/LAST_RUN.txt`. New checks cover all five profile/online/art/audio aliases,
exact redesign copy/palettes and order, entry coverage, clean exit, both bursts,
particle visibility/size/cap, reduced-motion particle absence, landing arc and
squash, badge bounds/head/headline separation, stagger order, and animated
headline margins at 360×640, 390×844, 867×553, 1366×1024, 669×787 and 844×390.

No existing assertions were weakened. The former exact 112-particle expectation
is superseded by the owner's two-burst specification: the replacement requires
108 live landing particles, a timed second burst, and the exact 140 total cap.
The Round 4 Jack display-name expectation and renamed ID fixtures now use the
approved names. Audio tests, the complete Round 3e suite, its layout snapshot,
board/layout/rules code and sound code are unchanged. A SHA-256 audit of the
47 locked core/audio files is retained in `tests/pass2_locked_sha256.json`.

Final release command:

```sh
sh godot/tools/export_web.sh /tmp/nineweave-r4b-export
```

**PASS. `index.pck` = 16,596,424 bytes (16.596424 MB / 15.828 MiB), below
20,000,000 bytes.** All 20 original Ogg recordings remain packed. This measurement
belongs to staging snapshot `/tmp/nineweave-export.2xXIoy/project`; the producer
updated source art during this task, so future source replacements require a
fresh import/export. No source-image writes were made by this pass.

The final release PCK was opened with the external `tools/check_pack.gd` audit:

```text
NINEWEAVE_PACK PASS hero_textures=320 select/versus/winner=PASS
```

Export/import still log the existing sandbox editor-listener restrictions;
there are no script parse/resource export failures. Final regression output
contains no SCRIPT ERROR, ERROR, or WARNING lines.

### Capture attempts — rendered-frame review remains blocked

The expanded `capture_shots.sh` matrix now requests initial versus frames
(0, 1/30, 0.05), the exit through 3.2s, landing/leap/badge beats, both winner
colours and draw across the review sizes, including short portrait and Duo.
The following commands were actually rerun:

```sh
xvfb-run -a sh godot/tools/capture_sequence.sh 390x844 versus_t 30 3.2 godot/screenshots/pass2/390x844-versus
ROUND4B_ONLY=1 xvfb-run -a sh godot/tools/capture_shots.sh godot/screenshots/pass2
```

Both fail before rendering: Xvfb cannot bind local display sockets and Godot
reports `X11 Display is not available`, then fails Wayland and DisplayServer
creation. Logs are in `tests/pass2_capture.log` and
`tests/pass2_capture_shots.log`. An offline Chromium/SwiftShader capture fallback
was also attempted; the sandbox rejects its local socket setup with
`Operation not permitted`. The engine lists headless rendering as `dummy`
only, so that mode cannot provide rendered screenshots.

**No frame PNGs were produced, and frame 0/1 or any other rendered frames could
not be visually inspected.** The entry/exit, particles, geometry and timing have
passing automated assertions, but GPU rendering, visual composition and 60fps
on a phone remain unverified. This pass does not claim rendered capture approval.

## Producer edits after Pass 2
- Owner roster changes: `max_granite` is now **Max Overdrive** (cyborg juggernaut art), `devin_torque` is now **Devin Riot** using the former Jack Riot crystal-surf art. IDs kept stable; display names/text/palettes updated in `characters/roster.gd`.
- Final hero art imported with `tools/import_hero_art.py` (hand fixes for Aiden, James II, Pope, Jack Sovereign, Simon, Dylan, Kellen, Siren, Aurelia; new Cryon/Ryan heads, tighter Aurelia heads).
- Capture-only: `NW_HERO` / `NW_RIVAL` environment overrides for the versus/winner debug scenarios (`tools/capture_shots.gd`, `main/main.gd` debug hook).
