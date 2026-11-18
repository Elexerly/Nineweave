/**
 * Email verification and recovery tests. Same harness as online.test.ts:
 * the real HTTP handler over an in-memory PGlite with `migrations/*.sql`
 * applied. The mailer is a recording fake — nothing touches the network.
 */
import { after, afterEach, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { buildCodeEmail, EMAIL_FROM, resendMailer, type EmailMessage } from "./mailer.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";

const MIGRATIONS = join(import.meta.dirname, "..", "..", "..", "migrations");
const START = Date.parse("2026-11-15T12:00:00Z");

let pg: PGlite;
let svc: Service;
let nowMs = START;
let sent: EmailMessage[] = [];
let failSend = false;
let logs: string[] = [];
const realConsole = { error: console.error, warn: console.warn, log: console.log };

function fakeMailer(message: EmailMessage): Promise<void> {
  if (failSend) return Promise.reject(new Error("provider down"));
  sent.push(message);
  return Promise.resolve();
}

function makeService(mailer: typeof fakeMailer | null = fakeMailer) {
  return createService({
    db: pgliteDb(pg),
    now: () => new Date(nowMs),
    cleanupIntervalMs: 0,
    limits: { device: 1000, write: 1000, email: 1000, verify: 1000 },
    mailer,
  });
}

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
  sent = [];
  failSend = false;
  logs = [];
  for (const k of ["error", "warn", "log"] as const)
    console[k] = (...args: unknown[]) => void logs.push(args.map(String).join(" "));
  svc = makeService();
});

afterEach(() => {
  Object.assign(console, realConsole);
});

