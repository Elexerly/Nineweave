# Round 5l: hero selection usability

Separate follow-up to Round 5k. Preserves all account/audio/cinematic safeguards.

- 16 heroes per page on wide/Duo layouts; 8 per page on narrow phones. Visible arrows/page dots and swipe remain. Selected hero opens on its own page, hinge handling retained.
- Tiles use BETH while selected plaque retains full name. Portrait offsets no longer overwrite multiline-caption spacing.
- Last locked-in hero now has a durable pending server preference bound to the current credential hash. A stale server value does not overwrite it. Failed synchronization retries every 30 seconds and after refresh. Only a matching server acknowledgement clears pending state. Signout/recovery/token replacement cannot transfer old pending choices across accounts.
- No server/database changes or live test records.

Feature tests: selector readability474 checks, hero sync19, Ryan/Jack real decoder lifecycle32, plus existing selector/lifecycle/account regression suites. Full aggregate expanded to27 suites. Rendering on a real Duo/phone remains to be visually checked; headless geometry checks cannot establish visual polish.
