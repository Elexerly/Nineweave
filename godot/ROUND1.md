# Nineweave — Round 1

## Scope and validation

A self-contained Godot **4.7.2** project, Compatibility renderer, entirely inside `godot/`. The independent React site is untouched. No packages were installed, no network assets fetched, no git commit/push performed. Godot was run headless only; there was no display or visual screenshot review in this round. The supplied reference JPG was viewed and its decorative crops inspected. Display-enabled capture tools are provided for the owner's Xvfb/Mesa pass.

The test runner covers four suites: rules, AI, layout and mounted UI/controller/transport. The rules run includes **2,400 complete seeded random games**, **141,611 moves** and **3,121,037 checks**. All suites print a PASS/FAIL summary and return a nonzero status on failure; the shell runner also rejects runtime/parse error lines. The final passing counts are rules **3,121,037**, AI **2,566**, layout **1,470** and UI **643**, all with zero failures. `tests/LAST_RUN.txt` records the summaries and measured results. The last full run measured Hard at **180.6 ms mean / 344.5 ms max** while export work was also running; the longest requested 2.5 ms work slice was **2.83 ms**. After the final keyboard-focus changes, the UI suite was rerun independently and passed.

A staged, single-threaded release Web export was produced under `/tmp/nineweave-r1-web-check` using the installed templates. Headless editor import/export can print denied local debug-listener socket errors in this restricted sandbox; runtime/test logs have no such listeners. These are editor infrastructure messages, not application network requests or script errors.

## Architecture

| File / directory | Responsibility |
|---|---|
| `project.godot`, `main/main.tscn` | Compatibility, canvas_items stretch, main Control scene |
| `kernel/rules.gd` | Pure RefCounted rules and state; no Nodes or scene dependencies |
| `ai/strategist.gd` | Seeded heuristic and cooperative alpha-beta jobs |
| `main/main.gd` | Menu/match controller, save/resume, AI scheduling, authoritative move acknowledgements, debug hooks |
| `ui/layout.gd` | Pure static classification and rectangle geometry |
| `ui/paint.gd`, `ui/ornate_button.gd` | Cinzel/Rajdhani typography, chamfered gold frames, bevel layers, glow strokes, real focusable buttons |
| `ui/board.gd` | Live 81-cell hit testing and rendering, claims, win beam, marks, hints, invalid shake |
| `ui/backdrop.gd` | Layered decorative art, procedural pillars, clouds, faceted crystals, drifting motes |
| `assets/shaders/` | Animated gold title, aurora/rays and subtle gold-frame shimmer |
| `net/` | Common transport signals, authoritative in-process rooms, HTTPRequest polling adapter |
| `settings/store.gd`, `fx/sound.gd` | ConfigFile preferences/resume; synthesized in-memory PCM cues |
| `tests/` | Four executable SceneTree suites and arranged tactical fixtures |
| `tools/` | Headless tests, staged Web export, reference crops, display-enabled captures |

There are no autoloads, external dependencies, threads, database, credentials, servers or runtime filesystem writes outside Godot's `user://` storage. The only runtime save is the player's local ConfigFile.

## Rules kernel API

```gdscript
var rules = preload("res://kernel/rules.gd").new()
rules.new_game()
var moves: Array = rules.legal_moves() # Vector2i(board, cell), sorted row-major
var accepted: bool = rules.play(board, cell)
rules.undo()
rules.redo()
var data: Dictionary = rules.serialize()
var compact_json: String = rules.compact()
var restored: bool = rules.deserialize(data) # also accepts compact JSON
```

Public state: `cells` (81 packed integers, board*9+cell), `owners` (nine integers), `turn`, `active_board`, `status`, `history`, `redo_stack`, `small_lines`, `big_lines`, `last_error`. Constants: OPEN=0, X=1, O=2, DRAW=3. `winner()` returns X/O or OPEN; `status` distinguishes draws. `board_owner(b)`, `winning_lines(b=-1)`, `move_history()`, `is_legal(b,c)`, `would_claim`, `would_win_game` and `copy()` support UI/AI/networking.