interface Res {
  status: number;
  body: Record<string, any>;
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
  return { status: res.status, body: text ? JSON.parse(text) : {} };
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

/** The 6-digit code from the last captured email (test-only interception). */
function lastCode(): string {
  const msg = sent.at(-1);
  assert.ok(msg, "no email was sent");
  const match = msg.text.match(/Your code: (\d{6})/);
  assert.ok(match, "code not found in email text");
  return match[1];
}

function wrongCode(code: string): string {
  return code === "000000" ? "111111" : "000000";
}

async function requestCode(token: string, email?: string) {
  return call("POST", "/me/email/verification", {
    token,
    body: email === undefined ? {} : { email },
  });
}

async function confirm(token: string, challenge_id: string, code: string) {
  return call("POST", "/me/email/verification/confirm", { token, body: { challenge_id, code } });
}

/** Request + confirm, returning the confirm response. */
async function verify(token: string, email: string) {
  const req = await requestCode(token, email);
  assert.equal(req.status, 200, JSON.stringify(req.body));
  const res = await confirm(token, req.body.challenge_id, lastCode());
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res;
}

describe("profile email fields", () => {
  it("advertises capabilities.email on register, GET /me and PATCH /me", async () => {
    const d = await device();
    assert.deepEqual(d.player.capabilities, {
      email: true,
      account_deletion: true,
      account_unlocks: true,
      tutorial_completion: true,
      online2: true,
      chat: true,
      tournaments: true,
      tournament_sizes: [4, 8],
      tournament_min_players: 3,
      tournament_start_options: [2, 5, 10, 15, 30, 60],
    });
    assert.equal(d.player.email, null);
    assert.equal(d.player.email_status, "none");
    assert.equal(d.player.email_verified_at, null);
    assert.deepEqual((await me(d.token)).capabilities, {
      email: true,
      account_deletion: true,
      account_unlocks: true,
      tutorial_completion: true,
      online2: true,
      chat: true,
      tournaments: true,
      tournament_sizes: [4, 8],
      tournament_min_players: 3,
      tournament_start_options: [2, 5, 10, 15, 30, 60],
    });
    const patched = await call("PATCH", "/me", { token: d.token, body: { last_hero_id: "cryon" } });
    assert.equal(patched.status, 200);
    assert.deepEqual(patched.body.capabilities, {
      email: true,
      account_deletion: true,
      account_unlocks: true,
      tutorial_completion: true,
      online2: true,
      chat: true,
      tournaments: true,
      tournament_sizes: [4, 8],
      tournament_min_players: 3,
      tournament_start_options: [2, 5, 10, 15, 30, 60],
    });
  });

  it("PATCH stores a trimmed, lowercased email as unverified; null and empty clear it", async () => {
    const d = await device();
    const res = await call("PATCH", "/me", {
      token: d.token,
      body: { email: "  Pat@Example.COM " },
    });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.email, "pat@example.com");
    assert.equal(res.body.email_status, "unverified");
    assert.equal(res.body.email_verified_at, null);
    assert.equal(sent.length, 0, "PATCH must not send a code");
    assert.equal((await me(d.token)).email, "pat@example.com");

    const cleared = await call("PATCH", "/me", { token: d.token, body: { email: null } });
    assert.equal(cleared.body.email, null);
    assert.equal(cleared.body.email_status, "none");

    await call("PATCH", "/me", { token: d.token, body: { email: "a@b.co" } });
    const empty = await call("PATCH", "/me", { token: d.token, body: { email: "   " } });
    assert.equal(empty.body.email, null);
  });

  it("changing the address resets verification; re-sending the same one keeps it", async () => {
    const d = await device();
    await verify(d.token, "pat@example.com");
    const same = await call("PATCH", "/me", { token: d.token, body: { email: "PAT@example.com" } });
    assert.equal(same.body.email_status, "verified");
    const changed = await call("PATCH", "/me", {
      token: d.token,
      body: { email: "new@example.com" },
    });
    assert.equal(changed.body.email, "new@example.com");
    assert.equal(changed.body.email_status, "unverified");
    assert.equal(changed.body.email_verified_at, null);

    nowMs += 61_000;
    await verify(d.token, "new@example.com");
    const cleared = await call("PATCH", "/me", { token: d.token, body: { email: null } });
    assert.equal(cleared.body.email_status, "none");
    assert.equal(cleared.body.email_verified_at, null);
  });

  it("rejects invalid emails and keeps rejecting unknown fields", async () => {
    const d = await device();
    const bad = [
      "no-at-sign",
      "@example.com",
      "pat@",
      "pat@example",
      "pat@@example.com",
      "pat example@example.com",
      "pat..x@example.com",
      `${"a".repeat(65)}@example.com`,
      `a@${"b".repeat(60)}.${"c".repeat(60)}.${"d".repeat(60)}.${"e".repeat(60)}.${"f".repeat(9)}.com`,
      42,
      ["a@b.co"],
    ];
    for (const email of bad) {
      const res = await call("PATCH", "/me", { token: d.token, body: { email } });
      assert.equal(res.status, 400, `accepted ${JSON.stringify(email)}`);
      const req = await requestCode(d.token, email as string);
      assert.equal(req.status, 400, `request accepted ${JSON.stringify(email)}`);
    }
    assert.equal(
      (await call("PATCH", "/me", { token: d.token, body: { mail: "a@b.co" } })).status,
      400,
    );
    assert.equal((await requestCode(d.token, undefined)).status, 400, "no stored address");
    assert.equal(sent.length, 0);
  });

  it("never puts email on the leaderboard", async () => {
    const d = await device("Mailer");
    await pg.query("update nw_players set matches_played = 1, matches_won = 1 where id = $1", [
      d.player_id,
    ]);
    await verify(d.token, "pat@example.com");
    const board = await call("GET", "/leaderboard", { token: d.token });
    assert.equal(board.body.players.length, 1);
    assert.ok(!JSON.stringify(board.body).includes("example.com"));
  });
});

