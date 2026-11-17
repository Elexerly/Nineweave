# Account entry UI, November 17

Base: account-fix-nov16-client 5d32625, the source of the published Round 5s account fix. No server, database, consent wording, roster or video changes.

Fresh players see Create Account and Sign In. Create Account opens a standard scrollable light-backed form with a normal LineEdit, like the working recovery form. Tapping the field is deliberate; no auto-focus or invisible HTML input. Back preserves the draft. Signing out then choosing a new account opens the form directly. Deletion clears the form state. Existing account gates and consent submission remain in place.

This addresses the reported first-screen interaction by changing its UI path. It is not proof of a particular Safari/Godot cause or a verified physical-device keyboard fix. Jack reported that the existing sign-in email field opens the keyboard while the first screen-name field does not. Required acceptance: test the exported build on his affected iPhone Safari, tapping Create Account then the screen-name field, typing, rotating, submitting, and checking Sign In still works. Test the same path in the native iPhone build.

Automated coverage: focused account-entry suite uses pointer events, focus and keyboard text input; checks no premature registration, draft retention, three viewport sizes, exact consent, sign-in navigation and busy guards. Existing regression fixtures explicitly enter the create form. Old baseline tests requiring invalid relative account URLs or no registration retry were updated to the already-shipped account-fix behavior, not bypassed.

Visual QA: 390x844 account-choice and create-form captures inspected. No live account request is made by fixtures. No site was published. Mac currently has iOS export templates only; web export remains a separate step.

Old test site https://elexerly.github.io/nineweave-web-test/ advertises Round 5r 0d70a8dcad95d516a5dcc75ce242835ce9f98130, before Patrick replaced Kite. The Sitebloc/Grok game advertises Round 5s source 5d326255de84b28b70b178cfa2548a6844e392d5. These are different builds, not solely a browser-cache diagnosis.

Validation: all 32 suites PASS on Godot 4.7.2; focused account-entry 19/19, rules 3,121,037 checks, AI 2,566 checks. Full log retained locally at /tmp/nineweave-web-entry-final.log.
