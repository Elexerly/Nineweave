# Nineweave test interstitial boundary

**Source integration only. Disabled by default. Not native-device verified.**
No ad SDK/binary, real ad unit, AdMob app registration, consent UI or production
serving is installed or activated by this change. Escape the Avalanche is not
modified and remains ad-free.

## Inspected dependency contract

Poing Studios `godot-admob-plugin` release v5.1.0, exact source commit
`615974e9f66921a54e3c71c33db0856bdbf19d13`:
https://github.com/poingstudios/godot-admob-plugin/tree/v5.1.0

The adapter calls the native `PoingGodotAdMob` and
`PoingGodotAdMobInterstitialAd` singleton methods/signals verified against that
release's GDScript API and iOS Objective-C++ source. This keeps all ad-library
symbols optional in the game, so Web and source tests work without an SDK.
Do not silently substitute a new plugin version: recheck method signatures,
privacy manifests, deployment target and callbacks on real devices.

The release states testing through Godot 4.7.2 and an iOS 15 minimum. This is
upstream evidence, **not our own native compatibility test**. Its EditorPlugin
installs missing binaries on activation; it has intentionally not been enabled.
The Mac build step must pin, inspect/install the native dependency and match the
app's deployment target. Only official Google test units are accepted in the
adapter source; changing to live units is a separate reviewed release change.

## Wiring and safety

`main.configure_native_test_ads(store_entitlement, consent_check)` is the explicit
native-only composition point. The provider must implement
`entitlement_ready()`, `ads_removed()` and `entitlement_changed`. The consent
check is a real reviewed consent/age flow, not a hard-coded production `true`.
Call `refresh_native_test_ads()` after consent changes. Until the provider/consent
flow are installed, do not call this method and no ad requests are made.

Unknown entitlement, verified Remove Ads, absent plugin, absent consent, no fill
or an ad that is not ready all continue straight to the next match. No fake
purchases, client-asserted backend purchases or saved unlock booleans are used.
The test request also requests non-personalized ads; this does **not** replace
consent obligations. The adapter initializes only with explicit consent.

- First match: no ad.
- Completed normal/local match: mark one pending boundary; on rematch/new match,
  show one ready test interstitial and then continue once after native dismissal.
- Returning to the menu preserves the pending boundary for the next match.
- Standard online rematch: do not send readiness until native dismissal/failure;
  repeated taps cannot send duplicate readiness.
- Offline tournament: gate before mutating the tournament's starting state.
- **Online tournaments deliberately skip ads for now.** Their backend creates
  running matches automatically; inserting an ad can consume an opponent's clock.
  A server-level two-player readiness phase is required before enabling ads there.
- Game Master audio is muted during the interstitial and restored to its prior
  mute state. The SDK handles its own ad audio. Real interruption testing remains.
- Navigation invalidates callbacks, so a late native dismissal cannot teleport
  the player into a stale match. Ads never start after a delayed load callback:
  loading only prepares an ad for a future explicit boundary.
- No arbitrary watchdog starts the next match while a native ad is still visible.
  SDK missing-dismissal/callback behavior must be verified in native QA.

## Remaining gates

Install native plugin and Google Mobile Ads framework on Mac; configure iOS
AdMob app ID (not another game's ID); integrate consent/age decisions, StoreKit
verified entitlement, background/foreground and audio interruptions. Add UI
purchase/restore integration separately. Verify actual test-ad impression,
close/skip, no-fill, offline, resumed app and online rematch on iPhone/iPad before
calling this functional native monetization. Online tournament readiness needs
backend work; no backend or production changes were made here.
