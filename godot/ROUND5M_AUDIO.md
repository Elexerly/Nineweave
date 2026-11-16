# Round 5m: Beth-only ending fade

Adds a0.30-second linear-amplitude tail fade to Beth Solstice
(`madame_solstice`) intro and victory soundtracks only. This multiplies existing
-8dB gain, reaching the existing -80dB mute floor at the end. Ryan, Jack, all
other heroes, announcer MP3s and original media files are unchanged.

Timing follows AudioStreamPlayer playback position, not elapsed wall time.
Endpoint is the lesser of video and audio duration. If the video backend does
not report duration, use the measured145frames/24fps =6.041667s for these two
shipped Beth clips. Their audio is6.058667s. If Beth media changes duration,
update this fallback measurement. Mute/unmute respects current fade position;
clear/completion stops playback and a new clip starts with fresh gain.

Evidence: ffmpeg decode of Beth tails shows last0.35s RMS -22.30dBFS intro,
-22.69dBFS victory, so this is a short tail softening rather than source repair.
No listening was performed; speech/music distinction and perceived smoothness
need a real-device audible check.

Godot4.7.2 headless verification:
- hero_audio_playback PASS73: Beth intro/victory envelope start/mid/end,
  actual decoder playback, mute/unmute during tail, skip/completion,
  no opponent promotion, Ryan/Jack unaffected, next-clip reset.
- hero_video PASS382 (existing regressions and all64 Vorbis loads).
