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