describe("verification", () => {
  it("request + confirm marks the email verified and stores only a hash", async () => {
    const d = await device();
    await call("PATCH", "/me", { token: d.token, body: { email: "Pat@Example.com" } });
    const req = await requestCode(d.token);
    assert.equal(req.status, 200, JSON.stringify(req.body));
    assert.match(req.body.challenge_id, /^ec_/);
    assert.equal(req.body.expires_at, new Date(START + 10 * 60_000).toISOString());
    assert.equal(req.body.resend_available_at, new Date(START + 60_000).toISOString());
    assert.equal(req.body.email, "pat@example.com");
    assert.equal(Object.keys(req.body).includes("code"), false);

    assert.equal(sent.length, 1);
    const msg = sent[0];
    const code = lastCode();
    assert.equal(msg.to, "pat@example.com");
    assert.equal(msg.subject, "Your Nineweave verification code");
    assert.ok(msg.html.includes(code) && msg.html.includes("Nineweave".toUpperCase()));
    assert.ok(msg.text.includes("10 minutes") && msg.text.includes("ignore"));
    assert.ok(!JSON.stringify(req.body).includes(code));

    const rows = (await pg.query<Record<string, unknown>>("select * from nw_email_challenges"))
      .rows;
    assert.equal(rows.length, 1);
    assert.match(String(rows[0].code_hash), /^[0-9a-f]{64}$/);
    assert.ok(!JSON.stringify(rows).includes(code), "plaintext code stored");
    assert.equal(rows[0].purpose, "verify");
    assert.equal(rows[0].email, "pat@example.com");

    nowMs += 30_000;
    const ok = await confirm(d.token, req.body.challenge_id, code);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.email, "pat@example.com");
    assert.equal(ok.body.email_status, "verified");
    assert.equal(ok.body.email_verified_at, new Date(START + 30_000).toISOString());
    assert.equal((await me(d.token)).email_status, "verified");

    // The challenge is spent.
    const again = await confirm(d.token, req.body.challenge_id, code);
    assert.equal(again.status, 400);
    assert.equal(again.body.error, "Invalid or expired code");
    assert.equal((await requestCode(d.token)).status, 409, "already verified");
  });

  it("request with a new email stores it unverified and clears prior verification", async () => {
    const d = await device();
    await verify(d.token, "old@example.com");
    nowMs += 61_000;
    const req = await requestCode(d.token, "New@Example.com");
    assert.equal(req.status, 200);
    const p = await me(d.token);
    assert.equal(p.email, "new@example.com");
    assert.equal(p.email_status, "unverified");
  });

  it("accepts a code sent as a number or with spaces", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    const spaced = `${lastCode().slice(0, 3)} ${lastCode().slice(3)}`;
    const ok = await confirm(d.token, req.body.challenge_id, spaced);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
  });

  it("wrong codes burn attempts and the 6th attempt is locked even with the right code", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    const code = lastCode();
    for (let i = 0; i < 5; i += 1) {
      const res = await confirm(d.token, req.body.challenge_id, wrongCode(code));
      assert.equal(res.status, 400);
      assert.equal(res.body.error, "Invalid or expired code");
    }
    const locked = await confirm(d.token, req.body.challenge_id, code);
    assert.equal(locked.status, 400);
    assert.equal(locked.body.error, "Invalid or expired code");
    assert.equal((await me(d.token)).email_status, "unverified");
    const row = (
      await pg.query<{ attempt_count: number }>("select attempt_count from nw_email_challenges")
    ).rows[0];
    assert.equal(row.attempt_count, 5);
  });

  it("the right code on the 5th attempt still works", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    const code = lastCode();
    for (let i = 0; i < 4; i += 1)
      assert.equal((await confirm(d.token, req.body.challenge_id, wrongCode(code))).status, 400);
    assert.equal((await confirm(d.token, req.body.challenge_id, code)).status, 200);
  });

  it("expires codes after 10 minutes", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    nowMs += 10 * 60_000 + 1;
    const res = await confirm(d.token, req.body.challenge_id, lastCode());
    assert.equal(res.status, 400);
    assert.equal(res.body.error, "Invalid or expired code");
  });

  it("a new request supersedes the previous code", async () => {
    const d = await device();
    const first = await requestCode(d.token, "pat@example.com");
    const firstCode = lastCode();
    nowMs += 61_000;
    const second = await requestCode(d.token);
    assert.equal(second.status, 200);
    assert.notEqual(second.body.challenge_id, first.body.challenge_id);
    assert.equal((await confirm(d.token, first.body.challenge_id, firstCode)).status, 400);
    assert.equal((await confirm(d.token, second.body.challenge_id, lastCode())).status, 200);
  });

  it("changing the address with PATCH kills open codes", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    await call("PATCH", "/me", { token: d.token, body: { email: "other@example.com" } });
    assert.equal((await confirm(d.token, req.body.challenge_id, lastCode())).status, 400);
    assert.equal((await me(d.token)).email_status, "unverified");
  });

  it("validates the confirm body and scopes challenges to their player", async () => {
    const a = await device();
    const b = await device();
    const req = await requestCode(a.token, "pat@example.com");
    const code = lastCode();
    assert.equal((await confirm(b.token, req.body.challenge_id, code)).status, 404);
    assert.equal((await confirm(a.token, "ec_unknown", code)).status, 404);
    assert.equal((await confirm(a.token, req.body.challenge_id, "12345")).status, 400);
    assert.equal((await confirm(a.token, req.body.challenge_id, "abcdef")).status, 400);
    const extra = await call("POST", "/me/email/verification/confirm", {
      token: a.token,
      body: { challenge_id: req.body.challenge_id, code, email: "x@y.co" },
    });
    assert.equal(extra.status, 400);
    // B's attempts did not burn A's challenge.
    assert.equal((await confirm(a.token, req.body.challenge_id, code)).status, 200);
  });

  it("requires a device token", async () => {
    assert.equal((await requestCode("", "pat@example.com")).status, 401);
    assert.equal((await requestCode("nwd_nope", "pat@example.com")).status, 401);
    assert.equal((await confirm("", "ec_x", "123456")).status, 401);
    assert.equal((await call("GET", "/me/email/verification")).status, 405);
    assert.equal((await call("POST", "/me/email/verification/other")).status, 404);
    assert.equal(sent.length, 0);
  });
});

