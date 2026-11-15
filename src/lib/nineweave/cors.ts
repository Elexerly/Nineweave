/**
 * CORS for the Nineweave API. Auth is a Bearer header (no cookies), so
 * credentials are never allowed; an allowed Origin is reflected.
 */
export const ALLOWED_ORIGINS: ReadonlySet<string> = new Set([
  "https://elexerly.github.io", // GitHub Pages (path /Nineweave shares this origin)
  "https://nineweave.grok.me",
  "http://localhost:8060",
  "http://localhost:8080",
  "http://127.0.0.1:8060",
  "http://127.0.0.1:8080",
]);

export function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = { Vary: "Origin" };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type";
    headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, OPTIONS";
    headers["Access-Control-Max-Age"] = "600";
  }
  return headers;
}
