/**
 * Framework-agnostic HTTP layer for `/api/nineweave/*`: `Request -> Response`.
 * The TanStack catch-all route delegates here; tests call it directly with a
 * PGlite-backed service, so the full HTTP contract is exercised without a
 * listening server. See ONLINE_API.md for the contract.
 */
import {
  blockPlayer,
  capabilities,
  chatFor,
  listBlocks,
  postChat,
  reportPlayer,
  unblockPlayer,
} from "./chat.ts";
import { redeemUnlock } from "./unlocks.ts";
import { deleteOwnAccount } from "./account-deletion.ts";
import { corsHeaders } from "./cors.ts";
import {
  confirmRecovery,
  confirmVerification,
  requestRecovery,
  requestVerification,
} from "./email.ts";
import { HERO_ALIASES, HERO_IDS, SECRET_HERO_IDS } from "./heroes.ts";
import {
  completeTutorial,
  leaderboard,
  playerByToken,
  profile,
  registerDevice,
  requirePlayer,
  updateMe,
} from "./players.ts";
import {
  confirmBoardReady,
  createRoom,
  joinRoom,
  leaveRoom,
  listRooms,
  playMove,
  pollRoom,
  requestRematch,
  stillHere,
} from "./rooms.ts";
import { isRoomCode } from "./security.ts";
import {
  createTournament,
  isTournamentCode,
  joinTournament,
  leaveTournament,
  listTournaments,
  pollTournament,
  syncTournamentByCode,
} from "./tournaments.ts";
import { ApiError, type Service } from "./service.ts";
import type { RateLimits } from "./rate-limit.ts";

export const MAX_BODY_BYTES = 8 * 1024;
const PREFIX = "/api/nineweave";

/** Cache-Control for the public, version-only `GET /capabilities`. */
const CACHEABLE = "public, max-age=60";

function json(status: number, body: unknown, origin: string | null, cache = "no-store"): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      ...(status === 204 ? {} : { "Content-Type": "application/json; charset=utf-8" }),
      "Cache-Control": cache,
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

