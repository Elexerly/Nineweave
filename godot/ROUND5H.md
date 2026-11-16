# Round 5h — real-input sign-in regression

Round 5g allowed recovery in frame/rebuild guards but not the general input
handler. After opening Sign in, the next mouse move, click or key called the
mandatory-name guard and navigated back to onboarding, losing its typed draft.

The input handler now recognizes recovery as an allowed pre-account screen and
lets its controls receive input. Escape explicitly cancels recovery. Email-first
sign-in remains unchanged; no screen-name lookup or disclosure of account email.
Cancelling returns to the typed screen name instead of overwriting it.

Regression uses actual Viewport input dispatch for sign-in click, mouse motion,
email-field press/release and keyboard typing, not only emitted button signals.
Unchanged 5g failed four checks; the fix passes all 24 recovery checks. Tests
continue to cover generic unknown-email responses, wrong code, stale callback,
retry/cancel, same account restoration, and no registration requests.

No server/database/admin changes or live accounts/emails. Browser-rendered QA is
still limited by cloud Chrome's missing WebGL2; engine input dispatch is verified.

Final verification: all 21 suites passed, 3,200,932 checks. Web export passed
(16,779,704-byte PCK) and exported-resource smoke passed 326 checks.
