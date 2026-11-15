# Nineweave — Round 2

Godot **4.7.2**, Compatibility renderer, single-threaded Web export. The React site outside this directory is independent and untouched.

Open `project.godot` to play. Modes: computer (Easy/Medium/Hard, choose X/O), Pass & Play, private-room HTTP client, and a clearly labelled in-process online demo. Computer games and settings save under `user://`.

```sh
sh godot/tools/run_tests.sh
sh godot/tools/export_web.sh /tmp/nineweave-web-check
# Display-enabled capture, performed by the project owner:
xvfb-run -a sh godot/tools/capture_shots.sh /workspace/nineweave-r2-shots
```

Scripts default to `/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64`; override `GODOT` if needed. All automated test/export runs are headless and put XDG data/config/cache under `/tmp`. Capture requires a display and refuses headless pixel readback.

See [ROUND2.md](ROUND2.md) for the Round 2 visual/animation pass and [ROUND1.md](ROUND1.md) for architecture, measurements, layouts and hooks, [ONLINE_PROTOCOL.md](ONLINE_PROTOCOL.md) for the future backend, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for font licenses and reference-derived decoration.
