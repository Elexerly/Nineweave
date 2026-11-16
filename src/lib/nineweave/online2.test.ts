/**
 * Nineweave online2 (round 5) tests: turn clock + "Still there?", no-show /
 * abandoned / forfeit rules, envelope additions, capabilities, chat, blocks,
 * reports and retention. Requests go through the real HTTP handler backed by
 * an in-memory PGlite with `migrations/*.sql` applied — never a remote
 * database.
 */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import { X_WIN_GAME } from "./fixtures.ts";
import { runCleanup } from "./rooms.ts";

const MIGRATIONS = join(import.meta.dirname, "..", "..", "..", "migrations");
const START = Date.parse("2026-11-15T12:00:00Z");
const at = (offsetMs: number) => new Date(START + offsetMs).toISOString();

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
    "truncate nw_reports, nw_blocks, nw_chat, nw_email_challenges, nw_matches, nw_rooms, nw_players restart identity cascade",
  );
  nowMs = START;
  svc = createService({
    db: pgliteDb(pg),
    now: () => new Date(nowMs),
    random: () => 0.1, // host (slot a) is X on the first match
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
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    }),
  );
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : {}, headers: res.headers };
}

async function device(screen_name?: string) {
  const res = await call("POST", "/auth/device", { body: screen_name ? { screen_name } : {} });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body as { token: string; player_id: string };
}

async function me(token: string) {
  return (await call("GET", "/me", { token })).body;
}

async function record(token: string) {
  const p = await me(token);
  return [p.matches_won, p.matches_lost, p.matches_played];
}

/** Create + join a public room; the host is X (seat 1). */
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
  return {
    code: created.body.code as string,
    host: created.body as Record<string, any>,
    guest: joined.body as Record<string, any>,
  };
}

/** Two named device players in an active match. */
async function namedMatch(hostName = "NightNight", guestName = "DayDay") {
  const hostDev = await device(hostName);
  const guestDev = await device(guestName);
  const m = await startMatch(hostDev.token, guestDev.token);
  return { ...m, hostDev, guestDev };
}

async function move(code: string, token: string, seq: number, [board, cell]: [number, number]) {
  return call("POST", `/rooms/${code}/moves`, { body: { board, cell, seq, token } });
}

/** Play moves alternating X (host) / O (guest), starting after `startSeq`. */
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

const poll = (code: string, token: string, query = "") =>
  call("GET", `/rooms/${code}${query}`, { token });
const stillHere = (code: string, token: string) =>
  call("POST", `/rooms/${code}/still-here`, { token });
const chat = (code: string, token: string, body: Record<string, unknown>) =>
  call("POST", `/rooms/${code}/chat`, { token, body });

async function matchRows() {
  return (await pg.query<{ end_reason: string }>("select end_reason from nw_matches")).rows;
}

// ---------------------------------------------------------------------------

