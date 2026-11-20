/**
 * Nineweave online tournaments (round 5, phase 3): create / join / leave /
 * list, the start (countdown, byes, cancel, exactly once), the bracket played
 * through to a champion, ready-window no-shows, forfeits, draw replays and
 * the envelope's privacy. Requests go through the real HTTP handler backed by
 * an in-memory PGlite with `migrations/*.sql` applied, on a fake clock.
 */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { canonicalHero } from "./heroes.ts";
import { O, Rules, X } from "./rules.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import {
  DRAW_GAME_LEVEL_BOARDS,
  DRAW_GAME_X_MORE_BOARDS,
  O_WIN_GAME,
  X_WIN_GAME,
} from "./fixtures.ts";

const MIGRATIONS = join(import.meta.dirname, "..", "..", "..", "migrations");
const START = Date.parse("2026-11-15T12:00:00Z");
const TWO_MIN = 120_000;

let pg: PGlite;
let svc: Service;
let nowMs = START;

before(async () => {
  pg = new PGlite({ parsers: { 20: Number } });
  await pg.waitReady;
  for (const file of readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith(".sql"))
    .sort()) {
    await pg.exec(readFileSync(join(MIGRATIONS, file), "utf8"));
  }
});

after(async () => {
  await pg.close();
});

beforeEach(async () => {
  await pg.exec(
    "truncate nw_tournament_matches, nw_tournament_players, nw_tournaments, nw_reports, nw_blocks, nw_chat, nw_email_challenges, nw_matches, nw_rooms, nw_players restart identity cascade",
  );
  nowMs = START;
  svc = createService({
    db: pgliteDb(pg),
    now: () => new Date(nowMs),
    cleanupIntervalMs: 0,
    retentionIntervalMs: 0,
    limits: {
      device: 1000,
      create: 1000,
      join: 1000,
      move: 10_000,
      write: 1000,
      chat: 10_000,
      moderation: 1000,
    },
  });
});

interface Res {
  status: number;
  body: Record<string, any>;
  text: string;
}

async function call(
  method: string,
  path: string,
  opts: { body?: unknown; token?: string | null } = {},
): Promise<Res> {
  const headers: Record<string, string> = {};
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  const res = await handleNineweaveRequest(
    svc,
    new Request(`http://localhost/api/nineweave${path}`, {
      method,
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    }),
  );
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : {}, text };
}

interface P {
  name: string;
  token: string;
  id: string;
}

async function device(name?: string): Promise<P> {
  const res = await call("POST", "/auth/device", { body: name ? { screen_name: name } : {} });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return { name: name ?? "", token: res.body.token, id: res.body.player_id };
}

const NAMES = ["Kai", "Mo", "Ana", "Bo", "Cy", "Di", "Ed", "Fy", "Gus"];

async function players(n: number): Promise<P[]> {
  const out: P[] = [];
  for (let i = 0; i < n; i += 1) out.push(await device(NAMES[i]));
  return out;
}

const createT = (p: P, body: Record<string, unknown>) =>
  call("POST", "/tournaments", { token: p.token, body });
const joinT = (code: string, p: P, body: Record<string, unknown> = {}) =>
  call("POST", `/tournaments/${code}/join`, { token: p.token, body });
const pollT = (code: string, p: P) => call("GET", `/tournaments/${code}`, { token: p.token });
const leaveT = (code: string, p: P) =>
  call("POST", `/tournaments/${code}/leave`, { token: p.token });

