# Online countdown visibility follow-up

Base: reviewed tutorial/idle client 48beb0f. Isolated client-only correction; no backend, migration, account or published build changes.

The original arc was painted on Main's own canvas, before child portrait artwork. The artwork can obscure it. A legacy room envelope with an expiry but no still_there_at also displayed bottom countdown text without any arc. Neither is asserted as the sole cause of Patrick's real-device report without an authenticated room capture.

A dedicated input-transparent foreground HUD now draws a high-contrast circular rail and blue/amber/red shrinking arc, plus seconds adjacent to the active portrait. It stays above portrait artwork and below prompts and hides during tutorials, cinematics, modals and results. Active seat is still selected from the authoritative room turn, independent of local X/O seat.

Complete envelopes retain existing server-derived phase and fraction, including the acknowledged ten-second allowance and third-late-turn expiry. Legacy envelopes display real expiry seconds; a shrinking fraction is calculated only if server start and expiry exist. Without a server duration the rail stays full, with no fabricated turn length or grace period. No timing policy changed.

Targeted tests cover foreground ordering, no input interception, visibility gates, local/opponent deadline equality, authoritative allowance, expired affordances, legacy packets, and non-overlap/on-screen geometry at 320x568, 390x844, 430x932, 844x390, 553x867, 780x900, 867x553, 1366x768.

Actual rendered screenshot QA remains pending: cloud Xorg cannot create Unix sockets (EPERM), and Mac GUI was intentionally not used. Geometric/headless tests do not substitute for visual confirmation on real folded/unfolded Duo and both seats. Existing tools/capture_idle_timer.gd can capture those scenarios when a permitted graphical surface is available.
