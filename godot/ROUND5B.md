# Round 5b — vs-computer tournament

## Rules and entry

The main menu offers **Tournament** alongside the existing quick computer match,
online match, and Pass & Play. A fresh tournament uses the existing hero selection
screen, then creates eight distinct entrants: the chosen hero and seven computer
heroes from the canonical roster. Single elimination means one loss ends the run.
A drawn match replays the same opponent at the same difficulty without advancing
or eliminating anyone.

The three rounds use the existing strategist levels:

| Round | Strategist |
| --- | --- |
| Quarterfinal | Easy |
| Semifinal | Medium |
| Final | Hard |

Hard is the strongest setting currently implemented in `ai/strategist.gd`.
Tournament difficulty overrides the match only; it does not change the player's
quick-match difficulty preference. Board rules, board rendering, first-run
tutorial, screen-name gate, email flow, Beth Solstice, and online mode retain
their existing behavior. Matches enter the normal versus screen, intro clips,
board, and winner/victory-clip flow. Missing clips use the existing illustrated
fallback. Undo and hints retain the normal computer-match behavior during play;
an already-recorded tournament result cannot be undone.

## Rivals and simulation

`tournament/session.gd::RIVALS` is the single rivalry map. Its only confirmed pair
is `shard_jack` (Jack Sovereign) ↔ `james_ii` (James II). The rival is included in
the entrants and seeded into the opposite half. The two can meet only in the
final if both advance. No additional pairs were inferred from roster flavor.

Computer-versus-computer matches resolve after the player's match in that round.
Each uses an independent RNG seed derived from the tournament seed, round, and
match index. The rival has a 78% chance against another computer hero; ordinary
computer pairings are 50/50. Thus upsets are possible, and reloading never rerolls
a computer result. No network or server is involved.

## Progress and trophies

One active tournament, its entrants, seed, results, round, and terminal state are
stored in a versioned local ConfigFile beside the profile:
`user://nineweave-profile-tournament.cfg` for the standard profile. Writes use a
temporary file and rename so results and trophies are saved together. Invalid
bracket topology or an invalid envelope is rejected on load.

Results save immediately after the deciding board move, before the winner
cinematic. Closing during a match returns to its bracket on reload; that
unfinished match restarts against the same opponent. Completed matches remain
completed. The menu offers **Resume Tournament** while a run is retained.
Visiting the menu during a live run preserves it. **Abandon tournament** opens a
confirmation; cancellation preserves the run, and confirmation clears only the
active tournament.

A loss shows “Eliminated in the Quarterfinal/Semifinal/Final”, with Try again and
Main menu. Try again rolls a fresh bracket with the same hero. Winning the final
shows **CHAMPION**, awards exactly one per-hero tournament win, and retains the
total trophy count. Repeated result callbacks cannot award another trophy.
Returning to the menu from a terminal outcome clears that finished run, while
earned trophies remain. Hero-select cards show a trophy icon and their hero's
local count. There are no paid unlocks.

The champion screen uses the existing victory video overlay when a clip is
available. Its input shield consumes the skip gesture, so it cannot hit the
buttons underneath. Without a clip, the illustrated celebration remains.

## Reusable bracket and motion

The implementation lives in `tournament/`, with a thin adapter in `main.gd`:

- `bracket.gd`: pure seeded bracket construction, result application, byes,
  advancement, elimination, and topology validation.
- `bracket_view.gd`: a presentation component accepting a model and result
  batch. It has no dependency on the local session, AI, storage, or networking.
- `session.gd`: local computer-tournament rules, simulation, saves, trophies.
- `screen.gd`: local tournament chrome, outcome screens, celebration and video.
- `flow.gd`: integration with hero selection and the normal computer-match flow.

The generic model supports **3–8 distinct entrants**, padded to four or eight
slots. Byes are distributed so there is no empty-versus-empty first match and
automatically advance their real entrant. Entrant IDs are opaque; display data
can include `name` and `hero_id`. The model is independent of the local roster.

Example for a future online waiting room:

