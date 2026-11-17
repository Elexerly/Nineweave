# Round 5s: Patrick Laquin and hero media refresh

Unpublished source integration of `hero-video-redo-nov16` (`d1e7b84`) onto the Round 5r working game.

- Nine supplied replacements and both Patrick videos are copied byte-for-byte, without recompression.
- Patrick replaces Kite in the same roster slot. Legacy `kite_hollow` IDs resolve to `patrick_laquin`; original stinger retained.
- Three transparent body WebPs and seven expression heads match the existing import pipeline; editable transparent sources are retained alongside original JPGs.
- Procedural fallback has Patrick's cowl/goatee/crossbow pose. Its 12-pose lookup uses the legacy motif index instead of the expanded 32-hero roster index.
- Media URLs/cache revision invalidate replaced sidecars. Kellen and Professor trim revisions are preserved.
- Added `hero_redo` regression suite for metadata, alias/save/online compatibility, transparent art, separate audio, fallback rig, and revision URLs.

## Release requirement

Deploy the client export together with the companion server hero whitelist/alias change. The old server rejects Patrick, and old clients do not recognize the new canonical ID. The prepared release branch must preserve the latest backend, legal policy, admin settings, and database configuration. No schema migration is required for this cosmetic change. No publication is authorized by this source integration.

## Validation

See the handoff report for final test results. The 31 Godot suites are invoked by `godot/tools/run_tests.sh`. Backend compatibility is independently tested with in-memory PGlite fixtures. The generic web scaffold on the Godot branch has pre-existing unavailable Grok metadata/dependency checks; it is not the production backend and should not replace production server code.
