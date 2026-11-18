import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { HERO_IDS, HERO_ALIASES, canonicalHero } from "./heroes.ts";

describe("Patrick replaces Kite in the server roster", () => {
  it("retains legacy slots plus the new tech hero with Patrick in Kite's original slot", () => {
    assert.equal(HERO_IDS.length, 33);
    assert.equal(new Set(HERO_IDS).size, 33);
    assert.equal(HERO_IDS[11], "patrick_laquin");
    assert.equal((HERO_IDS as readonly string[]).includes("kite_hollow"), false);
  });
  it("accepts canonical and legacy IDs without weakening validation", () => {
    assert.equal(HERO_ALIASES.kite_hollow, "patrick_laquin");
    assert.equal(canonicalHero("kite_hollow"), "patrick_laquin");
    assert.equal(canonicalHero(" patrick_laquin "), "patrick_laquin");
    for (const [oldId, currentId] of Object.entries(HERO_ALIASES)) assert.equal(canonicalHero(oldId), currentId);
    for (const invalid of [null, 123, "", "unknown", "__proto__"]) assert.equal(canonicalHero(invalid), null);
  });
});
