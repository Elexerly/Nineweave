# Nineweave Round 4 — illustrated roster and match flow

Implemented against the binding match-flow items 1–9 and the approved 16-hero
Style-3 roster. All source edits are under `godot/`. No git commands, network
requests, installs, new fonts, audio-system changes, or source-art alterations.

## Shipped behavior

- All player-visible hero surfaces now use the approved transparent WebP art:
  selection tiles, splash detail, scorecards, safe corner heads, claim pops,
  Duo character panel, versus bodies and winner victory poses. The old polygon
  rig has no runtime UI references. It remains only for the legacy internal
  `tools/rig_proof.gd` geometry tool; it is not instantiated by the game.
- Roster order: Cryon, Aurelia, Vesper Vale, Auric Rex, Nyx Thread, Cobalt Bastion,
  Ember Quill, Lumen Pike, Jack Riot (`shard_jack` stays protocol-stable), Madame
  Solstice, Bramble Ox, Kite Hollow, Professor Gilt, Siren Coil, Ryan Blaze,
  Tempest Vega. New heroes have original pop, victory and action lines. Jack's
  lines are updated, Kite is male, Siren is a human diver. Unknown profile IDs
  and unknown rendering IDs fall back to valid heroes.
- Corner reactions use whole registered 256×256 canvases: neutral; smug on a
  claim; delayed pout/panic on the other side; cheer/pout on win/loss. A 0.2s
  squash/stretch has a protected gutter and is clipped inside the existing safe
  rect. Expressions hold about 1.6s, then return to neutral. Idle face beats are
  spaced 6–10s apart. Reduced motion swaps instantly and disables idle beats.
  Opponent reactions trail by 0.28s. Scorecard portraits remain neutral whenever
  a separate corner/panel is active. No standalone corner is created without
  readable space; the existing scorecard head remains available there.
- Phone portrait selection has two rows of four, two pages, 44px arrows/dots,
  touch/mouse swipe and consistent wraparound. All other layouts show 16 at
  once, in a 4×4 grid. The detail area shows the selected splash, name and line.
  Pass-and-play explicitly asks PLAYER 1 then PLAYER 2, disabling P1's choice
  for P2 in both UI and controller. Local player labels do not replace the saved
  screen name. Computer mode assigns a random different rival. Online bypasses
  selection and uses profile heroes. Hero editing is available from the title
  and Options → Cosmetics, using this same grid.
- Every UI-created new match/rematch goes through a 2.8s versus screen. Portrait
  uses rival top on warm gold, player bottom on navy/cyan, a diagonal split,
  speed lines/halftone, white VS starburst with gold slanted type, and sliding
  screen-name/hero-name plates. Wide/Duo uses left/right; the rival faces left.
  Bodies slam in over 0.32s, VS overshoots once, plates arrive at 0.26s. Skip is
  available after 0.6s. The match clock, AI and board input wait for the intro.
  `start_game(..., present=false)` remains the low-level immediate-reset API for
  existing deterministic tests; product entry points pass `present=true`.
- The board's existing win animation runs first. The winner cutscene then shows
  the actual winner's `victory.webp`, correct screen name plus WINS!, hero name,
  small claimed-board score, rays/starburst and slanted REMATCH / MAIN MENU
  buttons. Entrance is fast; the cutscene settles over 5s and its art stays behind
  the actions. Buttons appear at 1.8s; skipping after 0.8s reveals them immediately.
  Draw has both illustrated heads and DRAW. Full-screen cards shield underlying
  controls; claim pops continue to ignore input. Existing skip-gesture protection
  prevents emulated mouse events from accidentally triggering Rematch.
- Local rematch starts immediately through versus, swaps X/O, keeps heroes with
  their players, and lets the new X move first. Computer rematch keeps the rival.
  Online rematch requires both agreements, with WAITING FOR OPPONENT… and
  OPPONENT WANTS A REMATCH / ACCEPT states. Loopback is the authoritative fake
  peer implementation; first sides are random, each rematch swaps them, and host
  identity stays stable even when host is O. Duplicate agreements are idempotent.
  The explicitly labelled local demo rival accepts after a simulated 1s delay.
  The HTTP interface and future endpoint/envelope are documented in
  `ONLINE_PROTOCOL.md`; no live backend is claimed.

## Locked contracts