describe("throttling", () => {
  it("enforces a 60 s resend cooldown per player", async () => {
    const d = await device();
    assert.equal((await requestCode(d.token, "pat@example.com")).status, 200);
    nowMs += 30_000;
    const early = await requestCode(d.token);
    assert.equal(early.status, 429);
    assert.equal(early.body.retry_after_seconds, 30);
    nowMs += 30_000;
    assert.equal((await requestCode(d.token)).status, 200);
    assert.equal(sent.length, 2);
  });

  it("caps requests at 5 per player per hour", async () => {
    const d = await device();
    for (let i = 0; i < 5; i += 1) {
      assert.equal((await requestCode(d.token, `p${i}@example.com`)).status, 200, `request ${i}`);
      nowMs += 61_000;
    }
    const capped = await requestCode(d.token, "p9@example.com");
    assert.equal(capped.status, 429);
    assert.ok(capped.body.retry_after_seconds > 0);
    nowMs = START + 60 * 60_000 + 1;
    assert.equal((await requestCode(d.token, "p9@example.com")).status, 200);
  });

  it("caps requests at 5 per email per hour across players", async () => {
    for (let i = 0; i < 5; i += 1) {
      const d = await device();
      assert.equal((await requestCode(d.token, "shared@example.com")).status, 200);
    }
    const d = await device();
    const capped = await requestCode(d.token, "Shared@Example.com");
    assert.equal(capped.status, 429);
    assert.equal(sent.length, 5);
  });

  it("rate-limits the email endpoints per IP", async () => {
    svc = createService({
      db: pgliteDb(pg),
      now: () => new Date(nowMs),
      limits: { device: 1000, email: 2, verify: 2 },
      mailer: fakeMailer,
    });
    const d = await device();
    const headers = { "X-Forwarded-For": "203.0.113.9" };
    const statuses: number[] = [];
    for (let i = 0; i < 3; i += 1)
      statuses.push(
        (await call("POST", "/me/email/verification", { token: d.token, body: {}, headers }))
          .status,
      );
    assert.equal(statuses[2], 429);
  });
});

describe("uniqueness", () => {
  it("returns 409 when the email is verified on another account", async () => {
    const a = await device();
    const b = await device();
    await verify(a.token, "pat@example.com");
    const res = await requestCode(b.token, "PAT@example.com");
    assert.equal(res.status, 409);
    assert.equal(res.body.error, "That email is already used by another account.");
    // Storing it unverified is still allowed; it just can't be verified.
    const patched = await call("PATCH", "/me", {
      token: b.token,
      body: { email: "pat@example.com" },
    });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.email_status, "unverified");
  });

  it("first confirm wins; the other account's open code is dead", async () => {
    const a = await device();
    const b = await device();
    const reqA = await requestCode(a.token, "pat@example.com");
    const codeA = lastCode();
    const reqB = await requestCode(b.token, "pat@example.com");
    const codeB = lastCode();
    assert.equal((await confirm(b.token, reqB.body.challenge_id, codeB)).status, 200);
    const late = await confirm(a.token, reqA.body.challenge_id, codeA);
    assert.ok([400, 409].includes(late.status), String(late.status));
    assert.equal((await me(a.token)).email_status, "unverified");
    assert.equal((await me(b.token)).email_status, "verified");
  });

  it("the unique index returns 409 if two confirms race past the pre-check", async () => {
    const a = await device();
    const b = await device();
    const reqA = await requestCode(a.token, "pat@example.com");
    const codeA = lastCode();
    // B gets verified behind the API's back (simulates a concurrent confirm).
    await pg.query(
      "update nw_players set email = 'pat@example.com', email_verified_at = now() where id = $1",
      [b.player_id],
    );
    const res = await confirm(a.token, reqA.body.challenge_id, codeA);
    assert.equal(res.status, 409);
    assert.equal((await me(a.token)).email_status, "unverified");
  });

  it("the database refuses two verified players with one email", async () => {
    const a = await device();
    const b = await device();
    await verify(a.token, "pat@example.com");
    await assert.rejects(
      pg.query(
        "update nw_players set email = 'PAT@example.com', email_verified_at = now() where id = $1",
        [b.player_id],
      ),
    );
  });
});