function intParam(url: URL, name: string): number {
  const raw = Number.parseInt(url.searchParams.get(name) ?? "0", 10);
  return Number.isFinite(raw) && raw > 0 ? raw : 0;
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
  if (head === "capabilities" && segments.length === 1) {
    if (method !== "GET") methodNotAllowed();
    return [200, { ...capabilities(), ...(svc.boardReadyEnabled ? { board_ready_v1: true } : {}) }];
  }
  if (head === "players" && segments.length === 2 && code === "block") {
    limit(svc, "moderation", request);
    if (method === "POST") return [200, await blockPlayer(svc, bearer, await readJson(request))];
    if (method === "DELETE")
      return [200, await unblockPlayer(svc, bearer, await readJson(request))];
    methodNotAllowed();
  }
  if (head === "players" && segments.length === 2 && code === "blocks") {
    if (method !== "GET") methodNotAllowed();
    return [200, await listBlocks(svc, bearer)];
  }
  if (head === "reports" && segments.length === 1) {
    if (method !== "POST") methodNotAllowed();
    limit(svc, "moderation", request);
    return [201, await reportPlayer(svc, bearer, await readJson(request))];
  }
  if (head === "heroes" && segments.length === 1) {
    if (method !== "GET") methodNotAllowed();
    return [200, { heroes: HERO_IDS, secret_heroes: SECRET_HERO_IDS, aliases: HERO_ALIASES }];
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
  if (head === "me" && code === "tutorial" && action === "complete" && rest.length === 0) {
    if (method !== "POST") methodNotAllowed();
    limit(svc, "write", request);
    const player = await requirePlayer(svc, bearer);
    const body = await readJson(request);
    if (Object.keys(body).length) throw new ApiError(400, "Send an empty object to complete the tutorial");
    return [200, await completeTutorial(svc, player)];
  }
  if (head === "me" && code === "unlocks" && segments.length === 2) {
    if (method !== "POST") methodNotAllowed();
    limit(svc, "write", request);
    const player = await requirePlayer(svc, bearer);
    return [200, await redeemUnlock(svc, player, await readJson(request))];
  }
  if (head === "me" && segments.length === 1) {
    if (method === "DELETE") {
      limit(svc, "write", request);
      return [200, await deleteOwnAccount(svc, bearer, await readJson(request))];
    }
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
    if (method === "GET") return [200, await listRooms(svc, bearer)];
    if (method === "POST" && head === "rooms") {
      limit(svc, "create", request);
      return [201, await createRoom(svc, await readJson(request), bearer)];
    }
    methodNotAllowed();
  }
  if (head === "tournaments" && segments.length === 1) {
    if (method === "GET") return [200, await listTournaments(svc)];
    if (method === "POST") {
      limit(svc, "create", request);
      return [201, await createTournament(svc, await readJson(request), bearer)];
    }
    methodNotAllowed();
  }
  if (head === "tournaments" && code !== undefined && rest.length === 0) {
    const tournamentCode = code.toUpperCase();
    if (!isTournamentCode(tournamentCode)) throw new ApiError(404, "Tournament not found");
    if (action === undefined) {
      if (method !== "GET") methodNotAllowed();
      return [200, await pollTournament(svc, tournamentCode, bearer)];
    }
    if (method !== "POST") methodNotAllowed();
    if (action === "join") {
      limit(svc, "join", request);
      return [200, await joinTournament(svc, tournamentCode, await readJson(request), bearer)];
    }
    if (action === "leave") {
      limit(svc, "move", request);
      return [200, await leaveTournament(svc, tournamentCode, bearer)];
    }
  }
  if (head === "rooms" && code !== undefined && rest.length === 0) {
    const [status, body] = await roomRoute(svc, request, code, action, url, bearer);
    // A tournament match that just ended moves its bracket on right away.
    const ended = body as { tournament?: { code: string } | null; status?: string };
    if (ended.tournament && (ended.status === "finished" || ended.status === "closed"))
      // Best effort: the room action already succeeded, and the next tournament poll retries.
      await syncTournamentByCode(svc, ended.tournament.code).catch(() => {});
    return [status, body];
  }
  throw new ApiError(404, "Not found");
}

async function roomRoute(
  svc: Service,
  request: Request,
  code: string,
  action: string | undefined,
  url: URL,
  bearer: string | null,
): Promise<[number, unknown]> {
  const method = request.method.toUpperCase();
  const roomCode = code.toUpperCase();
  if (!isRoomCode(roomCode)) throw new ApiError(404, "Room not found or expired");
  if (action === undefined) {
    if (method !== "GET") methodNotAllowed();
    const since = intParam(url, "since");
    const chatSince = intParam(url, "chat_since");
    return [
      200,
      await pollRoom(
        svc, roomCode, since, [bearer],
        (room, slot) => chatFor(svc, room, slot, chatSince),
        url.searchParams.get("board_ready_v1") === "1",
      ),
    ];
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
    case "board-ready":
      limit(svc, "move", request);
      return [200, await confirmBoardReady(svc, roomCode, await readJson(request), bearer)];
    case "still-here":
      limit(svc, "move", request);
      return [200, await stillHere(svc, roomCode, await readJson(request), bearer)];
    case "chat":
      limit(svc, "chat", request);
      return [
        200,
        await postChat(svc, roomCode, await readJson(request), bearer, intParam(url, "chat_since")),
      ];
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
    const cacheable = segments.length === 1 && segments[0] === "capabilities" && status === 200;
    return json(status, body, origin, cacheable ? CACHEABLE : "no-store");
  } catch (err) {
    if (err instanceof ApiError)
      return json(err.status, { error: err.message, ...err.extra }, origin);
    console.error("[nineweave] unhandled error:", err instanceof Error ? err.message : "unknown");
    return json(500, { error: "Something went wrong on the server" }, origin);
  }
}
