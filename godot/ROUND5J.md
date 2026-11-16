# Round 5j: cinematic/audio release plus confirmed account deletion

Combines the final Round 5i owner-announcer/cinematic source (`1bdabda`) with the independently reviewed deletion client (`e0f0a7e`). All character, FX and audio files remain byte-for-byte unchanged from the Round 5i source. The merge conflicts were limited to the release label and aggregate test list; both versus-flow and deletion suites are retained.

## Account controls

Options → Account exposes deletion only when supported by the authenticated server. Two explicit confirmations, including typing `DELETE MY ACCOUNT`, precede the authenticated request. Only an exact successful server response clears local account data. The warning distinguishes active-database deletion from hosting/email-provider records, backups and copies held by others; retained shared gameplay displays `####` while opponents retain their statistics.

A synchronous, deployment-scoped browser marker plus atomic local configuration protects uncertain deletion outcomes across reloads and other tabs. Rejected, missing or malformed responses do not silently recreate an account. Explicit verified-email sign-in or a separately confirmed **Start fresh on this device** can resolve the local state. Start fresh does not delete a server account, confirm an earlier deletion or automatically register a new account. See `docs/account_deletion.md`.

## Verification

- Godot 4.7.2 full aggregate: **23/23 suites passed**, clean writable XDG directories.
- Focused merged-source checks: deletion 139, versus flow 40, hero video 313, audio 270; all passed.
- Real localhost HTTP integration: actual Godot HTTPRequest → actual backend handler (`72d87b0`) → fresh isolated PGlite and fake mailer; 13 client checks passed. Confirmed cancellation sends no DELETE, deletion removes identifying account data while preserving anonymized shared records/opponent statistics, and a dropped response after committed deletion followed by restart GET 401 does not recreate the account. Zero emails or live database mutations.
- No production or real-player deletion was performed. Rendered browser video/audio playback is not claimed by these headless tests.

Release export and pack-audit evidence accompany the handoff. This client merge does not change backend deployment or the separate audio-slider mapping behavior.