First move is anywhere. Every move sends the opponent to the corresponding board, unless that board is closed. Wins close a small board immediately; drawn full boards are sealed and owned by neither side. The big board only counts claims. All closed without a line is a draw, regardless of claim counts. All simultaneous winning lines are preserved. Illegal play is mutation-free. History supports full undo/redo, including routing, ownership, result and lines.

Serialization version 1 has `cells` as 81 `.XO` characters, `turn`, `active`, `history` and `redo`. Deserialization is transactional, recomputes owners and winning lines, validates the active board, replays a supplied history and validates redo. An empty history allows structurally valid arranged positions for debug/capture; a backend must never accept client snapshots as authority. JSON numeric types are normalized for cross-platform round trips.

## AI and measured results

Easy chooses mostly random legal moves, with a 12% chance of preferring the leading immediate small-board win. Medium orders tactical wins and blocks, values big-board potential, checks routing danger, penalizes granting free choice and prefers center/corners. Its small tie noise is seeded.

Hard uses iterative depth-2 through depth-4 alpha-beta, with 18 ordered root moves and seven ordered replies per node. Evaluation values claimed boards, open big-board lines, small-board threats, positional value and terminal results. Immediate game wins are checked before any cutoff; immediate-loss fixtures cover both seats. A completed iteration supplies the stable result; the initial fallback is always the best legal heuristic move.

The recursive search is represented as an explicit stack, allowing `begin()`/`step(slice_us)` to yield between individual nodes. The UI uses 4.5 ms work slices, with a 380 ms minimum thinking presentation. Hard defaults to **700 nodes and a 450 ms wall ceiling**, configurable on the AI object. No worker threads or async HTTP are used for AI. Synchronous `choose_move()` drives the same job for tests. Seeded work ordering is deterministic; a wall cutoff on a much slower device can end at an earlier completed iteration.

Measured on this sandbox, alternating X/O seats and 30 fixed seeds per matchup:

| Matchup | Wins | Draws | Losses | Win rate |
|---|---:|---:|---:|---:|
| Medium vs Easy | 29 | 1 | 0 | 96.7% |
| Hard vs Easy | 30 | 0 | 0 | 100% |

The first full cooperative-search regression measured **150.6 ms mean / 227.0 ms max**, 45 positions, 700 nodes, 450 ms ceiling. These are native headless CPU measurements, not Safari/Web timing claims. The longest measured 2.5 ms requested incremental slice was **2.87 ms** in that regression. The test output prints current timings and longest incremental slice. Reproduction uses the same seeds and node limit as the shipping default.

## Responsive layouts

All geometry is computed by `NineweaveLayout.compute()` without instantiating a scene. CSS-sized logical units determine layout, independent of raster resolution. On Web, the controller reads the browser's CSS viewport; `canvas_items` stretch preserves crisp rasterization at device pixel density. The 2601×1659 capture normalizes to 867×553, exactly matching the measured Duo composition.

```text
Phone portrait           Phone landscape
[‹       settings]       [             ][‹       settings]
[You X] VS [Rival O]      [    BOARD    ][players / turn  ]
[      Turn X      ]     [             ][active / controls]
[                 ]
[      BOARD      ]      Tablet / desktop landscape
[                 ]     [You X] [             ] [settings/home]
[Active / guidance]     [ VS  ] [    BOARD    ] [turn / active ]
[Undo] [X] [O] [Hint]    [Rival] [             ] [map / controls]

Duo landscape            Duo portrait
[             ] [players / turn ]    [toolbar / players]
[    BOARD    ] [claims / timer  ]    [                 ]
[             ] [map | chronicle ]   [      BOARD      ]
[             ] [undo / hint     ]   [                 ]
                                    [turn / active]
Hinge: board |seam| rich panel       [map | history | stats/controls]
```

