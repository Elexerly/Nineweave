/** Server-only HTTP contract. Never return caught errors or submitted values. */
import { extractPostgresUrl } from "../../../scripts/database-url.mjs";
import { createHash, randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { adminSetupAvailable } from "./admin-setup.ts";
import { migrateAdminTarget } from "./admin-migrations.ts";
import { resolveNineweaveDatabaseUrl, resolveResendKey, type ConfigStore, type ConfigValues } from "./config.ts";
import { resendMailer, type Mailer } from "./mailer.ts";
import type { Db } from "./store.ts";

export interface AdminOptions {
  enabled: boolean;
  hash: string;
  builtin: () => Promise<Db>;
  config: ConfigStore;
  active: () => Promise<Db>;
  connect: (url: string) => Promise<Db>;
  migrations: Record<string, string>;
  env: Record<string, string | undefined>;
  now?: () => number;
  mailer?: (key: string | undefined) => Mailer | null;
}

export const ADMIN_HEADERS = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Robots-Tag": "noindex, nofollow",
};

function json(status: number, body: unknown): Response {
  return Response.json(body, { status, headers: { ...ADMIN_HEADERS, ...(status === 429 ? { "Retry-After": "900" } : {}) } });
}

export async function verifyAdminPassphrase(passphrase: string, hash: string): Promise<boolean> {
  if (!adminSetupAvailable(true, hash)) return false;
  const [, salt, expected] = hash.split("$");
  const key = await new Promise<Buffer>((resolve, reject) => {
    scrypt(passphrase, Buffer.from(salt, "hex"), 32, { N: 16384, r: 8, p: 1 }, (error, value) => error ? reject(error) : resolve(value));
  });
  return timingSafeEqual(key, Buffer.from(expected, "hex"));
}

/**
 * A single atomic upsert serializes the global rolling-hour budget across
 * instances. Reserve before scrypt; release only on success. Concurrent probes
 * cannot slip past the quota. No IP or passphrase is persisted in plaintext.
 */
async function authenticate(db: Db, request: Request, passphrase: string, hash: string, now: number) {
  const rawIp = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || request.headers.get("x-real-ip")?.trim() || "unknown";
  const ip = createHash("sha256").update(rawIp).digest("hex");
  const id = randomBytes(16).toString("hex");
  const entry = JSON.stringify([{ id, ip, at: now }]);
  const rows = await db.query(
    `insert into nw_admin_config (key, value) values ('admin_setup_attempts', $1)
     on conflict (key) do update set
       value = (coalesce((select jsonb_agg(e) from jsonb_array_elements(nw_admin_config.value::jsonb) e
         where (e->>'at')::bigint > $2::bigint - 3600000), '[]'::jsonb) || $1::jsonb)::text,
       updated_at = now()
     where (select count(*) from jsonb_array_elements(nw_admin_config.value::jsonb) e
       where (e->>'at')::bigint > $2::bigint - 3600000) < 20
       and (select count(*) from jsonb_array_elements(nw_admin_config.value::jsonb) e
       where e->>'ip' = $3 and (e->>'at')::bigint > $2::bigint - 900000) < 5
     returning key`,
    [entry, now, ip],
  );
  if (!rows.length) return 429;
  if (!await verifyAdminPassphrase(passphrase, hash)) return 401;
  await db.query(
    `update nw_admin_config set value = coalesce((select jsonb_agg(e) from jsonb_array_elements(value::jsonb) e
       where e->>'id' <> $1), '[]'::jsonb)::text, updated_at = now() where key = 'admin_setup_attempts'`,
    [id],
  );
  return 200;
}

class InputError extends Error {}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new InputError();
  const reader = request.body?.getReader();
  if (!reader) throw new InputError();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 16_384) { await reader.cancel(); throw new InputError(); }
    chunks.push(value);
  }
  let body: unknown;
  try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new InputError(); }
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new InputError();
  return body as Record<string, unknown>;
}

function postgresUrl(value: string): string {
  let url: URL;
  try { url = new URL(value); } catch { throw new InputError(); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname || !url.username || url.pathname.length < 2) throw new InputError();
  return value;
}

function hostOnly(value: string | undefined): string | null {
  try { return value ? new URL(value).hostname : null; } catch { return null; }
}

async function status(options: AdminOptions) {
  const [url, key, config, db] = await Promise.all([
    resolveNineweaveDatabaseUrl(options.env, options.config),
    resolveResendKey(options.env, options.config),
    options.config.read(),
    options.active(),
  ]);
  const overridden = Boolean(extractPostgresUrl(options.env.NINEWEAVE_DATABASE_URL));
  const neonActive = overridden || Boolean(config.nineweave_database_url);
  const migrations = await db.query<{ name: string; applied_at: Date | string }>(
    "select name, applied_at from _migrations order by name",
  );
  return {
    database: neonActive ? "Neon" : "built-in",
    neon_host: neonActive ? hostOnly(url) : null,
    database_env_override: overridden,
    resend_key_set: Boolean(key),
    resend_key_last4: key ? key.slice(-4) : null,
    resend_env_override: Boolean(options.env.NINEWEAVE_RESEND_API_KEY?.trim()),
    migrations: migrations.map(({ name, applied_at }) => ({ name, applied_at })),
  };
}

