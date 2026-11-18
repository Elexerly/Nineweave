/**
 * Nineweave online API tests. Requests go through the real HTTP handler
 * (`handleNineweaveRequest`) backed by an in-memory PGlite with
 * `migrations/*.sql` applied — never a remote database.
 */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import { DRAW_GAME_X_MORE_BOARDS, X_WIN_GAME } from "./fixtures.ts";
import { canonicalHero } from "./heroes.ts";
import { runCleanup } from "./rooms.ts";

const MIGRATIONS = join(import.meta.dirname, "..", "..", "..", "migrations");
const START = Date.parse("2026-11-15T12:00:00Z");

let pg: PGlite;
let svc: Service;
let nowMs = START;
let nextRandom = 0.1; // < 0.5 -> host (slot a) is X

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
    "truncate nw_reports, nw_blocks, nw_chat, nw_matches, nw_rooms, nw_players restart identity cascade",
  );
  nowMs = START;
  nextRandom = 0.1;
  svc = createService({
    db: pgliteDb(pg),
    now: () => new Date(nowMs),
    random: () => nextRandom,
    cleanupIntervalMs: 0,
    limits: { device: 1000, create: 1000, join: 1000, move: 10_000, write: 1000 },
  });
});

interface Res {
  status: number;
  body: Record<string, any>;
  headers: Headers;
}

async function call(
  method: string,
  path: string,
  opts: { body?: unknown; token?: string | null; headers?: Record<string, string> } = {},
): Promise<Res> {
  const headers: Record<string, string> = { ...opts.headers };
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  const res = await handleNineweaveRequest(
    svc,
    new Request(`http://localhost/api/nineweave${path}`, {
      method,
      headers,
      body:
        opts.body === undefined
          ? undefined
          : typeof opts.body === "string"
            ? opts.body
            : JSON.stringify(opts.body),
    }),
  );
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : {}, headers: res.headers };
}

async function device(screen_name?: string) {
  const res = await call("POST", "/auth/device", { body: screen_name ? { screen_name } : {} });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body as { token: string; player_id: string; player: Record<string, any> };
}

async function me(token: string) {
  const res = await call("GET", "/me", { token });
  assert.equal(res.status, 200);
  return res.body;
}

