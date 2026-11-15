# Hero video playback

`characters/hero_video.gd` is the only platform/source policy. The manifest at
`assets/hero_video/manifest.json` is authoritative; roster aliases are canonicalized
before lookup. Unknown heroes and unlisted clip kinds never issue HTTP requests.

- Native, mobile, editor and native headless tests read bundled `res://` clips.
  They never activate the cache or HTTP. Future native export presets must include
  `assets/hero_video/manifest.json` and leave the `.ogv` resources included.
- Web resolves `hero_video/<canonical_id>/<intro|victory>.ogv` against the document
  base URI, beside `index.html` (including GitHub Pages project subdirectories).
  No online API origin is involved. Complete cached files play from `user://`.
- Selection focus and the initial focus on **each** selection pass prefetch both
  kinds. Computer/local match start, online character receipt/match start, rematch
  and resume prefetch both kinds for both heroes. Prefetch is advisory and never
  awaited; a scene snapshots ready files on entry. A late completion is used by
  the next scene, never swapped into a running fallback.

`hero_video_cache.gd` permits two concurrent requests and three attempts, with
0.25/0.5 second backoff. HTTP 404 and exhausted retries are terminal for the
session. Other non-transient 4xx responses are also terminal. Files download to
`.part`; only complete Theora Ogg page sequences, EOS for every logical stream,
and matching Content-Length (when supplied) are atomically renamed into place.
Vorbis BOS identifies whether a clip has audio. Readiness uses an in-memory index;
existing files are validated once when the web cache starts. LRU limits are the
named `MAX_BYTES` (64 MiB) and `MAX_CLIPS` (8) constants. Active playback pins files;
release immediately reapplies the cap. A fully pinned cache may temporarily exceed
its cap. LRU ordering is session-local; persisted files are reindexed at startup.

`hero_video_overlay.gd` is a child of the cinematic's existing front layer, retaining
the three original cinematic children and all code animation clocks. Versus uses
portrait-aspect split frames, with original versus art on a side without a ready
intro. Victory uses a full-viewport letterboxed video. Decoder `finished` signals,
not the old versus deadline, end playback; two intros wait for both. A stopped
player without a finished signal is also released so it cannot trap the match.
Existing guarded skip and `_cinematic_finished("spotlight")` show the normal
results. Reduced motion uses the short code scenes. Analytic `seek()` clears video
and poses the original code animation, preserving deterministic capture scenarios.
For live pilot review, start an actual Jack/Max match and Max victory; analytic
capture tools intentionally show the code fallback.

Video audio uses the existing Master bus. Sound off mutes it and releases ducking;
two simultaneous audio clips share headroom. Vorbis playback extends the existing
`sound.duck_db` target; Announcer remains unducked. No buses are created by video.
Clear, skip, completion, and teardown stop players and release audio/cache pins.

The Web preset packs the manifest and excludes `.ogv` and MP4 sources. The export
script copies only `.ogv` sidecars. `tools/check_hero_video_pack.py` checks the
Godot 4.7 PCK v4 directory, packed manifest contents, absent clip paths/payloads,
and byte-identical sidecars. Keep `tools/convert_hero_videos.sh` as the offline
producer conversion step; playback/export do not run it.

Validation: `tools/run_tests.sh` includes `run_hero_video_tests.gd` as suite 13.
All HTTP tests use `tests/fake_http.gd` and isolated `user://hero-video-suite` data,
which the suite removes. The Round 4 legacy controller suite explicitly supplies
no video source to retain its original three-second fallback timing assertions.

## Local validation (2026-11-15)

- All 13 suites passed, including audio, Round 3e, Round 4b timing/capture, and
  120 hero-video checks. No script errors or warnings in the final suite run.
- Web release export passed: `index.pck` is 16,675,800 bytes (under 20 MB).
  The packed manifest matches the source; neither clip paths nor clip payloads
  are packed; both sidecars match their sources byte for byte.
- The installed web template includes VideoStreamTheora and VideoStreamPlayer.
  This confirms module availability, not successful browser frame/audio playback.

## Producer checks still needed

Headless tests verify readiness, branches, geometry, signals, pinning, skip/results,
and mix targets; they do not prove decoded frames or audible browser output.
Confirm live Jack vs Max and Max victory on the target web browsers, especially
Safari/iOS. Theora decoding is software work and web `user://` persistence depends
on browser storage availability. Audio still depends on the game's existing first
gesture unlock. Slow/failed sidecar downloads deliberately use the code fallback.