`kernel/rules.gd`, `ui/board.gd`, `ui/layout.gd`, `fx/sound.gd`, audio assets/buses,
title art, and `tests/layout_snapshot_r3c.json` were not edited. The complete
`run_round3e_tests.gd` source and its assertions are unchanged. In locked phone
portrait layouts the existing corner regions are below the controls; they are
reused as-is, including hiding standalone heads at short heights. Board rectangles
are unchanged in every layout, including Duo. Undo/Hint remain computer-only and
the gold last-move highlight is untouched.

Existing heroes retain their original audio motif indices even though the roster
order now starts with two new mascots. New heroes reuse appropriate existing
motifs through `Roster.audio_index`; the locked sound generator is untouched.
All typography uses the already bundled fonts (Rajdhani with shear/keyline for
comic cards); no third-party font/licence was added. Optional face regeneration
was skipped: all approved art pixels and per-hero registration are preserved.

## Files

| Files | Purpose |
|---|---|
| `characters/roster.gd` | 16 heroes, stable IDs, text/concept changes, stable audio mapping |
| `characters/art.gd` | Lazy texture cache and clipped, registered illustrated pose/face player |
| `characters/select.gd` | Adaptive grid, paging/arrows/dots/swipe, blocked P2 choice, splash detail |
| `characters/cinematic.gd` | Illustrated pops, versus and persistent winner/draw comic cards |
| `characters/match_button.gd` | Slanted result actions |
| `main/main.gd` | Two-player picks, match/cutscene transitions, reactions, names, rematch integration |
| `net/net_transport.gd`, `net/loopback_transport.gd`, `net/http_polling_transport.gd` | Agreement and authoritative round/seat interface |
| `ONLINE_PROTOCOL.md` | v3 rematch/side-assignment extension and future HTTP contract |
| `assets/heroes/*/*.webp.import` (160) | Hero-only Lossy mode 1, quality 0.85, mipmaps off |
| `tools/export_web.sh` | Preserve hero import settings in staging; avoid git commands; Round 4 build info |
| `tools/check_pack.gd` | Audit all 160 resources and select/versus/winner from the exported PCK |
| `tools/capture_shots.gd`, `tools/capture_shots.sh` | Seven new scenarios at four sizes; `ROUND4_ONLY=1` support |
| `tests/run_round4_tests.gd`, `tools/run_tests.sh` | Round 4 suite; 10-suite runner |
| `tests/run_ui_tests.gd`, `tests/run_round3_tests.gd`, `tests/run_round3b_tests.gd`, `tests/run_round3c_tests.gd` | Update superseded presentation expectations, retaining regression assertions |

## Tests and changes to older tests

The new suite checks all 160 loadable textures and hero-only import settings,
roster order/uniqueness, unknown saved ID fallback, preserved original audio
indices, paging via arrows/dots/actual touch events, 44px tile bounds at 12 sizes,
P2 duplicate rejection, timed/skip versus transitions in both orientations,
correct player/computer/P2/online winner identities, five-second result behavior,
action timing and navigation, all 28 capture fixtures, safe heads and HUD exclusion,
reaction faces/reduced motion/idle beats, local side/hero retention, and seeded
online side assignment plus three rematches across 16 seeds. Real controller
integration tests cover both requester-first waiting and opponent-first ACCEPT.

Older assertions were updated only where the requested new roster or flow makes
an old expectation invalid:

- Round 3: 12 → 16 roster/uniqueness; one local pick + lock-in → P1/P2 + versus;
  old articulated bones, merfolk legs and polygon-expression geometry → approved
  illustrated textures, all seven complete head canvases and shared registration.
- UI: confirm the new pre-match selection and skip versus before playing; use the
  new 0.8s winner skip window; two-client move sender follows the assigned seat
  rather than assuming the host always has X.
- Round 3b: 0.2s old spotlight skip → 0.8s winner skip; cinematic now has three
  retained nodes (two illustrated actors plus foreground lettering); online
  highlight fixture waits for versus and seeds its own-then-rival X-first case.
  Leak and non-overlap assertions remain in place.
- Round 3c: card pops now use heads as well as banners; polygon head/crown bounds
  become whole-canvas/clip checks. The obsolete visible loser inset becomes a
  check of the actual exclusive winner victory pose and result-action geometry.
  Pop safety, frame metrics, caption fit, scorecards, announcer, and rematch-rival
  assertions remain. The legacy pure inset geometry helpers remain tested too.

No rules, AI, layout, audio, or Round 3e assertions were weakened or removed.

## Export and visual-QA limitation

