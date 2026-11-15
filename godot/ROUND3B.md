# Nineweave — Round 3b (bug hunt and robustness pass)

This pass only fixes bugs and makes the game more robust. The board art, colours, emblems, Round 2 animations, game mechanics and character art are unchanged. Edits are limited to `godot/`. There were no git mutations, network access or installs. Godot 4.7.2 ran headless, with XDG dirs under `/tmp`.

Every fix has a regression test, mostly in the new suite `tests/run_round3b_tests.gd` (wired into `tools/run_tests.sh`), plus new assertions in `tests/run_layout_tests.gd`. To confirm the main tests actually catch their bugs, I disabled each fix in turn (skip guard, stale-hint guard, cinematic relayout, locked-duck gate, voice-queue cap) and checked that its test failed. Each fix was then restored.

## Bugs found and fixed

| # | Area | File(s) | Cause | Fix | Test |
|---|------|---------|-------|-----|------|
| 1 | Layout (1366×1024) | `ui/layout.gd`, `main/main.gd` | The tablet/desktop "landscape" corner bust was placed at `h-158` inside the left column. That column is the Rival AI scorecard, so the bust covered "0 claimed". | Landscape has no separate corner. The tall scorecards already hold full figures, so they become the live, reacting characters (unfrozen). | layout: `1366x1024 no bust over the scorecards`; corner-vs-HUD checks for all 25 sizes; round3b `live hero off board / clear of home/settings/undo/hint` |
| 2 | Layout (867×553 Duo) | `ui/layout.gd`, `main/main.gd` | The player corner was squeezed into the ~51 px strip under the board (~40 px figure), duplicating the Duo character panel. | In `duo_landscape` the player's live figure is the Duo character panel (`hero_player_host = "character"`): 175×187 at 867×553 and 134 px tall at 867×500. The strip under the board becomes the message lane. | layout: `867x553 player figure uses the Duo panel`, `Duo player figure readable` (≥120 px) |
| 3 | Layout (rival corner, every size) | `ui/layout.gd`, `main/main.gd` | The rival was a fixed 74×58 rect at the top-right, so it rendered as a cropped head. It overlapped the header rect, and the gear was shoved left to make room. | When there is room (tall phones, phone landscape), the rival gets a full bust mirrored to the player's: 113×106 at bottom-right on 390×844, 102×102 in the side deck on 932×430. Otherwise its scorecard medallion/figure becomes the live reactor. The gear goes back to the header's right end. Corners below `MIN_CORNER` (56 px) are never drawn. | layout: `readable corner`, `corner … clear of HUD …` for every HUD rect, `corners apart`, `390x844 rival bust mirrored…`; round3b live-node checks at all 25 sizes |
| 4 | Layout (message lane) | `ui/layout.gd`, `main/main.gd` | The invalid-move/online message was always drawn at `h-20`. That overlapped the control row on 360×640 and 375×667 (controls end at `h-14`), the Duo-landscape controls, and the new corner busts. | New `layout.message` lane: below the controls on short phones, under the board on Duo landscape, above the controls on phone landscape. Corners are laid out above it. | layout: `message lane clear of controls`; corner-vs-`message` checks |
| 5 | Win spotlight: double trigger | `main/main.gd` | On touch devices, the touch press skipped the spotlight. The emulated mouse press and release that followed then reached the newly built result panel and could press **Play Again** or **Menu** immediately. | A 350 ms guard (`SKIP_GUARD_MS`) after a pointer skip swallows the rest of that gesture. Keys are unaffected. | round3b: `skip gesture's emulated click does not press Play Again` and `a later deliberate tap on Play Again rematches` (real `push_input` through the viewport) |
| 6 | Hint | `main/main.gd` | The hint search kept running after a move, so a hint computed for an old position could appear as a stale or illegal suggestion. | Moves cancel the hint search. A finished hint is only shown if the ply matches and the move is legal. | round3b: `hint for an old position is discarded`, `hint legal on free move in UI` |
| 7 | Claim pop/spotlight on resize | `characters/cinematic.gd`, `main/main.gd` | Cinematic regions were computed once. Rotating the device mid-pop left the panel at the old coordinates, where it could cover the claimed board. | `cinematic.relayout(layout)` from `_relayout`. Placement is split into `_place()`, while age and clips are kept. | round3b: `pop re-placed after resize, claimed board visible` |
| 8 | Claim pop over Settings | `main/main.gd` | The pop (z 30) kept painting over the Settings modal for up to 1.2 s. | Opening Settings clears a pending pop (it is only flavour). | round3b: `settings clears pop` |
| 9 | Audio ducking stuck | `fx/sound.gd` | Voice lines queued before the first gesture kept the SFX/Music buses ducked by 4.5 dB until the audio unlocked. | Only playing or playable lines (unlocked and enabled) duck. | round3b: `lines waiting for first gesture do not duck`, `duck release restores exact SFX/music volume` |
| 10 | iOS audio unlock | `fx/sound.gd` | The silent unlock was only played on the press. iOS Safari treats `touchend` as the activating gesture. | A silent play on the first press **and** the first release (`unlock_plays`), each inside the input callback. | round3b: `silent unlock in first touchstart AND touchend (iOS)` |
| 11 | Voice queue | `fx/sound.gd` | The queue was unbounded, so fast claims could stack ladder lines that played seconds late. | Cap of 3 pending lines (`VOICE_QUEUE_MAX`). The oldest non-result line is dropped; result lines (victory/defeat/nineweave/clean_sweep/standoff) are never dropped. Lines still play one at a time with the 100 ms gap. | round3b: `stale lines capped, result lines kept`, `voice lines play one at a time, ending on the result` |
| 12 | Settings robustness | `settings/store.gd` | Values were loaded verbatim. `sound="yes"` crashed `bool()` in `Sound.configure`. A non-dictionary or seatless `resume.game` crashed `resume_game`. An unknown difficulty or a non-string name passed through. An array `audio_version` crashed `int()`. | `_sanitize()` coerces every key to its default's type, validates the difficulty, name and saved game (dictionary with `state` and seat 1/2), and guards the version read. `DEFAULTS` is the single source. | round3b: `non-bool mute → default`, `non-numeric volumes → defaults`, `bad difficulty/name repaired…`, `bad theme/saved game dropped`, `saved game with bad seat dropped` |
| 13 | Corrupt config file | `settings/store.gd`, `characters/profile.gd` | A binary-corrupt file (for example a torn write) went to the text parser, which logged an engine `ERROR:` and Unicode errors at every startup. | Files containing NUL bytes are treated as missing (defaults); the next save rewrites them. | round3b: `garbage file falls back to defaults` (the suite fails on any `ERROR:` line) |
| 14 | Profile robustness | `characters/profile.gd` | A wrong-typed `onboarded`, `character_id` or `display_name` could crash or skip onboarding. | Type checks with safe defaults. | round3b: `corrupt profile → safe defaults`, `selected character persists` |
| 15 | Resume | `main/main.gd` | A saved `rival_character` was trusted, including an unknown ID or the player's own hero. A non-numeric `seconds` crashed `float()`. | Validate the rival (and re-pick it if it clashes) and the seconds value. | covered by the store sanitizer tests and the full UI/R3 resume flows |
| 16 | Online after a debug/capture pose | `main/main.gd` | `_online_ready` did not reset `_debug_capture`, so after any capture pose the online demo rival never moved. | Reset it, as `start_game` does. | round3b: `online match leaves debug capture off`, `online rival move highlighted` |
| 17 | Per-frame particle realloc | `ui/backdrop.gd` | Every frame set `CPUParticles2D.amount` (which reallocates the multimesh even for the same value), the position and extents, and looked up two nodes by string path. | Cached node refs. The emitter is only touched when the size or Reduced Motion changes. | covered by the leak loop (node count flat) |
| 18 | Per-frame string formatting | `ui/board.gd` | The redraw signature was a 9-field `String` formatted every frame, and `claims.filter()` allocated a new array every frame. | Value-type signature (`Vector4i`/`Vector2i`/`Vector2`). Claims are filtered only when the oldest expires. | UI + Round 3 redraw/claim tests unchanged and passing |
| 19 | Per-frame literal arrays | `characters/rig.gd`, `fx/sound.gd` | 12-entry literal arrays were rebuilt per bone per frame, and the mix table per frame. | Hoisted to `STANCE_LEAN`, `DEFEAT_HEAD` and `MIX` constants; `StringName` shader parameters. | rig/idle-loop tests unchanged and passing |
| 20 | Web export verification | `tools/export_web.sh` | The export never checked that the owner audio was actually packed, and BUILD_INFO still said Round 3. | Fails if any `assets/audio/*/*.ogg` is missing from `index.pck` as an imported stream. BUILD_INFO now reads "Nineweave Round 3b". | export run below: `packed audio checked: 20 ogg` |

