# Nineweave — Round 3c (producer QA code-bug list)

This pass fixes only items 1–12 under "Code bugs (Claude, round 3c)" in `nineweave-qa-r3.md`. The board look, colours, emblems, Round 2 animations, character art and game rules are unchanged. All edits are under `godot/`. There were no git mutations, network access or installs. Godot 4.7.2 ran headless only, with XDG dirs under `/tmp`. The "Art/animation items (Codex, round 4)" section was left alone.

New suite: `tests/run_round3c_tests.gd` (5,743 checks). It is wired into `tools/run_tests.sh`, and the summary line now reads `ROUND3C … 7/7 suites`.

**Mutation checks.** For each main fix, I ran the new suite against a scratch copy of the project in `/tmp` with that fix disabled, then restored it. Every disabled fix made its test fail:

| Fix disabled | Result |
|---|---|
| Pop lanes (only the board protected) | 717 FAIL |
| Comic callout spark guard + `P.diamond` guard | 268 engine `ERROR:` lines |
| `P.diamond` guard only | 6 `ERROR:` lines |
| Old TURNAROUND rule | 201 FAIL |
| Rematch keeps rival | 8 FAIL |
| Spotlight inset frame | 42 FAIL |
| Inset caption lane | 19 FAIL |
| Inset headroom | 5 FAIL |
| Button caption layout | 8 FAIL |
| Scorecard lanes | 20 FAIL |
| Plaque lanes | 25 FAIL |

The runner fails a suite on any `ERROR:` line, so the callout mutation fails the run.

## Fixes

