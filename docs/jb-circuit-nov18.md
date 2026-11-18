# James II tech ranger, Sevryn and hidden Professor — review implementation

Prepared from the installed native six-second-intro baseline `8462e81` on the isolated `plax/jb-circuit-native-nov18` branch. No publish, phone install or production DB operation was performed. The AdMob/account-entitlement worktree was not modified.

The new James II tech ranger (`jb_circuit`) replaces Professor in default slot 12. The default selection still contains 32 heroes. Professor keeps `professor_gilt`, all artwork, clips and original audio motif; his record is marked secret and appears when the authenticated account inventory includes it. Nick and every legacy alias remain. The generic unlock success message now names the server-granted hero instead of always naming Nick.

The original James II is now **Sevryn**, retaining canonical ID `james_ii`, his existing art, clips, dialogue, audio motif, old saves and online records. The new tech ranger displays **James II** while retaining the separate new ID `jb_circuit`. There is no alias between these two IDs; the JAMES II tile label applies only to the tech ranger.

The separate backend review packet adds case-insensitive Prof26 using the already deployed account-unlock table and ownership guard. It does not add a migration. Deploy client and backend together after integration against the current host source. This native source does not itself grant server ownership.

## Artwork and media

`art_src/jb_circuit/` retains the supplied reference and ten generated transparent PNGs. `imagegen-provenance.json` records the built-in imagegen prompt set and outputs. The existing `import_hero_art.py` pipeline creates seven 256×256 expression heads and three alpha-cropped body WebPs with maximum height 768, using matching `.85` texture import quality. The generated character preserves brown hair, blue eyes, mustache/goatee, cyan-trim outfit and blue drone without a cape.

`source-assets/jb-circuit/audio/` retains independently extracted Vorbis audio. The OGV sidecars carry those same Vorbis packets; existing HeroAudio demuxes them into AudioStreamPlayer while embedded VideoStreamPlayer audio remains disabled. PCM decoded from the runtime OGV is exactly equal to the saved audio sidecar. Peaks remain below .71, with no nonfinite or clipped samples and no gain boost. Existing runtime -8 dB playback headroom remains.

The supplied 1152×1728 MP4s were converted to 540×810 Theora at 24 fps. Intro is 144 frames / 6.0 s; the existing overlay applies the last .30 s audio fade after its unchanged prelude. Victory retains all 145 frames / 6.0417 s. Files total 7,170,318 bytes versus 26,383,267 input bytes. Existing 66 hero clips were not changed. See `source-assets/jb-circuit/media-audit.json` for all hashes and measurements; `godot/tools/convert_jb_circuit_media.py` reproduces the conversion.

## Verification

The full 47-suite native sweep initially passed 44 suites. Three metadata/import/count failures were corrected, then all eleven affected suites passed on final source/assets. The original new suite passed 56 checks; its expanded two-identity compatibility suite now passes 80 checks. The complete final 47-suite rerun passes 47/47 after both names were assigned; see `post-rename-full.log` and `post-rename/`. All remaining suites, including rules, AI, saves, deletion, consent, online flows and tutorial behavior, passed the full sweep. Logs retain both the initial sweep and the corrected reruns in `docs/qa/jb-circuit-nov18/`.

Real OpenGL rendering was inspected at 390×844 for selection, unlocked Professor, moving intro/victory, and missing-media still fallbacks; the seven expression heads were inspected at 867×553. Decoder positions advanced for both intro lanes and the victory lane. These are local desktop checks, not a claim of iPhone playback or subjective speaker verification.

Backend regression coverage: eight PGlite tests plus 151 existing online tests pass in an offline reconstruction of the known released modules; TypeScript passes there. A generic scaffold test run has missing `.grok` metadata/template failures. Full current-host build, web export and integration tests remain blocked on current live source.

## Remaining blockers

The live public BUILD_INFO and downloaded pack independently confirm `fa059ed19a066614b7347dfc7ce3630a8ced40bb` and PCK SHA `8cf30a10e4a2350def23aca587310a806015e85fb32eab53b32140a061448d62`. GitHub's newest transfer branch is `e1385bd`; it explicitly has an older host baseline. Fetching the live source SHA from GitHub returns `not our ref`. The current host/client source is required to assemble a complete web release while preserving current CORS, account code and database configuration.

Patrick subsequently confirmed that the original JB character is `james_ii` and that the new tech ranger should inherit the display name James II. That naming work is now implemented as Sevryn (`james_ii`) and James II (`jb_circuit`). Jack Sovereign remains unchanged. The sole release blocker is the current live client/host source required for complete web integration. The exact source-export request is saved in the web review packet as `grok-source-request.txt`.
