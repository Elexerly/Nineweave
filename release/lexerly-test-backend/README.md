# Lexerly test backend only

Base host snapshot: 040c06c58aab754bfbd7eac8f422d49dd6cbb6c8.

Only runtime changes: heroes.ts and unlocks.ts. Professor becomes Prof26 secret; jb_circuit replaces its public slot; JB2026 unlocks jb_rocker. Nick/N2026 and Kite alias preserved. 32 public, 3 secret. No new migration and no CORS/database settings changes.

191/191 online backend tests passed, including real disposable in-memory PGlite SQL, restore/idempotency/account isolation and profile/room/tournament ownership guards. TypeScript passed. No remote database touched. Template script checks: 192/207 passed; 15 failures involve absent .grok skill fixtures/template auth or branding assumptions. Vite production bundle compiled successfully using isolated official Node 24.11.1. No migration build hook invoked. Browser/client integration remains unverified.

Use ONLY a separate test host and its own test database. Do not attach this code to the production DB. Current web assets in this checkout are the original snapshot, NOT the new client. Integrate the matching Lexerly test client separately. A static GitHub Pages deployment cannot run this backend. The default build script runs db:migrate; verify a dedicated test DB before deployment. Never copy production environment secrets into this folder.

## Dedicated hosted test API

https://br-still-mode-bdsyavce-lexerlytest.compute.c-8.us-east-2.aws.neon.tech

Project red-queen-81336596, branch br-still-mode-bdsyavce, database lexerly_test. New empty project in existing free org, no production records copied. Function lexerlytest deployment 1 completed. Existing nine migrations applied to this NEW database only and recorded. Injected database environment only; no credentials copied or printed. Email intentionally disabled. Existing production credentials/accounts cannot be used here. Create fresh device/test accounts.

Hosted smoke passed registration, mixed-case Prof26/JB2026/N2026, duplicate redemption, saved grants, cross-account isolation, ownership guards, hero selection and 32+3 roster. Two synthetic test accounts remain, no personal data. Exact Github Pages origin preflight 204 verified, health 200. Function rejects nonallowlisted browser Origins; bearer account authentication and existing rate limits retained. Production unchanged.
