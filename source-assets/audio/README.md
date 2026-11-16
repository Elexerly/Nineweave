# User-supplied versus announcement

`TwoHaveSteppedForward.mp3` is the exact recording supplied by the project owner on November 16, 2026 for the versus anticipation screen. It is preserved outside the Godot project/export. No external sound library was used or downloaded.

Original SHA-256: `3cf4201c262b66f378b8aa622af0caed2835c234971d040d926b3c9ed9f7094c`

Game asset: `godot/assets/audio/announcer/two_have_stepped_forward.ogg`

Conversion (attenuation only):

```
ffmpeg -i source-assets/audio/TwoHaveSteppedForward.mp3 -af volume=-1dB -c:a libvorbis -q:a 5 godot/assets/audio/announcer/two_have_stepped_forward.ogg
```

Converted SHA-256: `4fb30640ccf192d6faedf7800c57da197d4932b36666c0961e280923d3d6b0d6`

Technical checks: stereo, 48 kHz, clean decode. Source container duration 2.064 s; converted decoded duration 2.033708 s (MP3 container padding differs). Converted sample peak −7.3 dBFS, mean −22.6 dBFS. No amplification/normalization. Playback uses Announcer volume and another −3 dB player gain. Technical analysis is not an auditory listening claim.

The reveal clang reuses the project's existing `claim_gold_clang.ogg`, at −9 dB player gain (6 dB below ordinary cues), with normal SFX slider and video ducking when applicable.