describe("both_moved and pre-match cancellation", () => {
  it("both_moved turns true only after each seat has moved this round", async () => {
    const { code, host, guest } = await startMatch();
    assert.equal(guest.both_moved, false);
    const first = await move(code, host.token, 1, X_WIN_GAME[0]);
    assert.equal(first.body.both_moved, false);
    const second = await move(code, guest.token, 2, X_WIN_GAME[1]);
    assert.equal(second.body.both_moved, true);
    assert.equal((await poll(code, host.token)).body.both_moved, true);
  });

  it("leaving before both moved cancels with no records", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch();
    await move(code, host.token, 1, X_WIN_GAME[0]);
    const left = await call("POST", `/rooms/${code}/leave`, { token: guest.token });
    assert.equal(left.status, 200);
    assert.equal(left.body.status, "closed");
    assert.equal(left.body.end_reason, "cancelled");
    const view = await poll(code, host.token);
    assert.equal(view.body.opponent_left, true);
    assert.equal(view.body.result, null);
    assert.equal(view.body.end_reason, "cancelled");
    assert.equal(view.body.poll_after_ms, 0, "closed: stop polling");
    assert.deepEqual(await record(hostDev.token), [0, 0, 0]);
    assert.deepEqual(await record(guestDev.token), [0, 0, 0]);
    assert.equal((await matchRows()).length, 0);
  });

  it("a first-turn no-show after 35 s cancels with no records", async () => {
    const { code, guest, hostDev, guestDev } = await namedMatch();
    nowMs = START + 34_999;
    assert.equal((await poll(code, guest.token)).body.status, "active");
    nowMs = START + 35_000;
    const view = await poll(code, guest.token);
    assert.equal(view.body.status, "closed");
    assert.equal(view.body.end_reason, "no_show");
    assert.equal(view.body.result, null);
    assert.equal(view.body.opponent_left, true);
    assert.deepEqual(await record(hostDev.token), [0, 0, 0]);
    assert.deepEqual(await record(guestDev.token), [0, 0, 0]);
    assert.equal((await matchRows()).length, 0);
  });

  it("O's no-show after X's first move is also a no-show", async () => {
    const { code, host, hostDev } = await namedMatch();
    await move(code, host.token, 1, X_WIN_GAME[0]);
    nowMs = START + 36_000;
    await runCleanup(svc, true);
    const view = await poll(code, host.token);
    assert.equal(view.body.end_reason, "no_show");
    assert.deepEqual(await record(hostDev.token), [0, 0, 0]);
  });
});

describe("turn clock", () => {
  it("exposes the clock fields and server_now", async () => {
    const { code, host, guest } = await startMatch();
    for (const env of [guest, (await poll(code, host.token)).body]) {
      assert.equal(env.protocol, 2);
      assert.equal(env.server_now, at(0));
      assert.equal(env.turn_started_at, at(0));
      assert.equal(env.still_there_at, at(25_000));
      assert.equal(env.turn_expires_at, at(35_000));
      assert.equal(env.still_here_used, false);
      assert.equal(env.turn_seconds, 25);
      assert.equal(env.still_there_seconds, 10);
      assert.equal(env.grace_seconds, 60);
    }
    nowMs = START + 5_000;
    const moved = await move(code, host.token, 1, X_WIN_GAME[0]);
    assert.equal(moved.body.turn_started_at, at(5_000));
    assert.equal(moved.body.still_there_at, at(30_000));
    assert.equal(moved.body.turn_expires_at, at(40_000));
    assert.equal(moved.body.server_now, at(5_000));

    const waiting = await call("POST", "/rooms", { body: {} });
    assert.equal(waiting.body.turn_expires_at, null);
    assert.equal(waiting.body.still_there_at, null);
    assert.equal(waiting.body.turn_started_at, null);
  });

  it("a move at 34 s is accepted", async () => {
    const { code, host, guest } = await startMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2));
    nowMs = START + 34_000;
    const res = await move(code, host.token, 3, X_WIN_GAME[2]);
    assert.equal(res.status, 200);
    assert.equal(res.body.status, "active");
  });

  it("after both moved, a 35 s expiry is a recorded timeout loss", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2));
    nowMs = START + 35_000;
    const view = await poll(code, guest.token);
    assert.equal(view.body.status, "closed");
    assert.deepEqual(view.body.result, { winner: 2, reason: "timeout" });
    assert.equal(view.body.opponent_left, true);
    assert.deepEqual(await record(hostDev.token), [0, 1, 1]);
    assert.deepEqual(await record(guestDev.token), [1, 0, 1]);
    assert.equal((await matchRows())[0].end_reason, "timeout");
  });

  it("still-here inside the window restarts the clock once; a second confirm is 409", async () => {
    const { code, host, guest } = await startMatch();
    nowMs = START + 10_000;
    const early = await stillHere(code, host.token);
    assert.equal(early.status, 409, "before the prompt is showing");
    assert.equal(early.body.turn_expires_at, at(35_000), "error carries the envelope");

    nowMs = START + 20_000;
    await poll(code, guest.token); // the idle seat keeps polling
    nowMs = START + 26_000;
    const wrongSeat = await stillHere(code, guest.token);
    assert.equal(wrongSeat.status, 403);

    const ok = await stillHere(code, host.token);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.ok, true);
    assert.equal(ok.body.still_here_used, true);
    assert.equal(ok.body.turn_started_at, at(26_000));
    assert.equal(ok.body.still_there_at, at(51_000));
    assert.equal(ok.body.turn_expires_at, at(61_000));

    nowMs = START + 40_000;
    await poll(code, guest.token);
    nowMs = START + 52_000;
    const again = await stillHere(code, host.token);
    assert.equal(again.status, 409);
    assert.equal(again.body.turn_expires_at, at(61_000), "no extension");

    nowMs = START + 60_999;
    assert.equal((await poll(code, guest.token)).body.status, "active");
    nowMs = START + 61_000;
    const expired = await poll(code, guest.token);
    assert.equal(expired.body.status, "closed");
    assert.equal(expired.body.end_reason, "no_show");
  });

  it("still-here after expiry or in a non-active room is rejected; a move resets the allowance", async () => {
    const { code, host, guest } = await startMatch();
    nowMs = START + 26_000;
    assert.equal((await stillHere(code, host.token)).status, 200);
    nowMs = START + 30_000;
    const moved = await move(code, host.token, 1, X_WIN_GAME[0]);
    assert.equal(moved.body.still_here_used, false, "the next turn gets its own confirm");
    nowMs = START + 56_000;
    const guestConfirm = await stillHere(code, guest.token);
    assert.equal(guestConfirm.status, 200);
    assert.equal(guestConfirm.body.turn_expires_at, at(91_000));

    const waiting = await call("POST", "/rooms", { body: {} });
    assert.equal((await stillHere(waiting.body.code, waiting.body.token)).status, 409);

    // Past the hard deadline the turn has already expired: the room is closed.
    nowMs = START + 200_000;
    const late = await stillHere(code, guest.token);
    assert.equal(late.status, 409);
    assert.equal(late.body.status, "closed");
  });
});

