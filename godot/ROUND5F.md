# Round 5f — local intro audio, held result frame, honest email feedback

Client-only follow-up to published source `3b2bab59`. No server, database,
admin, credentials, or production deployment changes.

## Cinematics
- Left/local intro audio only. Right audio is exactly zero and is never promoted
  when the local clip ends or is unavailable. Settings still mute all audio.
- Audible video buffering is restored from 100 ms to the normal 500 ms. This is
  an underflow mitigation, not a confirmed diagnosis of reported Mac static.
- Natural victory completion retains the player's last decoded texture until
  navigation. Audio and music duck release; result controls and resizing work.
  Skip, replay, reduced motion, and subsequent scenes still clear old players.
- All 64 existing audio tracks decoded with ffmpeg without errors. Their mixed
  44.1/48 kHz stereo Vorbis encodings were preserved. No source corruption found.

## Email
- Distinguishes missing server delivery configuration (503), temporary service
  failure, and failed provider delivery (502). A feature capability is not
  evidence that the provider is configured or that an email was delivered.
- Shows Verify your email and Send code until the server returns a challenge;
  does not suggest checking an inbox before successful code request.
- Preserves the entered address through failure, retry and Change email; status
  survives account refresh, and longer feedback fits the scrollable mobile UI.
- Existing onboarding signup/token recovery flow remains intact. No deterministic
  cause of the user's earlier live delivery failure has been established.

## Verification
Focused Godot checks passed: Hero Video 309, Round 5c 198, Round 4g 336,
Round 5d 208. Full aggregate passed all 19 suites (3,200,847 checks). Web export passed
with a 16,769,628-byte PCK, 64 unchanged video sidecars and 20 audio clips.
Exported PCK resource smoke passed 326 checks, including 320 hero textures.
Tests use injected HTTP and local state only. No live accounts, codes, emails,
or database records were created. Mac listening and rendered final-frame QA
remain unverified in this headless environment; cloud Chrome lacks WebGL2.
