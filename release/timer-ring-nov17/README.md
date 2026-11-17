# Client-only countdown visibility transfer

Artifact-only branch. Do NOT merge/reset/publish this branch as an application. Preserve the current publishing project including the already released tutorial/idle server, Sitebloc CORS and migrations.

Source a141e1aceeee0c0c1ccedaa3253431c32604d48b, based on live client48beb0f. Dedicated foreground countdown HUD, brighter circular arc and adjacent seconds, plus real-deadline legacy-envelope fallback. No backend or database changes.

1. Fetch packet into a separate directory. Run `python3 verify_transfer.py /tmp/nineweave-ring-index.pck`.
2. Back up the current three public client files. Copy ONLY assembled PCK to public/index.pck, packet index.html to public/index.html, and BUILD_INFO.txt to public/BUILD_INFO.txt.
3. Leave all server code, migrations, environment, database connection, CORS, admin/privacy settings, JS/WASM and videos/audio unchanged. `client-source.patch` is for source/native integration, NOT publishing-project application.
4. Verify source a141e1a, pack45f8f33bbf011bba214d8ddb9badbff02a0d924c69b03bb0f085dda0d9c144a8 and mainPack index.pck?v=45f8f33bbf011bba. Wait for user's publication. Do not run migrations or change settings for this client-only update.
5. After publication, verify actual file hashes and both active-seat views on a real phone/Duo. Ring must shrink around active portrait, blue→amber→red, stay clear of board, and display true ten-second allowance; no new time on reconnect or third-strike expiry.

QA: full37/37 suites; independent idle50, round5a288, online_turn24, round3c6734, layout1948/25sizes. Exported-PCK smoke6/6, no network. Only3export files changed;64sidecars unchanged. Real rendered screenshot QA remains pending due cloud display socket restrictions; no Mac GUI was opened. Actual user's cause is not asserted conclusively without a live room capture.

This packet is prepared only; nothing is deployed by its verification script. Roll back only the saved3clientfiles if needed, never reset the application or database.
