# Nineweave — Round 2: visual fidelity and animation pass

Godot 4.7.2, Compatibility renderer, all changes inside `godot/`. Godot was run headless only. No display was available, so **no change in this round has been visually verified**; see "Not verified" below. No git operations, network access or installs.

## 1. Visual fidelity

**Marks** (`ui/paint.gd`). X and O are cached vertex-coloured `ArrayMesh`es built once (`x_mesh()`, `o_mesh()`). Each mark costs one mesh draw, one shadow draw and two soft halo quads.
- **X:** two faceted crystal bars with chamfered tips, a dark navy bevel rim, lit upper-left and darker lower-right facets, and a near-white core highlight. The stroke is 0.42 of the mark radius, about **14.5% of a cell**.
- **O:** a ring split into an outer bevel lit from the top-left and an inner wall lit from the bottom-right, with a dark bronze rim and a pale ridge highlight. Its weight matches the X.
- **Bloom:** a wide soft halo plus a tighter bright halo from a runtime `GradientTexture2D`.

**Gold frames.** `gold_frame()` draws a dark rim, a lit outer bevel band, a bright ridge, a mid-gold band and an inner dark line. Each of the 8 chamfer edges is shaded by its normal against a top-left light. `corner_ornament()` adds a jewel in a gold setting with two tapered scroll flourishes. `glint()` sweeps a travelling highlight along each frame's top edge. `panel()` (player capsules, Turn, info pill, every button, modals) now uses a vertical navy gradient, a glass sheen, this frame, a glint and ornaments. Button icons (gear, home, back, undo, hint, info, X/O) are drawn procedurally because the fonts lack reliable symbol glyphs.

**Board** (`ui/board.gd`). The board is split into four layers:
- **Base:** static and cached; redrawn only when the state signature changes or something is animating. It holds the heavy outer frame with cyan-jewel corners and mid-edge jewels, and each tile's gradient interior (`#142b4f` centre to `#050d1d` edges), inset top shadow, faint diagonal sheens, etched dim blue-grey grid, bevelled frame and corner ornaments.
- **Over** (additive, in front): the active board's wide outer bloom, hot rim, inner rim light and stacked strokes, all pulsing on a **1.2 s** period, plus a spark travelling round the frame. The active interior is a lighter teal (`#175a78`).
- **Under** (additive, behind): only light that spills outside the whole board.
- **Top** (normal blend): shards and sparks.

Glows use a new `edge_glow()` gradient band, which has no interior fill and so cannot wash out the marks.

**Backdrop** (`ui/backdrop.gd`, `assets/shaders/aurora.gdshader`). A full-viewport gradient and sky plate cover the whole viewport at every size, which fixes the dark top band. A one-quad shader adds 3-octave drifting cloud banks, warm rays fanning from the title anchor and a cool horizon glow. The art layer holds:
- the floating castle beneath the title;
- the crystal knight on the left and the gold goddess on the right;
- crystal clusters in both bottom corners;
- mirrored faint ruins and the castle low in-game;
- floating shards and sparkles, with gentle parallax.

Art is never drawn at more than **1.5x** its native size. On a 390×844 phone the statues show at about 0.93x as two figures flanking the title.

**Title** (`main/main.gd: _title_geometry/_draw_title/_draw_ribbon`). The procedural crystal crown with gold crescent wings sits directly above NINEWEAVE. The title is Cinzel Decorative with a new label-space gold gradient shader (`gold.gdshader`: pale top, gold, bronze base, travelling glint), a dark outline, shadow and warm bloom. The pointed, gold-framed "TIC TAC TOE" ribbon with jewelled rails sits directly beneath, then the tagline, then the menu. Arrangements by screen:
- **Portrait:** single column.
- **Landscape:** title block centred at the top, with a two-column menu grid below.
- **With a hinge:** title on the left, menu on the right.

