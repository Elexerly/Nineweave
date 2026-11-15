/**
 * Canonical hero (character) IDs — mirrors `godot/characters/roster.gd`.
 * Incoming legacy aliases are accepted and canonicalized; responses always
 * carry canonical IDs.
 */
export const HERO_IDS = [
  "cryon",
  "aurelia",
  "vesper_vale",
  "auric_rex",
  "nyx_thread",
  "cobalt_bastion",
  "ember_quill",
  "lumen_pike",
  "shard_jack",
  "madame_solstice",
  "bramble_ox",
  "kite_hollow",
  "professor_gilt",
  "siren_coil",
  "ryan_blaze",
  "tempest_vega",
  "james_ii",
  "sara",
  "daphne",
  "jason_danger",
  "dylan_volt",
  "max_granite",
  "kellen_byte",
  "simon_shade",
  "alex_wilder",
  "rose_valor",
  "grayson_quake",
  "erick_comet",
  "devin_torque",
  "pope_slam",
  "ethan_ricochet",
  "aiden_vortex",
] as const;

export const HERO_ALIASES: Readonly<Record<string, string>> = {
  erik_comet: "erick_comet",
  ak_shade: "simon_shade",
  derrick_torque: "devin_torque",
  nova_sable: "aiden_vortex",
  mateo_ricochet: "ethan_ricochet",
};

/** The Godot client's legacy default character. */
export const DEFAULT_HERO = "auric_rex";

const HERO_SET: ReadonlySet<string> = new Set(HERO_IDS);

/** Canonical ID for a known hero or alias, else null. */
export function canonicalHero(id: unknown): string | null {
  if (typeof id !== "string") return null;
  const trimmed = id.trim();
  const canonical = Object.hasOwn(HERO_ALIASES, trimmed) ? HERO_ALIASES[trimmed] : trimmed;
  return HERO_SET.has(canonical) ? canonical : null;
}