describe("mailer", () => {
  it("answers 503 when no mailer / API key is configured, without storing anything", async () => {
    svc = makeService(null);
    const d = await device();
    const res = await requestCode(d.token, "pat@example.com");
    assert.equal(res.status, 503);
    assert.match(res.body.error, /not available/);
    const rows = (await pg.query("select 1 from nw_email_challenges")).rows;
    assert.equal(rows.length, 0);
    assert.equal(resendMailer(undefined), null);
    assert.equal(resendMailer("   "), null);
  });

  it("answers 502 and kills the challenge when the provider fails", async () => {
    const d = await device();
    failSend = true;
    const res = await requestCode(d.token, "pat@example.com");
    assert.equal(res.status, 502);
    assert.equal(res.body.error, "Could not send email. Try again shortly.");
    const row = (
      await pg.query<{ invalidated_at: Date | null }>(
        "select invalidated_at from nw_email_challenges",
      )
    ).rows[0];
    assert.ok(row.invalidated_at);
  });

  it("posts to Resend with the right shape and never logs the key, body or code", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const key = "re_test_not_a_real_key";
    const ok = resendMailer(key, (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response("{}", { status: 200 });
    }) as unknown as typeof fetch)!;
    const msg = buildCodeEmail("pat@example.com", "482913", "verify", 10);
    await ok(msg);
    assert.equal(calls[0].url, "https://api.resend.com/emails");
    assert.equal(calls[0].init.method, "POST");
    assert.equal((calls[0].init.headers as Record<string, string>).Authorization, `Bearer ${key}`);
    const body = JSON.parse(String(calls[0].init.body));
    assert.deepEqual(Object.keys(body).sort(), ["from", "html", "subject", "text", "to"]);
    assert.equal(body.from, EMAIL_FROM);
    assert.equal(body.from, "Nineweave <no-reply@nineweave.sitebloc.com>");

    const failing = resendMailer(
      key,
      (async () => new Response("bad", { status: 422 })) as unknown as typeof fetch,
    )!;
    await assert.rejects(failing(msg));
    const throwing = resendMailer(key, (async () => {
      throw new Error(`network down ${key}`);
    }) as unknown as typeof fetch)!;
    await assert.rejects(throwing(msg), (err: Error) => !err.message.includes(key));

    const all = logs.join("\n");
    assert.ok(!all.includes(key), "API key logged");
    assert.ok(!all.includes("482913"), "code logged");
    assert.ok(!all.includes("pat@example.com"), "recipient logged");
  });

  it("builds a branded email with no secrets, links or tracking", () => {
    const msg = buildCodeEmail("pat<x>@example.com", "012345", "verify", 10);
    assert.equal(msg.subject, "Your Nineweave verification code");
    assert.ok(msg.html.includes("012345") && msg.text.includes("012345"));
    assert.ok(msg.html.includes("NINEWEAVE"));
    assert.ok(msg.html.includes("10 minutes") && msg.text.includes("10 minutes"));
    assert.ok(!/<img|<a\s|https?:\/\//i.test(msg.html), "no images, links or remote resources");
    assert.ok(!msg.html.includes("pat<x>"), "recipient is escaped");
    const recover = buildCodeEmail("pat@example.com", "012345", "recover", 10);
    assert.equal(recover.subject, "Your Nineweave sign-in code");
  });

  it("handler logs never contain the code", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    const code = lastCode();
    await confirm(d.token, req.body.challenge_id, wrongCode(code));
    await confirm(d.token, req.body.challenge_id, code);
    failSend = true;
    nowMs += 61_000;
    await call("PATCH", "/me", { token: d.token, body: { email: "x@example.com" } });
    await requestCode(d.token);
    const all = logs.join("\n");
    assert.ok(!all.includes(code));
    assert.ok(!all.includes("example.com"));
  });
});

