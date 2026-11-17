# Nineweave online usability: CLIENT FILE TRANSFER ONLY

DO NOT deploy, merge, reset to, or publish this branch as a whole. Its inherited backend is historical, not the current publishing project.

Verified source: local fdef75771c3618082c725343c9446ecb302e3f7f.
GitHub source mirror: plax/online-usability-source-nov17, commit 1cccd15df483b3f6fbebfdf46b88a284045ca71f.
Both source trees are exactly 53237d05f1a7e64368158362f4009b4fca7ee30e.

Fetch this transfer branch into a SEPARATE checkout. Use release/online-usability-nov17:
1. Concatenate index.pck.part-a then index.pck.part-b into a temporary index.pck.
2. Verify SHA256 and byte length below.
3. Copy ONLY assembled index.pck, index.html, BUILD_INFO.txt to the CURRENT publishing project's public/ folder.
4. Keep every other current project file untouched. Especially preserve Sitebloc CORS, server API/account deletion, database connection, environment/settings, admin state, privacy policy, JS/WASM/worklets, videos and audio sidecars.
5. Verify the preview's BUILD_INFO and HTML pack query; report back before the user manually publishes.

Expected assembled pack:
bytes: 16723644
SHA256: d4007395e6c4903c6af90dd3a6e22f798d381f11c4db38c3fddc9dc7c92681ad
HTML SHA256: ef43a8939797eeeba85c9837d385402c57fc1d27a8e3d7e4d7d18931cde51b94
BUILD_INFO SHA256: 532a0e050f48895abb238e95cac57b5e7ce6baadcc57ea718659d6cfcfc4d34c
HTML mainPack: index.pck?v=d4007395e6c4903c

Example from this separate checkout:
cat release/online-usability-nov17/index.pck.part-a release/online-usability-nov17/index.pck.part-b > /tmp/nineweave-online.pck
sha256sum /tmp/nineweave-online.pck
# Or on macOS: shasum -a 256 /tmp/nineweave-online.pck
# Then copy only the three files as described above. Do not replace the backend.

QA: all 35 source suites pass across the full run plus updated flow-expectation reruns; one load-related AI timing failure passed isolated rerun. Exported pack smoke 14 checks pass. Twenty Mac screenshots reviewed, including narrow phones with chat and mute. The exact reported repeated sound was not audibly reproduced; stale solo AI/audio entering matchmaking was fixed and regression-tested.
