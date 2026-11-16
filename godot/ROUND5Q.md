# Round 5q: measured result text stack

Replaces independent fixed text lanes with one measured vertical stack used directly by rendering and regression tests. Every baseline accounts for actual font ascent, descent, outline thickness and padding. Larger heading/name sizes are retained when they fit; the stack scales down only for constrained viewports. Long names and multiline character outcomes cannot collide with one another or the buttons.

Regression coverage now tests actual measured text blocks, not only empty layout rectangles. Screenshots supplied by the owner were inspected. Local Xorg virtual-display startup failed because listening sockets were unavailable, so rendered-device verification remains outstanding.

Kellen's trimmed clip, all other videos/audio, and backend remain unchanged.
