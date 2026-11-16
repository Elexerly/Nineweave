# Nineweave Round 5v — all hero videos, Beth maskless

All 32 canonical roster heroes have intro and victory clips: 64 clips total.
Missing heroes or clip kinds: **none**. The manifest is regenerated in canonical
ID order. Approved clips were copied byte for byte, without trimming or encoding.

Source mapping from `/workspace/nineweave-video-pilot/`:

- Canonical roster folders use `ogv/intro.ogv` and `ogv/victory.ogv`.
- Daphne's canonical roster ID is `daphne`.
- `jack_fm/ogv/intro_best.ogv` and `victory_best.ogv` become
  `shard_jack/{intro,victory}.ogv`, replacing the pilot intro.
- `max_granite/ogv/{intro,victory}.ogv` replace both old Max clips.
- `madame_solstice` is Beth Solstice, including her maskless clips.
- Root pilot files, attempts and `_tools` are not imported.

Beth's versus, victory, splash and seven expression heads are byte-identical to
`madame_solstice/maskless_art/godot_ready/*.webp`. Existing filenames and all ten
import sidecars are preserved. Body dimensions are respectively 610×768,
516×768 and 602×768; all heads remain 256×256.

Web retains the manifest in the PCK and lazily downloads Theora sidecars. Native
continues to read bundled clips. Cache stamps now include `CONTENT_VERSION`
(`r5v`) plus verified byte length, so old pilot stamps cannot retain the replaced
Jack/Max media. Current stamps still avoid repeated Ogg page validation; truncated
files, retries, eviction, pinning and fallback behavior remain covered.

Legacy controller tests explicitly skip ready video intros before testing moves.
The Round 4b motion suite explicitly selects procedural fallback, preserving its
original timeline assertions. The hero-video suite covers full-roster native
readiness, canonical aliases, complete Ogg streams, lazy web requests, playback,
Beth's labels/layout, and invalidation of an old size-matching pilot stamp.

Validation with Godot 4.7.2:

- Full `tools/run_tests.sh`: **PASS, 16/16 suites**, no warnings or errors.
- Hero-video suite: **305 checks, zero failures**.
- All 64 clips: 540×720 Theora with Vorbis; complete Ogg streams and approved
  source hashes verified. Durations range from 5.333333 to 8.042653 seconds.
- Final `tools/export_web.sh`: **PASS**; BUILD_INFO title is
  `Nineweave Round 5v (all hero videos, Beth maskless)`.
- `index.pck`: **16,701,508 bytes**, below the 20,000,000-byte budget.
- `hero_video` sidecars: **222,729,858 bytes** (212.41 MiB), 64 clips.
- PCK directory/payload audit: manifest matches; no OGV paths or payloads packed;
  all 64 sidecars are byte-identical to their project assets. No `.ok` files ship.
- All ten import sidecars match HEAD; `git diff --check` passes.

The requested `/workspace/nineweave-web-build-r5v` destination is read-only in
this session. The successful final export is instead at
`/workspace/nineweave/godot/.godot/r5v/web/index.html`, with test/export logs under
`godot/.godot/r5v/`. Rendered capture was unavailable because the sandbox could
not initialize X11/Wayland; these checks do not claim live browser frame/audio
verification. No commits, tags or pushes were made; the sibling r5b project is
untouched.
