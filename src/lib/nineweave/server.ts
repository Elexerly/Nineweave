/**
 * Production wiring: one service per server instance backed by `getSql()`
 * (Neon HTTP when a database URL is configured).
 *
 * `@/lib/db` is imported lazily: loading it with no database configured
 * starts the embedded PGLite fallback, which the production bundle can't run
 * (and which would keep games in throwaway per-instance memory anyway). So a
 * production build without a database answers the API with 503 and leaves
 * the rest of the site untouched; the dev server keeps using PGLite.
 */
import { resolveDatabaseUrl } from "../../../scripts/database-url.mjs";
import { errorResponse, handleNineweaveRequest } from "./api.ts";
import { createService, type Service } from "./service.ts";

let servicePromise: Promise<Service> | null = null;

function getService(): Promise<Service> {
  servicePromise ??= import("../db")
    .then(({ getSql }) => getSql())
    .then((db) => createService({ db }))
    .catch((err) => {
      servicePromise = null;
      throw err;
    });
  return servicePromise;
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