## Audited and confirmed correct (with new tests)

- **Rules:** sent to a claimed board or a full/sealed board gives a free move. A board that fills without a line seals. A line on a board's ninth cell is a claim, not a draw. An overall draw on the very last move works. A last-move win that also fills the final board counts as a win, not a draw. Undo after a claim, a draw or a win restores the board, target and status, and the game can be replayed. No moves are possible after a win.
- **AI:** 1,000+ probes over 14 random games, at all three difficulties, including more than 10 free-move positions. Every move was legal. Hints are legal on free moves, both in the kernel and through the UI.
- **Last-move highlight:** correct after undo, new game, rematch (local and online), in pass-and-play and in the online loopback (own move clears, rival move highlights, rematch clears).
- **Pops:** fast consecutive claims reuse one panel with no stacking (the cinematic child count is constant). The pop shows the claiming side's hero and colour for both X and O. It is freed on Menu.
- **Spotlight:** the board rejects play while the spotlight shows. Inside the 200 ms protection window, a key is swallowed and does not skip. It is never re-triggered after a skip. Key, tap and click all skip. The board unfreezes. Undo after a win reopens the game. Play Again and Menu work after a skip.
- **Audio routing:** every one of the 20 owner Oggs is reachable from a cue and resolves to `AudioStreamOggVorbis`. Cues with no owner file (`place_x`, `place_o`, `draw`, `unlock`, hero stingers) use the synth. Mute blocks both voices and SFX. Bus volumes match the settings exactly after ducking. Victory/defeat/standoff routing and pass-and-play using only nineweave/standoff remain covered by the Round 3 suite.
- **Leaks:** 56 complete games (alternating local and computer) including claims, pops, spotlights, Settings, resizes and Menu. Node count is **78 → 78** and orphan nodes **0 → 0**. No tweens are used anywhere in the project.