describe("disconnect grace", () => {
  it("a seat silent for 60 s while not due to move abandons (recorded) after both moved", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2)); // guest seen at 0
    // Host is due and keeps the turn alive with polls + one still-here.
    nowMs = START + 26_000;
    assert.equal((await stillHere(code, host.token)).status, 200);
    nowMs = START + 59_000;
    const alive = await poll(code, host.token);
    assert.equal(alive.body.status, "active");
    assert.equal(alive.body.opponent_connected, false);
    assert.equal(alive.body.opponent_last_seen_at, at(0));
    nowMs = START + 60_000;
    const view = await poll(code, host.token);
    assert.equal(view.body.status, "closed");
    assert.deepEqual(view.body.result, { winner: 1, reason: "abandoned" });
    assert.equal(view.body.end_reason, "abandoned");
    assert.equal(view.body.opponent_left, true);
    assert.deepEqual(await record(hostDev.token), [1, 0, 1]);
    assert.deepEqual(await record(guestDev.token), [0, 1, 1]);
    assert.equal((await matchRows())[0].end_reason, "abandoned");
  });

  it("reconnecting inside the grace continues normally", async () => {
    const { code, host, guest } = await startMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2));
    nowMs = START + 26_000;
    await stillHere(code, host.token);
    nowMs = START + 50_000;
    const back = await poll(code, guest.token);
    assert.equal(back.body.status, "active");
    nowMs = START + 60_000;
    const view = await poll(code, host.token);
    assert.equal(view.body.status, "active");
    assert.equal(view.body.opponent_connected, true);
    assert.equal((await move(code, host.token, 3, X_WIN_GAME[2])).status, 200);
  });

  it("before both moved, a lost grace is a no-show", async () => {
    const { code, host, guest, hostDev } = await namedMatch();
    await move(code, host.token, 1, X_WIN_GAME[0]); // host seen at 0, guest due
    nowMs = START + 26_000;
    await stillHere(code, guest.token);
    nowMs = START + 60_000;
    await runCleanup(svc, true); // nobody polls: the sweep resolves it
    const view = await poll(code, guest.token);
    assert.equal(view.body.end_reason, "no_show");
    assert.equal(view.body.result, null);
    assert.deepEqual(await record(hostDev.token), [0, 0, 0]);
  });
});