/** A tournament created by ps[0] (2 minutes out) and joined by the rest. */
async function tournament(ps: P[], size = 8, extra: Record<string, unknown> = {}) {
  const created = await createT(ps[0], {
    size,
    starts_in_minutes: 2,
    character_id: "cryon",
    ...extra,
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const code = created.body.code as string;
  for (const p of ps.slice(1)) {
    nowMs += 100; // distinct join order
    const res = await joinT(code, p, { password: extra.password });
    assert.equal(res.status, 200, JSON.stringify(res.body));
  }
  return code;
}

/** Create, fill and start (at starts_at). */
async function started(n: number, size = 8) {
  const ps = await players(n);
  const code = await tournament(ps, size);
  nowMs = START + TWO_MIN;
  const view = await pollT(code, ps[0]);
  assert.equal(view.status, 200, JSON.stringify(view.body));
  return { ps, code, view: view.body };
}

const pollRoom = (code: string, token: string) => call("GET", `/rooms/${code}`, { token });

async function move(code: string, token: string, seq: number, [board, cell]: [number, number]) {
  return call("POST", `/rooms/${code}/moves`, { body: { board, cell, seq, token } });
}

async function playMoves(
  code: string,
  xToken: string,
  oToken: string,
  moves: [number, number][],
  startSeq = 0,
) {
  let last: Res | null = null;
  for (let i = 0; i < moves.length; i += 1) {
    const token = (startSeq + i) % 2 === 0 ? xToken : oToken;
    last = await move(code, token, startSeq + i + 1, moves[i]);
    assert.equal(last.status, 200, `move ${startSeq + i + 1}: ${JSON.stringify(last.body)}`);
  }
  return last!;
}

/** Both players' your_match, after both entered the room (the match is live). */
async function enter(code: string, a: P, b: P) {
  const ma = (await pollT(code, a)).body.your_match;
  const mb = (await pollT(code, b)).body.your_match;
  assert.ok(ma && mb, "both have a match");
  assert.equal(ma.room_code, mb.room_code);
  assert.equal((await pollRoom(ma.room_code, ma.token)).body.status, "waiting");
  const live = await pollRoom(mb.room_code, mb.token);
  assert.equal(live.body.status, "active");
  return { room: ma.room_code as string, a: ma, b: mb };
}

/** Play a full match between two entrants; `winner` wins by a real game. */
async function playMatch(code: string, winner: P, loser: P) {
  const { room, a, b } = await enter(code, winner, loser);
  const [w, l] = [a, b];
  if (w.seat === 1) await playMoves(room, w.token, l.token, X_WIN_GAME);
  else await playMoves(room, l.token, w.token, O_WIN_GAME);
  const end = await pollRoom(room, w.token);
  assert.equal(end.body.status, "finished");
  assert.equal(end.body.result.winner, w.seat);
  return room;
}

/** The two entrants of an open match, by name. */
function entrantsOf(view: Record<string, any>, ps: P[], round: number, slot: number) {
  const m = view.rounds[round - 1][slot];
  return [ps.find((p) => p.name === m.a.name)!, ps.find((p) => p.name === m.b.name)!];
}

async function record(p: P) {
  const me = (await call("GET", "/me", { token: p.token })).body;
  return [me.matches_won, me.matches_lost, me.matches_played];
}

async function count(table: string) {
  return Number(
    (await pg.query<{ n: number }>(`select count(*)::int as n from ${table}`)).rows[0].n,
  );
}

// ---------------------------------------------------------------------------

describe("create, join, leave and list", () => {
  it("creates a tournament with the creator joined and validates input", async () => {
    const [kai, mo] = await players(2);
    const anon = await device();
    assert.equal((await createT(anon, { size: 4, starts_in_minutes: 5 })).status, 403);
    assert.equal(
      (await call("POST", "/tournaments", { body: { size: 4, starts_in_minutes: 5 } })).status,
      401,
    );
    assert.equal((await createT(kai, { size: 6, starts_in_minutes: 5 })).status, 400);
    assert.equal((await createT(kai, { size: 4, starts_in_minutes: 3 })).status, 400);
    assert.equal((await createT(kai, { size: 4 })).status, 400);
    const soon = new Date(START + 60_000).toISOString();
    assert.equal((await createT(kai, { size: 4, starts_at: soon })).status, 400);
    assert.equal(
      (await createT(kai, { size: 4, starts_in_minutes: 5, private: true })).status,
      400,
    );

    const at = new Date(START + 3 * 3600_000).toISOString();
    const res = await createT(kai, { size: 4, starts_at: at, character_id: "cryon" });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.match(res.body.code, /^T[A-Z0-9]{5}$/);
    assert.equal(res.body.status, "registering");
    assert.equal(res.body.size, 4);
    assert.equal(res.body.joined, 1);
    assert.equal(res.body.min_players, 3);
    assert.equal(res.body.starts_at, at);
    assert.equal(res.body.host, "Kai");
    assert.deepEqual(res.body.you, { seed: null, name: "Kai", hero: "cryon", state: "registered" });
    assert.deepEqual(res.body.rounds, []);
    assert.equal(res.body.your_match, null);
    assert.equal(res.body.poll_after_ms, 5000);
    // One tournament at a time.
    assert.equal((await createT(kai, { size: 4, starts_in_minutes: 5 })).status, 409);
    // Non-entrants can view a public tournament.
    const seen = await pollT(res.body.code, mo);
    assert.equal(seen.status, 200);
    assert.equal(seen.body.you, null);
    assert.equal((await call("GET", `/tournaments/${res.body.code}`)).status, 401);
    assert.equal((await call("GET", "/tournaments/TZZZZZ", { token: mo.token })).status, 404);
    assert.equal((await call("GET", "/tournaments/ABCDE", { token: mo.token })).status, 404);
  });

  it("lists public tournaments newest first, hiding private and full ones", async () => {
    const ps = await players(7);
    const pub = await tournament([ps[0], ps[1]], 4);
    nowMs += 1000;
    const priv = await tournament([ps[2]], 4, { private: true, password: "secret" });
    nowMs += 1000;
    const full = await tournament([ps[3], ps[4], ps[5], ps[6]], 4);
    const list = await call("GET", "/tournaments");
    assert.equal(list.status, 200);
    const codes = list.body.tournaments.map((t: any) => t.code);
    assert.deepEqual(codes, [pub]);
    assert.ok(!codes.includes(priv) && !codes.includes(full));
    assert.deepEqual(Object.keys(list.body.tournaments[0]).sort(), [
      "code",
      "created_at",
      "host",
      "joined",
      "min_players",
      "size",
      "starts_at",
    ]);
    assert.equal(list.body.tournaments[0].joined, 2);
    assert.equal(list.body.tournaments[0].host, "Kai");
  });

  it("checks the password of a private tournament and hides it from non-entrants", async () => {
    const [kai, mo, ana] = await players(3);
    const code = await tournament([kai], 4, { private: true, password: "secret" });
    assert.equal((await pollT(code, mo)).status, 403);
    assert.equal((await joinT(code, mo)).status, 403);
    assert.equal((await joinT(code, mo, { password: "nope" })).status, 403);
    const ok = await joinT(code, mo, { password: "secret", character_id: "sara" });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.joined, 2);
    assert.equal(ok.body.private, true);
    assert.equal(ok.body.you.hero, "sara");
    // Joining again is idempotent.
    assert.equal((await joinT(code, mo, { password: "secret" })).body.joined, 2);
    assert.equal((await pollT(code, mo)).status, 200);
    assert.equal((await pollT(code, ana)).status, 403);
  });

  it("leaving before the start frees the slot and hands the host on", async () => {
    const [kai, mo, ana, bo, cy] = await players(5);
    const code = await tournament([kai, mo, ana, bo], 4);
    let view = (await pollT(code, kai)).body;
    assert.equal(view.status, "starting", "full bracket starts the countdown");
    assert.equal(view.starting_at, new Date(nowMs + 10_000).toISOString());
    assert.equal(view.poll_after_ms, 2000);
    assert.equal((await joinT(code, cy)).status, 409);

    const left = await leaveT(code, kai);
    assert.equal(left.status, 200, JSON.stringify(left.body));
    assert.equal(left.body.status, "registering", "a free slot stops the countdown");
    assert.equal(left.body.starting_at, null);
    assert.equal(left.body.joined, 3);
    assert.equal(left.body.host, "Mo");
    assert.equal(left.body.you, null);
    assert.equal((await leaveT(code, kai)).status, 409);
    assert.equal((await joinT(code, cy)).status, 200);
    // Kai may join something else now.
    const other = await createT(kai, { size: 4, starts_in_minutes: 5 });
    assert.equal(other.status, 201);
    assert.equal((await leaveT(other.body.code, kai)).body.status, "cancelled");
    view = (await pollT(other.body.code, kai)).body;
    assert.equal(view.cancel_reason, "Everyone left");
    assert.equal(view.poll_after_ms, 0);
    assert.deepEqual(await record(kai), [0, 0, 0]);
  });
});

describe("start", () => {
  it("a full 8/8 bracket starts 10 s after filling, with no byes and 3 rounds", async () => {
    const ps = await players(8);
    const code = await tournament(ps, 8);
    let view = (await pollT(code, ps[3])).body;
    assert.equal(view.status, "starting");
    const filled = nowMs;
    nowMs = filled + 9_999;
    assert.equal((await pollT(code, ps[3])).body.status, "starting");
    nowMs = filled + 10_000;
    view = (await pollT(code, ps[3])).body;
    assert.equal(view.status, "running");
    assert.equal(view.bracket_size, 8);
    assert.equal(view.rounds.length, 3);
    assert.deepEqual(
      view.rounds.map((r: unknown[]) => r.length),
      [4, 2, 1],
    );
    assert.ok(view.rounds[0].every((m: any) => !m.bye && m.status === "ready"));
    assert.deepEqual(
      view.rounds[0].map((m: any) => [m.a.seed, m.b.seed]),
      [
        [1, 8],
        [4, 5],
        [2, 7],
        [3, 6],
      ],
    );
    assert.deepEqual(view.players.map((p: any) => p.seed).sort(), [1, 2, 3, 4, 5, 6, 7, 8]);
    for (const p of ps) {
      const mine = (await pollT(code, p)).body;
      assert.equal(mine.you.state, "playing");
      assert.ok(mine.your_match.room_code);
      assert.equal(mine.poll_after_ms, 1000);
    }
    assert.equal(await count("nw_rooms"), 4);
  });

  it("6 of 8: two byes to the top seeds, who advance to round 2; play to a champion", async () => {
    const { ps, code, view } = await started(6);
    assert.equal(view.status, "running");
    assert.equal(view.bracket_size, 8);
    assert.equal(view.rounds.length, 3);
    const r1 = view.rounds[0];
    assert.equal(r1.filter((m: any) => m.bye).length, 2);
    for (const m of r1.filter((x: any) => x.bye)) {
      assert.ok(m.a.seed <= 2, "byes go to the top seeds");
      assert.equal(m.b, null);
      assert.equal(m.status, "done");
      assert.equal(m.winner, "a");
    }
    // Byes fill round 2 side "a" slots of their feeders.
    const r2 = view.rounds[1];
    assert.equal(r2[0].a.seed, 1);
    assert.equal(r2[1].a.seed, 2);
    assert.equal(r2[0].status, "pending");
    const top = ps.find((p) => p.name === r2[0].a.name)!;
    const topView = (await pollT(code, top)).body;
    assert.equal(topView.you.state, "bye");
    assert.equal(topView.your_match, null);
    assert.equal(topView.poll_after_ms, 4000);

    // Play everything out: side "a" always wins.
    for (const slot of [1, 3]) {
      const [a, b] = entrantsOf(view, ps, 1, slot);
      await playMatch(code, a, b);
    }
    let now = (await pollT(code, ps[0])).body;
    assert.deepEqual(
      now.rounds[1].map((m: any) => m.status),
      ["ready", "ready"],
    );
    for (const slot of [0, 1]) {
      const [a, b] = entrantsOf(now, ps, 2, slot);
      await playMatch(code, a, b);
    }
    now = (await pollT(code, ps[0])).body;
    const [fa, fb] = entrantsOf(now, ps, 3, 0);
    await playMatch(code, fa, fb);
    now = (await pollT(code, fb)).body;
    assert.equal(now.status, "finished");
    assert.deepEqual(Object.keys(now.champion).sort(), ["hero", "name"]);
    assert.equal(now.champion.name, fa.name);
    assert.equal(now.you.state, "eliminated");
    assert.equal(now.poll_after_ms, 0);
    assert.equal((await pollT(code, fa)).body.you.state, "champion");
    assert.equal(now.players.filter((p: any) => !p.eliminated).length, 1);
    const champ = (await call("GET", "/me", { token: fa.token })).body;
    assert.equal(champ.tournament_wins, 1);
    // The top seed had a bye, so the title took two wins.
    assert.deepEqual([champ.matches_won, champ.matches_played], [2, 2]);
  });

  it("5 of 8: three byes, and two bye winners meet at once in round 2", async () => {
    const { view } = await started(5);
    assert.equal(view.bracket_size, 8);
    const r1 = view.rounds[0];
    assert.equal(r1.filter((m: any) => m.bye).length, 3);
    assert.deepEqual(
      r1
        .filter((m: any) => m.bye)
        .map((m: any) => m.a.seed)
        .sort(),
      [1, 2, 3],
    );
    assert.equal(view.rounds[1][1].status, "ready", "seeds 2 and 3 meet straight away");
    assert.deepEqual([view.rounds[1][1].a.seed, view.rounds[1][1].b.seed], [2, 3]);
    assert.equal(await count("nw_rooms"), 2);
  });

  it("3 of 4: one bye in a 4 bracket of 2 rounds", async () => {
    const { view } = await started(3, 4);
    assert.equal(view.bracket_size, 4);
    assert.equal(view.rounds.length, 2);
    assert.equal(view.rounds[0].filter((m: any) => m.bye).length, 1);
    assert.equal(view.rounds[0][0].a.seed, 1);
    assert.equal(view.rounds[0][0].bye, true);
    assert.equal(view.rounds[0][1].status, "ready");
  });

  it("2 joined at the start time: cancelled, nobody penalized", async () => {
    const ps = await players(2);
    const code = await tournament(ps, 4);
    nowMs = START + TWO_MIN - 15_000;
    assert.equal((await pollT(code, ps[1])).body.poll_after_ms, 2000, "last 15 s");
    nowMs = START + TWO_MIN;
    const view = (await pollT(code, ps[1])).body;
    assert.equal(view.status, "cancelled");
    assert.equal(view.cancel_reason, "Not enough players joined");
    assert.equal(view.poll_after_ms, 0);
    assert.equal(await count("nw_rooms"), 0);
    for (const p of ps) assert.deepEqual(await record(p), [0, 0, 0]);
    // Both are free to join another one.
    assert.equal((await createT(ps[0], { size: 4, starts_in_minutes: 2 })).status, 201);
  });

  it("the list sweep starts due tournaments", async () => {
    const ps = await players(3);
    const code = await tournament(ps, 4);
    nowMs = START + TWO_MIN;
    await call("GET", "/tournaments");
    const row = (await pg.query<{ status: string }>("select status from nw_tournaments")).rows[0];
    assert.equal(row.status, "running");
    assert.equal((await pollT(code, ps[0])).body.status, "running");
  });

  it("starts exactly once under concurrent polls", async () => {
    const ps = await players(4);
    const code = await tournament(ps.slice(0, 3), 4);
    nowMs = START + TWO_MIN;
    const views = await Promise.all([
      ...ps.slice(0, 3).map((p) => pollT(code, p)),
      ...ps.slice(0, 3).map((p) => pollT(code, p)),
      call("GET", "/tournaments"),
      joinT(code, ps[3]),
    ]);
    for (const v of views.slice(0, 6)) {
      assert.equal(v.status, 200, JSON.stringify(v.body));
      assert.equal(v.body.status, "running");
    }
    assert.equal(views[7].status, 409, "too late to join");
    assert.equal(await count("nw_tournament_matches"), 3);
    assert.equal(await count("nw_rooms"), 1);
    const seeds = (await pg.query<{ seed: number }>("select seed from nw_tournament_players")).rows;
    assert.deepEqual(seeds.map((s) => s.seed).sort(), [1, 2, 3]);
  });
});

describe("matches", () => {
  it("your_match token works with room endpoints; live score; one game; champion recorded", async () => {
    const { ps, code, view } = await started(4, 4);
    const [a, b] = entrantsOf(view, ps, 1, 0);
    const mine = (await pollT(code, a)).body.your_match;
    assert.deepEqual(Object.keys(mine).sort(), [
      "opponent",
      "ready_deadline",
      "room_code",
      "round",
      "seat",
      "slot",
      "status",
      "token",
    ]);
    assert.match(mine.token, /^nws_/);
    assert.equal(mine.opponent.name, b.name);
    assert.equal(mine.ready_deadline, new Date(nowMs + 60_000).toISOString());
    // Stable token across polls.
    assert.equal((await pollT(code, a)).body.your_match.token, mine.token);

    const { room, a: ma, b: mb } = await enter(code, a, b);
    const roomView = (await pollRoom(room, ma.token)).body;
    assert.equal(roomView.seat, ma.seat);
    assert.equal(roomView.tournament.code, code);
    assert.equal(roomView.tournament.round, 1);
    assert.equal(roomView.tournament.rematch, false);
    assert.equal((await pollT(code, a)).body.poll_after_ms, 4000, "entered: back to 4 s");
    assert.equal((await pollT(code, a)).body.rounds[0][0].status, "live");

    // Play half the X win and check the live score.
    const [xTok, oTok, xSide] =
      ma.seat === 1 ? [ma.token, mb.token, "a"] : [mb.token, ma.token, "b"];
    const half = X_WIN_GAME.slice(0, 15);
    await playMoves(room, xTok, oTok, half);
    const kernel = Rules.fromHistory(half.map(([board, cell]) => ({ board, cell })));
    const xBoards = kernel.boardsWon(X);
    const oBoards = kernel.boardsWon(O);
    assert.ok(xBoards + oBoards > 0, "some boards are claimed by now");
    const live = (await pollT(code, ps[2])).body.rounds[0][0];
    assert.deepEqual(
      live.score,
      xSide === "a" ? { a: xBoards, b: oBoards } : { a: oBoards, b: xBoards },
    );
    assert.ok(!JSON.stringify(live).includes("cells"), "no spectating");
    await playMoves(room, xTok, oTok, X_WIN_GAME.slice(15), 15);
    const ended = await pollRoom(room, ma.token);
    assert.equal(ended.body.status, "finished");
    const rematch = await call("POST", `/rooms/${room}/rematch`, { body: { token: ma.token } });
    assert.equal(rematch.status, 409);
    assert.match(rematch.body.error, /no rematch/);

    const xWinner = xSide === "a" ? a : b;
    const xLoser = xSide === "a" ? b : a;
    assert.deepEqual(await record(xWinner), [1, 0, 1]);
    assert.deepEqual(await record(xLoser), [0, 1, 1]);
    let t = (await pollT(code, xLoser)).body;
    assert.equal(t.you.state, "eliminated");
    assert.equal(t.rounds[0][0].status, "done");
    assert.equal(t.rounds[0][0].winner, xSide);
    assert.equal((await pollT(code, xWinner)).body.you.state, "waiting");

    const [c, d] = entrantsOf(view, ps, 1, 1);
    await playMatch(code, c, d);
    t = (await pollT(code, ps[0])).body;
    assert.equal(t.rounds[1][0].status, "ready");
    await playMatch(code, xWinner, c);
    t = (await pollT(code, d)).body;
    assert.equal(t.status, "finished");
    assert.equal(t.champion.name, xWinner.name);
    const lb = (await call("GET", "/leaderboard", { token: xWinner.token })).body;
    assert.equal(lb.players.find((r: any) => r.screen_name === xWinner.name).tournament_wins, 1);
    assert.equal(lb.me.tournament_wins, 1);
    assert.equal((await call("GET", "/me", { token: c.token })).body.tournament_wins, 0);
    // Polling again doesn't award twice.
    await pollT(code, xWinner);
    assert.equal((await call("GET", "/me", { token: xWinner.token })).body.tournament_wins, 1);
  });

  it("no-show: the player who opened the room advances, no records", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a, b] = entrantsOf(view, ps, 1, 1);
    const mb = (await pollT(code, b)).body.your_match;
    const waiting = await pollRoom(mb.room_code, mb.token);
    assert.equal(waiting.body.status, "waiting");
    assert.equal(waiting.body.poll_after_ms, 1000);
    assert.equal(waiting.body.tournament.ready.you, true);
    assert.equal(waiting.body.tournament.ready.opponent, false);
    nowMs += 59_999;
    assert.equal((await pollRoom(mb.room_code, mb.token)).body.status, "waiting");
    nowMs += 1;
    const closed = await pollRoom(mb.room_code, mb.token);
    assert.equal(closed.body.status, "closed");
    assert.equal(closed.body.end_reason, "no_show");
    assert.equal(closed.body.result.winner, mb.seat);
    const t = (await pollT(code, a)).body;
    assert.equal(t.rounds[0][1].winner, "b");
    assert.equal(t.rounds[0][1].end_reason, "no_show");
    assert.equal(t.you.state, "eliminated");
    assert.equal(t.rounds[1][0].status, "ready", "final opens: bye winner vs " + b.name);
    assert.deepEqual(await record(a), [0, 0, 0]);
    assert.deepEqual(await record(b), [0, 0, 0]);
  });

  it("no-show: when neither opens the room, the higher seed advances", async () => {
    const { ps, code, view } = await started(3, 4);
    const m = view.rounds[0][1];
    nowMs += 60_000;
    const t = (await pollT(code, ps[0])).body;
    assert.equal(t.rounds[0][1].status, "done");
    assert.equal(t.rounds[0][1].winner, m.a.seed < m.b.seed ? "a" : "b");
    assert.equal(t.rounds[0][1].end_reason, "no_show");
  });

  it("third consecutive own late turn eliminates the player and advances the opponent", async () => {
    const { ps, code, view } = await started(3,4);
    const [a,b]=entrantsOf(view,ps,1,1);
    const {room,a:ma,b:mb}=await enter(code,a,b);
    const [xTok,oTok]=ma.seat===1?[ma.token,mb.token]:[mb.token,ma.token];
    for(let n=0;n<2;n++) {
      nowMs+=25_000;
      assert.equal((await move(room,xTok,n*2+1,X_WIN_GAME[n*2])).status,200);
      assert.equal((await move(room,oTok,n*2+2,X_WIN_GAME[n*2+1])).status,200);
    }
    nowMs+=25_000;
    const ended=await pollRoom(room,oTok);
    assert.deepEqual(ended.body.result,{winner:2,reason:"timeout"});
    const loser=ma.seat===1?a:b;
    const winner=ma.seat===1?b:a;
    assert.deepEqual(await record(loser),[0,1,1]);
    assert.deepEqual(await record(winner),[1,0,1]);
    const t=(await pollT(code,winner)).body;
    assert.equal(t.players.find((p:any)=>p.name===loser.name).eliminated,true);
    assert.equal(t.rounds[1][0].status,"ready");
  });

  it("leaving after both moved is a recorded forfeit that eliminates", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a, b] = entrantsOf(view, ps, 1, 1);
    const { room, a: ma, b: mb } = await enter(code, a, b);
    const [xTok, oTok] = ma.seat === 1 ? [ma.token, mb.token] : [mb.token, ma.token];
    await playMoves(room, xTok, oTok, X_WIN_GAME.slice(0, 2));
    const left = await leaveT(code, a);
    assert.equal(left.status, 200, JSON.stringify(left.body));
    assert.equal(left.body.you.state, "eliminated");
    const roomView = (await pollRoom(room, mb.token)).body;
    assert.equal(roomView.end_reason, "forfeit");
    assert.equal(roomView.result.winner, mb.seat);
    assert.deepEqual(await record(a), [0, 1, 1]);
    assert.deepEqual(await record(b), [1, 0, 1]);
    const t = (await pollT(code, b)).body;
    assert.equal(t.rounds[0][1].winner, "b");
    assert.equal(t.players.find((p: any) => p.name === a.name).eliminated, true);
    assert.equal(t.rounds[1][0].status, "ready");
  });

  it("a turn timeout after both moved eliminates the slow player", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a, b] = entrantsOf(view, ps, 1, 1);
    const { room, a: ma, b: mb } = await enter(code, a, b);
    const [xTok, oTok] = ma.seat === 1 ? [ma.token, mb.token] : [mb.token, ma.token];
    await playMoves(room, xTok, oTok, X_WIN_GAME.slice(0, 2));
    nowMs += 35_000; // X is due and never moves
    const t = (await pollT(code, ps[0])).body;
    const xSide = ma.seat === 1 ? "a" : "b";
    assert.equal(t.rounds[0][1].winner, xSide === "a" ? "b" : "a");
    assert.equal(t.rounds[0][1].end_reason, "timeout");
  });

  it("leaving before the first move: the opponent advances on a no-show", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a, b] = entrantsOf(view, ps, 1, 1);
    await enter(code, a, b);
    await leaveT(code, a);
    const t = (await pollT(code, b)).body;
    assert.equal(t.rounds[0][1].winner, "b");
    assert.equal(t.rounds[0][1].end_reason, "no_show");
    assert.deepEqual(await record(a), [0, 0, 0]);
  });

  it("leaving while waiting for the next round forfeits that match", async () => {
    const { ps, code, view } = await started(3, 4);
    const top = ps.find((p) => p.name === view.rounds[0][0].a.name)!;
    const left = await leaveT(code, top);
    assert.equal(left.body.you.state, "eliminated");
    const [a, b] = entrantsOf(view, ps, 1, 1);
    await playMatch(code, a, b);
    const t = (await pollT(code, a)).body;
    assert.equal(t.status, "finished");
    assert.equal(t.rounds[1][0].end_reason, "forfeit");
    assert.equal(t.champion.name, a.name);
    assert.deepEqual(await record(top), [0, 0, 0]);
    assert.equal((await call("GET", "/me", { token: a.token })).body.tournament_wins, 1);
  });

  it("a draw replays when boards are level and is decided by small boards otherwise", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a, b] = entrantsOf(view, ps, 1, 1);
    const { room, a: ma, b: mb } = await enter(code, a, b);
    let [xTok, oTok] = ma.seat === 1 ? [ma.token, mb.token] : [mb.token, ma.token];
    const replay = await playMoves(room, xTok, oTok, DRAW_GAME_LEVEL_BOARDS);
    assert.equal(replay.body.status, "active", "level draw: replay");
    assert.equal(replay.body.match.round, 2);
    assert.equal(replay.body.both_moved, false);
    assert.equal(replay.body.state.history.length, 0);
    assert.deepEqual(await record(a), [0, 0, 0]);
    // Seats swap for the replay.
    const now = (await pollRoom(room, ma.token)).body;
    assert.equal(now.seat, 3 - ma.seat);
    [xTok, oTok] = [oTok, xTok];
    const xPlayer = now.seat === 1 ? a : b;
    const oPlayer = xPlayer === a ? b : a;
    const done = await playMoves(room, xTok, oTok, DRAW_GAME_X_MORE_BOARDS);
    assert.equal(done.body.status, "finished");
    assert.equal(done.body.end_reason, "boards");
    assert.equal(done.body.result.reason, "boards");
    assert.deepEqual(await record(xPlayer), [1, 0, 1]);
    assert.deepEqual(await record(oPlayer), [0, 1, 1]);
    const t = (await pollT(code, a)).body;
    const xSide = xPlayer === a ? "a" : "b";
    assert.equal(t.rounds[0][1].winner, xSide);
    assert.deepEqual(t.rounds[0][1].score, xSide === "a" ? { a: 5, b: 4 } : { a: 4, b: 5 });
    assert.equal(t.rounds[0][1].end_reason, "boards");
  });

  it("tournament rooms can't be joined, cancelled or listed", async () => {
    const { ps, code, view } = await started(3, 4);
    const [a] = entrantsOf(view, ps, 1, 1);
    const mine = (await pollT(code, a)).body.your_match;
    const stranger = await device("Zed");
    assert.equal(
      (await call("POST", `/rooms/${mine.room_code}/join`, { token: stranger.token, body: {} }))
        .status,
      403,
    );
    assert.equal(
      (await call("POST", `/rooms/${mine.room_code}/cancel`, { body: { token: mine.token } }))
        .status,
      409,
    );
    assert.equal((await call("GET", "/rooms")).body.rooms.length, 0);
  });
});

