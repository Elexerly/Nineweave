import { adminSetupAvailable, ADMIN_PASSPHRASE_HASH, ADMIN_SETUP_ENABLED } from "./admin-setup.ts";
import { ADMIN_HEADERS } from "./admin-api.ts";

export function adminSetupPage(html: string, enabled: boolean = ADMIN_SETUP_ENABLED, hash: string = ADMIN_PASSPHRASE_HASH) {
  return adminSetupAvailable(enabled, hash)
    ? new Response(html, { headers: { ...ADMIN_HEADERS, "Content-Type": "text/html; charset=utf-8" } })
    : new Response("Not found", { status: 404, headers: ADMIN_HEADERS });
}