describe("leave and rematch", () => {
  it("leaving after both moved is a forfeit", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch();
    await playMoves(code, host.token, guest.token, X_WIN_GAME.slice(0, 2));
    const left = await call("POST", `/rooms/${code}/leave`, { token: guest.token });
    assert.deepEqual(left.body.result, { winner: 1, reason: "forfeit" });
    assert.deepEqual(await record(hostDev.token), [1, 0, 1]);
    assert.deepEqual(await record(guestDev.token), [0, 1, 1]);
  });

  it("a rematch starts a fresh both_moved check and clock", async () => {
    const { code, host, guest } = await startMatch();
    const end = await playMoves(code, host.token, guest.token, X_WIN_GAME);
    assert.equal(end.body.status, "finished");
    assert.equal(end.body.both_moved, true);
    assert.equal(end.body.turn_expires_at, null);
    assert.equal(end.body.poll_after_ms, 4000);
    nowMs = START + 5_000;
    await call("POST", `/rooms/${code}/rematch`, { body: { round: 1, token: host.token } });
    const next = await call("POST", `/rooms/${code}/rematch`, {
      body: { round: 1, token: guest.token },
    });
    assert.equal(next.body.status, "active");
    assert.equal(next.body.match.round, 2);
    assert.equal(next.body.both_moved, false);
    assert.equal(next.body.still_here_used, false);
    assert.equal(next.body.turn_expires_at, at(40_000));
    // Guest is X now; leaving before both moved is a free cancel again.
    const left = await call("POST", `/rooms/${code}/leave`, { token: host.token });
    assert.equal(left.body.end_reason, "cancelled");
  });
});

