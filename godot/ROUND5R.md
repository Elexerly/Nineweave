# Round 5r: Professor trimmed intro

Integrates the exact owner-supplied clip from commit fd1c7e0d73b521d600e834c39debeab9611600c0, Git blob 29b77d0af4cf057df385945c435881ed508b81a4. The supplied OGV is already 4,085,813 bytes, not the reported ~21 MB, so it is preserved bit-for-bit rather than degraded by another lossy encode.

Theora 540x720 at 24 fps: 6.041667 seconds. Stereo Vorbis 48 kHz / 112 kbps: 6.058667 seconds. Both streams start at zero; full decoding is error-free. SHA-256: c3a73d19f59ba4b99c5db18d662c1836262098c109f56120c32e7527dde81637.

Only Professor's intro media changes. His ending, Kellen's trimmed intro, other media, gain, fade logic and gameplay are unchanged. HTTP clip version and persistent cache stamp invalidate the previous intro. Runtime audio test includes Professor to exercise demux, independent playback and duration. Original versions remain in Git history and the owner's supplied branch.
