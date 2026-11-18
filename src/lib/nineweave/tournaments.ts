/**
 * Online tournaments: single-elimination brackets of 3–8 device players with
 * a screen name. See ONLINE_API.md "Tournaments" for the contract.
 *
 * Lifecycle: registering -> starting (10 s countdown once full) -> running ->
 * finished, or cancelled (fewer than 3 players at the start time, or the
 * last player left). There is no cron: whichever request touches a
 * tournament first after a deadline (poll, list, join, or a finished match
 * room) moves it on. Every tournament write is one atomic batch guarded by
 * the tournament's `rev` (the same divide-by-zero guard as rooms.ts), so the
 * start, each bracket step and the champion's `tournament_wins` happen
 * exactly once however many requests race.
 *
 * Bracket: next power of two >= players (4 or 8). Seeds are a crypto-random
 * shuffle at the start; round 1 pairs seed s with seed bracket+1-s, so the
 * missing seeds hand byes to the top seeds (at most one each, round 1 only).
 * Each match is a normal nw_rooms room (match rules v2), opened with a 60 s
 * ready window and played as one game (no rematch; a level draw replays).
 */
import { randomInt } from "node:crypto";
import { canonicalHero, DEFAULT_HERO, requireHeroOwnership } from "./heroes.ts";
import { requirePlayer, TOURNAMENT_CAPABILITIES, type PlayerRow } from "./players.ts";
import {
  leaveRoom,
  refreshRoom,
  seatOf,
  tournamentRoomInsert,
  tournamentSeatToken,
  type RoomRow,
  type Slot,
} from "./rooms.ts";
import { O, Rules, X } from "./rules.ts";
import { hashPassword, newId, verifyPassword } from "./security.ts";
import { ApiError, type Service } from "./service.ts";
import { pgCode, type Statement } from "./store.ts";

export const TOURNAMENT_SIZES = TOURNAMENT_CAPABILITIES.tournament_sizes;
export const TOURNAMENT_MIN_PLAYERS = TOURNAMENT_CAPABILITIES.tournament_min_players;
export const TOURNAMENT_START_OPTIONS = TOURNAMENT_CAPABILITIES.tournament_start_options;
/** Countdown between the bracket filling up and the start. */
export const STARTING_COUNTDOWN_MS = 10_000;
/** Ended (or abandoned) tournaments are purged this long after their last update. */
export const TOURNAMENT_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const START_MIN_MS = 2 * 60_000;
const START_MAX_MS = 24 * 60 * 60_000;
const LAST_CALL_MS = 15_000;
const PASSWORD_MAX = 64;
const MAX_ATTEMPTS = 6;
const LIST_MAX = 50;
const DUE_SWEEP_MAX = 10;

/** Server hints for the client's next tournament poll. */
export const TOURNAMENT_POLL_MS = {
  registering: 5000,
  countdown: 2000, // last 15 s before starts_at, or the full-bracket countdown
  waiting: 4000, // waiting room while other matches play
  yourMatch: 1000, // your match room is open and you haven't entered it yet
  ended: 0, // stop polling
} as const;

export type TournamentStatus = "registering" | "starting" | "running" | "finished" | "cancelled";

interface TournamentRow {
  id: string;
  code: string;
  status: TournamentStatus;
  size: number;
  bracket_size: number | null;
  is_private: boolean;
  password_hash: string | null;
  host_player_id: string | null;
  starts_at: Date;
  starting_at: Date | null;
  started_at: Date | null;
  finished_at: Date | null;
  cancel_reason: string | null;
  champion_player_id: string | null;
  champion_name: string | null;
  champion_hero: string | null;
  rev: string;
  created_at: Date;
  updated_at: Date;
}

interface EntrantRow {
  player_id: string;
  name: string;
  hero: string;
  seed: number | null;
  eliminated: boolean;
  withdrawn: boolean;
  joined_at: Date;
}

type MatchStatus = "pending" | "ready" | "live" | "done";

interface MatchRow {
  round: number;
  slot: number;
  a_player_id: string | null;
  b_player_id: string | null;
  a_seed: number | null;
  b_seed: number | null;
  bye: boolean;
  status: MatchStatus;
  room_id: string | null;
  winner: Slot | null;
  end_reason: string | null;
  a_boards: number | null;
  b_boards: number | null;
}

interface Loaded {
  t: TournamentRow;
  entrants: EntrantRow[];
  matches: MatchRow[];
  rooms: Map<string, RoomRow>;
}

const ms = (d: Date | string | null) => (d ? new Date(d).getTime() : 0);
const iso = (d: Date | string | null) => (d ? new Date(d).toISOString() : null);

