/**
 * Framework-agnostic HTTP layer for `/api/nineweave/*`: `Request -> Response`.
 * The TanStack catch-all route delegates here; tests call it directly with a
 * PGlite-backed service, so the full HTTP contract is exercised without a
 * listening server. See ONLINE_API.md for the contract.
 */
import { corsHeaders } from "./cors.ts";
import {
  confirmRecovery,
  confirmVerification,
  requestRecovery,
  requestVerification,
} from "./email.ts";
import { HERO_ALIASES, HERO_IDS } from "./heroes.ts";
import {
  leaderboard,
  playerByToken,
  profile,
  registerDevice,
  requirePlayer,
  updateMe,
} from "./players.ts";
import {
  createRoom,
  joinRoom,
  leaveRoom,
  listRooms,
  playMove,
  pollRoom,
  requestRematch,
} from "./rooms.ts";
import { isRoomCode } from "./security.ts";
import { ApiError, type Service } from "./service.ts";
import type { RateLimits } from "./rate-limit.ts";

export const MAX_BODY_BYTES = 8 * 1024;
const PREFIX = "/api/nineweave";

function json(status: number, body: unknown, origin: string | null): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      ...(status === 204 ? {} : { "Content-Type": "application/json; charset=utf-8" }),
      "Cache-Control": "no-store",
      ...corsHeaders(origin),
    },
  });
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  const match = header?.match(/^Bearer\s+(\S+)\s*$/i);
  return match ? match[1] : null;
}

function clientKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || request.headers.get("x-real-ip")?.trim() || "unknown";
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) throw new ApiError(413, "Request body is too large");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES)
    throw new ApiError(413, "Request body is too large");
  if (!text.trim()) return {};
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new ApiError(400, "Request body must be JSON");
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    throw new ApiError(400, "Request body must be a JSON object");
  return data as Record<string, unknown>;
}

function limit(svc: Service, bucket: keyof RateLimits, request: Request) {
  if (!svc.limiter.hit(bucket, clientKey(request), svc.now().getTime()))
    throw new ApiError(429, "Too many requests. Slow down and try again shortly.");
}

function methodNotAllowed(): never {
  throw new ApiError(405, "Method not allowed");
}

