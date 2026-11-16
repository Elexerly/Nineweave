# Own-account deletion backend verification

Local branch only; no server deployment, remote push, schema migration or live data operations performed.

## Contract

- `DELETE /api/nineweave/me`, device Bearer credential, JSON `{"confirm":"DELETE MY ACCOUNT"}`. Extra fields and caller-selected target IDs rejected.
- `200 {"deleted":true,"retained_gameplay_label":"####"}`; 400 confirmation/input failure; 401 invalid/revoked credential; 409 active participation; 503 bounded locking contention.
- `account_deletion: true` advertised by public capabilities and player capabilities when this code is deployed.
- Atomic active-database deletion of the caller's profile, email/challenges, chat, blocks, membership and reports involving the caller, including notes/snapshots. Shared results retain `####` and null player references. Opponent statistics remain unchanged.
- Associated rooms close, rematch flags clear and revisions change. Tournament revisions change. Seat-token issuance checks live ownership/device authentication; stale authorization cannot resurrect credentials.
- Registering tournaments must be left first. Started tournaments must finish, even if the caller is eliminated/withdrawn. No arbitrary result awards or cancellation of other players' tournaments.

## Verification

2026-11-16, isolated in-memory PGlite fixtures and fake mailer only:

```
node --experimental-strip-types --test --test-concurrency=1 src/lib/nineweave/*.test.ts
```

PASS: **151 tests, 28 suites, zero failures**. Includes 12 deletion tests: auth/confirmation, both-seat scrubbing and preserved opponents, active states, transaction rollback, credential rotation, already-authorized rematch interleaved with deletion, stale tournament envelope and cached token rejection.

TypeScript 5.9.3 targeted strict backend check, PASS:

```
./node_modules/.bin/tsc --strict --noEmit --types node --allowImportingTsExtensions --module nodenext --target es2022 --skipLibCheck src/lib/nineweave/account-deletion.ts src/lib/nineweave/account-deletion.test.ts src/lib/nineweave/api.ts
```

`git diff --check`: PASS.

Full-project `npm run typecheck` is blocked by missing `vite/client` in the slim audit dependency installation. No frontend/browser checks on this backend branch. Production build was not run because its package script invokes database migrations. Default parallel backend execution was not the final verification: capability expectations were updated and resource-stable sequential execution passed all tests.

## Publication boundaries

Served `legal/privacy.md` is unchanged. `legal/drafts/account-deletion.md` is an unpublished proposal, not a deployed-policy claim. Frontend integration is separate. Backups, provider mail records and hosting logs are not deleted by this API; retention is unverified. Shared dates/opponents/gameplay can permit indirect identification. Other people's text is not scanned for unlinked identifying mentions. Existing contact placeholder must be resolved before policy publication.
