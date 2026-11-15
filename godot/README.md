# Nineweave — Round 3

Godot **4.7.2**, Compatibility renderer, single-threaded Web export. The React site outside this directory is independent and untouched.

Open `project.godot` to play. Modes: computer (Easy/Medium/Hard, choose X/O), Pass & Play, private-room HTTP client, and a clearly labelled in-process online demo. Computer games and settings save under `user://`.

```sh
sh godot/tools/run_tests.sh
sh godot/tools/export_web.sh /tmp/nineweave-web-check
# Display-enabled capture, performed by the project owner:
xvfb-run -a sh godot/tools/capture_shots.sh /workspace/nineweave-r3-shots
```

Scripts default to `/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64`; override `GODOT` if needed. All automated test/export runs are headless and put XDG data/config/cache under `/tmp`. Capture requires a display and refuses headless pixel readback.

See [ROUND3B.md](ROUND3B.md) for the Round 3b bug-fix pass (corner layout, input/audio/settings robustness, leak tests; 6 test suites), [ROUND3.md](ROUND3.md) for sound, characters, local cosmetics, capture scenarios and validation limits. [ROUND2.md](ROUND2.md) for the Round 2 visual/animation pass and [ROUND1.md](ROUND1.md) for architecture, measurements, layouts and hooks, [ONLINE_PROTOCOL.md](ONLINE_PROTOCOL.md) for the future backend, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for font licenses and reference-derived decoration.

Round 3 adds twelve original local-profile heroes, first-match character selection, skippable comic claim/win presentations, synthesized sound with first-gesture unlock, SFX/Announcer volumes, and local-only sky/board themes. Hero identity is carried by the online abstraction; no remote backend is included. All visual/audio/device-performance verification still needs the owner’s display/speaker pass.
