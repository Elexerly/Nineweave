# Round 5g — account flow and cinematic mix

Client-only follow-up to Round 5f. No server, database, admin or deployment
configuration changes; no live test accounts, email sends or records created.

## Account flow
Successful explicit onboarding email confirmation continues to the main menu or
requested Online lobby. Background refresh, Settings verification, cancelled and
late responses do not steal navigation.

Options checks and saves names atomically through authenticated PATCH /me.
Only a server-confirmed name becomes local state. Taken, rejected, invalid and
offline cases preserve the prior name and verified email. Repeated submits are
blocked while pending. A rejected rename session never registers a new identity.

Existing players can sign in from the create-name screen with their previously
verified email and a code. This uses existing server recovery endpoints, not
registration. Server token rotation signs out the previous device; the UI
explains this. Unknown addresses receive the same generic request response.

## Audio mitigation
Videos retain left-only audio and hold the final victory frame. Audible video
now has -6 dB gain; background Music/SFX duck immediately to -12 dB while current
and queued announcer commentary is stopped/suppressed during the cinematic.
Normal mixing resumes afterward. This reserves headroom but is not a confirmed
Mac playback fix. No media files were re-encoded.

## Media/export audit
Only a Web preset exists in this repository. Videos are excluded from the PCK
and copied beside the web export: 64 OGV files, 222,729,858 bytes total. Web
prefetches focused heroes and both match heroes with intros first, at most two
downloads concurrently. Its cache has eight-clip / 64 MiB ceilings, so evicted
clips can download again. Four live Jack/Max intro/ending downloads byte-matched
source. Browser playback was not measured by these HTTP checks.
Native code reads res:// clips, but no iOS/Android export preset or generated
mobile artifact exists here; native inclusion is not verified. A mobile web
browser uses the same web sidecar path, not native bundled media.

## Validation
21 suites passed 3,200,926 checks. The first aggregate exposed two superseded
rename assertions; after updating those contracts, both affected suites passed,
and the other 19 suites were unchanged and passed. Web export passed with a
16,779,592-byte PCK; exported resource smoke passed 326 checks. A real isolated
backend recovery response was also consumed successfully by the Godot client,
restoring the same verified identity without a registration request.

A local in-memory backend
audit passed 35 tests / 7 suites including authenticated, unique rename that
preserves player ID, verified email, and sends no new verification email.