`sh godot/tools/export_web.sh /tmp/nineweave-r4-export` succeeds and checks all
20 packed Ogg recordings. Final PCK size and complete test output are recorded
below. The staged project retains all 160 hero import settings; existing non-hero
texture import behavior is unchanged. Editor import/export logs include sandbox
TCP-listener failures (`_sock == -1` / `ERR_CANT_CREATE`); there are no GDScript
parse/resource export failures. These editor listener failures do not prevent
packing the release.

Capture command attempted, including a final attempt after integration:

```sh
ROUND4_ONLY=1 xvfb-run -a sh godot/tools/capture_shots.sh /tmp/nineweave-r4-shots-codex
```

**Visual QA is not complete.** Xvfb cannot bind a local display socket in this
sandbox (`Cannot establish any listening sockets`); Godot reports `X11 Display
is not available` and cannot create a DisplayServer. No actual Round 4 rendered
screenshots were produced, so none were visually inspected. I inspected the four
approved mocks and source versus images, but cannot claim rendered/mock parity.
The 28 scenarios are instantiated and geometrically checked headlessly by Round 4.
This remains a required follow-up visual review when a rendering display is available.
The optional touch-ups were intentionally not attempted without visual verification.

Real cross-device online play still requires the backend already absent in previous
rounds. The client contract, fake-peer authority, agreement states and side swaps
are implemented and tested; this is not a claim that a backend was deployed.

## Final verification

Final `index.pck`: **10,177,988 bytes** (10.18 MB / 9.71 MiB), below 16 MB.
Export destination: `/tmp/nineweave-r4-export`. All 20 Ogg recordings checked.
The release PCK was also opened directly with the Godot binary and the external
`tools/check_pack.gd` script; all 160 packed hero textures loaded and the packed
select → versus → winner flow passed:

```text
NINEWEAVE_PACK PASS hero_textures=160 select/versus/winner=PASS
```

Final hardening also checks that a claim pop hides the retained versus lettering
layer, and that an already settled winner card relayouts correctly on rotation.
The full regression runner has no SCRIPT ERROR, ERROR, or WARNING lines.

Full output of `sh godot/tools/run_tests.sh`:

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

AI incremental slices=83 max_slice_ms=2.84
AI_STRENGTH Medium vs Easy N=30 wins=29 draws=1 losses=0 rate=96.6666666666667% moves=1194 node_limit=700
AI_STRENGTH Hard vs Easy N=30 wins=30 draws=0 losses=0 rate=100.0% moves=1091 node_limit=700
AI_TIMING Hard samples=45 mean_ms=157.1 max_ms=237.24 hard_ceiling_ms=450
NINEWEAVE_AI PASS checks=2566 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_LAYOUT PASS checks=1948 failures=0 sizes=25
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_UI PASS checks=867 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

AUDIO synthesis_all_ms=2054.443 (lazy; startup only unlock)
NINEWEAVE_ROUND3 PASS checks=752 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

LEAK games=56 nodes_after_6=37.0 nodes_after_56=37.0 orphans=0.0→0.0
NINEWEAVE_ROUND3B PASS checks=597 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

TURNAROUND_RATE { "turnaround": 197, "first_claim": 120, "old": 394 }
NINEWEAVE_ROUND3C PASS checks=5886 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_AUDIO PASS checks=270 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_ROUND3E PASS checks=965 failures=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

NINEWEAVE_ROUND4 PASS checks=1399 failures=0
NINEWEAVE ROUND4 TEST SUMMARY: PASS (10/10 suites; rules, AI, layout, UI, Round 3, Round 3b, Round 3c, audio, Round 3e, Round 4)
```

## Producer QA fix (post-Codex)

Rendered captures (real Xvfb, 28 shots at 390x844 / 390x664 / 867x553 / 1366x1024)
showed every mirrored (`facing = -1`) illustration was invisible or shoved off-screen:
the rival body on the versus screen and the rival's scorecard/corner head. Cause:
`art.gd` drew with a negative-width rect, which the GL Compatibility renderer does not
flip in place. Fixed by mirroring with `draw_set_transform` around the control's
width. All 10 suites re-run and pass; captures re-checked against the mocks.

Second QA fix: in the web build the select-screen page dots ("●", U+25CF) rendered as
missing-glyph boxes because the bundled Rajdhani font has no such glyph (desktop
captures hid it via system-font fallback). Now uses "•" (U+2022, in Rajdhani) at 36px.
Web export re-checked in headless Chrome: select → versus → match, sound peaks ~0.70.
