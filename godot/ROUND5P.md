# Round 5p: Kellen intro v4

Replaces only Kellen Byte's intro with the owner-provided OGV from Elexerly/Nineweave commit 60713cab0ef3b90ef19d5104767faa85e0dc91a2.

- Original Git blob: 9d28600712f471948a303774b5b57a04f49eb44c.
- SHA-256: 96c20b4943a07501e2648451c93e5259ac7bd96e85d1ec35226d7dba872fabe7; 3,551,833 bytes.
- Theora 540x720: 7.625 seconds. Vorbis stereo 48 kHz: 7.658667 seconds. Both streams start at zero; complete ffmpeg decode reports no errors.
- Separate playback still demuxes the clip's own unchanged Vorbis pages. Existing gain, all other intros/endings, and Beth fade remain untouched.
- Bumps persistent video-cache stamp and versions Kellen's HTTP URL so previous cached media does not survive replacement.
- Native runtime audio lifecycle tests now include Kellen and assert the new intro soundtrack duration. Browser/device playback and subjective sync still require device verification.

## Victory typography

- Enlarged VICTORY/DEFEAT heading and player-name line, giving each more vertical space while retaining explicit inter-line gaps.
- Outcome and score lanes remain bounded above action buttons at portrait, Duo, and short landscape sizes.
- Reviewed owner screenshot IMG_0702.jpeg; actual revised rendering remains device QA.
