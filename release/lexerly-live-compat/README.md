# Additive API compatibility patch — NOT deployed

Base host: 040c06c58aab754bfbd7eac8f422d49dd6cbb6c8.
Only production runtime files changed: src/lib/nineweave/heroes.ts and unlocks.ts.

- Preserve Professor as public and unguarded for the currently published frontend.
- Add jb_circuit (new James II) without changing james_ii (Sevryn) identity.
- Add jb_rocker as secret, with existing server-owned entitlement guard.
- PROF26 -> professor_gilt, JB2026 -> jb_rocker, case insensitive.
- Keep Nick/N2026, Kite alias, all other codes/records.
- Temporary server catalog: 33 public IDs for backwards compatibility, 2 secret IDs. New frontend independently displays 32 public and hides Professor until grant. After frontend rollout, Professor can move to server secret list in a separate reviewed update.

184/184 online tests passed with disposable SQL fixtures, TypeScript passed, Vite compilation passed. Test coverage includes mixed old-Professor/new-tech match, legacy sign-up/profile selection, rocker unauthorized selection blocked for profile/rooms/tournaments, code grants and token restoration. Old frontend cannot render new hero artwork it does not include; fallback visual compatibility still needs in-game verification.

No database migration, public assets, CORS, email settings, account records, or secrets changed. No live deployment performed. Live health/email/online/unlock capabilities and GitHub Pages preflight checked read-only and working.

## Builder handoff

Fetch this transfer branch into a separate directory. Do NOT merge/reset/cherry-pick the whole branch: it is based on a historical host snapshot. Run git apply --check on release/lexerly-live-compat/backend-source.patch against your CURRENT project, then apply only that patch. If it does not apply cleanly, stop and report the exact mismatch. Keep all existing public game files, CORS, database connection, Resend key, migrations, admin settings, and privacy pages unchanged. Run your backend tests/typecheck. Report the two changed files and readiness; do not publish until Patrick asks.

After authorized publish, verify heroes includes professor_gilt + jb_circuit publicly and nick + jb_rocker as secret, account_unlocks/email stay true, and exact GitHub Pages CORS remains. Prof26/JB2026 should then work with the test client using EXISTING live accounts. This patch does not rebuild or replace either frontend.

## Optional requested email branding patch

Apply email-branding.patch as a second checked patch. It changes ONLY mailer.ts: subjects become Your Lexerly sign-in code / Your Lexerly verification code, message wording/header/footer say Lexerly, sender display name becomes Lexerly. Exact sender mailbox no-reply@nineweave.sitebloc.com, Resend endpoint, API-key resolution, DNS/domain configuration, code generation/expiry and account behavior stay unchanged. Existing live Nineweave frontend receives the new Lexerly-branded emails too; both clients share the same account API. No frontend rebuild needed.

Successful email recovery already rotates the account's single device token: old account tokens then return 401. Merely requesting a code does not revoke the old token. This branding patch does not change recovery behavior. Existing separate active-room seat tokens are not explicitly revoked by recovery. Regression tests verify token retirement and profile/tutorial preservation.