Classification uses aspect ratio and size, not exact pixel equality. Short heights below 450 always use phone landscape. Duo landscape spans width 700–1200, height 480–740, aspect 1.02–1.75, retaining the earlier near-square test cases. Near-square portrait uses width ≥600 and aspect .78–.95. The explicit tablet 768×1024 stays tablet portrait; 1024×768 stays the traditional landscape composition. The superseded 1180×820 guess now also uses traditional landscape.

| Logical viewport(s) | Expected mode | Approx. board edge |
|---|---|---:|
| 390×844, 430×932 | phone_portrait | 366, 406 |
| 360×640, 375×667 | phone_portrait | 322, 349 |
| 844×390, 932×430 | phone_landscape | 362, 402 |
| 667×375, 568×320 | phone_landscape | 347, 292 |
| 768×1024 | tablet_portrait | 692 |
| 1024×768, 1366×1024 | landscape | 591, 815 |
| 1280×720, 1920×1080 | landscape | 656, 1016 |
| **867×553** | **duo_landscape** | **423** |
| 867×500, 867×600 | duo_landscape | 423 |
| **669×787**, 669×720 | **duo_portrait** | **483**, 416 |
| 1024×720, 960×720, 800×600 | duo_landscape | 504, 471, 388 |
| 800×700, 720×700 | duo_landscape | 388, 346 |
| 1180×820 | landscape | 693 |
| 2601×1659 raster | duo_landscape at 3× | 423 logical |

Duo panels include live board counts, elapsed match timer, move count, mini-map and a native scrollable RichTextLabel chronicle. The mini-map shows owners, sealed boards and active destinations. `set_hinge_rect(Rect2)` accepts a vertical seam in logical CSS units; no seam is the default. An explicit seam selects a split composition, including in Duo portrait: the board remains wholly left, game controls/panels remain right, and Settings also stays right. Title/menu and online room controls also respect the seam. `debug_simulate_hinge(width=22)` centers a test seam. Major layout rectangles are checked for viewport containment and pairwise overlap; action controls have at least 44×44 targets. The dense 9×9 playing surface necessarily has smaller cell pitches on narrow phones; 44px individual cells cannot fit within a 360px display.

## Art and animation

The UI is live drawing, not a cropped mock. Gold multi-stroke chamfered frames, corner jewels, dark inset cells, thin blue grid lines, cyan crystalline X and warm ring O use layered antialiased strokes for Compatibility-safe bloom-like halos. Active boards pulse and carry a traveling glint. Marks pop for 320 ms with six sparks. Buttons use real hover, press, disabled and keyboard-focus states. Invalid boards shake for 350 ms.

The supplied statue, portrait, distant castle, crystal cluster and sky are reproducibly cropped by `tools/crop_reference.py` (Python/PIL). Crop boundaries avoid UI/device/text regions. Background layers drift separately, with geometric crystals, cloud strips, silhouetted pillars, CPU particles and deterministic drawn twinkles. The title uses bundled Cinzel Decorative, a live gold shader, crystal crown and framed TIC TAC TOE ribbon.

A small-board claim runs **1.55 s**: beam traces the winning line, flash, expanding shockwave, 32 cyan crystal shards or gold sparks, short board shake, dimmed cells and a scaling giant owner sigil. Input resumes after 160 ms; the effect continues. Drawn boards have a grey sealed crystal. Game wins run **3.6 s**: massive beam joins the three claims, screen/board flash, rotating rays, 100 sparks, board pulse, then an ornate result panel at 78% with Play Again/Menu. Draw, victory, defeat and local X/O wins have separate headings. Reduced motion uses .45 s claims / 1.2 s wins, no shake/pulse, fewer effects/motes and subdued background drift.

## Online, persistence and tools