describe("envelope additions", () => {
  it("returns poll_after_ms hints for each situation", async () => {
    const created = await call("POST", "/rooms", { body: { name: "A" } });
    assert.equal(created.body.poll_after_ms, 3000, "waiting");
    const joined = await call("POST", `/rooms/${created.body.code}/join`, { body: {} });
    assert.equal(joined.body.poll_after_ms, 1500, "guest (O) waits for X");
    assert.equal((await poll(created.body.code, created.body.token)).body.poll_after_ms, 3000);
  });

  it("names you, players and the opponent without exposing ids", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch("NightNight", "DayDay");
    assert.equal(host.opponent_joined_at, null, "nobody had joined yet");
    assert.deepEqual(host.players, {
      "1": { name: "NightNight", hero: "vesper_vale", connected: true },
    });
    assert.deepEqual(guest.you, { name: "DayDay", hero: "auric_rex" });
    assert.deepEqual(guest.players, {
      "1": { name: "NightNight", hero: "vesper_vale", connected: true },
      "2": { name: "DayDay", hero: "auric_rex", connected: true },
    });
    const view = await poll(code, host.token);
    assert.equal(view.body.opponent, "DayDay");
    assert.equal(view.body.opponent_joined_at, at(0));
    assert.equal(view.body.opponent_connected, true);
    assert.equal(view.body.opponent_last_seen_at, at(0));
    assert.deepEqual(view.body.you, { name: "NightNight", hero: "vesper_vale" });
    const text = JSON.stringify(view.body);
    for (const secret of [hostDev.player_id, guestDev.player_id, "hash", "room_"])
      assert.ok(!text.includes(secret), secret);
  });

  it("serves public capabilities and advertises them on player objects", async () => {
    const res = await call("GET", "/capabilities");
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("cache-control"), "public, max-age=60");
    assert.equal(res.body.protocol, 2);
    assert.equal(res.body.online2, true);
    assert.equal(res.body.chat, true);
    assert.equal(res.body.tournaments, true);
    assert.equal(res.body.email, true);
    assert.equal(res.body.chat_presets.gg, "Good game!");
    assert.equal((await call("POST", "/capabilities")).status, 405);

    const d = await device("Caps");
    const expected = {
      email: true,
      account_deletion: true,
      online2: true,
      chat: true,
      tournaments: true,
      tournament_sizes: [4, 8],
      tournament_min_players: 3,
      tournament_start_options: [2, 5, 10, 15, 30, 60],
    };
    assert.deepEqual((await me(d.token)).capabilities, expected);
    const patched = await call("PATCH", "/me", { token: d.token, body: { last_hero_id: "cryon" } });
    assert.deepEqual(patched.body.capabilities, expected);
  });

  it("keeps round4g-style clients working (no chat_since, ignoring new fields)", async () => {
    const created = await call("POST", "/rooms", { body: { name: "Old", character_id: "cryon" } });
    const joined = await call("POST", `/rooms/${created.body.code}/join`, {
      body: { name: "Older" },
    });
    const code = created.body.code;
    for (const key of [
      "code",
      "seat",
      "seq",
      "state",
      "status",
      "private",
      "opponent",
      "opponent_left",
      "characters",
      "match",
      "result",
      "end_reason",
      "turn_expires_at",
    ])
      assert.ok(key in joined.body, key);
    const m = await call("POST", `/rooms/${code}/moves`, {
      body: { board: 4, cell: 0, seq: 1, token: created.body.token },
    });
    assert.equal(m.status, 200);
    const p = await call("GET", `/rooms/${code}?since=0`, { token: joined.body.token });
    assert.equal(p.status, 200);
    assert.deepEqual(p.body.moves, [{ board: 4, cell: 0, seq: 1 }]);
    assert.deepEqual(p.body.chat, []);
    assert.equal(p.body.chat_seq, 0);
    assert.equal(
      (
        await call("POST", `/rooms/${code}/moves`, {
          body: { board: 0, cell: 4, seq: 2, token: joined.body.token },
        })
      ).status,
      200,
    );
    const left = await call("POST", `/rooms/${code}/leave`, {
      body: { token: created.body.token },
    });
    assert.deepEqual(left.body.result, { winner: 2, reason: "forfeit" });
  });
});