**Crops** (`tools/crop_reference.py`, regenerated PNGs). Crops are numpy smoothstep-feathered on every free edge with an elliptical vignette, and no hard rectangles remain. They keep their native size and are never upscaled in the script. The knight uses a soft cut-out mask over the logo "N" so the face is kept without lettering. New crops are `crystal_cluster_left.png` and `ruins.png`, and the portraits are 128 px downscales. The script avoids all device, UI and text regions; boundaries are documented in it.

## 2. Animations (all pure functions of progress, so debug poses show everything)

**Board claim, 1.6 s** (0.45 s with reduced motion). Timings are fractions of progress p:

| Effect | Timing | Notes |
|---|---|---|
| Beam through the real 3 cells | draws over p 0–0.2 | thick, overshoots the ends, fades 0.55–0.85 |
| Tile flash, white to player colour | 0.03 → 0.7 | |
| Rotating light rays from the board | 0.04 → 0.88 | 14 rays |
| Shockwave rings | 0.1 → 0.86 | 3 staggered rings reaching ~1.4–1.65 tile widths, past the board edges |
| Particles | start 0.10–0.18, live 0.62–0.87 | **96** crystal shards for X or gold sparks for O, flying to ~1.9 tile widths with gravity |
| Screen-wide tinted flash | 0.02 → 0.65 | peak 0.22 |
| Camera punch-in | 0 → 0.62 | ×1.055 around the claimed board |
| Shake | p < 0.42 | 4.5 px |
| Giant emblem | 0.40 → 0.68 | ~90% of the board, back-out overshoot, settles with a tinted overlay, coloured border and big halo |

**Game win, 3.5 s** (1.2 s with reduced motion):

| Effect | Timing | Notes |
|---|---|---|
| Energy beam across the three claimed boards | 0.02 → 0.24 | width 3.4% of the board, white core |
| Full-screen flash | white peak at ~0.015, then a colour wash to 0.7 | |
| Rotating rays behind the board | from 0 | 30 rays, filling the screen |
| Screen shockwave | 0 → 0.35 | |
| Fireworks | 0.05 → 0.99 | **7 bursts × 36 = 252 sparks** |
| Board shards | from 0.08 | **3 × 34 = 102** from the winning boards |
| Camera punch | | ×1.065 plus shake |
| Board pulse | throughout | |
| Statue glow | throughout | winning side's statue glows (knight for X, goddess for O) |
| Result panel | from **0.75** | ornate panel scales and slides in with overshoot by 0.95: gold frame, glow, Cinzel Decorative VICTORY / DEFEAT / X WINS / O WINS / DRAW, emblem, result line, Play Again / Menu |

**Reduced Motion.** No shake, no punch-in, 14 claim particles, 2×16 fireworks, 12 rays and 6 claim rays.