/** Delete only the specified test players and associated data, atomically. */
export async function clearTestAccounts(db: Db) {
  const target = "select id from nw_players where screen_name like 'T4c%' or screen_name like 'NWSmoke%'";
  const rooms = `select id from nw_rooms where a_player_id in (${target}) or b_player_id in (${target})`;
  const tournaments = `select id from nw_tournaments where host_player_id in (${target}) or champion_player_id in (${target}) or id in (select tournament_id from nw_tournament_players where player_id in (${target}))`;
  // Count via RETURNING before the final player delete; FK cascades then have
  // no hidden leftovers. Whole associated test tournaments/rooms are removed
  // to avoid leaving live brackets pointing at deleted seats.
  const steps = [
    ["reports", `delete from nw_reports where reporter_id in (${target}) or reported_id in (${target}) returning id`],
    ["blocks", `delete from nw_blocks where blocker_id in (${target}) or blocked_id in (${target}) returning blocker_id`],
    ["email_challenges", `delete from nw_email_challenges where player_id in (${target}) returning id`],
    ["chat", `delete from nw_chat where player_id in (${target}) or room_id in (${rooms}) or room_id in (select id from nw_rooms where tournament_id in (${tournaments})) returning id`],
    ["matches", `delete from nw_matches where x_player_id in (${target}) or o_player_id in (${target}) or room_id in (${rooms}) or room_id in (select id from nw_rooms where tournament_id in (${tournaments})) returning id`],
    ["rooms", `delete from nw_rooms where id in (${rooms}) or tournament_id in (${tournaments}) returning id`],
    ["tournament_matches", `delete from nw_tournament_matches where tournament_id in (${tournaments}) or a_player_id in (${target}) or b_player_id in (${target}) returning tournament_id`],
    ["tournament_players", `delete from nw_tournament_players where tournament_id in (${tournaments}) or player_id in (${target}) returning tournament_id`],
    // Keep tournament membership until after deleting the parent to preserve
    // the target predicate; see the snapshot step below.
  ];
  // Use a transaction-local snapshot in one SQL CTE for tournament IDs, since
  // membership is itself deleted. All steps use the same materialized IDs.
  const result = await db.transaction([
    { text: `create temporary table nw_admin_cleanup_tournaments on commit drop as ${tournaments}` },
    ...steps.map(([, text]) => ({ text: text.replaceAll(`(${tournaments})`, "(select id from nw_admin_cleanup_tournaments)") })),
    { text: "delete from nw_tournaments where id in (select id from nw_admin_cleanup_tournaments) returning id" },
    { text: `delete from nw_players where id in (${target}) returning id` },
  ]);
  return Object.fromEntries([...steps.map(([name], index) => [name, result[index + 1].length]), ["tournaments", result.at(-2)!.length], ["players", result.at(-1)!.length]]);
}

export async function handleAdminSetup(request: Request, options: AdminOptions): Promise<Response> {
  if (!adminSetupAvailable(options.enabled, options.hash)) return json(404, { error: "Not found" });
  if (!['GET', 'POST'].includes(request.method)) return json(405, { error: "Method not allowed" });
  // Header/body credentials only: never URLs, cookies or cross-origin CORS.
  const origin = request.headers.get("origin");
  if ((origin && origin !== new URL(request.url).origin) || request.headers.get("sec-fetch-site") === "cross-site") return json(403, { error: "Forbidden" });
  try {
    let body: Record<string, unknown> = {};
    if (request.method === 'POST') body = await readBody(request);
    const passphrase = request.method === 'GET' ? request.headers.get("x-nineweave-admin-passphrase") : body.passphrase;
    const credential = typeof passphrase === "string" && Buffer.byteLength(passphrase) <= 1024 ? passphrase : "";
    const auth = await authenticate(await options.builtin(), request, credential, options.hash, (options.now ?? Date.now)());
    if (auth !== 200) return json(auth, { error: auth === 429 ? "Too many attempts. Try again later." : "Invalid passphrase" });
    if (request.method === 'GET') return json(200, await status(options));

    const action = body.action ?? "save";
    if (action === "clear_test_accounts") return json(200, { cleared: await clearTestAccounts(await options.active()) });
    if (action === "send_test_email") {
      const mailer = (options.mailer ?? resendMailer)(await resolveResendKey(options.env, options.config));
      if (!mailer) return json(503, { error: "Email is not configured" });
      await mailer({ to: "patrick@probeyahngroup.com", subject: "Nineweave setup test", text: "Nineweave email is connected.", html: "<p>Nineweave email is connected.</p>" });
      return json(200, { sent: true });
    }
    if (action !== 'save') throw new InputError();
    const values: ConfigValues = {};
    for (const key of ['nineweave_database_url', 'resend_api_key'] as const) {
      if (body[key] !== undefined && typeof body[key] !== 'string') throw new InputError();
      const value = (body[key] as string | undefined)?.trim();
      if (value) values[key] = value;
    }
    if (values.resend_api_key && (values.resend_api_key.length < 8 || /\s/.test(values.resend_api_key))) throw new InputError();
    if (!Object.keys(values).length) throw new InputError();
    if (values.nineweave_database_url) {
      const url = postgresUrl(values.nineweave_database_url);
      // Failures never save the URL or the accompanying key. Migrations are
      // bundled strings, so deployed handlers never read the filesystem.
      await migrateAdminTarget(await options.connect(url), options.migrations);
    }
    await options.config.save(values);
    return json(200, { saved: true });
  } catch (error) {
    if (error instanceof InputError) return json(400, { error: "Check the submitted fields" });
    return json(503, { error: "Setup could not complete. Check the connection and try again." });
  }
}