describe("chat", () => {
  it("delivers messages on the poll with chat_since paging", async () => {
    const { code, host, guest } = await namedMatch("NightNight", "DayDay");
    const sent = await chat(code, host.token, { text: "  hello\nthere  " });
    assert.equal(sent.status, 200, JSON.stringify(sent.body));
    assert.equal(sent.body.message.text, "hello there");
    assert.equal(sent.body.message.name, "NightNight");
    assert.equal(sent.body.message.preset, null);
    assert.equal(sent.body.message.filtered, false);
    const id = sent.body.message.id;
    assert.equal(sent.body.chat_seq, id);

    nowMs += 1_000;
    const viaPreset = await chat(code, guest.token, { preset: "gl" });
    assert.equal(viaPreset.body.message.text, "Good luck!");
    assert.equal(viaPreset.body.message.preset, "gl");

    const g = await poll(code, guest.token, "?since=0&chat_since=0");
    assert.equal(g.body.chat_seq, viaPreset.body.message.id);
    assert.deepEqual(
      g.body.chat.map((c: any) => [c.seat, c.mine, c.name, c.text, c.preset]),
      [
        [1, false, "NightNight", "hello there", null],
        [2, true, "DayDay", "Good luck!", "gl"],
      ],
    );
    assert.equal(g.body.chat[0].at, at(0));
    const later = await poll(code, host.token, `?chat_since=${id}`);
    assert.deepEqual(
      later.body.chat.map((c: any) => c.text),
      ["Good luck!"],
    );
    const none = await poll(code, host.token, `?chat_since=${viaPreset.body.message.id}`);
    assert.deepEqual(none.body.chat, []);
    assert.ok(!JSON.stringify(g.body.chat).includes("p_"), "no player ids");
  });

  it("validates presets, text length, newlines and control characters", async () => {
    const { code, host } = await namedMatch();
    assert.equal((await chat(code, host.token, { preset: "nope" })).status, 400);
    assert.equal((await chat(code, host.token, { text: "a", preset: "gg" })).status, 400);
    assert.equal((await chat(code, host.token, {})).status, 400);
    assert.equal((await chat(code, host.token, { text: "   " })).status, 400);
    assert.equal((await chat(code, host.token, { text: "x".repeat(121) })).status, 400);
    assert.equal((await chat(code, host.token, { text: "x", color: "red" })).status, 400);
    const ok = await chat(code, host.token, { text: `a\nb\tc\u0000d ${"y".repeat(113)}` });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.message.text, `a b cd ${"y".repeat(113)}`);
  });

  it("masks profanity, blocks contact info and slurs", async () => {
    const { code, host } = await namedMatch();
    const masked = await chat(code, host.token, { text: "what the f*ck, sh1t" });
    assert.equal(masked.status, 200);
    assert.equal(masked.body.message.text, "what the ****, ****");
    assert.equal(masked.body.message.filtered, true);
    for (const bad of ["see www.example.com", "me@example.com", "call 555 123 4567", "n1gger"]) {
      nowMs += 3_000;
      const res = await chat(code, host.token, { text: bad });
      assert.equal(res.status, 400, bad);
      assert.equal(res.body.error, "Message not allowed");
    }
    const stored = (
      await pg.query<{ text: string; filtered: boolean }>("select text, filtered from nw_chat")
    ).rows;
    assert.deepEqual(stored, [{ text: "what the ****, ****", filtered: true }]);
  });

  it("rate-limits 5 per 10 s and 30 per 5 minutes per player", async () => {
    const { code, host } = await namedMatch();
    for (let i = 0; i < 5; i += 1)
      assert.equal((await chat(code, host.token, { preset: "hi" })).status, 200);
    const sixth = await chat(code, host.token, { preset: "hi" });
    assert.equal(sixth.status, 429);
    assert.equal(sixth.body.retry_after_seconds, 10);
    nowMs += 10_001;
    assert.equal((await chat(code, host.token, { preset: "hi" })).status, 200);

    // 30 per 5 minutes: spread out so the 10 s window never fills.
    await pg.exec("delete from nw_chat");
    for (let i = 0; i < 30; i += 1) {
      nowMs += 2_500;
      // Keep the match alive: polling as the due player doesn't expire it, so move the clock via SQL.
      await pg.query("update nw_rooms set turn_started_at = $1, a_seen_at = $1, b_seen_at = $1", [
        new Date(nowMs),
      ]);
      assert.equal((await chat(code, host.token, { preset: "gg" })).status, 200, `msg ${i}`);
    }
    nowMs += 2_500;
    await pg.query("update nw_rooms set turn_started_at = $1, a_seen_at = $1, b_seen_at = $1", [
      new Date(nowMs),
    ]);
    const over = await chat(code, host.token, { preset: "gg" });
    assert.equal(over.status, 429);
    assert.ok(over.body.retry_after_seconds > 10 && over.body.retry_after_seconds <= 300);
  });

  it("requires a screen name and an opponent; closed rooms refuse chat", async () => {
    const anon = await startMatch();
    const res = await chat(anon.code, anon.host.token, { text: "hi" });
    assert.equal(res.status, 403);
    assert.equal(res.body.error, "Create a screen name to chat");
    const nameless = await device();
    const created = await call("POST", "/rooms", { body: {}, token: nameless.token });
    assert.equal((await chat(created.body.code, nameless.token, { text: "hi" })).status, 403);

    const named = await device("Lonely");
    const waiting = await call("POST", "/rooms", { body: {}, token: named.token });
    const w = await chat(waiting.body.code, waiting.body.token, { text: "hi" });
    assert.equal(w.status, 409, "nobody to talk to yet");

    const { code, host, guest } = await namedMatch("A1", "B1");
    await call("POST", `/rooms/${code}/leave`, { token: guest.token });
    assert.equal((await chat(code, host.token, { text: "bye" })).status, 409);

    // Device token instead of the seat token also works for chat.
    const m = await namedMatch("C1", "D1");
    assert.equal((await chat(m.code, m.hostDev.token, { preset: "hi" })).status, 200);
  });
});