// ---------------------------------------------------------------------------
// Codes and loading

const CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/** "T" + five uppercase letters/digits (room codes are five characters). */
export function newTournamentCode(): string {
  let code = "T";
  for (let i = 0; i < 5; i += 1) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

export function isTournamentCode(code: string): boolean {
  return /^T[A-Z0-9]{5}$/.test(code);
}

async function tournamentByCode(svc: Service, code: string): Promise<TournamentRow> {
  const rows = await svc.db.query<TournamentRow>(
    `select * from nw_tournaments where code = $1
      order by (status in ('registering', 'starting', 'running')) desc, created_at desc limit 1`,
    [code],
  );
  if (!rows[0]) throw new ApiError(404, "Tournament not found");
  return rows[0];
}

async function load(svc: Service, id: string): Promise<Loaded> {
  const [t] = await svc.db.query<TournamentRow>("select * from nw_tournaments where id = $1", [id]);
  if (!t) throw new ApiError(404, "Tournament not found");
  const entrants = await svc.db.query<EntrantRow>(
    `select player_id, name, hero, seed, eliminated, withdrawn, joined_at
       from nw_tournament_players where tournament_id = $1 order by seed nulls last, joined_at, player_id`,
    [id],
  );
  const matches = await svc.db.query<MatchRow>(
    `select round, slot, a_player_id, b_player_id, a_seed, b_seed, bye, status, room_id, winner,
            end_reason, a_boards, b_boards
       from nw_tournament_matches where tournament_id = $1 order by round, slot`,
    [id],
  );
  return { t, entrants, matches, rooms: new Map() };
}

/** Load the rooms of open matches, resolving any due turn / grace / ready-window deadline. */
async function loadRooms(svc: Service, matches: MatchRow[]): Promise<Map<string, RoomRow>> {
  const ids = matches
    .filter((m) => (m.status === "ready" || m.status === "live") && m.room_id)
    .map((m) => m.room_id!);
  const rooms = new Map<string, RoomRow>();
  if (ids.length === 0) return rooms;
  const placeholders = ids.map((_, i) => `$${i + 1}`).join(", ");
  const rows = await svc.db.query<RoomRow>(
    `select * from nw_rooms where id in (${placeholders})`,
    ids,
  );
  for (const row of rows) rooms.set(row.id, await refreshRoom(svc, row));
  return rooms;
}

// ---------------------------------------------------------------------------
// Optimistic commit (same pattern as rooms.ts commitRoom)

async function commitTournament(
  svc: Service,
  t: TournamentRow,
  sets: Partial<Record<keyof TournamentRow, unknown>>,
  extra: Statement[] = [],
): Promise<boolean> {
  const newRev = newId("r");
  const params: unknown[] = [t.id, t.rev, newRev, svc.now()];
  const assigns = ["rev = $3", "updated_at = $4"];
  for (const [col, value] of Object.entries(sets)) {
    params.push(value);
    assigns.push(`${col} = $${params.length}`);
  }
  try {
    await svc.db.transaction([
      {
        text: `update nw_tournaments set ${assigns.join(", ")} where id = $1 and rev = $2`,
        params,
      },
      {
        text: "select 1 / count(*) as ok from nw_tournaments where id = $1 and rev = $2",
        params: [t.id, newRev],
      },
      ...extra,
    ]);
    return true;
  } catch (err) {
    const code = pgCode(err);
    if (code === "22012" || code === "23505" || code === "40001") return false;
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Bracket

/** Round-1 seed pairs, in slot order: seed s meets seed bracket+1-s. */
function firstRoundPairs(bracket: number): [number, number][] {
  return bracket === 4
    ? [
        [1, 4],
        [2, 3],
      ]
    : [
        [1, 8],
        [4, 5],
        [2, 7],
        [3, 6],
      ];
}

const roundsFor = (bracket: number) => Math.round(Math.log2(bracket));

function shuffle<T>(items: T[]): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = randomInt(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** The higher seed (lower number) of a match. */
function higherSeedSide(m: MatchRow): Slot {
  if (m.a_player_id === null) return "b";
  if (m.b_player_id === null) return "a";
  return (m.a_seed ?? 99) <= (m.b_seed ?? 99) ? "a" : "b";
}

/** Small boards won by each side, from a room's current game. */
function roomScore(room: RoomRow): { a: number; b: number } {
  const rules = Rules.fromHistory(room.state.history);
  const aMark = seatOf(room, "a") === 1 ? X : O;
  const bMark = aMark === X ? O : X;
  return { a: rules.boardsWon(aMark), b: rules.boardsWon(bMark) };
}

interface Plan {
  changed: Set<MatchRow>;
  rooms: Statement[];
  eliminated: Set<string>;
  championId: string | null;
}

/**
 * Advance the bracket in memory: record ended rooms, move winners up, auto-
 * resolve matches with a withdrawn player, and open rooms for matches whose
 * two players are now known. Returns what changed.
 */
function advance(svc: Service, loaded: Loaded): Plan {
  const { t, entrants, matches, rooms } = loaded;
  const plan: Plan = { changed: new Set(), rooms: [], eliminated: new Set(), championId: null };
  const byId = new Map(entrants.map((e) => [e.player_id, e]));
  const rounds = roundsFor(t.bracket_size ?? 4);
  const at = (round: number, slot: number) =>
    matches.find((m) => m.round === round && m.slot === slot);
  const finish = (m: MatchRow, winner: Slot, reason: string, score?: { a: number; b: number }) => {
    m.status = "done";
    m.winner = winner;
    m.end_reason = reason;
    if (score) {
      m.a_boards = score.a;
      m.b_boards = score.b;
    }
    plan.changed.add(m);
  };

  for (const m of matches) {
    if (m.status !== "ready" && m.status !== "live") continue;
    const room = m.room_id ? rooms.get(m.room_id) : undefined;
    if (!room) {
      finish(m, higherSeedSide(m), "no_show");
    } else if (room.status === "finished" || room.status === "closed") {
      finish(
        m,
        room.winner_slot ?? higherSeedSide(m),
        room.end_reason ?? "no_show",
        roomScore(room),
      );
    } else if (room.status === "active" && m.status === "ready") {
      m.status = "live";
      plan.changed.add(m);
    }
  }

  let moved = true;
  while (moved) {
    moved = false;
    for (const m of matches) {
      if (m.status !== "done" || !m.winner || m.round >= rounds) continue;
      const next = at(m.round + 1, m.slot >> 1);
      if (!next) continue;
      const side: Slot = m.slot % 2 === 0 ? "a" : "b";
      if (next[`${side}_player_id`] !== null) continue;
      next[`${side}_player_id`] = m[`${m.winner}_player_id`];
      next[`${side}_seed`] = m[`${m.winner}_seed`];
      plan.changed.add(next);
      moved = true;
    }
    for (const m of matches) {
      if (m.status !== "pending" || !m.a_player_id || !m.b_player_id) continue;
      const a = byId.get(m.a_player_id);
      const b = byId.get(m.b_player_id);
      const aOut = !a || a.withdrawn;
      const bOut = !b || b.withdrawn;
      if (aOut || bOut) {
        finish(m, aOut && bOut ? higherSeedSide(m) : aOut ? "b" : "a", "forfeit");
      } else {
        const room = tournamentRoomInsert(
          svc,
          { tournamentId: t.id, code: t.code, round: m.round, slot: m.slot },
          { playerId: a.player_id, name: a.name, hero: a.hero },
          { playerId: b.player_id, name: b.name, hero: b.hero },
        );
        m.status = "ready";
        m.room_id = room.id;
        plan.rooms.push(room.statement);
        plan.changed.add(m);
      }
      moved = true;
    }
  }

  for (const m of matches) {
    if (m.status !== "done" || !m.winner || m.bye) continue;
    const loser = m[`${m.winner === "a" ? "b" : "a"}_player_id`];
    if (loser && !byId.get(loser)?.eliminated) plan.eliminated.add(loser);
  }
  const final = at(rounds, 0);
  if (final?.status === "done" && final.winner)
    plan.championId = final[`${final.winner}_player_id`];
  return plan;
}

function matchUpsert(t: TournamentRow, m: MatchRow, now: Date): Statement {
  return {
    text: `insert into nw_tournament_matches
      (tournament_id, round, slot, a_player_id, b_player_id, a_seed, b_seed, bye, status, room_id,
       winner, end_reason, a_boards, b_boards, updated_at)
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
      on conflict (tournament_id, round, slot) do update set
        a_player_id = excluded.a_player_id, b_player_id = excluded.b_player_id,
        a_seed = excluded.a_seed, b_seed = excluded.b_seed, bye = excluded.bye,
        status = excluded.status, room_id = excluded.room_id, winner = excluded.winner,
        end_reason = excluded.end_reason, a_boards = excluded.a_boards,
        b_boards = excluded.b_boards, updated_at = excluded.updated_at`,
    params: [
      t.id,
      m.round,
      m.slot,
      m.a_player_id,
      m.b_player_id,
      m.a_seed,
      m.b_seed,
      m.bye,
      m.status,
      m.room_id,
      m.winner,
      m.end_reason,
      m.a_boards,
      m.b_boards,
      now,
    ],
  };
}

/** Statements for a plan, plus the tournament columns to set. */
function planWrites(svc: Service, loaded: Loaded, plan: Plan) {
  const { t, entrants } = loaded;
  const now = svc.now();
  const extra: Statement[] = [...plan.rooms];
  for (const m of plan.changed) extra.push(matchUpsert(t, m, now));
  for (const id of plan.eliminated)
    extra.push({
      text: "update nw_tournament_players set eliminated = true where tournament_id = $1 and player_id = $2",
      params: [t.id, id],
    });
  const sets: Partial<Record<keyof TournamentRow, unknown>> = {};
  if (plan.championId && t.status === "running") {
    const champ = entrants.find((e) => e.player_id === plan.championId);
    Object.assign(sets, {
      status: "finished",
      finished_at: now,
      champion_player_id: plan.championId,
      champion_name: champ?.name ?? null,
      champion_hero: champ?.hero ?? null,
    });
    extra.push({
      text: "update nw_players set tournament_wins = tournament_wins + 1, updated_at = $2 where id = $1",
      params: [plan.championId, now],
    });
  }
  return { sets, extra };
}

/** Seed the entrants, build the bracket and open the first rooms (one batch). */
async function start(svc: Service, loaded: Loaded): Promise<boolean> {
  const { t, entrants } = loaded;
  const n = entrants.length;
  if (n < TOURNAMENT_MIN_PLAYERS)
    return commitTournament(svc, t, {
      status: "cancelled",
      cancel_reason: "Not enough players joined",
      starting_at: null,
      finished_at: svc.now(),
    });
  const bracket = n <= 4 ? 4 : 8;
  const seeded = shuffle(entrants).map((e, i) => ({ ...e, seed: i + 1 }));
  const bySeed = (s: number) => seeded.find((e) => e.seed === s) ?? null;
  const matches: MatchRow[] = [];
  const blank = { room_id: null, winner: null, end_reason: null, a_boards: null, b_boards: null };
  firstRoundPairs(bracket).forEach(([sa, sb], slot) => {
    const a = bySeed(sa)!; // seeds 1..bracket/2 always exist (n >= 3)
    const b = bySeed(sb);
    matches.push({
      ...blank,
      round: 1,
      slot,
      a_player_id: a.player_id,
      b_player_id: b?.player_id ?? null,
      a_seed: sa,
      b_seed: b ? sb : null,
      bye: !b,
      status: b ? "pending" : "done",
      winner: b ? null : "a",
      end_reason: b ? null : "bye",
    });
  });
  for (let round = 2; round <= roundsFor(bracket); round += 1)
    for (let slot = 0; slot < bracket >> round; slot += 1)
      matches.push({
        ...blank,
        round,
        slot,
        a_player_id: null,
        b_player_id: null,
        a_seed: null,
        b_seed: null,
        bye: false,
        status: "pending",
      });
  const next: Loaded = {
    t: { ...t, bracket_size: bracket, status: "running" },
    entrants: seeded,
    matches,
    rooms: new Map(),
  };
  const plan = advance(svc, next);
  for (const m of matches) plan.changed.add(m);
  const { extra } = planWrites(svc, next, plan);
  const now = svc.now();
  for (const e of seeded)
    extra.push({
      text: "update nw_tournament_players set seed = $3 where tournament_id = $1 and player_id = $2",
      params: [t.id, e.player_id, e.seed],
    });
  return commitTournament(
    svc,
    t,
    { status: "running", bracket_size: bracket, started_at: now, starting_at: null },
    extra,
  );
}

function startDue(t: TournamentRow, nowMs: number): boolean {
  if (t.status === "registering") return nowMs >= ms(t.starts_at);
  if (t.status === "starting")
    return nowMs >= ms(t.starts_at) || (t.starting_at !== null && nowMs >= ms(t.starting_at));
  return false;
}

/**
 * Bring a tournament up to date: start (or cancel) it when due, then record
 * finished matches and open the next rooms. Returns the fresh state.
 */
async function sync(svc: Service, id: string): Promise<Loaded> {
  for (let i = 0; i < MAX_ATTEMPTS; i += 1) {
    const loaded = await load(svc, id);
    const { t } = loaded;
    if (startDue(t, svc.now().getTime())) {
      await start(svc, loaded); // a lost race means another request started it
      continue;
    }
    if (t.status !== "running") return loaded;
    loaded.rooms = await loadRooms(svc, loaded.matches);
    const plan = advance(svc, loaded);
    if (plan.changed.size === 0 && plan.eliminated.size === 0 && !plan.championId) return loaded;
    const { sets, extra } = planWrites(svc, loaded, plan);
    await commitTournament(svc, t, sets, extra);
  }
  throw new ApiError(503, "The tournament is busy. Try again in a moment.");
}

/** Called after a tournament room ended, so the bracket moves on right away. */
export async function syncTournamentByCode(svc: Service, code: string): Promise<void> {
  const t = await tournamentByCode(svc, code).catch(() => null);
  if (t && t.status === "running") await sync(svc, t.id);
}

/**
 * Opportunistic sweep (throttled like the room cleanup): start or cancel
 * tournaments past their start time and purge old ones.
 */
export async function sweepTournaments(svc: Service, force = false): Promise<void> {
  const nowMs = svc.now().getTime();
  if (!force && nowMs - svc.lastTournamentSweepMs < svc.cleanupIntervalMs) return;
  svc.lastTournamentSweepMs = nowMs;
  const now = new Date(nowMs);
  const due = await svc.db.query<{ id: string }>(
    `select id from nw_tournaments
      where status in ('registering', 'starting')
        and (starts_at <= $1 or starting_at <= $1)
      order by starts_at limit ${DUE_SWEEP_MAX}`,
    [now],
  );
  for (const row of due) await sync(svc, row.id);
  await svc.db.query("delete from nw_tournaments where updated_at < $1", [
    new Date(nowMs - TOURNAMENT_TTL_MS),
  ]);
}

// ---------------------------------------------------------------------------
// Envelope (screen names, hero ids and seeds only: never player ids or hashes)

type YouState = "registered" | "playing" | "waiting" | "eliminated" | "champion" | "bye";

function yourMatchRow(loaded: Loaded, playerId: string): MatchRow | null {
  const mine = loaded.matches.filter(
    (m) => m.a_player_id === playerId || m.b_player_id === playerId,
  );
  return mine.length ? mine[mine.length - 1] : null;
}

function youState(loaded: Loaded, me: EntrantRow): YouState {
  const { t } = loaded;
  if (t.champion_player_id === me.player_id) return "champion";
  if (t.status !== "running" && t.status !== "finished") return "registered";
  if (me.eliminated || me.withdrawn) return "eliminated";
  const current = yourMatchRow(loaded, me.player_id);
  if (!current) return "waiting";
  if (current.status === "ready" || current.status === "live") return "playing";
  // Through on a round-1 bye and the round-2 opponent isn't decided yet.
  const opening = loaded.matches.find(
    (m) => m.round === 1 && (m.a_player_id === me.player_id || m.b_player_id === me.player_id),
  );
  if (opening?.bye && (current === opening || current.round === 2)) return "bye";
  return "waiting";
}

async function envelope(
  svc: Service,
  loaded: Loaded,
  viewer: PlayerRow | null,
  deviceToken: string | null,
) {
  const { t, entrants, matches, rooms } = loaded;
  const now = svc.now().getTime();
  const byId = new Map(entrants.map((e) => [e.player_id, e]));
  const me = viewer ? (byId.get(viewer.id) ?? null) : null;
  const side = (id: string | null, seed: number | null) => {
    const e = id ? byId.get(id) : undefined;
    return e ? { name: e.name, hero: e.hero, seed } : null;
  };

  const rounds: unknown[][] = [];
  for (const m of matches) {
    const room = m.room_id ? rooms.get(m.room_id) : undefined;
    const score =
      m.status === "live" && room
        ? roomScore(room)
        : m.status === "done" && m.a_boards !== null && m.b_boards !== null
          ? { a: m.a_boards, b: m.b_boards }
          : null;
    (rounds[m.round - 1] ??= []).push({
      slot: m.slot,
      a: side(m.a_player_id, m.a_seed),
      b: side(m.b_player_id, m.b_seed),
      bye: m.bye,
      status: m.status,
      score,
      winner: m.winner,
      end_reason: m.end_reason,
    });
  }

  let yourMatch: Record<string, unknown> | null = null;
  let enteredRoom = true;
  if (me && deviceToken && t.status === "running" && !me.withdrawn) {
    const m = yourMatchRow(loaded, me.player_id);
    const room = m?.room_id ? rooms.get(m.room_id) : undefined;
    if (m && room && (m.status === "ready" || m.status === "live")) {
      const slot: Slot = m.a_player_id === me.player_id ? "a" : "b";
      const opp = byId.get(m[`${slot === "a" ? "b" : "a"}_player_id`] ?? "");
      enteredRoom = (slot === "a" ? room.a_ready_at : room.b_ready_at) !== null;
      yourMatch = {
        room_code: room.code,
        token: await tournamentSeatToken(svc, room, slot, deviceToken),
        seat: seatOf(room, slot),
        round: m.round,
        slot: m.slot,
        status: m.status,
        opponent: opp ? { name: opp.name, hero: opp.hero } : null,
        ready_deadline: iso(room.ready_deadline),
      };
    }
  }

  let pollAfter: number;
  if (t.status === "finished" || t.status === "cancelled") pollAfter = TOURNAMENT_POLL_MS.ended;
  else if (t.status === "running")
    pollAfter =
      yourMatch && !enteredRoom ? TOURNAMENT_POLL_MS.yourMatch : TOURNAMENT_POLL_MS.waiting;
  else
    pollAfter =
      t.status === "starting" || ms(t.starts_at) - now <= LAST_CALL_MS
        ? TOURNAMENT_POLL_MS.countdown
        : TOURNAMENT_POLL_MS.registering;

  const host = t.host_player_id ? byId.get(t.host_player_id) : undefined;
  return {
    code: t.code,
    status: t.status,
    size: t.size,
    joined: entrants.length,
    min_players: TOURNAMENT_MIN_PLAYERS,
    bracket_size: t.bracket_size,
    starts_at: iso(t.starts_at),
    starting_at: iso(t.starting_at),
    started_at: iso(t.started_at),
    finished_at: iso(t.finished_at),
    server_now: svc.now().toISOString(),
    private: t.is_private,
    host: host?.name ?? null,
    is_host: !!me && t.host_player_id === me.player_id,
    cancel_reason: t.cancel_reason,
    you: me ? { seed: me.seed, name: me.name, hero: me.hero, state: youState(loaded, me) } : null,
    players: entrants.map((e) => ({
      seed: e.seed,
      name: e.name,
      hero: e.hero,
      eliminated: e.eliminated || e.withdrawn,
    })),
    rounds,
    your_match: yourMatch,
    champion: t.champion_name ? { name: t.champion_name, hero: t.champion_hero } : null,
    poll_after_ms: pollAfter,
  };
}

// ---------------------------------------------------------------------------
// Validation helpers

function requireScreenName(player: PlayerRow): string {
  if (!player.screen_name) throw new ApiError(403, "Choose a screen name to play tournaments");
  return player.screen_name;
}

function readHero(body: Record<string, unknown>, player: PlayerRow): string {
  if (body.character_id === undefined || body.character_id === null || body.character_id === "")
    return player.last_hero_id ?? DEFAULT_HERO;
  const hero = canonicalHero(body.character_id);
  if (!hero) throw new ApiError(400, "Unknown character_id");
  return hero;
}

function readPassword(body: Record<string, unknown>): string | null {
  const pw = body.password;
  if (pw === undefined || pw === null || pw === "") return null;
  if (typeof pw !== "string") throw new ApiError(400, "password must be text");
  if (pw.length > PASSWORD_MAX)
    throw new ApiError(400, `password must be ${PASSWORD_MAX} characters or fewer`);
  return pw;
}

function readStartsAt(svc: Service, body: Record<string, unknown>): Date {
  const now = svc.now().getTime();
  const hasMinutes = body.starts_in_minutes !== undefined && body.starts_in_minutes !== null;
  const hasAt = body.starts_at !== undefined && body.starts_at !== null;
  if (hasMinutes === hasAt)
    throw new ApiError(400, "Send exactly one of starts_in_minutes or starts_at");
  if (hasMinutes) {
    const minutes = body.starts_in_minutes;
    if (!(TOURNAMENT_START_OPTIONS as readonly unknown[]).includes(minutes))
      throw new ApiError(
        400,
        `starts_in_minutes must be one of ${TOURNAMENT_START_OPTIONS.join(", ")}`,
      );
    return new Date(now + (minutes as number) * 60_000);
  }
  const at = typeof body.starts_at === "string" ? Date.parse(body.starts_at) : Number.NaN;
  if (!Number.isFinite(at)) throw new ApiError(400, "starts_at must be an ISO-8601 timestamp");
  if (at - now < START_MIN_MS || at - now > START_MAX_MS)
    throw new ApiError(400, "starts_at must be between 2 minutes and 24 hours from now");
  return new Date(at);
}

/** 409 when the player is already registered in, or still playing, another tournament. */
async function ensureFree(svc: Service, playerId: string, exceptId?: string): Promise<void> {
  const busy = async () =>
    svc.db.query<{ id: string }>(
      `select t.id from nw_tournament_players tp join nw_tournaments t on t.id = tp.tournament_id
        where tp.player_id = $1 and t.id <> $2
          and (t.status in ('registering', 'starting')
               or (t.status = 'running' and not tp.eliminated and not tp.withdrawn))`,
      [playerId, exceptId ?? ""],
    );
  let rows = await busy();
  if (rows.length === 0) return;
  // Bring those up to date first: one may have just been cancelled or ended.
  for (const row of rows) await sync(svc, row.id);
  rows = await busy();
  if (rows.length > 0) throw new ApiError(409, "You're already in a tournament");
}

// ---------------------------------------------------------------------------
// Endpoints

/** POST /tournaments */
export async function createTournament(
  svc: Service,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  const player = await requirePlayer(svc, bearer);
  const name = requireScreenName(player);
  if (!(TOURNAMENT_SIZES as readonly unknown[]).includes(body.size))
    throw new ApiError(400, "size must be 4 or 8");
  const startsAt = readStartsAt(svc, body);
  if (body.private !== undefined && typeof body.private !== "boolean")
    throw new ApiError(400, "private must be true or false");
  const password = readPassword(body);
  const isPrivate = body.private === true || password !== null;
  if (isPrivate && !password) throw new ApiError(400, "Private tournaments need a password");
  const hero = readHero(body, player);
  await requireHeroOwnership(svc, player.id, hero);
  await sweepTournaments(svc);
  await ensureFree(svc, player.id);
  const passwordHash = password ? await hashPassword(password) : null;
  const now = svc.now();
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const id = newId("tour");
    try {
      await svc.db.transaction([
        {
          text: `insert into nw_tournaments
            (id, code, status, size, is_private, password_hash, host_player_id, starts_at, rev, created_at, updated_at)
            values ($1, $2, 'registering', $3, $4, $5, $6, $7, $8, $9, $9)`,
          params: [
            id,
            newTournamentCode(),
            body.size,
            isPrivate,
            passwordHash,
            player.id,
            startsAt,
            newId("r"),
            now,
          ],
        },
        {
          text: `insert into nw_tournament_players (tournament_id, player_id, name, hero, joined_at)
                 values ($1, $2, $3, $4, $5)`,
          params: [id, player.id, name, hero, now],
        },
      ]);
    } catch (err) {
      if (pgCode(err) === "23505") continue; // live code collision: pick another
      throw err;
    }
    return envelope(svc, await load(svc, id), player, bearer);
  }
  throw new ApiError(503, "Couldn't allocate a tournament code. Try again.");
}

/** GET /tournaments — public tournaments still taking players, newest first. */
export async function listTournaments(svc: Service) {
  await sweepTournaments(svc);
  const rows = await svc.db.query<{
    code: string;
    size: number;
    joined: number;
    host: string | null;
    starts_at: Date;
    created_at: Date;
  }>(
    `select t.code, t.size, t.starts_at, t.created_at,
            (select count(*) from nw_tournament_players p where p.tournament_id = t.id) as joined,
            (select name from nw_tournament_players p
              where p.tournament_id = t.id and p.player_id = t.host_player_id) as host
       from nw_tournaments t
      where t.status = 'registering' and not t.is_private
        and (select count(*) from nw_tournament_players p where p.tournament_id = t.id) < t.size
      order by t.created_at desc limit ${LIST_MAX}`,
  );
  const now = svc.now().getTime();
  return {
    server_now: new Date(now).toISOString(),
    tournaments: rows
      .filter((r) => ms(r.starts_at) > now) // due ones beyond the sweep cap start on their next touch
      .map((r) => ({
        code: r.code,
        size: r.size,
        joined: Number(r.joined),
        min_players: TOURNAMENT_MIN_PLAYERS,
        host: r.host,
        starts_at: iso(r.starts_at),
        created_at: iso(r.created_at),
      })),
    poll_after_ms: TOURNAMENT_POLL_MS.registering,
  };
}

/** GET /tournaments/:code — the poll. Private tournaments are visible to entrants only. */
export async function pollTournament(svc: Service, code: string, bearer: string | null) {
  const player = await requirePlayer(svc, bearer);
  const t = await tournamentByCode(svc, code);
  const loaded = await sync(svc, t.id);
  const isEntrant = loaded.entrants.some((e) => e.player_id === player.id);
  if (loaded.t.is_private && !isEntrant)
    throw new ApiError(403, "This tournament is private: join it with the password");
  return envelope(svc, loaded, player, bearer);
}

/** POST /tournaments/:code/join */
export async function joinTournament(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  const player = await requirePlayer(svc, bearer);
  const name = requireScreenName(player);
  const hero = readHero(body, player);
  await requireHeroOwnership(svc, player.id, hero);
  const password = readPassword(body);
  const found = await tournamentByCode(svc, code);
  let passwordOk = false;
  for (let i = 0; i < MAX_ATTEMPTS; i += 1) {
    const loaded = await sync(svc, found.id);
    const { t, entrants } = loaded;
    if (entrants.some((e) => e.player_id === player.id))
      return envelope(svc, loaded, player, bearer); // already in: idempotent
    if (t.is_private && !passwordOk) {
      if (!password || !t.password_hash || !(await verifyPassword(password, t.password_hash)))
        throw new ApiError(403, "Wrong tournament password");
      passwordOk = true;
    }
    if (t.status === "running") throw new ApiError(409, "This tournament has already started");
    if (t.status === "finished" || t.status === "cancelled")
      throw new ApiError(409, "This tournament has ended");
    if (entrants.length >= t.size) throw new ApiError(409, "This tournament is full");
    await ensureFree(svc, player.id, t.id);
    const now = svc.now();
    const fills = entrants.length + 1 === t.size;
    const ok = await commitTournament(
      svc,
      t,
      fills
        ? { status: "starting", starting_at: new Date(now.getTime() + STARTING_COUNTDOWN_MS) }
        : {},
      [
        {
          text: `insert into nw_tournament_players (tournament_id, player_id, name, hero, joined_at)
                 values ($1, $2, $3, $4, $5)`,
          params: [t.id, player.id, name, hero, now],
        },
      ],
    );
    if (ok) return envelope(svc, await load(svc, t.id), player, bearer);
  }
  throw new ApiError(503, "The tournament is busy. Try again in a moment.");
}

/**
 * POST /tournaments/:code/leave. Before the start: frees the slot (no
 * penalty); the host hands over to the next joiner, or the tournament is
 * cancelled when nobody is left. After the start: forfeits your current (or
 * next) match.
 */
export async function leaveTournament(svc: Service, code: string, bearer: string | null) {
  const player = await requirePlayer(svc, bearer);
  const found = await tournamentByCode(svc, code);
  for (let i = 0; i < MAX_ATTEMPTS; i += 1) {
    const loaded = await sync(svc, found.id);
    const { t, entrants } = loaded;
    const me = entrants.find((e) => e.player_id === player.id);
    if (!me) throw new ApiError(409, "You're not in this tournament");

    if (t.status === "registering" || t.status === "starting") {
      const rest = entrants
        .filter((e) => e.player_id !== player.id)
        .sort((x, y) => ms(x.joined_at) - ms(y.joined_at));
      const sets: Partial<Record<keyof TournamentRow, unknown>> = {};
      if (t.status === "starting")
        Object.assign(sets, { status: "registering", starting_at: null });
      if (t.host_player_id === player.id) sets.host_player_id = rest[0]?.player_id ?? null;
      if (rest.length === 0)
        Object.assign(sets, {
          status: "cancelled",
          cancel_reason: "Everyone left",
          starting_at: null,
          finished_at: svc.now(),
        });
      const ok = await commitTournament(svc, t, sets, [
        {
          text: "delete from nw_tournament_players where tournament_id = $1 and player_id = $2",
          params: [t.id, player.id],
        },
      ]);
      if (ok) return { ok: true, ...(await envelope(svc, await load(svc, t.id), player, bearer)) };
      continue;
    }

    if (t.status === "running" && !me.withdrawn && !me.eliminated) {
      const m = yourMatchRow(loaded, player.id);
      const room = m?.room_id ? loaded.rooms.get(m.room_id) : undefined;
      // Leaving the room ends it by the room rules: before both players moved
      // the opponent advances on a no-show; after, it's a recorded forfeit.
      if (room && (room.status === "waiting" || room.status === "active"))
        await leaveRoom(svc, room.code, {}, bearer);
      await svc.db.query(
        `update nw_tournament_players set withdrawn = true, eliminated = true
          where tournament_id = $1 and player_id = $2`,
        [t.id, player.id],
      );
      return { ok: true, ...(await envelope(svc, await sync(svc, t.id), player, bearer)) };
    }
    return { ok: true, ...(await envelope(svc, loaded, player, bearer)) };
  }
  throw new ApiError(503, "The tournament is busy. Try again in a moment.");
}
