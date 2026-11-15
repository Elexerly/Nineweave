# Nineweave Round 3e

## 1. Portrait-phone layout (`ui/layout.gd` `_phone_portrait`, phone_portrait only)
- Header row (44 px): back · TURN bar · gear. Full-width scorecard row (52 px, 46 px when
  height-limited) right under it. No separate turn row.
- The "Active Board / Play your X…" info panel is gone in phone_portrait (`r.info = Rect2()`;
  `_draw_info` is skipped for an empty rect). A ≤16 px lane under the board shows, in order:
  message (errors), "Reading the threads…", the result line, else a quiet "Play X in Center".
- Board: 10 px side margins (≥ 92 % of width) at every tested phone size, square.
  Height-limited cases tighten the chrome first (header/cards/gaps/controls), then shrink the board.
- Undo · X/O · Hint pinned to the bottom; the X/O tiles (which overhang the row by 4 px) keep
  ≥ 8 px bottom margin. Spare height goes to corner busts only when they read (≥ 80 px,
  e.g. 390x844), otherwise it centres the board block between the cards and the controls.
- Every other mode is byte-identical: `tests/layout_snapshot_r3c.json` is asserted key-for-key.
  main.gd drawing changes are guarded to phone_portrait (or to an empty info rect, which only
  phone_portrait produces). Claim pops use the free lanes; with no lane (e.g. 390x620) the pop
  is skipped by the existing rule rather than covering play.

| Viewport (CSS px) | Board before | Board after |
|---|---|---|
| 390x844 | 366 | 370 |
| 390x664 (Safari, toolbars) | 346 | 370 |
| 390x620 | 302 | 370 |
| 375x553 | 235 | 355 |

## 2. Undo / Hint only vs computer
`_rebuild` creates the Undo/Hint buttons only when `mode == "computer"` (all layouts);
`undo_move()` / `request_hint()` also refuse in local and online. The X/O tiles stay centred.

## 3. Last-move highlight
`ui/board.gd`: warm gold `#FFD54A` core line (2.5–4.5 px), dark keyline, soft outer glow,
additive gold bloom in the Over layer and a 0.18 gold fill (X/O stays readable). Cell or whole
small board (`last_move_whole`). 0.35 s pop (fade in + scale overshoot, settles to 1.0), then a
very slow ±0.05 alpha breathe; settled alpha ≥ 0.9. Reduced motion: static. Same
`sync_last_move` rule (opponent's move only; both in pass-and-play).

## Tests
`sh godot/tools/run_tests.sh` → 9/9 suites (new `run_round3e_tests.gd`). Older tests updated:
phone header overlap checked via its two buttons (TURN lives in the header row), no info rect,
Undo/Hint tests moved to vs-computer. `capture_shots.sh` adds 390x664 / 390x620 midgame.
