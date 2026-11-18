# Nick secret hero transfer ONLY

Do not merge/reset/publish this branch wholesale. It contains an older host baseline.

1. Keep current hosting project and its backend, Sitebloc CORS, database connection, admin-off, all existing videos, migrations and privacy settings. Current live checked18Nov2026 advertises account_unlocks:true and source8d10a36. This patch REQUIRES that secret-unlock deployment (0011); adds NO migration.
2. Copy release/nick into a separate temporary directory. Run `python verify_transfer.py /tmp/nick-index.pck` and require all hashes to pass.
3. Run `git apply --check backend-source.patch` against CURRENT project. If it fails, stop and report; no branch reset. Apply only this patch. It touches api/heroes/players/rooms/tournaments/unlocks to grant N2026 and enforce account ownership. Optional backend-tests.patch adds tests. No client-source patch is needed in host.
4. Replace ONLY public/index.pck (assembled pack), public/index.html, public/BUILD_INFO.txt. ADD public/hero_video/nick/intro.ogv and victory.ogv. Keep index.wasm/index.js and all previous sidecars unchanged.
5. Run isolated online tests/typecheck without live DB writes, verify preview pack/source and both Nick sidecar sizes/hashes. Need account_unlocks table already present. Do not create/delete tester accounts merely to stage.
6. Report staging ready; owner manually publishes. After publishing verify live source5161626, pack75837c7912cd396b, sidecars200, N2026 redemption on owner's authorized account, permanent availability on re-login and own intro audio only.

Expected PCK17,144,420bytes SHA25675837c7912cd396bb83df42eb72b3c96a114148d15db64784dc228490d3c2477.
Source5161626; backend c9dc380. Server179/179 tests/typecheck pass.39/40Godot suites pass. Unchanged AI suite had one seeded-search determinism failure under CPU timing limits; strength tests pass, baseline comparison pending. Packed Nick resources and independent audio playback pass. No real-device subjective audio claim.

Native iPhone build is separate; this packet does not update installed apps.