| # | Item | File(s) | Cause | Fix | Test (`run_round3c_tests.gd` unless noted) |
|---|------|---------|-------|-----|------|
| 1 | Pop covers the Duo character panel and minimap | `characters/cinematic.gd` | `pop_region` tried two fixed candidates and only rejected the board and hinge. In Duo landscape the "controls+12" candidate always landed on `layout.character`. | New `protected_rects(layout)`: board, hinge, players (scorecards / live figures), turn, info, controls, message, minimap, stats, character, both hero corners, home/settings buttons, the active-card crown, the callout lip above the board, and the phone X/O turn tiles. `free_rects()` lists the empty rectangles between them (column bands × vertical gaps). `pop_region` picks a full card if one fits, otherwise the largest free lane, then the one nearest the claimed board. ~0.17 ms per call. | `pop_lanes`: 25 sizes + 9 Duo hinge variants × 9 boards. The pop exists, is in view, and misses every protected rect (an independent list in the test). Pinned: `867x553 pop leaves the Duo character panel visible`. `live_pops`: in the real scene at all 25 sizes, the pop misses every live hero node and the home/settings/undo/hint buttons. |
| 2 | Pop hides "Active Board" on landscape | same | The landscape candidate was placed at the top of `layout.info`. | `info` is protected. Landscape now uses the free strip above or below the board (1024×768, 1366×1024, 1180×820) or the gap between home and gear (1280×720, 1920×1080). | `1366x1024 full card off the Active Board heading`, plus the 25×9 sweep. |
| 3 | Pop covers a corner bust on phone portrait | same | The card sat beside the busts. | Both busts are protected. At 390×844 and 430×932 the card fits in the gap between them (135×104 and 162×116). | `390x844 pop between the busts, board 0–8`, plus the sweep. |
| 4 | Pop falls back onto the board on short screens | same | When no candidate fitted, the fallback was placed inside `layout.board`. | The on-board fallback is gone. If no card fits, a **compact banner** (28–56 px tall, ≤280 wide) fills a free strip, usually the header gap between back and gear. It shows a bust crop (`hero.configure(id, true)`, clipped by the rig) next to the action word and line, with both text sizes fitted by the new `P.fit_box`. If nothing fits at all, the pop is skipped (it is flavour) and never covers play. Board input, skipping and Reduced Motion are unchanged. Relayout on resize still works and can switch between card and banner. | `568x320 compact banner off the board`; `360x640 reduced-motion banner pop` (0.55 s, no slide, skippable); `board accepts input under a pop` at all 25 sizes; `resize to 568x320 re-places as a banner`; `both card and banner variants in use`. |
| 5 | Engine `ERROR: Invalid polygon data` from the callout | `fx/comic_callout.gd`, `ui/paint.gd` | The end-of-callout spark diamonds had radius `(1-t)*3`, which goes to ~0 as t→1. Tiny polygons far from the transform origin fail triangulation. | `P.diamond` returns early below `DIAMOND_MIN` (0.5 px), and also for a NaN/negative radius or transparent colour. The callout also skips sparks below the minimum, and returns early for a degenerate region. | `callout_fine_steps`: four callouts stepped at 1/240 s, plus a 200-frame dense sweep of the last 2%. A probe draws 840 sub-pixel diamonds under the callout's transform. The runner fails on any `ERROR:` line. |
| 6 | TURNAROUND fires too often | `fx/announcer.gd`, `tests/run_round3_tests.gd` | Fired on any claim while behind (even if still behind), or whenever the rival held any open threat. | `turned_around()`: the claim takes the mover from behind to level or ahead. Blocking stays SHUTOUT. All line IDs, texts, weights and .ogg files are unchanged. The Round 3 detector case used the old "still behind" fixture, so it now uses 0–1 → 1–1. | Unit cases: levelling, still behind, block while level, block that levels (SHUTOUT first, TURNAROUND kept), unrelated threat, leading, extending. Over 120 random games every TURNAROUND is behind→level, and it fires half as often as the old rule (197 vs 394). |
| 7 | Spotlight loser inset badly framed (867×553) | `characters/cinematic.gd`, `characters/rig.gd` | The inset was a wide 218×152 box, but the bust is sized to the height. The extra width exposed the tip of Auric's sceptre at the clip edge (the stray "1"). In early defeat frames the crown reached the top edge. The caption was placed at `inset.end+4` and ran into the plaque. | `loser_frame()` has the bust view's aspect (164:186). The clip is therefore the frame, and the sceptre (rig x ≥ 159 of 164) falls fully outside it. Rig `bust_view`/`bust_lift` (defaults unchanged) give the loser inset 20 units of headroom. In landscape the frame sits right-aligned over the plaque, with a 16 px caption lane and a gap before the plaque frame. Portrait keeps its old position, narrowed to the aspect. | 25 sizes + hinge: aspect, below the title, clear of plaque, caption clear of plaque. All 12 heroes' heads stay inside the clip at defeat ages 0 / 0.3 / 3 s. `sceptre fully clipped`. Live `debug_scenario("win_spotlight")` check at all 25 sizes. |
| 8 | Undo/Hint captions overflow on narrow phones | `ui/ornate_button.gd` | The icon+label row was centred on the full button, ignoring the gold frame, and the caption could shrink to 9 px. | `caption_layout()` fits the row inside the frame's inner rect. If that would need a font under 15 px, it stacks icon over label, as tablets already do. Buttons 62 px or taller keep the original layout. | All 25 sizes, live Undo/Hint buttons: caption ink inside the frame, ≥12 px, icon clear of the caption. |
| 9 | Scorecard text under the medallion at 568×320 | `main/main.gd` | The text lane started or ended inside the medallion ring, and the "N claimed" line was centred without a width limit. | `scorecard_geometry()` ends the lanes at the ring (radius + stroke + 3 px). `fit_label()` shrinks the name to 10 px, then truncates it with "…". `claimed_line()` shrinks the line, then drops the mark icon, then drops the word. | All non-landscape sizes, both cards: lanes clear of the medallion. "You/Rival AI/Thinking.../Player O" and 0/1/9 claimed all fit. `568x320 Rival AI ends before the medallion`. |
| 10 | Select plaque name clipped (390×844) | `characters/select.gd`, `ui/paint.gd` | The name lane started 1 px below the plaque top (inside the frame), and 25 px Cinzel is taller than the 27 px lane. | `plaque_lanes()` puts the name and line lanes inside the frame. `P.fit_box` fits both width and height. | 25 sizes × 12 heroes: lanes inside the frame, and name and line fit both height and width. `VESPER VALE stays readable` (≥14 px). |
| 11 | Pop over the message lane in phone landscape | `characters/cinematic.gd` | Same as #1. | `message` and both side-deck busts are protected. 844×390 and 667×375 use a banner between the busts or the header gap. 932×430 fits a card between the busts. | Same sweep as #1. |
| 12 | Play Again re-rolls the rival | `main/main.gd` | `start_game` always called `randi()`. | `start_game(mode, mark, rematch=false)`. Play Again passes `rematch=true` and keeps the rival, unless it is invalid or now matches the player's hero. A new game from the menu or setup still re-rolls. | 8 rematches keep the rival, the real Play Again button keeps it, a menu start still re-rolls, the rival is never the player's hero, and a clashing rival is re-picked. |

