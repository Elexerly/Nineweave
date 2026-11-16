/** Server-only temporary setup switch. Disable and redeploy after setup. */
export const ADMIN_SETUP_ENABLED = true;

/** Replace with scripts/hash-admin-passphrase.mjs output. Never use plaintext. */
export const ADMIN_PASSPHRASE_HASH = "scrypt$2a502bfe97370f5cc7711fe55ff402e8$ebd27b3201ee5bf8cd2d019ab44ab6a8000d781c290470ad19d679245e513879";

export function adminSetupAvailable(
  enabled: boolean = ADMIN_SETUP_ENABLED,
  hash: string = ADMIN_PASSPHRASE_HASH,
): boolean {
  return enabled && /^scrypt\$[a-f0-9]{32}\$[a-f0-9]{64}$/.test(hash);
}