describe("blocks and reports", () => {
  it("block hides the blocked player's chat and keeps them out of the blocker's rooms", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch("Blocker", "Pest");
    await chat(code, guest.token, { text: "before" });
    const blocked = await call("POST", "/players/block", {
      token: hostDev.token,
      body: { room_code: code.toLowerCase(), seat: 2 },
    });
    assert.equal(blocked.status, 200, JSON.stringify(blocked.body));
    nowMs += 1_000;
    await chat(code, guest.token, { text: "after" });
    await chat(code, host.token, { text: "mine" });

    const hostView = await poll(code, host.token, "?chat_since=0");
    assert.deepEqual(
      hostView.body.chat.map((c: any) => c.text),
      ["mine"],
    );
    const guestView = await poll(code, guest.token, "?chat_since=0");
    assert.deepEqual(
      guestView.body.chat.map((c: any) => c.text),
      ["before", "after", "mine"],
    );

    const list = await call("GET", "/players/blocks", { token: hostDev.token });
    assert.deepEqual(list.body.blocks, [{ name: "Pest", blocked_at: at(0) }]);

    // The blocked player can't join (or even see) the blocker's new room.
    const room = await call("POST", "/rooms", { body: {}, token: hostDev.token });
    const lobby = await call("GET", "/rooms", { token: guestDev.token });
    assert.ok(!lobby.body.rooms.some((r: any) => r.code === room.body.code));
    const join = await call("POST", `/rooms/${room.body.code}/join`, {
      body: {},
      token: guestDev.token,
    });
    assert.equal(join.status, 409);
    assert.equal(join.body.error, "Room is full");

    // Unblock by name; then joining works.
    const unblocked = await call("DELETE", "/players/block", {
      token: hostDev.token,
      body: { name: "pest" },
    });
    assert.equal(unblocked.status, 200);
    assert.deepEqual(
      (await call("GET", "/players/blocks", { token: hostDev.token })).body.blocks,
      [],
    );
    const join2 = await call("POST", `/rooms/${room.body.code}/join`, {
      body: {},
      token: guestDev.token,
    });
    assert.equal(join2.status, 200);
  });

  it("unblocks by room + seat and validates requests", async () => {
    const { code, hostDev, guest } = await namedMatch("U1", "U2");
    const body = { room_code: code, seat: 2 };
    assert.equal((await call("POST", "/players/block", { body })).status, 401);
    assert.equal(
      (await call("POST", "/players/block", { token: guest.token, body })).status,
      401,
      "seat tokens can't block",
    );
    assert.equal(
      (
        await call("POST", "/players/block", {
          token: hostDev.token,
          body: { room_code: code, seat: 1 },
        })
      ).status,
      400,
      "own seat",
    );
    assert.equal(
      (
        await call("POST", "/players/block", {
          token: hostDev.token,
          body: { room_code: code, seat: 3 },
        })
      ).status,
      400,
    );
    const stranger = await device("Stranger");
    assert.equal(
      (await call("POST", "/players/block", { token: stranger.token, body })).status,
      403,
    );
    assert.equal(
      (await call("POST", "/players/block", { token: hostDev.token, body })).status,
      200,
    );
    assert.equal(
      (await call("POST", "/players/block", { token: hostDev.token, body })).status,
      200,
      "idempotent",
    );
    assert.equal(
      (await call("DELETE", "/players/block", { token: hostDev.token, body })).status,
      200,
    );
    assert.equal((await pg.query("select * from nw_blocks")).rows.length, 0);
    assert.equal(
      (await call("DELETE", "/players/block", { token: hostDev.token, body: { name: "Nobody" } }))
        .status,
      404,
    );
  });

  it("report stores a chat snapshot and is rate-limited", async () => {
    const { code, host, guest, hostDev, guestDev } = await namedMatch("Reporter", "Rude");
    for (const text of ["one", "two", "three"]) {
      nowMs += 3_000;
      await chat(code, guest.token, { text });
    }
    await chat(code, host.token, { text: "not mine to report" });
    const bad = await call("POST", "/reports", {
      token: hostDev.token,
      body: { room_code: code, seat: 2, reason: "rude" },
    });
    assert.equal(bad.status, 400);
    assert.equal(
      (
        await call("POST", "/reports", {
          token: hostDev.token,
          body: { room_code: code, seat: 2, reason: "spam", note: "x".repeat(501) },
        })
      ).status,
      400,
    );
    const res = await call("POST", "/reports", {
      token: hostDev.token,
      body: { room_code: code, seat: 2, reason: "harassment", note: " keeps\nspamming " },
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.deepEqual(res.body, { ok: true });
    const row = (await pg.query<any>("select * from nw_reports")).rows[0];
    assert.equal(row.reporter_id, hostDev.player_id);
    assert.equal(row.reported_id, guestDev.player_id);
    assert.equal(row.reported_name, "Rude");
    assert.equal(row.room_code, code);
    assert.equal(row.reason, "harassment");
    assert.equal(row.note, "keeps spamming");
    assert.deepEqual(
      row.chat_snapshot.map((m: any) => m.text),
      ["one", "two", "three"],
    );

    for (let i = 1; i < 10; i += 1) {
      const r = await call("POST", "/reports", {
        token: hostDev.token,
        body: { room_code: code, seat: 2, reason: "other" },
      });
      assert.equal(r.status, 201, `report ${i + 1}`);
    }
    const over = await call("POST", "/reports", {
      token: hostDev.token,
      body: { room_code: code, seat: 2, reason: "other" },
    });
    assert.equal(over.status, 429);
    assert.ok(over.body.retry_after_seconds > 0 && over.body.retry_after_seconds <= 3600);
  });
});

describe("retention", () => {
  it("deletes chat after 24 h and 1 h after the room closed; reports after 30 days", async () => {
    const live = await namedMatch("Live1", "Live2");
    await chat(live.code, live.host.token, { text: "old message" });
    const closed = await namedMatch("Gone1", "Gone2");
    await chat(closed.code, closed.host.token, { text: "closing soon" });
    await call("POST", "/reports", {
      token: closed.hostDev.token,
      body: { room_code: closed.code, seat: 2, reason: "spam" },
    });
    await call("POST", `/rooms/${closed.code}/leave`, { token: closed.guest.token });

    const count = async (table: string) =>
      Number((await pg.query<{ n: number }>(`select count(*)::int as n from ${table}`)).rows[0].n);

    nowMs = START + 59 * 60_000;
    await runCleanup(svc, true);
    assert.equal(await count("nw_chat"), 2);
    nowMs = START + 61 * 60_000;
    await runCleanup(svc, true);
    assert.equal(await count("nw_chat"), 1, "closed room's chat is gone after 1 h");

    nowMs = START + 24 * 60 * 60_000 + 1;
    await runCleanup(svc, true);
    assert.equal(await count("nw_chat"), 0, "24 h-old chat is gone");
    assert.equal(await count("nw_reports"), 1);

    nowMs = START + 30 * 24 * 60 * 60_000 + 1;
    await runCleanup(svc, true);
    assert.equal(await count("nw_reports"), 0, "reports are purged after 30 days");
  });
});
