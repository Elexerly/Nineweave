# Lexerly isolated test integration

Based on recovered source 3b711c2044c3446a10e778c93096ec28f2c2000c, proven equivalent to released six-second game. This branch is CLIENT SOURCE ONLY. Its inherited backend/public folder is stale. Never merge or deploy the whole branch as the site.

## Changes
- Home title text is LEXERLY, retaining original font, shader, shimmer, scene and layout. Announcer nineweave logical event retains its key but text says LEXERLY and recording is the supplied complete 6.84-second voice/flourish.
- Original james_ii is Sevryn, unchanged identity and media. New jb_circuit is James II in old Professor public slot.
- professor_gilt hidden under server Prof26; Nick remains N2026; new jb_rocker is JB Rocker under JB2026. 32 default and 3 optional heroes.
- Both new heroes have 7 expression heads and transparent still art. JB rocker source supplied a single body pose, used for all three body stills.
- JB rocker video is six-second Theora with independent Vorbis soundtrack extraction using the EXISTING HeroAudio path. VideoStreamPlayer audio remains muted; separate AudioStreamPlayer owns it. Imported audio retains -3dB preprocessing and final .4-second fade; runtime intro also has existing .3-second fade. Existing heroes unchanged.
- Internal project/app data name, accounts, API paths and canonical hero IDs are preserved. Do not rename user-data namespace during app branding.

## Test-only routing
Web export preset custom_features=lexerly_test. json_api.gd uses configured window.LEXERLY_TEST_API_URL (HTTPS) or same origin for that feature, never the production default. Existing localhost api= override remains. Backend is separately prepared from exact live host snapshot, by test_backend worker. Static bundle alone does not provide account/unlock services.

For a future PRODUCTION export, explicitly clear lexerly_test only after owner approves release and matching current backend is assembled. Do not simply publish this branch.

## Inputs
JB package jb2026-assets.tar.gz, SHA256 f9d1353f74cce832408bd0844ec56fe0eb86831a8b73cbb2b41c22665b9550d5.
Lexerly audio LEXERLY.mp3, MP3 SHA256 2ce8cc4464dc0f1e2a71960ad96abe445dc4f828e00b32c3b3da5a4d87946b00.
Native James II source cb2ac17984ddd178aeba658e2d6ccf00b52d68ab.

## Verification
Initial recovered + James II port 41/41 suites passed. Final JB/Rebrand affected checks: Lexerly 38, James II 80, all videos 407; complete final suite logs in qa/final-suites. Local OpenGL title, character selection, secret Professor screenshots inspected. Native phone playback and external test site deployment separate, not claimed here.