describe("privacy and capabilities", () => {
  it("envelopes carry no player ids or hashes, and only your own seat token", async () => {
    const { ps, code, view } = await started(4, 4);
    const [a, b] = entrantsOf(view, ps, 1, 0);
    const mineA = (await pollT(code, a)).body;
    const mineB = (await pollT(code, b)).body;
    const roomRows = (
      await pg.query<{ id: string; a_token_hash: string; b_token_hash: string }>(
        "select id, a_token_hash, b_token_hash from nw_rooms",
      )
    ).rows;
    const tournamentIds = (await pg.query<{ id: string }>("select id from nw_tournaments")).rows;
    for (const res of [mineA, mineB, view, (await call("GET", "/tournaments")).body]) {
      const text = JSON.stringify(res);
      for (const p of ps) {
        assert.ok(!text.includes(p.id), "no player ids");
        assert.ok(!text.includes(p.token), "no device tokens");
      }
      for (const r of roomRows) {
        assert.ok(!text.includes(r.a_token_hash) && !text.includes(r.b_token_hash));
        assert.ok(!text.includes(r.id), "no room ids");
      }
      for (const t of tournamentIds) assert.ok(!text.includes(t.id), "no tournament ids");
      assert.ok(!text.includes("hash"));
    }
    assert.ok(!JSON.stringify(mineA).includes(mineB.your_match.token));
    assert.ok(!JSON.stringify(mineB).includes(mineA.your_match.token));
    // The seat tokens differ per player and per seat.
    assert.notEqual(mineA.your_match.token, mineB.your_match.token);
    // Your token is for your seat only.
    const asB = await pollRoom(mineA.your_match.room_code, mineB.your_match.token);
    assert.equal(asB.body.seat, mineB.your_match.seat);
  });

  it("advertises tournaments in capabilities", async () => {
    const caps = (await call("GET", "/capabilities")).body;
    assert.equal(caps.tournaments, true);
    assert.deepEqual(caps.tournament_sizes, [4, 8]);
    assert.equal(caps.tournament_min_players, 3);
    assert.deepEqual(caps.tournament_start_options, [2, 5, 10, 15, 30, 60]);
    const d = await device("Caps");
    const me = (await call("GET", "/me", { token: d.token })).body;
    assert.equal(me.capabilities.tournaments, true);
    assert.equal(me.tournament_wins, 0);
  });

  it("purges ended tournaments after 7 days", async () => {
    const ps = await players(2);
    await tournament(ps, 4);
    nowMs = START + TWO_MIN;
    await call("GET", "/tournaments"); // cancelled (too few)
    assert.equal(await count("nw_tournaments"), 1);
    nowMs += 7 * 24 * 3600_000 + 1000;
    await call("GET", "/tournaments");
    assert.equal(await count("nw_tournaments"), 0);
    assert.equal(await count("nw_tournament_players"), 0);
  });
});