**Product default (#12), flagged for Patrick:** a rematch now keeps the same rival hero. This is reversible: to restore re-rolling, drop the `true` argument in the Play Again callback in `main/main.gd` `_overlay_controls`.

## Where the pop goes now (board 0 / board 8)

| Size | Pop |
|---|---|
| 390×844 | card 135×104 between the busts |
| 430×932 | card 162×116 between the busts |
| 360×640, 375×667, 768×1024 | banner in the header gap |
| 844×390 | banner 218×56 between the side-deck busts |
| 932×430 | card 176×100 between the side-deck busts |
| 667×375 | banner between info and the message lane |
| 568×320 | banner 128×38 in the header gap |
| 1024×768, 1366×1024, 1180×820 | above the board |
| 1280×720, 1920×1080 | card between home and gear |
| Duo 1024/960×720, 800×600, 867×600 | card under the Active Board card |
| Duo 800×700, 720×700 | card above or below the board |
| 867×553, 867×500, 2601×1659 | banner in the header gap (the strip under the Active Board card is 59 px, too short for a card) |
| Duo portrait 669×787, 669×720 | banner in the header gap |

## Not fixed / left for Codex / not verified

- **Not visually verified.** I was limited to headless runs, so I could not render or screenshot the new banner, the moved pops, the stacked Undo/Hint buttons, the scorecard text or the new spotlight inset. All checks are geometric (rects, font metrics, mesh bounds). A fresh capture pass on a real display is recommended before sign-off.
- **Bust inset still ends at the chest.** The QA note "body cut off at the bottom" is how the bust crop is drawn, so it is left as is. A fuller loser figure is art, for Codex (Round 4). Art item 7 (portrait inset overlapping the winner's bow) was not re-composed. The narrower aspect only reduces that overlap.
- **Pop card content** (bust crop, bigger slanted type: art item 4) is for Codex. The banner already uses a bust crop, and the card keeps the full figure. Codex should design within `Cinema.pop_region` / `CARD_MIN` / `BANNER_MAX`.
- **Duo duplicate Vesper (art item 8) and 844×390 sceptre shard (art item 9)** were not touched. The rig `bust_view` knob added here could be reused for item 9.
- **Behaviour change to an existing test:** the Round 3 suite's "compact pop inside view" required `pop.width ≤ 0.45 × board`, a rule that only mattered while the pop could cover the board. It now asserts that the pop is inside the view and off the board.
- **Intermittent engine crash during export:** on the first export run, Godot's own `--import` step segfaulted while re-importing `Rajdhani-SemiBold.ttf` (exit 139, `WEB EXPORT: FAIL`). No project script runs at that point. An immediate re-run passed cleanly. It is reported here in case it recurs.

## Test results

Web export (second run): `sh godot/tools/export_web.sh /tmp/nw-r3c-web` gave `packed audio checked: 20 ogg` and `WEB EXPORT: PASS -> /tmp/nw-r3c-web/index.html`, with 0 `ERROR`/`WARNING` lines in the import and export logs. BUILD_INFO now reads "Nineweave Round 3c".

`git diff --check -- godot` is clean.

Final full runner (`sh godot/tools/run_tests.sh`):

```
NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
NINEWEAVE_AI PASS checks=2566 failures=0
NINEWEAVE_LAYOUT PASS checks=1894 failures=0 sizes=25
NINEWEAVE_UI PASS checks=857 failures=0
NINEWEAVE_ROUND3 PASS checks=720 failures=0
NINEWEAVE_ROUND3B PASS checks=585 failures=0
NINEWEAVE_ROUND3C PASS checks=5743 failures=0
NINEWEAVE ROUND3C TEST SUMMARY: PASS (7/7 suites; rules, AI, layout, UI, Round 3, Round 3b, Round 3c)
```

Across all seven suite logs there are 0 `SCRIPT ERROR`, `Parse Error`, `ERROR:` or `WARNING:` lines.

NINEWEAVE ROUND3C TEST SUMMARY: PASS (7/7 suites; rules, AI, layout, UI, Round 3, Round 3b, Round 3c)
