# Native launch integration contract

Status: preparation, not an App Store build. No SDK, ads, payments or entitlement
unlock is implemented by this directory. The web game remains unchanged.

## Confirmed baseline

Source 5d326255de84b28b70b178cfa2548a6844e392d5 (Claude absolute account URL fix)
contains Round 5s and Patrick Laquin. Build with Godot 4.7.2 and matching templates.
The `iOS` export preset targets iPhone and iPad, bundles all 64 OGV clips and the
manifest, and exports an Xcode project only. The existing Web preset is unchanged.
Signing Team ID, registered bundle ID and final icon are deliberately blank; no
placeholder identifier should accidentally become the app's permanent identifier.
The source media total is about 202 MiB, not the final App Store download size.

## Monetization behavior to implement next

- Free installation, one **non-consumable** Remove Ads purchase, intended US price
  $5.99. Fetch the localized price from StoreKit, not a hard-coded dollar label.
- Options: Remove Ads, Restore Purchases, honest loading/cancelled/pending/error
  states. Only verified StoreKit entitlement unlocks removal. Listen for transaction
  updates, finish verified transactions, handle refunds/revocations and reinstall.
- Never use `PATCH /me purchases` as proof of purchase: current backend accepts
  client-supplied lists. Never persist a plain `ads_removed=true` as authority.
- Show an interstitial only at the completed-match boundary, after the result,
  before the next round. If no ad is ready or consent disallows serving, continue;
  never block gameplay waiting for an ad. No mid-game interruptions or first-load ad.
- Online: finish/dismiss the ad **before sending rematch readiness**. The server
  can start the next round as soon as both players consent. Do not start its clock
  while either player is in an ad. Tournament readiness needs equivalent gating.
- Ad dismissal/error/cancellation paths resume once only. Repeated taps and stale
  callbacks must not start duplicate games. Do not show ads to verified owners.
- Keep entitlement independent from Nineweave screen-name/account switching.
  Define deletion/reinstall semantics explicitly: deleting a game account does not
  revoke an Apple purchase; restore must still be available via the Apple account.
- Use test ads and StoreKit sandbox only during development. No real ad IDs or
  secrets in source. Pin and audit native plugin + SDK versions against Godot 4.7.2.
- An ad provider is not installed. Native Swift StoreKit bridge and a maintained
  Godot Mobile Ads bridge are integration candidates, not confirmed dependencies.
  Verify actual compile/device compatibility before choosing or advertising support.

## Required engineering gates before TestFlight

1. On macOS, install matching Godot templates and Xcode iOS platform support;
   configure owner Team ID and chosen registered bundle ID without sharing passwords.
2. Integrate StoreKit + ad SDK and consent flow; audit SDK privacy manifests and
   deployment-target requirements before finalizing minimum iOS version.
3. Use Keychain for long-lived native bearer credentials and review backup behavior.
   Current `device_store.gd` persists token/email in a ConfigFile; this is not an
   implemented native secure-storage solution.
4. Add safe-area handling (notch/home indicator) and audit iPad resizing/rotation.
5. Exercise background/foreground, audio interruptions, ad return and online
   reconnect. Current polling background flag is not full audio/video lifecycle QA.
6. Verify bundled Theora dual-video playback and separated audio on actual iPhone
   and iPad. Check Ryan lip sync, Beth fade, peak distortion, memory/thermals and
   offline video startup. A desktop headless pass does not establish these.
7. Test email verification/login/recovery, rename/sign-out/deletion, multiplayer,
   tournament rematch and X/O rotation on devices without touching real users.
8. Replace draft/inaccurate privacy copy only after data/SDK audit. Publish actual
   support contact escapetheavalanchedeux@gmail.com, deletion behavior, retention
   and ad disclosures. Audit online communication/report/block if exposed in app.
9. Produce app icon, iPhone/iPad screenshots, age rating and App Store privacy
   answers. Archive, validate and TestFlight first; release only after approval.

## Verification commands

From `godot/`, run `GODOT=/path/to/Godot_v4.7.2 tools/run_tests.sh`.
`python3 tools/native_preflight.py` checks source/preset/media readiness only.
`python3 tools/native_preflight.py --signing` additionally checks configured
identifiers, icon, macOS/Xcode and reports missing setup. It does not access Apple,
create certificates, change account settings or submit an app.

Reference documentation reviewed 2026-11-17:
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformios.html

For native payload-only verification (not an iOS executable): export with Godot
`--export-pack iOS /path/to/native-content.pck`, then run
`python3 tools/native_preflight.py --pack /path/to/native-content.pck` to verify all
64 clips are in the actual PCK byte-identical to their source, and QA/raw sources
are excluded. This can run on Linux but does not replace Xcode/device validation.
