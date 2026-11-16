# Round 5i: single-screen versus lightning reveal

- A single opaque anticipation screen says **Two have stepped forward** while both intro files become ready. With sound audible, the supplied “Two have stepped forward” recording plays once and the lead-in covers its duration plus 0.12 seconds (about 2.154 seconds). Actual playback still running also gates the reveal, with a bounded extra two-second watchdog for a stalled audio device. Without audible announcement, warm-cache lead-in remains 0.85 seconds.
- One 0.18-second fade-out flash directly reveals the side-by-side intros, separated by a static lightning bolt, with the existing metallic clang at reduced gain. There are no intervening portrait/title scenes or repeating flashes.
- Cold downloads retain the existing 12-second bound. One unavailable side falls back to its portrait; if both are unavailable, the same reveal shows both portraits for three seconds and enters the game.
- Touch/keyboard Skip and navigation cancel a pending reveal and stop unfinished speech. The skip-input guard remains. Reduced Motion retains the existing short, no-flash fallback.
- Left-only intro audio, −6 dB video headroom, background ducking and held victory-final-frame behavior are unchanged. Both possible victory clips remain prefetched by the existing pair-prefetch logic.

## Verification and limits

Focused Godot 4.7.2 headless suites: hero video 313 checks; Round 5c 199; versus flow 40. The new flow suite dispatches actual touch and keyboard events through `Input.parse_input_event`, and checks lead-in timing, one reveal, pair completion, cancellation and responsive geometry.

Final full aggregate after audio integration: 22/22 suites passed on Godot 4.7.2 (including Round 3b owner-asset coverage: 599 checks). Production pack audit results are recorded with the release handoff. Headless tests do not demonstrate rendered pixels or actual browser video/audio playback. This environment has no local graphical display/Xvfb, and the cloud browser's WebGL2 limitation remains; visual/browser playback verification is not claimed.
