/** In-memory SQL tests only. Never imports the production database connection. */
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { accountUnlocks, redeemUnlock } from "./unlocks.ts";
import { canonicalHero, HERO_IDS, SECRET_HERO_IDS, requireHeroOwnership } from "./heroes.ts";
import { createService, type Service } from "./service.ts";
import { pgliteDb } from "./store.ts";
import type { PlayerRow } from "./players.ts";

let pg: PGlite;
let svc: Service;
const owner = { id: "owner" } as PlayerRow;
const other = { id: "other" } as PlayerRow;
before(async () => {
  pg = new PGlite();
  await pg.waitReady;
  await pg.exec("create table nw_players(id text primary key)");
  // Exercise the already-shipped table definition in a disposable local DB.
  await pg.exec(readFileSync(new URL("../../../migrations/0011_nineweave_account_unlocks.sql", import.meta.url), "utf8"));
});
after(async () => { await pg.close(); });
beforeEach(async () => {
  await pg.exec("truncate nw_players cascade; insert into nw_players(id) values('owner'),('other')");
  svc = createService({ db: pgliteDb(pg), now: () => new Date("2026-11-18T14:00:00Z") });
});

describe("JB Circuit and Professor account contract", () => {
  it("keeps 32 public heroes, canonical Professor ID, and Nick", () => {
    assert.equal(HERO_IDS.length, 32);
    assert.ok(HERO_IDS.includes("jb_circuit"));
    assert.ok(!HERO_IDS.some((id: string) => id === "professor_gilt"));
    assert.deepEqual(SECRET_HERO_IDS, ["nick", "professor_gilt", "jb_rocker"]);
    assert.equal(canonicalHero("professor_gilt"), "professor_gilt");
    assert.equal(canonicalHero("jb_circuit"), "jb_circuit");
  });
  it("keeps old James II records distinct from the new tech hero", async () => {
    assert.equal(canonicalHero("james_ii"), "james_ii");
    assert.notEqual(canonicalHero("james_ii"), canonicalHero("jb_circuit"));
    assert.ok(HERO_IDS.includes("james_ii"));
    await requireHeroOwnership(svc, null, "james_ii");
    await requireHeroOwnership(svc, null, "jb_circuit");
  });
  it("accepts mixed-case Prof26 and idempotently stores one permanent grant", async () => {
    for (const [i, code] of ["Prof26", "pRoF26", "PROF26", " prof26 "].entries()) {
      const result = await redeemUnlock(svc, owner, { code });
      assert.deepEqual(result.unlock, { kind: "hero", id: "professor_gilt" });
      assert.equal(result.already_owned, i > 0);
      assert.deepEqual(result.unlocked_heroes, ["professor_gilt"]);
    }
    const rows = await svc.db.query("select * from nw_account_unlocks where player_id=$1", [owner.id]);
    assert.equal(rows.length, 1);
    const restoredService = createService({ db: pgliteDb(pg) });
    assert.deepEqual(await accountUnlocks(restoredService, owner.id), { unlocked_backgrounds: [], unlocked_heroes: ["professor_gilt"] });
    await requireHeroOwnership(restoredService, owner.id, "professor_gilt");
  });
  it("retains N2026 in either redemption order and across restored sessions", async () => {
    for (const player of [owner, other]) {
      const codes = player === owner ? ["n2026", "pROf26"] : ["Prof26", "N2026"];
      for (const code of codes) await redeemUnlock(svc, player, { code });
      const restoredService = createService({ db: pgliteDb(pg) });
      assert.deepEqual((await accountUnlocks(restoredService, player.id)).unlocked_heroes, ["nick", "professor_gilt"]);
      await requireHeroOwnership(restoredService, player.id, "nick");
      await requireHeroOwnership(restoredService, player.id, "professor_gilt");
    }
  });
  it("rejects unowned Professor and Nick for guests and other accounts", async () => {
    await redeemUnlock(svc, owner, { code: "Prof26" });
    for (const playerId of [null, other.id]) {
      for (const hero of ["professor_gilt", "nick"]) {
        await assert.rejects(requireHeroOwnership(svc, playerId, hero), { status: 403, extra: { code: "hero_locked" } });
      }
    }
    assert.deepEqual((await accountUnlocks(svc, other.id)).unlocked_heroes, []);
    await requireHeroOwnership(svc, null, "jb_circuit");
  });
  it("does not allow spoofing the owner or unlock kind in request payloads", async () => {
    for (const payload of [{ code: "Prof26", player_id: "owner" }, { code: "Prof26", kind: "hero" }, { code: "Prof26", id: "nick" }]) {
      await assert.rejects(redeemUnlock(svc, other, payload), { status: 400 });
    }
    assert.deepEqual((await accountUnlocks(svc, other.id)).unlocked_heroes, []);
  });
  it("continues background codes and unlocks JB2026 independently", async () => {
    assert.deepEqual((await redeemUnlock(svc, owner, { code: "bLiZzArD" })).unlock, { kind: "background", id: "blizzard" });
    assert.deepEqual((await redeemUnlock(svc, owner, { code: "jb2026" })).unlock, {kind: "hero", id: "jb_rocker"});
    assert.deepEqual((await accountUnlocks(svc, owner.id)).unlocked_heroes, ["jb_rocker"]);
  });
  it("cascades account deletion and never reuses the removed account grant", async () => {
    await redeemUnlock(svc, owner, { code: "Prof26" });
    await svc.db.query("delete from nw_players where id=$1", [owner.id]);
    assert.deepEqual((await accountUnlocks(svc, owner.id)).unlocked_heroes, []);
    await assert.rejects(redeemUnlock(svc, owner, { code: "Prof26" }), { status: 401 });
  });
});
