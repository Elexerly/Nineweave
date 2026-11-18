# Six-second intros: client-only transfer

Do not merge, reset, or publish this branch wholesale. Stage from your current Nick-enabled hosting project.

1. Copy only release/six-second-intros from this branch into a separate temporary folder.
2. Run `python verify_transfer.py /tmp/six-second-intros.pck`. Require all hashes and size checks to pass.
3. Replace ONLY public/index.pck with the assembled pack, public/index.html, and public/BUILD_INFO.txt.
4. Do NOT apply client-source.patch in the host. It is source backup/native-port evidence only. No backend patch, migration, or database action is needed. Keep all current Nick/unlock server code and tables, Sitebloc CORS, database connection, privacy/admin settings, index.js, index.wasm, and all 66 video files unchanged.
5. Verify preview source fa059ed19a066614b7347dfc7ce3630a8ced40bb and pack index.pck?v=8cf30a10e4a2350d; PCK 17144772 bytes / SHA256 8cf30a10e4a2350def23aca587310a806015e85fb32eab53b32140a061448d62. Stage only and report; do not publish until Patrick does so.
6. After publication check live BUILD_INFO.txt and pack reference before testing. Versus videos share six seconds after loading/prelude; shorter videos hold final frames, local audio gently fades, rival audio remains muted. Victory clips are unchanged. Test skip, repeat match, missing-video fallback, Nick unlocked selection, and online match start. Native app installation is separate.

Verification: all 41 Godot suites passed (full sequential sweep followed by five affected suites rerun after fallback cleanup). Actual Theora test confirms short Jack5.33s holding while Kellen7.66s continues, both done at6s. Web export passed; all66 sidecars and runtime JS/WASM match previous Nick export byte-for-byte. No original media reencoded. No production publish or DB writes.