## Found but not fixed / not verified

- **Text-level config garbage** (valid UTF-8 that isn't ConfigFile syntax) still makes Godot's parser print its own `ERROR: ConfigFile parse error`. The game then falls back to defaults correctly. Only binary corruption is intercepted before the parser.
- At **568×320** and other very short screens, the live reactor is the scorecard medallion (~39 px). There is no free space for a larger bust without moving the approved board. The same applies to 360×640, 375×667, 667×375 and 768×1024 portrait.
- **Not touched (intentional):** Round 2 `OrnateButton` redraws every frame for the approved glint shimmer, and `main._draw` repaints the HUD every frame. Changing either would affect approved animation.
- **Not verified here (no display or speakers):** how the new corner placements look on screen, real iOS/Safari audio unlock, the audio mix, and device frame pacing. The producer's art items (stiff rigs, face shadow, reaction readability, rim light, select-screen polish) are for Round 4 / Codex, as instructed.

## Test results

Web export: `sh godot/tools/export_web.sh /tmp/nw-web` gave `WEB EXPORT: PASS` and `packed audio checked: 20 ogg`. The import and export logs contain **0** `ERROR`/`WARNING` lines (the Round 3 editor-socket diagnostics did not occur in this run). All 35 files under `assets/` are in `index.pck`, and tests/tools are excluded.

Full runner (`sh godot/tools/run_tests.sh`), final run:

```
NINEWEAVE_RULES PASS checks=3121037 failures=0 fuzz_games=2400 fuzz_moves=141611
NINEWEAVE_AI PASS checks=2566 failures=0
NINEWEAVE_LAYOUT PASS checks=1894 failures=0 sizes=25
NINEWEAVE_UI PASS checks=857 failures=0
NINEWEAVE_ROUND3 PASS checks=720 failures=0
NINEWEAVE_ROUND3B PASS checks=585 failures=0
NINEWEAVE ROUND3B TEST SUMMARY: PASS (6/6 suites; rules, AI, layout, UI, Round 3, Round 3b)
```

Across all six suite logs there are 0 `SCRIPT ERROR`, `Parse Error`, `ERROR:` or `WARNING:` lines. `git diff --check -- godot` is clean. Layout went from 1,630 to 1,894 checks with the new corner-vs-HUD assertions. The leak loop reported `LEAK games=56 nodes_after_6=78 nodes_after_56=78 orphans=0→0`.

NINEWEAVE ROUND3B TEST SUMMARY: PASS (6/6 suites; rules, AI, layout, UI, Round 3, Round 3b)