```gdscript
const Bracket = preload("res://tournament/bracket.gd")
const BracketView = preload("res://tournament/bracket_view.gd")
var model = Bracket.generate(entrants, seed_value, local_player_id)
var view = BracketView.new()
view.size = available_size
view.reduced_motion = user_reduced_motion
add_child(view)
view.present(model, [], local_player_id)

# Apply verified server results to the model, then present the updated snapshot.
var result = Bracket.apply_result(model, round_index, match_index, winner_id)
view.present(model, [result], local_player_id, current_match_id)
```

`present()` copies its inputs, so presentation does not mutate the caller's
model. A result batch contains `{round, index, winner, loser}` events returned
by `apply_result()`. `current_match_id` can explicitly select a live pairing;
otherwise the next match involving the focused entrant is highlighted.
`reveal_finished` signals completion. `seek(seconds)` supports deterministic
captures, and `advance_pose()` exposes the actual moving portrait geometry.

The phone composition ascends from quarterfinals through semifinals to the final
and crown. Desktop uses a horizontal tree. Both use existing hero art, fonts,
navy panels, gold framing, and crystal-blue highlights. Completed player paths
light up and the current pairing pulses. A winning portrait flies along the
bracket connectors over **1.15 seconds**, leaving a crystal trail; the defeated
portrait cracks, dims, and falls back. Computer results use staggered **0.34
second** flip/flash reveals. The reusable view also animates a final winner into
the crown. The local champion screen adds a spring trophy drop, light rays, and
64 bounded confetti strokes. Round-label ink lanes stay clear of bracket rails,
and desktop preview art preserves its original aspect ratio.

Reduced motion immediately settles advances/results, uses a static current-match
highlight, skips trophy movement/confetti, and skips the champion video. It also
continues to use the existing reduced-motion match cinematic policy.

## Verification

Run the complete regression suite:

```sh
sh godot/tools/run_tests.sh
```

The runner includes `tests/run_round5b_tests.gd` and reports 16 suites. The new
suite covers generation, distinct heroes, opposite-half rival seeding, seeded
simulation and upsets, difficulties, wins/losses/draw policy, trophies and repeat
callback protection, reloads, abandonment confirmation/cancellation, normal
match/video/tutorial integration, quick-match preservation, and fake-HTTP-only
operation. It checks bracket/outcome region bounds and overlap at **390×844**
and **1366×768**, samples moving portraits at 21 points per advance for all
supported entrant counts, and samples the trophy drop at 31 points per layout.

Final rerun: **PASS, 16/16 suites**. The new Round 5b suite passed **2,638
checks, zero failures**. The runner's exact summary was:

```text
NINEWEAVE ROUND5B TEST SUMMARY: PASS (16/16 suites; rules, AI, layout, UI, Round 3, Round 3b, Round 3c, audio, Round 3e, Round 4, Round 4b, Round 4c, hero video, Round 4e, Round 4g, Round 5b)
```

## Screenshot capture

The deterministic native capture runner is ready:

```sh
xvfb-run -a sh godot/tools/capture_r5b.sh /workspace/nineweave-r5b-shots
```

It captures these eight PNGs from the real Godot viewport:

```text
390x844-bracket_start.png
390x844-bracket_semis.png
390x844-bracket_final_rival.png
390x844-eliminated.png
390x844-champion.png
390x844-animation_advance.png
1366x768-bracket_start.png
1366x768-champion.png
```

The rival-final fixture finds a real deterministic seed in which Jack and James
both advance, rather than inventing results. The advance capture seeks to 0.23
seconds; settled frames seek past the result reveals. Champion capture freezes
the illustrated celebration so a video cannot obscure it.

**Capture status in this restricted workspace:** the native attempt could not
initialize a display. Xvfb failed to bind its local listener, and connecting to
the existing X displays returned `Operation not permitted`. The requested
`/workspace/nineweave-r5b-shots` directory is also outside the writable workspace
roots. A capture attempt with an in-repository output override hit the same
display restriction. No PNGs were produced, and no visual screenshot review is
claimed. The geometry/animation tests above passed; they do not replace a real
pixel review. Run the supplied capture command in an environment with display
access and a writable output directory to complete that final check.