describe("recovery", () => {
  async function recover(email: string) {
    return call("POST", "/auth/email/recover", { body: { email } });
  }
  async function recoverConfirm(challenge_id: string, code: string) {
    return call("POST", "/auth/email/recover/confirm", { body: { challenge_id, code } });
  }

  it("issues a new device token for a verified email and retires the old one", async () => {
    const d = await device("Recoverer");
    await call("POST", "/me/tutorial/complete", {token:d.token, body:{}});
    await verify(d.token, "pat@example.com");
    nowMs += 61_000;
    const req = await recover("PAT@example.com");
    assert.equal(req.status, 200);
    assert.match(req.body.challenge_id, /^ec_/);
    assert.equal(sent.at(-1)!.subject, "Your Nineweave sign-in code");
    const res = await recoverConfirm(req.body.challenge_id, lastCode());
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.match(res.body.token, /^nwd_/);
    assert.equal(res.body.player_id, d.player_id);
    assert.equal(res.body.player.screen_name, "Recoverer");
    assert.equal(res.body.player.tutorial_completed, true);
    assert.equal(res.body.player.email_status, "verified");
    assert.equal((await call("GET", "/me", { token: d.token })).status, 401);
    assert.equal((await me(res.body.token)).player_id, d.player_id);
    // Single use.
    assert.equal((await recoverConfirm(req.body.challenge_id, lastCode())).status, 400);
  });

  it("looks identical for unknown and unverified emails and sends nothing", async () => {
    const d = await device();
    await call("PATCH", "/me", { token: d.token, body: { email: "pat@example.com" } });
    const unverified = await recover("pat@example.com");
    const unknown = await recover("nobody@example.com");
    for (const res of [unverified, unknown]) {
      assert.equal(res.status, 200);
      assert.deepEqual(Object.keys(res.body).sort(), [
        "challenge_id",
        "expires_at",
        "resend_available_at",
      ]);
      assert.match(res.body.challenge_id, /^ec_/);
      const bad = await recoverConfirm(res.body.challenge_id, "123456");
      assert.equal(bad.status, 400);
      assert.equal(bad.body.error, "Invalid or expired code");
    }
    assert.equal(sent.length, 0);
    assert.equal((await recover("not-an-email")).status, 400);
  });

  it("a verification code can't be used to recover, and vice versa", async () => {
    const d = await device();
    const req = await requestCode(d.token, "pat@example.com");
    const res = await recoverConfirm(req.body.challenge_id, lastCode());
    assert.equal(res.status, 400);
    assert.equal((await confirm(d.token, req.body.challenge_id, lastCode())).status, 200);
    nowMs += 61_000;
    const rec = await recover("pat@example.com");
    assert.equal(
      (await confirm(d.token, rec.body.challenge_id, lastCode())).status,
      404,
      "recover challenge is not a verification challenge",
    );
  });

  it("is throttled silently and locks after 5 wrong codes", async () => {
    const d = await device();
    await verify(d.token, "pat@example.com");
    nowMs += 61_000;
    const req = await recover("pat@example.com");
    const code = lastCode();
    const early = await recover("pat@example.com");
    assert.equal(early.status, 200, "cooldown is not revealed");
    assert.equal(sent.length, 2, "no extra email during cooldown");
    for (let i = 0; i < 5; i += 1)
      assert.equal((await recoverConfirm(req.body.challenge_id, wrongCode(code))).status, 400);
    assert.equal((await recoverConfirm(req.body.challenge_id, code)).status, 400);
    assert.equal((await me(d.token)).player_id, d.player_id, "old token still valid");
  });

  it("stops working once the address is changed", async () => {
    const d = await device();
    await verify(d.token, "pat@example.com");
    nowMs += 61_000;
    const req = await recover("pat@example.com");
    const code = lastCode();
    await call("PATCH", "/me", { token: d.token, body: { email: "new@example.com" } });
    assert.equal((await recoverConfirm(req.body.challenge_id, code)).status, 400);
    assert.equal((await me(d.token)).player_id, d.player_id);
  });

  it("answers 503 without a mailer", async () => {
    svc = makeService(null);
    assert.equal((await recover("pat@example.com")).status, 503);
  });
});
