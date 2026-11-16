# Round 5n: Beth fade clock correction; Ryan sync investigation

## Beth
The prior0.30s fade used only AudioStreamPlayer.get_playback_position. Official
Godot4.7.2 web sample implementation holds its position-reporting worklet reset
high for one second; the processor resets the reported position every block
while high. Thus the reported sample clock can lag the actual video finish and
never enter the prior fade window before completion stops audio.

The Beth-only fade now uses max(video presentation position, audio position).
The video clock is also the stop/completion clock. A stale sample clock cannot
postpone the fade beyond it. No seeking, pitch/rate change, or embedded-audio
fallback. Existing -8dB gain and0.30s ramp retained. Jack/Ryan/announcer unchanged.
Tests simulate one-second stale audio at fade midpoint and video endpoint,
including mute/unmute and next-clip lifecycle regressions.

Engine evidence:
https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/js/libs/library_godot_audio.js
https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/js/libs/audio.position.worklet.js

## Ryan
Both source streams start at timestamp0. Intro video/audio durations6.041667/
6.058667s; victory7.041667/7.061333s. No container-level timestamp offset found.
Actual native headless decoder clocks sampled5times over3.5s for each clip:
video minus audio ranged approximately -60ms to+52ms. This is a dummy-audio,
non-rendered diagnostic, not a live web lip-sync test or listening result.

Source mouth animation alignment vs browser startup delay/runtime drift remains
unresolved. No speculative fixed offset, recurring seek, pitch change or clip
replacement was made; those could damage audio the owner reports sounds good.
First-frame gating alone cannot prove sync with asynchronously scheduled web
sample playback. A real browser capture of Ryan's speech/frames is needed to
identify offset and direction. A non-speaking clip is a creative alternative,
not a technical correction, and was not generated or substituted.
