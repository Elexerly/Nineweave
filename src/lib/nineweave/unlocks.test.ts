import { after, before, beforeEach, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { handleNineweaveRequest } from "./api.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import { hashToken } from "./security.ts";
const dir = new URL("../../../migrations/", import.meta.url);
let pg: PGlite, svc: Service, now: number;
const migration = readFileSync(new URL("0011_nineweave_account_unlocks.sql", dir), "utf8");
before(async () => {
  pg = new PGlite();
  await pg.waitReady;
  for (const f of readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort())
    await pg.exec(readFileSync(new URL(f, dir), "utf8"));
});
after(async () => {
  await pg.close();
});
beforeEach(async () => {
  await pg.exec("truncate nw_players cascade");
  now = Date.parse("2026-11-17T12:00:00Z");
  svc = createService({
    db: pgliteDb(pg),
    now: () => new Date(now),
    limits: { write: 1000, device: 1000 },
  });
});
async function call(method: string, path: string, token?: string, body?: unknown, service = svc) {
  const r = await handleNineweaveRequest(
    service,
    new Request("http://localhost/api/nineweave" + path, {
      method,
      headers: token ? { authorization: "Bearer " + token } : {},
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
  return { status: r.status, body: (await r.json()) as any };
}
async function device() {
  const r = await call("POST", "/auth/device", undefined, {});
  assert.equal(r.status, 201);
  return r.body;
}
const redeem = (token: string, code: unknown) => call("POST", "/me/unlocks", token, { code });
it("requires real account token; rejects wrong method and forged ownership", async () => {
  assert.equal((await redeem("", "Blizzard")).status, 401);
  assert.equal((await redeem("fake", "Blizzard")).status, 401);
  const d = await device();
  assert.equal((await call("GET", "/me/unlocks", d.token)).status, 405);
  assert.equal(
    (await call("POST", "/me/unlocks", d.token, { code: "Blizzard", player_id: "other" })).status,
    400,
  );
  assert.equal(
    (await call("PATCH", "/me", d.token, { unlocked_backgrounds: ["blizzard"] })).status,
    400,
  );
});
it("normalizes codes, persists all backgrounds, exact odd fourth code and no automatic selection", async () => {
  const d = await device();
  const codes = [" blIZZaRD ", "TicTacToe", "010127", "0704027", "Patrick"];
  for (const c of codes) {
    const r = await redeem(d.token, c);
    assert.equal(r.status, 200);
    assert.equal(r.body.already_owned, false);
    assert.equal(r.body.unlock.kind, "background");
  }
  const p = (await call("GET", "/me", d.token)).body;
  assert.deepEqual(p.unlocked_backgrounds, [
    "blizzard",
    "fourth_july",
    "new_year",
    "st_patrick",
    "tictactoe",
  ]);
  assert.deepEqual(p.unlocked_heroes, []);
  assert.equal(p.capabilities.account_unlocks, true);
  assert.equal((await redeem(d.token, "070427")).status, 400);
});
it("duplicate codes idempotent and account isolated", async () => {
  const a = await device(),
    b = await device();
  assert.equal((await redeem(a.token, "Blizzard")).body.already_owned, false);
  assert.equal((await redeem(a.token, "BLIZZARD")).body.already_owned, true);
  assert.deepEqual((await call("GET", "/me", b.token)).body.unlocked_backgrounds, []);
  assert.equal((await redeem(b.token, "Blizzard")).body.already_owned, false);
});
it("all nine reserved codes return readable unavailable with no grants", async () => {
  const d = await device();
  for (const code of [
    "W2026",
    "G2026",
    "J2026",
    "B2026",
    "E2026",
    "T2026",
    "JY2026",
    "GM2026",
    "D2026",
  ]) {
    now += 61000;
    const r = await redeem(d.token, code);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, "code_unavailable");
    assert.match(r.body.error, /not available yet/);
  }
  assert.deepEqual((await call("GET", "/me", d.token)).body.unlocked_heroes, []);
  assert.equal((await pg.query("select * from nw_account_unlocks")).rows.length, 0);
});
it("rejects bad formats and prototype property codes", async () => {
  const d = await device();
  for (const code of [
    null,
    {},
    42,
    "",
    " ",
    "x".repeat(65),
    "B LIZZARD",
    "__proto__",
    "constructor",
  ]) {
    assert.equal((await redeem(d.token, code)).status, 400);
  }
});
it("concurrent replay grants exactly once", async () => {
  const d = await device();
  const rs = await Promise.all(Array.from({ length: 8 }, () => redeem(d.token, "Blizzard")));
  assert.equal(rs.filter((r) => r.body.already_owned === false).length, 1);
  assert.ok(rs.every((r) => r.status === 200));
  assert.equal((await pg.query("select * from nw_account_unlocks")).rows.length, 1);
});
it("database quota shared across service instances including invalid and reserved attempts", async () => {
  const d = await device();
  const other = createService({ db: pgliteDb(pg), now: () => new Date(now) });
  const rs = await Promise.all(
    Array.from({ length: 15 }, (_, i) =>
      call("POST", "/me/unlocks", d.token, { code: i % 2 ? "bad" : "W2026" }, i % 2 ? svc : other),
    ),
  );
  assert.equal(rs.filter((r) => r.status === 429).length, 5);
  now += 60000;
  assert.equal((await redeem(d.token, "Blizzard")).status, 200);
});
it("ownership survives token rotation as used by email recovery and service restart", async () => {
  const d = await device();
  await redeem(d.token, "Patrick");
  await pg.query("update nw_players set token_hash=$1 where id=$2", [
    hashToken("replacement"),
    d.player_id,
  ]);
  const other = createService({ db: pgliteDb(pg) });
  assert.equal((await call("GET", "/me", d.token)).status, 401);
  assert.deepEqual(
    (await call("GET", "/me", "replacement", undefined, other)).body.unlocked_backgrounds,
    ["st_patrick"],
  );
});
it("account deletion removes entitlements and quota, recreated account owns nothing", async () => {
  const d = await device();
  await redeem(d.token, "Blizzard");
  assert.equal(
    (await call("DELETE", "/me", d.token, { confirm: "DELETE MY ACCOUNT" })).status,
    200,
  );
  assert.equal((await pg.query("select * from nw_account_unlocks")).rows.length, 0);
  assert.equal((await pg.query("select * from nw_unlock_rate")).rows.length, 0);
  assert.equal((await redeem(d.token, "Blizzard")).status, 401);
  const n = await device();
  assert.deepEqual((await call("GET", "/me", n.token)).body.unlocked_backgrounds, []);
});
it("migration never promotes client-asserted legacy unlocks and preserves verified grants on rerun", async () => {
  const d = await device();
  const legacy = ["blizzard", "tictactoe", "new_year", "fourth_july", "st_patrick", "W2026"];
  // The old /me API deliberately accepts these untrusted legacy assertions.
  const asserted = await call("PATCH", "/me", d.token, { unlocks: legacy });
  assert.equal(asserted.status, 200);
  assert.deepEqual(asserted.body.unlocked_backgrounds, []);
  // Reproduce first deployment after a client has prefilled the legacy column.
  await pg.exec("drop table nw_account_unlocks, nw_unlock_rate");
  await pg.exec(migration);
  await pg.exec(migration);
  const p = (await call("GET", "/me", d.token)).body;
  assert.deepEqual(p.unlocks, legacy);
  assert.deepEqual(p.unlocked_backgrounds, []);
  assert.deepEqual(p.unlocked_heroes, []);
  await redeem(d.token, "Patrick");
  await call("PATCH", "/me", d.token, { unlocks: ["blizzard"] });
  await pg.exec(migration);
  assert.deepEqual((await call("GET", "/me", d.token)).body.unlocked_backgrounds, ["st_patrick"]);
});

it("N2026 grants Nick once, persists across recovery, and leaves base roster untouched", async () => {
  const a = await device(),
    b = await device();
  const r = await redeem(a.token, " n2026 ");
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.unlock, { kind: "hero", id: "nick" });
  assert.deepEqual(r.body.unlocked_heroes, ["nick"]);
  assert.equal((await redeem(a.token, "N2026")).body.already_owned, true);
  assert.deepEqual((await call("GET", "/me", b.token)).body.unlocked_heroes, []);
  const roster = (await call("GET", "/heroes")).body;
  assert.equal(roster.heroes.length, 33);
  assert.equal(roster.heroes.includes("nick"), false);
  assert.deepEqual(roster.secret_heroes, ["nick", "jb_rocker"]);
  await pg.query("update nw_players set token_hash=$1 where id=$2", [
    hashToken("nick-recovered"),
    a.player_id,
  ]);
  assert.deepEqual((await call("GET", "/me", "nick-recovered")).body.unlocked_heroes, ["nick"]);
  assert.equal(
    (await call("DELETE", "/me", "nick-recovered", { confirm: "DELETE MY ACCOUNT" })).status,
    200,
  );
  assert.deepEqual((await call("GET", "/me", (await device()).token)).body.unlocked_heroes, []);
});
it("Nick cannot be selected by forged profile, guest, room or tournament requests", async () => {
  assert.equal(
    (await call("POST", "/auth/device", undefined, { last_hero_id: "nick" })).status,
    403,
  );
  const d = await device();
  await call("PATCH", "/me", d.token, { screen_name: "NickTester", unlocks: ["nick", "N2026"] });
  const patch = () => call("PATCH", "/me", d.token, { last_hero_id: "nick" });
  assert.equal((await patch()).status, 403);
  assert.equal((await call("POST", "/rooms", undefined, { character_id: "nick" })).status, 403);
  assert.equal((await call("POST", "/rooms", d.token, { character_id: "nick" })).status, 403);
  const otherRoom = await call("POST", "/rooms", undefined, { name: "Other" });
  assert.equal(otherRoom.status, 201);
  assert.equal(
    (await call("POST", `/rooms/${otherRoom.body.code}/join`, d.token, { character_id: "nick" }))
      .status,
    403,
  );
  const tour = { size: 4, starts_in_minutes: 5, character_id: "nick" };
  assert.equal((await call("POST", "/tournaments", d.token, tour)).status, 403);
  const host = await device();
  await call("PATCH", "/me", host.token, { screen_name: "TourHost" });
  const publicTour = await call("POST", "/tournaments", host.token, {
    size: 4,
    starts_in_minutes: 5,
  });
  assert.equal(publicTour.status, 201);
  assert.equal(
    (
      await call("POST", `/tournaments/${publicTour.body.code}/join`, d.token, {
        character_id: "nick",
      })
    ).status,
    403,
  );
  await redeem(d.token, "N2026");
  assert.equal((await patch()).status, 200);
  const joined = await call("POST", `/rooms/${otherRoom.body.code}/join`, d.token, {
    character_id: "nick",
  });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  assert.equal((await call("POST", "/tournaments", d.token, tour)).status, 201);
});

it("jb_rocker cannot be selected by forged profile, guest, room or tournament requests", async () => {
  assert.equal(
    (await call("POST", "/auth/device", undefined, { last_hero_id: "jb_rocker" })).status,
    403,
  );
  const d = await device();
  await call("PATCH", "/me", d.token, { screen_name: "NickTester", unlocks: ["jb_rocker", "JB2026"] });
  const patch = () => call("PATCH", "/me", d.token, { last_hero_id: "jb_rocker" });
  assert.equal((await patch()).status, 403);
  assert.equal((await call("POST", "/rooms", undefined, { character_id: "jb_rocker" })).status, 403);
  assert.equal((await call("POST", "/rooms", d.token, { character_id: "jb_rocker" })).status, 403);
  const otherRoom = await call("POST", "/rooms", undefined, { name: "Other" });
  assert.equal(otherRoom.status, 201);
  assert.equal(
    (await call("POST", `/rooms/${otherRoom.body.code}/join`, d.token, { character_id: "jb_rocker" }))
      .status,
    403,
  );
  const tour = { size: 4, starts_in_minutes: 5, character_id: "jb_rocker" };
  assert.equal((await call("POST", "/tournaments", d.token, tour)).status, 403);
  const host = await device();
  await call("PATCH", "/me", host.token, { screen_name: "TourHost" });
  const publicTour = await call("POST", "/tournaments", host.token, {
    size: 4,
    starts_in_minutes: 5,
  });
  assert.equal(publicTour.status, 201);
  assert.equal(
    (
      await call("POST", `/tournaments/${publicTour.body.code}/join`, d.token, {
        character_id: "jb_rocker",
      })
    ).status,
    403,
  );
  await redeem(d.token, "JB2026");
  assert.equal((await patch()).status, 200);
  const joined = await call("POST", `/rooms/${otherRoom.body.code}/join`, d.token, {
    character_id: "jb_rocker",
  });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  assert.equal((await call("POST", "/tournaments", d.token, tour)).status, 201);
});

it("JB2026 is case insensitive, idempotent, account-scoped and survives token recovery", async () => {
 const a = await device(), b = await device();
 for (const [i,code] of ["jb2026"," JB2026 ","jB2026"].entries()) {
  const r = await redeem(a.token,code);
  assert.equal(r.status,200);
  assert.deepEqual(r.body.unlock,{kind:"hero",id:"jb_rocker"});
  assert.equal(r.body.already_owned,i>0);
 }
 assert.deepEqual((await call("GET","/me",b.token)).body.unlocked_heroes,[]);
 await pg.query("update nw_players set token_hash=$1 where id=$2",[hashToken("rocker-recovered"),a.player_id]);
 assert.deepEqual((await call("GET","/me","rocker-recovered")).body.unlocked_heroes,["jb_rocker"]);
 await redeem("rocker-recovered","Prof26"); await redeem("rocker-recovered","N2026");
 assert.deepEqual((await call("GET","/me","rocker-recovered")).body.unlocked_heroes,["jb_rocker","nick","professor_gilt"]);
 assert.equal((await call("DELETE","/me","rocker-recovered",{confirm:"DELETE MY ACCOUNT"})).status,200);
 assert.deepEqual((await call("GET","/me",(await device()).token)).body.unlocked_heroes,[]);
});

it("legacy Professor stays selectable before/after Prof26, new tech and original James remain distinct", async () => {
 const d=await device();
 for(const hero of ['professor_gilt','jb_circuit','james_ii']) {
  assert.equal((await call('PATCH','/me',d.token,{last_hero_id:hero})).status,200);
  assert.equal((await call('POST','/auth/device',undefined,{last_hero_id:hero})).status,201);
 }
 const r=await redeem(d.token,'pRoF26');assert.equal(r.status,200);
 assert.equal(r.body.unlock.id,'professor_gilt');assert.equal((await redeem(d.token,'PROF26')).body.already_owned,true);
 assert.deepEqual((await call('GET','/me',d.token)).body.unlocked_heroes,['professor_gilt']);
 const roster=(await call('GET','/heroes')).body;
 assert.ok(roster.heroes.includes('professor_gilt'));assert.ok(roster.heroes.includes('jb_circuit'));assert.ok(roster.heroes.includes('james_ii'));
});
it("old Professor client can match the new tech client without unlocking", async () => {
 const a=await device(),b=await device();
 const room=await call('POST','/rooms',a.token,{name:'LegacyProfessor',character_id:'professor_gilt'});
 assert.equal(room.status,201);
 const join=await call('POST',`/rooms/${room.body.code}/join`,b.token,{name:'NewJames',character_id:'jb_circuit'});
 assert.equal(join.status,200);
 const x=room.body.seat===1?room.body.token:join.body.token;
 assert.equal((await call('POST',`/rooms/${room.body.code}/moves`,undefined,{token:x,board:4,cell:0,seq:1})).status,200);
 const stateA=await call('GET',`/rooms/${room.body.code}`,room.body.token);
 const stateB=await call('GET',`/rooms/${room.body.code}`,join.body.token);
 assert.equal(stateA.status,200);assert.equal(stateB.status,200);assert.deepEqual(stateA.body.state,stateB.body.state);
});
