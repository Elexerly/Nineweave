# Authoritative UMP consent companion (source only)

Pinned Poing5.1.0 native ConsentInformation exposes `consentStatus` and privacy options
but omits Google's `canRequestAds`. Status enums must not be used as a substitute.
This tiny companion queries the **same UMP singleton**. It neither requests consent nor
stores it, initializes ads, sets ATT status, resets choices or creates an ad account.

Native integration must compile against exact Godot4.7.2 generated headers and existing
Google UserMessagingPlatform3.1.0 headers. Link the same UMP framework already supplied
by Poing; NEVER install or embed a second UMP copy. Build static xcframework device and
simulator slices. `.gdip.in` is deliberately inactive; move/rename only after compilation
and linking are proven. Its dependency declaration relies on Poing linking UMP, so it
must not be enabled by itself. No native build or device test has run yet.

## Adapter contract (not activated)

- Detect singleton `NineweaveConsent`; absent => deny ad initialization/request/show.
- Assert `is_main_thread()` in real-device tests; off-main getters intentionally return
  false/unknown, rather than call UMP illegally or risk a synchronous-dispatch deadlock.
- Existing Poing `ConsentInformation.update()` runs once each app launch, with the
  correctly configured age/test parameters. Load/present required form through Poing.
- After update and form completion (including errors), evaluate `can_request_ads()`.
  Google's persisted state may permit requests after an update error; do not infer this.
- Evaluate again immediately before ad load and before show. On denial destroy cached ad.
- Use `privacy_options_status()` (`required`, `not_required`, `unknown`) for the Options
  entry point. Existing Poing `UserMessagingPlatform.show_privacy_options_form(callback)`
  presents the form; re-evaluate on dismissal.
- No forced consent and no repeated initialization from duplicate callbacks. Gate on
  the StoreKit entitlement too. Test-only staging never activates production requests.

This bridge does NOT attest that Apple tracking authorization is unnecessary. ATT,
SDK configuration and privacy disclosure are separate launch requirements.

Sources inspected:
https://developers.google.com/admob/ios/privacy
https://developers.google.com/admob/ios/privacy/api/reference/Classes/UMPConsentInformation
https://github.com/poingstudios/godot-admob-plugin/tree/615974e9f66921a54e3c71c33db0856bdbf19d13

## Off-main Godot loop

Use `request_snapshot(nonce)` then poll `pop_snapshot()` from Godot. Request handling
runs asynchronously on UIKit's main queue, reads Google state there, and stores JSON in
an NSLock-protected ObjC mailbox. No Godot API is called from that queue and no synchronous
dispatch occurs. JSON contains nonce, can_request_ads, privacy_options_status. Missing,
late, malformed or mismatched response means deny. Permit at most one pending request.
Invalidate nonce when privacy form opens, app backgrounds or provider changes; never use
an earlier allowed result after those transitions. Request a fresh snapshot before each
load/show decision. Existing direct getters remain fail-closed off-main for diagnostics.
No consent UI is invoked by requesting a snapshot.

`consent_snapshot.gd` implements the polling side without activating it in the game.
It accepts only an exact boolean from the latest native nonce, expires snapshots five
seconds after the request (not receipt), permits one pending read, and denies during
refresh. Background/focus loss, privacy-form opening (`invalidate()`), and provider
replacement invalidate old grants. Resuming does not grant or automatically request
consent. The coordinator still needs launch update/form handling and must request a
fresh snapshot before each load/show; this component does not constitute that UI.

`run_consent_snapshot_tests.gd` exercises the GDScript boundary with an explicitly fake
mailbox. It does not prove ObjC compilation, UIKit threading, SDK consent, or device
behavior. Native source still requires Mac compilation and end-to-end tests.

`ad_consent_guard.gd` is an inactive operation coordinator: `request_load(callback)`
and `request_show(callback)` each request a distinct native snapshot and recheck
entitlement at delivery. They never approve from a cached load result. Call
`before_privacy_form()` BEFORE presenting the real SDK form, and `after_privacy_form()`
after dismissal; pending approvals are canceled and subsequent operations need a new
snapshot. The privacy entry point remains reachable even when status expires.

This guard is **not wired to the game's raw ad adapter yet**. Production composition
must route every SDK initialization/load/show path (including asynchronous initialization
callbacks and preloads) through the appropriate fresh authorization, rather than keep
using the adapter's existing consent boolean. Launch UMP update/form flow, age parameters,
background behavior and actual SDK rendering must be validated before activation.
