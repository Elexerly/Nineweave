/**
 * Production wiring: one service per server instance backed by `getSql()`
 * (Neon HTTP when a database URL is configured) and, when
 * `NINEWEAVE_RESEND_API_KEY` is set, a Resend mailer for email codes.
 *
 * `@/lib/db` is imported lazily: loading it with no database configured
 * starts the embedded PGLite fallback, which the production bundle can't run
 * (and which would keep games in throwaway per-instance memory anyway). So a
 * production build without a database answers the API with 503 and leaves
 * the rest of the site untouched; the dev server keeps using PGLite.
 */
import { resolveDatabaseUrl } from "../../../scripts/database-url.mjs";
import { errorResponse, handleNineweaveRequest } from "./api.ts";
import { adminConfig, resolveResendKey } from "./config.ts";
import type { Db } from "./store.ts";
import { resendMailer } from "./mailer.ts";
import { createService, type Service } from "./service.ts";

let service: Service | undefined;
let activeDb: Db | undefined;
let activeKey: string | undefined;
let activeBoardReady: boolean | undefined;

async function getService(): Promise<Service> {
  const { getSql } = await import("../db");
  const [db, key] = await Promise.all([getSql(), resolveResendKey(process.env, adminConfig)]);
  const boardReadyEnabled = process.env.NINEWEAVE_BOARD_READY_V1 === "1";
  if (!service || activeDb !== db || activeKey !== key || activeBoardReady !== boardReadyEnabled) {
    service = createService({ db, mailer: resendMailer(key), boardReadyEnabled });
    activeDb = db;
    activeKey = key;
    activeBoardReady = boardReadyEnabled;
  }
  return service;
}

export async function handleNineweave(request: Request): Promise<Response> {
  if (import.meta.env.PROD && !resolveDatabaseUrl(process.env)) {
    return errorResponse(request, 503, "Online play is not configured on this server yet");
  }
  try {
    return await handleNineweaveRequest(await getService(), request);
  } catch {
    return errorResponse(request, 503, "Online server is temporarily unavailable");
  }
}
