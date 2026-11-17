# TRANSFER ONLY: do not publish this branch

This branch stages the November 17 account-entry UI update. Its inherited backend is NOT the current deployed project: it lacks the deployed Sitebloc CORS change. Do not switch your publishing project to this branch or merge/reset its whole tree.

Source equivalent commits: Mac 5b02407426efff28c51d260754688e891c37afdc; cloud export c495cfbea3fc55473fcc476184104e543e45bc80. Both apply the same tested patch atop deployed source5d32625. All32 Godot suites passed. Native iOS code/settings are not included.

In a separate checkout, assemble:

```sh
cat release/account-entry-nov17/index.pck.part-a release/account-entry-nov17/index.pck.part-b > /tmp/nineweave-account-entry-index.pck
sha256sum /tmp/nineweave-account-entry-index.pck
```

Expected SHA256: 3fc5fd37298b3ec67af49af87a92e6a63f58a7d9a976d2cb13a72af7590e52c2
Expected size: 16720796 bytes.

Only after the hash matches, copy the assembled pack plus this folder's index.html and BUILD_INFO.txt over the CURRENT publishing project's public/index.pck, public/index.html, public/BUILD_INFO.txt. Preserve every other file, current CORS, backend, database connection, migrations, environment settings, privacy policy, videos and runtime binaries. Do not create a nested public/public directory.

Preview must show Create Account and Sign In; Create Account opens the light-backed form. The HTML references index.pck?v=3fc5fd37298b3ec6. BUILD_INFO source is c495cfb. Have Patrick manually publish the current project, then verify those same values on https://nineweave.sitebloc.com and https://nineweave.grok.me. Confirm Sitebloc CORS and account capabilities remain intact. Jack must test the actual Safari keyboard: physical-device fix is not yet verified.