async function route(
  svc: Service,
  request: Request,
  segments: string[],
  url: URL,
): Promise<[number, unknown]> {
  const method = request.method.toUpperCase();
  const bearer = bearerToken(request);
  const [head, code, action, ...rest] = segments;

  if (head === "health" && segments.length === 1) {
    if (method !== "GET") methodNotAllowed();
    return [200, { ok: true }];
  }
  if (head === "heroes" && segments.length === 1) {
    if (method !== "GET") methodNotAllowed();
    return [200, { heroes: HERO_IDS, aliases: HERO_ALIASES }];
  }
  if (head === "auth" && code === "device" && segments.length === 2) {
    if (method !== "POST") methodNotAllowed();
    limit(svc, "device", request);
    return [201, await registerDevice(svc, await readJson(request))];
  }
  if (
    head === "auth" &&
    code === "email" &&
    action === "recover" &&
    (rest.length === 0 || (rest.length === 1 && rest[0] === "confirm"))
  ) {
    if (method !== "POST") methodNotAllowed();
    if (rest.length === 0) {
      limit(svc, "email", request);
      return [200, await requestRecovery(svc, await readJson(request))];
    }
    if (rest[0] === "confirm") {
      limit(svc, "verify", request);
      return [200, await confirmRecovery(svc, await readJson(request))];
    }
  }
  if (
    head === "me" &&
    code === "email" &&
    action === "verification" &&
    (rest.length === 0 || (rest.length === 1 && rest[0] === "confirm"))
  ) {
    if (method !== "POST") methodNotAllowed();
    if (rest.length === 0) {
      limit(svc, "email", request);
      const player = await requirePlayer(svc, bearer);
      return [200, await requestVerification(svc, player, await readJson(request))];
    }
    if (rest[0] === "confirm") {
      limit(svc, "verify", request);
      const player = await requirePlayer(svc, bearer);
      return [200, await confirmVerification(svc, player, await readJson(request))];
    }
  }
  if (head === "me" && segments.length === 1) {
    if (method === "GET") return [200, await profile(svc, await requirePlayer(svc, bearer))];
    if (method === "PATCH") {
      limit(svc, "write", request);
      const player = await requirePlayer(svc, bearer);
      return [200, await updateMe(svc, player, await readJson(request))];
    }
    methodNotAllowed();
  }
  if (head === "leaderboard" && segments.length === 1) {
    if (method !== "GET") methodNotAllowed();
    // An unknown/seat token on the leaderboard is simply anonymous.
    const caller = bearer ? await playerByToken(svc, bearer) : null;
    return [200, await leaderboard(svc, url.searchParams.get("limit"), caller)];
  }
  if ((head === "rooms" || head === "lobby") && segments.length === 1) {
    if (method === "GET") return [200, await listRooms(svc)];
    if (method === "POST" && head === "rooms") {
      limit(svc, "create", request);
      return [201, await createRoom(svc, await readJson(request), bearer)];
    }
    methodNotAllowed();
  }
  if (head === "rooms" && code !== undefined && rest.length === 0) {
    const roomCode = code.toUpperCase();
    if (!isRoomCode(roomCode)) throw new ApiError(404, "Room not found or expired");
    if (action === undefined) {
      if (method !== "GET") methodNotAllowed();
      const sinceRaw = Number.parseInt(url.searchParams.get("since") ?? "0", 10);
      const since = Number.isFinite(sinceRaw) && sinceRaw > 0 ? sinceRaw : 0;
      return [200, await pollRoom(svc, roomCode, since, [bearer])];
    }
    if (method !== "POST") methodNotAllowed();
    switch (action) {
      case "join":
        limit(svc, "join", request);
        return [200, await joinRoom(svc, roomCode, await readJson(request), bearer)];
      case "moves":
        limit(svc, "move", request);
        return [200, await playMove(svc, roomCode, await readJson(request), bearer)];
      case "rematch":
        limit(svc, "move", request);
        return [200, await requestRematch(svc, roomCode, await readJson(request), bearer)];
      case "leave":
        limit(svc, "move", request);
        return [200, await leaveRoom(svc, roomCode, await readJson(request), bearer)];
      case "cancel":
        limit(svc, "move", request);
        return [
          200,
          await leaveRoom(svc, roomCode, await readJson(request), bearer, { hostCancelOnly: true }),
        ];
    }
  }
  throw new ApiError(404, "Not found");
}

/** A bare error response with the API's CORS / no-store headers. */
export function errorResponse(request: Request, status: number, message: string): Response {
  if (request.method.toUpperCase() === "OPTIONS")
    return json(204, null, request.headers.get("origin"));
  return json(status, { error: message }, request.headers.get("origin"));
}

/** Handle any request under `/api/nineweave`. */
export async function handleNineweaveRequest(svc: Service, request: Request): Promise<Response> {
  const origin = request.headers.get("origin");
  if (request.method.toUpperCase() === "OPTIONS") return json(204, null, origin);
  const url = new URL(request.url);
  const at = url.pathname.indexOf(PREFIX);
  const tail = at === -1 ? "" : url.pathname.slice(at + PREFIX.length);
  const segments = tail.split("/").filter(Boolean).map(decodeURIComponent);
  try {
    const [status, body] = await route(svc, request, segments, url);
    return json(status, body, origin);
  } catch (err) {
    if (err instanceof ApiError)
      return json(err.status, { error: err.message, ...err.extra }, origin);
    console.error("[nineweave] unhandled error:", err instanceof Error ? err.message : "unknown");
    return json(500, { error: "Something went wrong on the server" }, origin);
  }
}