See [ONLINE_PROTOCOL.md](ONLINE_PROTOCOL.md) for endpoints, JSON, tokens, ordering and backend transaction requirements. Online clients only commit authoritative acknowledgements. Loopback validates turns, legality and seq, then broadcasts both ways. HTTP polling uses a single HTTPRequest, one-second polling, eight-second timeout and graceful missing-server messaging. A production backend, persistent rooms and reconnect support are not included. Online hints/undo are disabled. The Web preset opts into the virtual keyboard; code entry survives rebuilds, and viewport relayout is deferred while a LineEdit owns focus so opening the keyboard does not discard the entry.

`settings/store.gd` persists sound, reduced motion, hint visibility, difficulty and player name. There is no music track in Round 1. Computer game state, human seat and elapsed timer save/resume locally. X always opens, even when the player chooses O.

```sh
# Headless tests (all four suites, exit !=0 if any fail)
sh godot/tools/run_tests.sh

# Headless import, keeping user data out of the home directory
XDG_DATA_HOME=/tmp/nw/data XDG_CONFIG_HOME=/tmp/nw/config \
XDG_CACHE_HOME=/tmp/nw/cache \
/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --import

# Staged release export; default OUT=/workspace/nineweave-web-build
sh godot/tools/export_web.sh /tmp/nineweave-web-check

# Display-enabled only, for the owner's screenshot pass
xvfb-run -a sh godot/tools/capture_shots.sh /workspace/nineweave-r1-shots
```

Export copies sources to `/tmp`, performs import/export there, uses the preinstalled Web templates through an XDG-local symlink, excludes tests/tools/reference/Markdown from the PCK, and copies complete OFL notices beside the distribution. `BUILD_INFO.txt` reports exact source SHA, branch, uncommitted-tree status, engine version and thread configuration. There is no publishing step.

Capture supports `title`, `midgame`, `claim`, `win`, `duo`, `duo_hinge`/`hinge`, `settings`, `online`; optional `--progress` freezes claim/win progress. It refuses headless readback, never starts a display itself, and writes the requested PNG. Example:

```sh
GODOT=/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64
# Run under an existing display or prefix with xvfb-run -a:
"$GODOT" --path godot --resolution 390x844 \
  --script res://tools/capture_shots.gd -- \
  --scenario claim --progress 0.62 --out /workspace/nineweave-r1-shots/claim.png
```

The batch captures 390×844, 844×390, 867×553, 2601×1659, 669×787, 1366×1024 and 1280×720 for title/midgame/claim/win; both Duo resolutions with a hinge; phone Settings and online waiting screen. The midgame is a legal 26-ply position, X to play, active Center, with distributed marks and actual move history. Capture mutes audio, freezes decorative pose and disables ambient particle randomness.

Debug APIs on the main scene, guarded by `OS.is_debug_build()`:

- `debug_load_position(serialized)` — restore an arranged or real position, stop AI.
- `debug_preview_claim(board_index, player, progress)` — pose without changing rules state.
- `debug_preview_win(line, player, progress)` — pose without changing rules state.
- `debug_scenario(name, progress)` — prepared captures.
- `debug_simulate_hinge(width)` — centered seam; `set_view_size(physical)` — capture/test sizing.

## Known gaps and Round 2

This is a layered 2D interpretation of the reference's rendered 3D art, using reference-derived decorative crops. There are no 3D statue models, physical volumetric lighting or real HDR bloom. Full-screen composition, text rendering, shader appearance and Web performance still need the owner's display-enabled screenshot pass; headless mounted geometry cannot prove visual fidelity. The narrowest phones have small board cells. Landscape and portrait vertical seams are covered geometrically; irregular or horizontal hardware folds need an additional layout pass.

Round 2 priorities: review the requested captures against the art, tune lighting/ornaments based on actual Safari output, profile shader/AI frame time on the measured Duo, add a touch magnifier or selection confirmation for small cells, commission independent statue/backdrop assets if needed, and implement the documented authoritative backend with reconnect/room TTL. Optional music, accessibility narration, richer tutorials and additional AI tuning can follow.
