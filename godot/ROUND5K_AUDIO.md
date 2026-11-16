# Round 5k: independent hero soundtrack playback

## Evidence and scope
All 64 shipped intro/victory OGVs were decoded with ffmpeg to float32 PCM.
No samples exceeded 0.999; the highest absolute sample was 0.805596
(pope_slam intro, about -1.88 dBFS). No decoder errors were reported.
That does not establish that the perceptual artifacts are absent in the media,
but does not support another simple full-scale clipping/volume reduction fix.
At Patrick’s request, hero soundtrack gain is now -8 dB, 2 dB lower than the
previous -6 dB setting. With the measured maximum source sample, peak output
of the isolated hero soundtrack is about -9.88 dBFS before Master gain. This
is not a guarantee for the sum of all buses; announcer MP3 levels are untouched.

The previous implementation mixed embedded Vorbis through VideoStreamPlayer,
whose Theora audio delivery is tied to video updates. This revision removes that
potential starvation path rather than merely enlarging the same buffer.

## Implementation
- Demultiplex the original cached OGV's Vorbis logical pages without transcoding.
- Load their compressed packets into AudioStreamOggVorbis and play through a
  dedicated AudioStreamPlayer on Master. No duplicate audio assets/downloads.
- Set VideoStreamPlayer.audio_track = -1 before assigning its stream, skipping
  embedded audio decoding in the Godot 4.7.2 Theora implementation. Video player
  volume is also zero defensively.
- Only first/local intro or featured victory gets a soundtrack. Never promote
  opponent audio. Existing master control, mute, music ducking remain; hero soundtrack gain is -8 dB.
- Start soundtrack and video together, mute without restarting, stop on skip,
  completion or decode fallback, and release soundtrack on clear.
- Parser rejects malformed/truncated/unsupported pages, bounds input to16 MiB
  and extracted audio to2 MiB. A failed audio load leaves video silent rather
  than reactivating the render-driven audio path.

## Verification
Godot 4.7.2 headless:
- hero_video: PASS382, including all64 actual independent Vorbis loads and
  malformed page tests, local-only audio and sound controls.
- hero_audio_playback: PASS12; actual silent Theora decoder opens for intro and
  victory alongside standalone soundtrack, mute/unmute timing, skip and finish.

No live browser listening or audiovisual timing judgement was performed here.
These tests establish parsing and lifecycle, not an auditory guarantee. A real
browser/device check of both versus and victory peaks is still required.