**Bug fixes:**
- **Result panel in poses:** it now appears from 0.75 in both the real flow (`_process`) and `debug_preview_win`.
- **Debug scenarios:** they now replay real games, using `MIDGAME + CLAIM_TAIL` (X's top row claims Center) and `WIN_GAME` (Medium vs Easy seed 1, middle column 1-4-7, last move claims Bottom). The beam always passes through genuine marks and owners.
- **Particles in frozen frames:** they are computed deterministically from progress, so posed frames show them.

## 3. Bugs
- After game over, the info pill and side card show the result: "Victory! X wins the game", "Rival AI wins the game" or "Draw — all boards sealed".
- The mini-map, via `minimap_states()`, tints only owned boards. Sealed boards are grey, nothing is active after game over, and the winning line is drawn.
- No lone "O"+number pairs remain: stats, player cards and the Turn capsule use drawn X/O icons, and the chronicle says "Crystal X" / "Gold O".
- Vs-computer shows "Rival AI" in a gold-ringed portrait medallion (goddess for O, knight for X) with a "Thinking…" label and a rotating cyan arc. All game capture scenarios use vs-computer.
- `set_view_size` drops full-rect anchors before sizing, so the set_size warning is gone. `run_tests.sh` now also fails on any `WARNING:` line.

## 4. Tablet / landscape
`ui/layout.gd`: left column `clamp(w*.165,130,300)`, right column `clamp(w*.23,210,380)`. Tall player cards fill 84% of the height (medallion, crown, name, icon + claims, big VS). The right panel stacks the home and gear buttons, a Turn box, an Active Board card filling the column (title, board name, large mini-map, two-line guidance), and Undo/Hint. Type scales by `clamp(h/700,1,1.5)`.

## 5. Layouts
All existing modes and classifications are unchanged, and the layout suite still checks 25 sizes plus hinge variants. The phone crown now rides above the name so it clears the header buttons. Duo layouts keep their geometry; the panels gain the richer framing, a larger lit mini-map, portrait medallions and icon stats.

## Debug / capture
Scenarios: `title, midgame, thinking, claim (0.45), claim_end (1.0), win (0.45), win_end (0.95), duo_hinge/hinge, settings, online`. `main.debug_refresh()` repaints every layer for paused captures. `tools/capture_shots.sh` defaults to `/workspace/nineweave-r2-shots`. It captures title/midgame/claim/win at 8 sizes (adding 1024×768); claim_end, win_end, claim-early and thinking at 390×844 and 867×553; hinge at three sizes; midgame at 7 extra phone/desktop sizes; settings and online.

## Test results (final)
```
NINEWEAVE_RULES PASS checks=3121037 failures=0
NINEWEAVE_AI PASS checks=2566 failures=0
NINEWEAVE_LAYOUT PASS checks=1470 failures=0 sizes=25
NINEWEAVE_UI PASS checks=662 failures=0   (+19 new Round 2 checks)
NINEWEAVE ROUND2 TEST SUMMARY: PASS (4/4 suites; rules, AI, layout, UI)
```
New UI checks:
- the info pill shows the result after game over;
- the mini-map tints only owned boards after a win, with no active board;
- vs-computer shows Rival AI;
- the win panel is fully visible at the end of the real win and in `debug_preview_win(…,0.95)`, and hidden at 0.45;
- the claim and win poses use genuine lines and owners;
- the posed claim at 0.45 shows 60+ particles, punch-in and flash;
- the win at 0.45 keeps its colour wash;
- the claim_end and thinking scenarios.

Headless `--import` is clean. `tools/export_web.sh` PASSES. A headless probe drew every scenario at 10 sizes, including 2601×1659, with zero errors or warnings. In headless runs a full redraw of every layer fits within the ~6.9 ms frame pacing; that is an upper bound on CPU cost, not a GPU measurement.

## Not verified (no display)
I have seen none of the new rendering:
- mesh shading and halos;
- additive layers;
- shader clouds/rays;
- gold title gradient band placement (`band_top`/`band_height` derive from font metrics);
- statue and castle composition;
- ribbon proportions;
- panel entrance;
- fireworks density.

Colours, alphas and sizes are reasoned, not tuned. Particularly worth checking in the owner's captures:
- title legibility over the warm ray core;
- halo strength on dense boards;
- the knight cut-out edge;
- portrait medallions at small sizes.

GPU fill cost of the full-screen sky shader and the additive layers on phones is unmeasured.

## Known gaps vs the reference
- Still a 2D interpretation: no 3D statues, volumetric light or true HDR bloom.
- Statues and portraits are reference crops limited by source resolution, and they are soft at 3x DPR.
- Duo layouts were restyled but not recomposed.
- No dedicated home/house button on phones (back arrow, as in the art).
- The "Made with" and feature strip from the mockup are intentionally absent.

## Suggested Round 3
1. Tune alphas, sizes and timings from the Round 2 captures.
2. Profile on real phones/Safari; cache the board base into a `SubViewport` texture if fill-bound.
3. Commission higher-resolution independent statue/backdrop art.
4. Recompose Duo panels around a larger mini-map and portraits.
5. Add audio stingers synced to the new claim/win beats.
6. Add a touch magnifier for small cells, then the backend from ONLINE_PROTOCOL.md.