/** Create + join a public room. Host is X unless `nextRandom >= 0.5`. */
async function startMatch(hostDevice?: string, guestDevice?: string) {
  const created = await call("POST", "/rooms", {
    body: { name: "Host", character_id: "vesper_vale" },
    token: hostDevice,
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const joined = await call("POST", `/rooms/${created.body.code}/join`, {
    body: { name: "Guest", character_id: "auric_rex" },
    token: guestDevice,
  });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  return { code: created.body.code as string, host: created.body, guest: joined.body };
}

/** Play `moves` alternately from whichever player holds seat 1 (X). */
async function playMoves(
  code: string,
  xToken: string,
  oToken: string,
  moves: [number, number][],
  startSeq = 0,
) {
  let last: Res | null = null;
  for (let i = 0; i < moves.length; i += 1) {
    const [board, cell] = moves[i];
    const token = (startSeq + i) % 2 === 0 ? xToken : oToken;
    last = await call("POST", `/rooms/${code}/moves`, {
      body: { board, cell, seq: startSeq + i + 1, token },
    });
    assert.equal(last.status, 200, `move ${i + 1}: ${JSON.stringify(last.body)}`);
  }
  return last!;
}

describe("device auth and profile", () => {
  it("registers a device, returns the token once and stores only its hash", async () => {
    const d = await device();
    assert.match(d.token, /^nwd_/);
    assert.match(d.player_id, /^p_/);
    assert.equal(d.player.screen_name, null);
    assert.deepEqual(d.player.purchases, []);
    const rows = (await pg.query<{ token_hash: string }>("select token_hash from nw_players")).rows;
    assert.equal(rows.length, 1);
    assert.notEqual(rows[0].token_hash, d.token);
    assert.match(rows[0].token_hash, /^[0-9a-f]{64}$/);
    const profile = await me(d.token);
    assert.equal(profile.player_id, d.player_id);
    assert.equal((await call("GET", "/me")).status, 401);
    assert.equal((await call("GET", "/me", { token: "nwd_bogus" })).status, 401);
  });

  it("enforces unique, clean screen names and persists profile fields", async () => {
    const a = await device();
    const ok = await call("PATCH", "/me", {
      token: a.token,
      body: { screen_name: "  Patrick   B ", last_hero_id: "erik_comet" },
    });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.screen_name, "Patrick B");
    assert.equal(ok.body.last_hero_id, "erick_comet", "alias canonicalized");

    const b = await device();
    const dup = await call("PATCH", "/me", { token: b.token, body: { screen_name: "patrick b" } });
    assert.equal(dup.status, 409);
    assert.match(dup.body.error, /taken/);

    for (const bad of ["", "   ", "x".repeat(25), "sh1thead", "F.U.C.K", "<script>"]) {
      const res = await call("PATCH", "/me", { token: b.token, body: { screen_name: bad } });
      assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(bad)}`);
      assert.equal(typeof res.body.error, "string");
    }
    // Ordinary names that contain blocked fragments are allowed.
    for (const fine of ["Cassandra", "The Therapist", "Spicy Peacock"]) {
      const res = await call("PATCH", "/me", { token: b.token, body: { screen_name: fine } });
      assert.equal(res.status, 200, `${fine}: ${JSON.stringify(res.body)}`);
    }
    assert.equal(
      (await call("PATCH", "/me", { token: b.token, body: { last_hero_id: "nobody" } })).status,
      400,
    );
    assert.equal((await call("PATCH", "/me", { token: b.token, body: { wins: 99 } })).status, 400);

    const pu = await call("PATCH", "/me", {
      token: b.token,
      body: { purchases: ["hero_pack_1"], unlocks: ["cryon", "cryon"] },
    });
    assert.equal(pu.status, 200);
    assert.deepEqual(pu.body.purchases, ["hero_pack_1"]);
    assert.deepEqual(pu.body.unlocks, ["cryon"]);
  });

  it("can register with a screen name in one call", async () => {
    const d = await device("Ada");
    assert.equal(d.player.screen_name, "Ada");
    const clash = await call("POST", "/auth/device", { body: { screen_name: "ADA" } });
    assert.equal(clash.status, 409);
    assert.equal(
      (await pg.query("select 1 from nw_players")).rows.length,
      1,
      "no orphan player on conflict",
    );
  });

  it("stores consent on PATCH /me and on registration", async () => {
    const a = await device();
    assert.equal(a.player.tos_version, null);
    assert.equal(a.player.privacy_version, null);
    assert.equal(a.player.accepted_at, null);
    assert.equal(a.player.age_confirmed, null);

    const acceptedAt = "2026-11-15T12:00:00.000Z";
    const ok = await call("PATCH", "/me", {
      token: a.token,
      body: {
        tos_version: "2026-11-15",
        privacy_version: "2026-11-15",
        accepted_at: acceptedAt,
        age_confirmed: true,
      },
    });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.tos_version, "2026-11-15");
    assert.equal(ok.body.privacy_version, "2026-11-15");
    assert.equal(ok.body.accepted_at, acceptedAt);
    assert.equal(ok.body.age_confirmed, true);
    const stored = await me(a.token);
    assert.equal(stored.tos_version, "2026-11-15");
    assert.equal(stored.age_confirmed, true);
    const row = (
      await pg.query<{ tos_version: string; age_confirmed: boolean }>(
        "select tos_version, age_confirmed from nw_players where id = $1",
        [a.player_id],
      )
    ).rows[0];
    assert.equal(row.tos_version, "2026-11-15");
    assert.equal(row.age_confirmed, true);

    const registered = await call("POST", "/auth/device", {
      body: {
        screen_name: "Consented",
        tos_version: "2026-11-15",
        privacy_version: "2026-11-15",
        accepted_at: acceptedAt,
        age_confirmed: true,
      },
    });
    assert.equal(registered.status, 201, JSON.stringify(registered.body));
    assert.equal(registered.body.player.tos_version, "2026-11-15");
    assert.equal(registered.body.player.privacy_version, "2026-11-15");
    assert.equal(registered.body.player.accepted_at, acceptedAt);
    assert.equal(registered.body.player.age_confirmed, true);

    const missingAt = await call("PATCH", "/me", {
      token: a.token,
      body: { tos_version: "2026-11-15", privacy_version: "2026-11-15", age_confirmed: true },
    });
    assert.equal(missingAt.status, 200, JSON.stringify(missingAt.body));
    assert.equal(typeof missingAt.body.accepted_at, "string");
    assert.ok(Date.parse(missingAt.body.accepted_at));

    assert.equal(
      (await call("PATCH", "/me", { token: a.token, body: { tos_version: "not a version!" } }))
        .status,
      400,
    );
    assert.equal(
      (await call("PATCH", "/me", { token: a.token, body: { accepted_at: "Tuesday" } })).status,
      400,
    );
    assert.equal(
      (await call("PATCH", "/me", { token: a.token, body: { age_confirmed: "yes" } })).status,
      400,
    );
    assert.equal(
      (await call("PATCH", "/me", { token: a.token, body: { consent: true } })).status,
      400,
    );
  });
});

describe("lobby", () => {
  it("creates a public room, lists it without secrets, and joins", async () => {
    const created = await call("POST", "/rooms", {
      body: { name: "Patrick", character_id: "vesper_vale" },
    });
    assert.equal(created.status, 201);
    const c = created.body;
    assert.match(c.code, /^[A-Z0-9]{5}$/);
    assert.match(c.token, /^nws_/);
    assert.equal(c.seat, 1);
    assert.equal(c.seq, 0);
    assert.equal(c.status, "waiting");
    assert.equal(c.opponent, "");
    assert.deepEqual(c.state, {
      v: 1,
      cells: ".".repeat(81),
      turn: 1,
      active: -1,
      history: [],
      redo: [],
    });
    assert.deepEqual(c.characters, { "1": "vesper_vale" });
    assert.deepEqual(c.match, { round: 1, seat: 1, local: false, remote: false });

    const list = await call("GET", "/rooms");
    assert.equal(list.status, 200);
    assert.equal(list.body.rooms.length, 1);
    assert.deepEqual(Object.keys(list.body.rooms[0]).sort(), [
      "code",
      "created_at",
      "host_hero",
      "host_name",
    ]);
    assert.equal(list.body.rooms[0].host_name, "Patrick");
    assert.ok(!JSON.stringify(list.body).includes("token"));
    assert.equal((await call("GET", "/lobby")).body.rooms.length, 1);

    const joined = await call("POST", `/rooms/${c.code.toLowerCase()}/join`, {
      body: { name: "Friend", character_id: "mateo_ricochet" },
    });
    assert.equal(joined.status, 200);
    assert.equal(joined.body.seat, 2);
    assert.equal(joined.body.opponent, "Patrick");
    assert.equal(joined.body.status, "active");
    assert.notEqual(joined.body.token, c.token);
    assert.deepEqual(joined.body.characters, { "1": "vesper_vale", "2": "ethan_ricochet" });

    assert.equal((await call("GET", "/rooms")).body.rooms.length, 0, "full rooms leave the lobby");
    const third = await call("POST", `/rooms/${c.code}/join`, { body: { name: "Third" } });
    assert.equal(third.status, 409);
    assert.equal((await call("POST", "/rooms/ZZZZZ/join", { body: { name: "X" } })).status, 404);

    const poll = await call("GET", `/rooms/${c.code}?since=0`, { token: c.token });
    assert.equal(poll.status, 200);
    assert.equal(poll.body.opponent, "Friend");
    assert.equal(poll.body.opponent_left, false);
    assert.equal(poll.headers.get("cache-control"), "no-store");
    assert.ok(!JSON.stringify(poll.body).includes("hash"));
  });

  it("randomly assigns X/O on the first match", async () => {
    nextRandom = 0.9;
    const { host, guest } = await startMatch();
    assert.equal(host.seat, 2);
    assert.equal(guest.seat, 1);
    assert.deepEqual(guest.characters, { "2": "vesper_vale", "1": "auric_rex" });
  });

  it("validates character ids and defaults to the legacy hero", async () => {
    assert.equal(
      (await call("POST", "/rooms", { body: { name: "A", character_id: "ghost" } })).status,
      400,
    );
    const res = await call("POST", "/rooms", { body: { name: "A" } });
    assert.deepEqual(res.body.characters, { "1": "auric_rex" });
  });

  it("hides private rooms and requires the password", async () => {
    const created = await call("POST", "/rooms", {
      body: { name: "Pat", private: true, password: "hunter2" },
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.private, true);
    assert.equal((await call("GET", "/rooms")).body.rooms.length, 0);
    const stored = (await pg.query<{ password_hash: string }>("select password_hash from nw_rooms"))
      .rows[0];
    assert.match(stored.password_hash, /^scrypt\$/);
    assert.ok(!stored.password_hash.includes("hunter2"));

    const code = created.body.code;
    assert.equal((await call("POST", `/rooms/${code}/join`, { body: { name: "F" } })).status, 403);
    assert.equal(
      (await call("POST", `/rooms/${code}/join`, { body: { name: "F", password: "nope" } })).status,
      403,
    );
    const ok = await call("POST", `/rooms/${code}/join`, {
      body: { name: "F", password: "hunter2" },
    });
    assert.equal(ok.status, 200);
    assert.equal(
      (await call("POST", "/rooms", { body: { private: true } })).status,
      400,
      "private needs a password",
    );
  });

  it("lets the host cancel a waiting room", async () => {
    const created = await call("POST", "/rooms", { body: { name: "A" } });
    const res = await call("POST", `/rooms/${created.body.code}/cancel`, {
      token: created.body.token,
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.status, "closed");
    assert.equal(res.body.end_reason, "cancelled");
    assert.equal((await call("GET", "/rooms")).body.rooms.length, 0);
    assert.equal(
      (await call("POST", `/rooms/${created.body.code}/join`, { body: {} })).status,
      404,
    );
  });

  it("expires waiting rooms after 10 idle minutes, but not while the host polls", async () => {
    const idle = await call("POST", "/rooms", { body: { name: "Idle" } });
    const active = await call("POST", "/rooms", { body: { name: "Active" } });
    for (let t = 1; t <= 6; t += 1) {
      nowMs = START + t * 120_000; // poll every 2 minutes for 12 minutes
      assert.equal(
        (await call("GET", `/rooms/${active.body.code}`, { token: active.body.token })).status,
        200,
      );
    }
    const list = await call("GET", "/rooms");
    assert.deepEqual(
      list.body.rooms.map((r: any) => r.code),
      [active.body.code],
    );
    const stale = await call("GET", `/rooms/${idle.body.code}`, { token: idle.body.token });
    assert.equal(stale.body.status, "closed");
    assert.equal(stale.body.end_reason, "expired");
  });

  it("rejects bad auth and malformed requests", async () => {
    const { code } = await startMatch();
    assert.equal((await call("GET", `/rooms/${code}`)).status, 401);
    assert.equal((await call("GET", `/rooms/${code}`, { token: "nws_wrong" })).status, 403);
    assert.equal((await call("GET", "/rooms/ABCDE", { token: "nws_wrong" })).status, 404);
    assert.equal((await call("POST", "/rooms", { body: "{nope" })).status, 400);
    assert.equal((await call("POST", "/rooms", { body: { name: "x".repeat(9000) } })).status, 413);
    assert.equal((await call("DELETE", "/rooms")).status, 405);
    assert.equal((await call("GET", "/nothing")).status, 404);
  });
});

describe("authoritative play", () => {
  it("plays a full game to a win and updates records only at match end", async () => {
    const hostDev = await device("Host Hero");
    const guestDev = await device("Guest Star");
    const { code, host, guest } = await startMatch(hostDev.token, guestDev.token);
    assert.equal(host.opponent, "", "nobody had joined yet when the host created");
    assert.equal(guest.opponent, "Host Hero", "stored screen name wins over body name");
    assert.equal((await me(hostDev.token)).last_hero_id, "vesper_vale", "hero remembered");

    const xToken = host.seat === 1 ? host.token : guest.token;
    const oToken = host.seat === 1 ? guest.token : host.token;

    await playMoves(code, xToken, oToken, X_WIN_GAME.slice(0, 20));
    for (const tok of [hostDev.token, guestDev.token]) {
      const p = await me(tok);
      assert.equal(p.matches_played, 0, "no record change mid-match");
    }
    const lb0 = await call("GET", "/leaderboard");
    assert.equal(lb0.body.players.length, 0);

    // Poll shows moves after `since`, sorted.
    const poll = await call("GET", `/rooms/${code}?since=18`, { token: oToken });
    assert.deepEqual(
      poll.body.moves.map((m: any) => m.seq),
      [19, 20],
    );
    assert.deepEqual(poll.body.moves[0], {
      board: X_WIN_GAME[18][0],
      cell: X_WIN_GAME[18][1],
      seq: 19,
    });
    assert.equal(poll.body.seq, 20);
    assert.equal(poll.body.state.history.length, 20);

    const [b, c] = X_WIN_GAME[20];
    const last = await call("POST", `/rooms/${code}/moves`, {
      body: { board: b, cell: c, seq: 21, token: xToken },
    });
    assert.equal(last.status, 200);
    assert.deepEqual(last.body.moves, [{ board: b, cell: c, seq: 21 }]);
    assert.equal(last.body.status, "finished");
    assert.deepEqual(last.body.result, { winner: 1, reason: "win" });

    const hostMe = await me(hostDev.token);
    const guestMe = await me(guestDev.token);
    assert.equal(hostMe.matches_won, 1);
    assert.equal(hostMe.matches_played, 1);
    assert.equal(hostMe.matches_lost, 0);
    assert.ok(hostMe.boards_won >= 3);
    assert.equal(guestMe.matches_won, 0);
    assert.equal(guestMe.matches_lost, 1);
    assert.equal(guestMe.matches_played, 1);

    const lb = await call("GET", "/leaderboard", { token: guestDev.token });
    assert.deepEqual(
      lb.body.players.map((p: any) => [p.rank, p.screen_name, p.matches_won, p.matches_played]),
      [
        [1, "Host Hero", 1, 1],
        [2, "Guest Star", 0, 1],
      ],
    );
    assert.ok(!("boards_won" in lb.body.players[0]));
    assert.equal(lb.body.me.screen_name, "Guest Star");
    assert.equal(lb.body.me.rank, 2);
    assert.equal(typeof lb.body.me.boards_won, "number");
    assert.equal(lb.body.me.last_hero_id, "auric_rex");

    const after = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 0, cell: 0, seq: 22, token: oToken },
    });
    assert.equal(after.status, 422);
    const log = (
      await pg.query<{ result: string; end_reason: string }>(
        "select result, end_reason from nw_matches",
      )
    ).rows;
    assert.deepEqual(log, [{ result: "x", end_reason: "win" }]);
  });

  it("records a draw as played-only, with no board-count tiebreak", async () => {
    const hostDev = await device("Drawer One");
    const guestDev = await device("Drawer Two");
    const { code, host, guest } = await startMatch(hostDev.token, guestDev.token);
    const last = await playMoves(code, host.token, guest.token, DRAW_GAME_X_MORE_BOARDS);
    assert.equal(last.body.status, "finished");
    assert.deepEqual(last.body.result, { winner: 0, reason: "draw" });
    const h = await me(hostDev.token);
    const g = await me(guestDev.token);
    assert.deepEqual([h.matches_won, h.matches_lost, h.matches_played, h.boards_won], [0, 0, 1, 5]);
    assert.deepEqual([g.matches_won, g.matches_lost, g.matches_played, g.boards_won], [0, 0, 1, 4]);
  });

  it("makes move retries idempotent and rejects stale, future, wrong-seat and illegal moves", async () => {
    const { code, host, guest } = await startMatch();
    const first = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 0, seq: 1, token: host.token },
    });
    assert.equal(first.status, 200);
    assert.equal(first.body.seq, 1);

    const retry = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 0, seq: 1, token: host.token },
    });
    assert.equal(retry.status, 200);
    assert.deepEqual(retry.body.moves, first.body.moves);
    assert.deepEqual(retry.body.state, first.body.state);
    assert.equal((await pg.query("select state from nw_rooms")).rows.length, 1);

    // Bearer header is accepted as the seat credential too.
    const o1 = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 0, cell: 4, seq: 2 },
      token: guest.token,
    });
    assert.equal(o1.status, 200);

    // Retry of seq 1 after the game moved on still returns the original ack.
    const late = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 0, seq: 1, token: host.token },
    });
    assert.equal(late.status, 200);
    assert.equal(late.body.seq, 1);
    assert.equal(late.body.state.history.length, 1);

    const stale = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 1, seq: 2, token: host.token },
    });
    assert.equal(stale.status, 409);
    assert.equal(stale.body.seq, 2, "conflicts carry the current snapshot");
    assert.equal(stale.body.state.history.length, 2);

    const future = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 1, seq: 5, token: host.token },
    });
    assert.equal(future.status, 409);

    const wrongSeat = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 1, seq: 3, token: guest.token },
    });
    assert.equal(wrongSeat.status, 403);

    const illegal = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 3, cell: 0, seq: 3, token: host.token },
    });
    assert.equal(illegal.status, 422);
    assert.equal(illegal.body.error, "Choose an empty cell in the active board");
    const occupied = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 0, seq: 3, token: host.token },
    });
    assert.equal(occupied.status, 422);

    const badToken = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 1, seq: 3, token: "nws_nope" },
    });
    assert.equal(badToken.status, 403);
    const badBody = await call("POST", `/rooms/${code}/moves`, {
      body: { board: "4", cell: 1, seq: 3, token: host.token },
    });
    assert.equal(badBody.status, 400);
  });

  it("serializes concurrent duplicate moves into one accepted move", async () => {
    const { code, host } = await startMatch();
    const body = { board: 4, cell: 4, seq: 1, token: host.token };
    const results = await Promise.all(
      [1, 2, 3].map(() => call("POST", `/rooms/${code}/moves`, { body })),
    );
    assert.deepEqual(
      results.map((r) => r.status),
      [200, 200, 200],
    );
    const state = (await pg.query<{ state: { history: unknown[] } }>("select state from nw_rooms"))
      .rows[0].state;
    assert.equal(state.history.length, 1);
  });

  it("refuses moves before the opponent joins", async () => {
    const created = await call("POST", "/rooms", { body: { name: "Solo" } });
    const res = await call("POST", `/rooms/${created.body.code}/moves`, {
      body: { board: 0, cell: 0, seq: 1, token: created.body.token },
    });
    assert.equal(res.status, 409);
  });
});

describe("rematch", () => {
  it("requires both players, is idempotent, swaps seats and resets state", async () => {
    const { code, host, guest } = await startMatch();
    assert.equal(host.seat, 1);

    // Ignored during a live game.
    const early = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: host.token },
    });
    assert.equal(early.status, 200);
    assert.equal(early.body.ignored, true);
    assert.equal(early.body.match.local, false);

    await playMoves(code, host.token, guest.token, X_WIN_GAME);

    const a = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: host.token },
    });
    assert.equal(a.status, 200);
    assert.deepEqual(a.body.match, { round: 1, seat: 1, local: true, remote: false });
    const again = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: host.token },
    });
    assert.deepEqual(again.body.match, { round: 1, seat: 1, local: true, remote: false });

    const guestView = await call("GET", `/rooms/${code}?since=21`, { token: guest.token });
    assert.deepEqual(guestView.body.match, { round: 1, seat: 2, local: false, remote: true });

    const stale = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 0, token: guest.token },
    });
    assert.equal(stale.status, 409);

    const b = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: guest.token },
    });
    assert.equal(b.status, 200);
    assert.deepEqual(b.body.match, { round: 2, seat: 1, local: false, remote: false });
    assert.equal(b.body.seat, 1, "guest is now X");
    assert.equal(b.body.seq, 0);
    assert.equal(b.body.status, "active");
    assert.equal(b.body.state.cells, ".".repeat(81));
    assert.deepEqual(
      b.body.characters,
      { "1": "auric_rex", "2": "vesper_vale" },
      "heroes follow players",
    );
    assert.equal(b.body.opponent, "Host");

    const hostView = await call("GET", `/rooms/${code}?since=21`, { token: host.token });
    assert.deepEqual(hostView.body.match, { round: 2, seat: 2, local: false, remote: false });
    assert.deepEqual(hostView.body.moves, []);

    // New round: guest (X) moves first with seq 1; host can't.
    assert.equal(
      (
        await call("POST", `/rooms/${code}/moves`, {
          body: { board: 0, cell: 0, seq: 1, token: host.token },
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await call("POST", `/rooms/${code}/moves`, {
          body: { board: 0, cell: 0, seq: 1, token: guest.token },
        })
      ).status,
      200,
    );
    const oldRound = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: host.token },
    });
    assert.equal(oldRound.body.ignored, true, "live game: ignored");
  });

  it("is rejected after the opponent leaves", async () => {
    const { code, host, guest } = await startMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME);
    assert.equal((await call("POST", `/rooms/${code}/leave`, { token: guest.token })).status, 200);
    const res = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: host.token },
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.opponent_left, true);
  });
});

describe("forfeits and timeouts", () => {
  it("leaving an active match forfeits it to the opponent", async () => {
    const hostDev = await device("Quitter");
    const guestDev = await device("Stayer");
    const { code, host, guest } = await startMatch(hostDev.token, guestDev.token);
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 5));
    const left = await call("POST", `/rooms/${code}/leave`, { token: host.token });
    assert.equal(left.status, 200);
    assert.equal(left.body.status, "closed");

    const view = await call("GET", `/rooms/${code}`, { token: guest.token });
    assert.equal(view.body.opponent_left, true);
    assert.deepEqual(view.body.result, { winner: guest.seat, reason: "forfeit" });

    const q = await me(hostDev.token);
    const s = await me(guestDev.token);
    assert.deepEqual([q.matches_won, q.matches_lost, q.matches_played], [0, 1, 1]);
    assert.deepEqual([s.matches_won, s.matches_lost, s.matches_played], [1, 0, 1]);

    // Leaving again is a no-op; no double counting.
    assert.equal((await call("POST", `/rooms/${code}/leave`, { token: host.token })).status, 200);
    assert.equal((await me(guestDev.token)).matches_won, 1);
  });

  // Round 5 (online2): the 180 s turn timeout became 25 s + 10 s "Still
  // there?", and it only costs a match once both players have moved.
  it("forfeits the player due to move 35 s into a turn once both players moved", async () => {
    const hostDev = await device("Slowpoke");
    const guestDev = await device("Speedy");
    const { code, host, guest } = await startMatch(hostDev.token, guestDev.token);
    // X (host), O (guest), X move, then O (guest) stalls.
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 3));
    nowMs += 34_000;
    assert.equal(
      (await call("GET", `/rooms/${code}`, { token: host.token })).body.status,
      "active",
    );
    nowMs += 1_000;
    const view = await call("GET", `/rooms/${code}`, { token: host.token });
    assert.equal(view.body.status, "closed");
    assert.equal(view.body.opponent_left, true);
    assert.deepEqual(view.body.result, { winner: 1, reason: "timeout" });
    assert.equal((await me(hostDev.token)).matches_won, 1);
    assert.equal((await me(guestDev.token)).matches_lost, 1);
  });

  it("the global sweep resolves timeouts even when nobody polls the room", async () => {
    const hostDev = await device("Ghost");
    const { code, host, guest } = await startMatch(hostDev.token);
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2)); // both moved
    nowMs += 200_000;
    await runCleanup(svc, true);
    const row = (
      await pg.query<{ status: string; end_reason: string }>(
        "select status, end_reason from nw_rooms where code = $1",
        [code],
      )
    ).rows[0];
    assert.deepEqual(row, { status: "closed", end_reason: "timeout" });
    assert.equal((await me(hostDev.token)).matches_lost, 1, "host was X and due to move");
  });
});

describe("CORS and limits", () => {
  it("answers preflight for allowed origins only", async () => {
    const ok = await call("OPTIONS", "/rooms", {
      headers: { Origin: "https://elexerly.github.io" },
    });
    assert.equal(ok.status, 204);
    assert.equal(ok.headers.get("access-control-allow-origin"), "https://elexerly.github.io");
    assert.equal(ok.headers.get("access-control-allow-headers"), "Authorization, Content-Type");
    assert.equal(
      ok.headers.get("access-control-allow-methods"),
      "GET, POST, PATCH, DELETE, OPTIONS",
    );
    assert.equal(ok.headers.get("access-control-allow-credentials"), null);
    for (const origin of [
      "https://nineweave.grok.me",
      "http://localhost:8060",
      "http://127.0.0.1:8080",
    ]) {
      const r = await call("GET", "/health", { headers: { Origin: origin } });
      assert.equal(r.headers.get("access-control-allow-origin"), origin);
    }
    const evil = await call("OPTIONS", "/rooms", { headers: { Origin: "https://evil.example" } });
    assert.equal(evil.headers.get("access-control-allow-origin"), null);
  });

  it("allows the Sitebloc origin on preflight and errors, and rejects lookalikes", async () => {
    const origin = "https://nineweave.sitebloc.com";
    const preflight = await call("OPTIONS", "/auth/device", {
      headers: {
        Origin: origin,
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization, content-type",
      },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get("access-control-allow-origin"), origin);
    assert.equal(preflight.headers.get("access-control-allow-headers"), "Authorization, Content-Type");
    assert.equal(
      preflight.headers.get("access-control-allow-methods"),
      "GET, POST, PATCH, DELETE, OPTIONS",
    );
    assert.equal(preflight.headers.get("access-control-allow-credentials"), null);

    const missing = await call("GET", "/me", { headers: { Origin: origin } });
    assert.equal(missing.status, 401);
    assert.equal(missing.headers.get("access-control-allow-origin"), origin);
    assert.equal(typeof missing.body.error, "string");

    for (const fake of [
      "https://nineweave.sitebloc.com.evil.example",
      "https://evil.nineweave.sitebloc.com",
      "https://www.nineweave.sitebloc.com",
      "http://nineweave.sitebloc.com",
      "https://nineweave.sitebloc.co",
      "https://nineweavesitebloc.com",
      "*",
    ]) {
      const blocked = await call("OPTIONS", "/auth/device", { headers: { Origin: fake } });
      assert.equal(blocked.headers.get("access-control-allow-origin"), null, fake);
      const blockedError = await call("GET", "/me", { headers: { Origin: fake } });
      assert.equal(blockedError.status, 401, fake);
      assert.equal(blockedError.headers.get("access-control-allow-origin"), null, fake);
    }
  });

  it("rate-limits room creation per client", async () => {
    svc = createService({ db: pgliteDb(pg), now: () => new Date(nowMs), limits: { create: 2 } });
    const hdr = { "X-Forwarded-For": "203.0.113.9" };
    assert.equal((await call("POST", "/rooms", { body: {}, headers: hdr })).status, 201);
    assert.equal((await call("POST", "/rooms", { body: {}, headers: hdr })).status, 201);
    const third = await call("POST", "/rooms", { body: {}, headers: hdr });
    assert.equal(third.status, 429);
    assert.equal(typeof third.body.error, "string");
  });
});


describe("Patrick Laquin hero compatibility", () => {
  it("accepts Patrick and canonicalizes legacy Kite profile choices", async () => {
    const d = await device("PatrickTest");
    for (const id of ["patrick_laquin", "kite_hollow"]) {
      const res = await call("PATCH", "/me", { token: d.token, body: { last_hero_id: id } });
      assert.equal(res.status, 200, JSON.stringify(res.body));
      assert.equal(res.body.last_hero_id, "patrick_laquin");
      assert.equal((await me(d.token)).last_hero_id, "patrick_laquin");
    }
  });

  it("accepts Patrick rooms and old Kite joins without losing either character", async () => {
    const created = await call("POST", "/rooms", { body: { name: "Patrick", character_id: "patrick_laquin" } });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const joined = await call("POST", `/rooms/${created.body.code}/join`, { body: { name: "Legacy", character_id: "kite_hollow" } });
    assert.equal(joined.status, 200, JSON.stringify(joined.body));
    assert.deepEqual(joined.body.characters, { "1": "patrick_laquin", "2": "patrick_laquin" });
  });
});


describe("pre-upgrade persisted Kite records", () => {
  it("loads old selected hero and an existing match without rewriting identities", async () => {
    const d = await device("OldKite");
    await pg.query("update nw_players set last_hero_id = 'kite_hollow' where id = $1", [d.player_id]);
    const profile = await me(d.token);
    assert.equal(profile.player_id, d.player_id);
    assert.equal(canonicalHero(profile.last_hero_id), "patrick_laquin");
    const match = await startMatch(d.token);
    await pg.query("update nw_rooms set a_hero = 'kite_hollow' where code = $1", [match.code]);
    const view = await call("GET", `/rooms/${match.code}`, { token: match.host.token });
    assert.equal(view.status, 200, JSON.stringify(view.body));
    assert.equal(canonicalHero(view.body.characters["1"]), "patrick_laquin");
    assert.equal(view.body.characters["2"], "auric_rex");
    assert.equal(view.body.code, match.code);
  });
});