describe("Patrick tournament compatibility", () => {
  it("allows Patrick to host and a legacy Kite selection to join", async () => {
    const [host, guest] = await players(2);
    const created = await createT(host, { size: 4, starts_in_minutes: 2, character_id: "patrick_laquin" });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const joined = await joinT(created.body.code, guest, { character_id: "kite_hollow" });
    assert.equal(joined.status, 200, JSON.stringify(joined.body));
    assert.equal(joined.body.you.hero, "patrick_laquin");
    assert.deepEqual(joined.body.players.map((p: { hero: string }) => p.hero), ["patrick_laquin", "patrick_laquin"]);
  });
});


describe("pre-upgrade persisted Kite tournament entries", () => {
  it("loads old entrants while retaining their tournament and seat", async () => {
    const [host, guest] = await players(2);
    const created = await createT(host, { size: 4, starts_in_minutes: 2, character_id: "patrick_laquin" });
    await joinT(created.body.code, guest, { character_id: "auric_rex" });
    await pg.query("update nw_tournament_players set hero = 'kite_hollow' where hero = 'patrick_laquin'");
    const view = await pollT(created.body.code, host);
    assert.equal(view.status, 200, JSON.stringify(view.body));
    assert.equal(canonicalHero(view.body.you.hero), "patrick_laquin");
    assert.equal(view.body.players.length, 2);
    assert.equal(view.body.code, created.body.code);
  });
});

