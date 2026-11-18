import { ApiError, type Service } from "./service.ts";
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
  "patrick_laquin",
  "professor_gilt", // Keep legacy client selection valid until frontend rollout.
  "jb_circuit",
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
  kite_hollow: "patrick_laquin",
  erik_comet: "erick_comet",
  ak_shade: "simon_shade",
  derrick_torque: "devin_torque",
  nova_sable: "aiden_vortex",
  mateo_ricochet: "ethan_ricochet",
};

/** The Godot client's legacy default character. */
export const DEFAULT_HERO = "auric_rex";

export const SECRET_HERO_IDS = ["nick", "jb_rocker"] as const;
const SECRET_HERO_SET: ReadonlySet<string> = new Set(SECRET_HERO_IDS);
const HERO_SET: ReadonlySet<string> = new Set([...HERO_IDS, ...SECRET_HERO_IDS]);

/** Server entitlements, never the client-asserted legacy unlocks JSON. */
export async function requireHeroOwnership(svc: Service, playerId: string | null, hero: string) {
  if (!SECRET_HERO_SET.has(hero)) return;
  const rows = playerId
    ? await svc.db.query<{ unlock_id: string }>(
        "select unlock_id from nw_account_unlocks where player_id=$1 and kind='hero' and unlock_id=$2",
        [playerId, hero],
      )
    : [];
  if (!rows.length)
    throw new ApiError(403, "Unlock this secret character on your account first.", {
      code: "hero_locked",
    });
}

/** Canonical ID for a known hero or alias, else null. */
export function canonicalHero(id: unknown): string | null {
  if (typeof id !== "string") return null;
  const trimmed = id.trim();
  const canonical = Object.hasOwn(HERO_ALIASES, trimmed) ? HERO_ALIASES[trimmed] : trimmed;
  return HERO_SET.has(canonical) ? canonical : null;
}
