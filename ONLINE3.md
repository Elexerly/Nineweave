# Nineweave online3 (Round 5, phase 3 server): tournaments

Online single-elimination tournaments with a live bracket and waiting room.
Everything is additive: regular 1v1 rooms behave as before, and round4g /
round5a clients keep working. They ignore the new fields, and
`capabilities.tournaments` tells newer clients the feature exists. Full
contract: `ONLINE_API.md` ("Tournaments").

## For the builder

- **Migration `migrations/0006_nineweave_tournaments.sql` must be applied.**
  `npm run build` applies it on publish (`npm run db:migrate` runs after
  `vite build`). It's idempotent (`if not exists`, drop-then-add constraint).
  It adds:
  - `nw_players.tournament_wins`
  - tables `nw_tournaments`, `nw_tournament_players`, `nw_tournament_matches`
  - `nw_rooms` columns `tournament_id`, `tournament_code`, `tournament_round`,
    `tournament_slot`, `ready_deadline`, `a_ready_at`, `b_ready_at`
  - a `boards` value in the `nw_matches.end_reason` check
- No new secrets, environment variables, dependencies or cron. Starts,
  no-shows and bracket steps run on whichever request arrives first after a
  deadline. Polls stay light: a tournament poll is about 4 small queries.
- PII: none new beyond public screen names (copied into the bracket) and the
  player ids linking them. Tournament passwords are scrypt hashes. Tournament
  rows are purged 7 days after their last update.

## Rules as implemented

| Rule | Value |
|---|---|
| Create | `POST /tournaments` `{size: 4\|8, starts_in_minutes: 2\|5\|10\|15\|30\|60` or `starts_at` (2 min–24 h), `private`, `password?`, `character_id?}`. The creator auto-joins as host. The code is `T` + 5 characters. |
| Who | Device players with a screen name, one tournament at a time. |
| Start | At `starts_at`, or 10 s (`starting_at`) after the bracket fills. Exactly once (version-guarded batch). |
| Minimum | 3; otherwise `cancelled` ("Not enough players joined"), no penalty. |
| Bracket | Next power of two ≥ players. Random (crypto) seeding. Byes go to the top seeds: 3 → 1, 5 → 3, 6 → 2, 7 → 1. Round 1 only, one each, auto-advance. |
| Match | A normal room (rules v2), one game, no rematch. A draw is won on small boards (`boards`, recorded). Level boards replay in the same room. |
| Ready window | 60 s. One player present: they advance (`no_show`, no records). Neither: the higher seed advances. |
| Forfeits | Before both moved: the opponent advances, no records. After: the normal v2 loss (forfeit / timeout / abandoned), recorded, and the loser is eliminated. |
| Leave | Before the start: frees the slot, the host passes on, and it's cancelled if empty. After the start: forfeits your current or next match. |
| Champion | `tournament_wins + 1`, shown on `/me` and on leaderboard rows. |

## For the client (Godot)

1. Check `capabilities.tournaments` (also `tournament_sizes`,
   `tournament_min_players`, `tournament_start_options`) on
   `GET /capabilities` or `/me`.
2. Lobby: `GET /tournaments`. Create, join and leave with the device token.
3. Poll `GET /tournaments/<CODE>` at `poll_after_ms`: registering 5000, the
   last 15 s / countdown 2000, waiting room 4000, your match open but not
   entered 1000, and finished/cancelled 0 (stop).
4. Bracket screen from `rounds`, with the live small-board score per match
   from `score` ("Kai 3 – 2 Mo"). No spectating.
5. When `your_match` appears, auto-open it: versus screen, then poll the room
   with `your_match.room_code` + `your_match.token` within `ready_deadline`
   (60 s). From there it's the normal room flow. Room envelopes now carry
   `tournament: {code, round, slot, ready_deadline, ready, rematch:false}`.
6. After the match, go back to the tournament poll (no rematch). Show
   `you.state`: `waiting`, `bye`, `playing`, `eliminated` or `champion`.

No tournament-wide chat (scope kept tight). In-match chat works in tournament
rooms as usual.

## Files

- New: `migrations/0006_nineweave_tournaments.sql`,
  `src/lib/nineweave/tournaments.ts`, `src/lib/nineweave/tournaments.test.ts`,
  and this file.
- Changed: `rooms.ts` (ready window, tournament no-show and leave endings,
  draw tiebreak/replay, no rematch/cancel, `tournament` envelope field,
  tournament room creation and seat tokens, sweep), `api.ts` (routes; an
  ended tournament room moves its bracket on), `players.ts`
  (`tournament_wins`, capabilities), `chat.ts` (capabilities),
  `service.ts` (sweep throttle), `fixtures.ts` (`O_WIN_GAME`,
  `DRAW_GAME_LEVEL_BOARDS`), `ONLINE_API.md`, `package.json` (`test:online`
  runs the new tests).
- Tests changed on purpose: the capability assertions in `email.test.ts` and
  `online2.test.ts` now expect `tournaments: true` and the tournament options.