describe("tournament board readiness", () => {
  const roomPoll = (code: string, token: string, optIn = true) =>
    call("GET", `/rooms/${code}${optIn ? "?board_ready_v1=1" : ""}`, { token });
  const acknowledge = (code: string, token: string) =>
    call("POST", `/rooms/${code}/board-ready`, { token, body: { round: 1 } });

  async function setupOpening(optIn: boolean) {
    svc.boardReadyEnabled = true;
    const { ps, code, view } = await started(3, 4);
    const [a,b] = entrantsOf(view,ps,1,1);
    const ma = (await pollT(code,a)).body.your_match;
    const mb = (await pollT(code,b)).body.your_match;
    assert.equal(ma.room_code, mb.room_code);
    const room = ma.room_code;
    const first = await roomPoll(room,ma.token);
    assert.equal(first.body.status, "waiting");
    assert.equal(first.body.turn_started_at, null);
    assert.equal(first.body.opening, undefined);
    nowMs += 9_000;
    const second = await roomPoll(room,mb.token,optIn);
    assert.equal(second.body.status, "active");
    return { a, b, ma, mb, room, code, second };
  }

  it("two arrivals still require two board confirmations, then play the full opening turn", async () => {
    const { a, ma, mb, room, code, second } = await setupOpening(true);
    assert.equal(second.body.opening.waiting, true);
    assert.equal(second.body.turn_started_at, null);
    assert.equal((await pollT(code,a)).body.rounds[0][1].status, "ready");
    assert.equal((await acknowledge(room,ma.token)).body.opening.waiting,true);
    nowMs += 13_000;
    const active = await acknowledge(room,mb.token);
    assert.equal(active.body.opening.waiting,false);
    assert.equal(active.body.turn_started_at,new Date(nowMs).toISOString());
    assert.equal(active.body.still_there_at,new Date(nowMs+25_000).toISOString());
    assert.equal(active.body.turn_expires_at,new Date(nowMs+35_000).toISOString());
    assert.equal((await pollT(code,a)).body.rounds[0][1].status,"live");
  });

  it("missing board sends no turn penalties, advances the one ready or the existing higher-seed fallback", async () => {
    for (const oneReady of [true,false]) {
      // Reset between cases via the in-memory fixture, not a real database.
      if (!oneReady) {
        await pg.exec("truncate nw_tournament_matches,nw_tournament_players,nw_tournaments,nw_rooms,nw_players restart identity cascade");
        nowMs = START;
      }
      const { a, b, ma, mb, room, code, second } = await setupOpening(true);
      if (oneReady) await acknowledge(room,ma.token);
      nowMs = Date.parse(second.body.opening.deadline_at);
      const late = await acknowledge(room,mb.token);
      assert.equal(late.status,409);
      assert.equal(late.body.opening.expired,true);
      assert.equal(late.body.turn_started_at,null);
      assert.equal(late.body.result.winner,oneReady ? ma.seat : 0);
      const t = (await pollT(code,a)).body;
      const original = t.rounds[0][1];
      assert.equal(original.status,"done");
      assert.equal(original.end_reason,"no_show");
      assert.equal(original.winner,oneReady ? "a" : original.a.seed < original.b.seed ? "a" : "b");
      assert.deepEqual(await record(a),[0,0,0]);
      assert.deepEqual(await record(b),[0,0,0]);
    }
  });

  it("one legacy tournament client keeps the existing arrival-based clock", async () => {
    const { second } = await setupOpening(false);
    assert.equal(second.body.opening,undefined);
    assert.equal(second.body.turn_started_at,new Date(nowMs).toISOString());
  });
});
