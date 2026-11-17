# Nineweave StoreKit 2 bridge (SOURCE ONLY, NOT RELEASE READY)

No Apple account changes, SDK binary, purchase product, Xcode project or export activation
are included. Linux tests cover the GDScript contract, NOT Swift compilation or StoreKit.
Compile and sandbox-test on macOS before enabling this bridge. Do not ship the `.gdip.in`
file as an installed plugin without its matching compiled framework.

## Contract

`native/store_entitlement.gd` is a Node, not an autoload. Call `initialize(product_id)`
once after attaching it. It provides `entitlement_changed`, `ads_removed()` and
`entitlement_ready()` to the ad coordinator. Unknown entitlement must suppress ads until
StoreKit answers; it must NOT grant a persistent fake purchase. No ConfigFile or backend
`purchases` values are used as evidence. `localized_price` comes from StoreKit, never a
hardcoded currency string. Buttons call `purchase()` and `restore()`; only deliberate
Restore taps may initiate Apple's authentication dialog. Product ID is deliberately
unconfigured until a non-consumable is created in App Store Connect.

Native singleton `NineweaveStoreKit` exposes configure, pop_event, acknowledge,
query_product, refresh, purchase, restore. Polling transports JSON only from this native
singleton; do not route server/client JSON into `_handle_event`. `verified:true` is an
internal bridge assertion reached only after StoreKit `.verified`, not a server API.
Each purchase/update gets an opaque delivery token. GDScript first applies entitlement
and synchronously notifies consumers, then acknowledges that token; only then does native
code finish the transaction. Startup unfinished transactions are redelivered. Unsupported
products/unverified transactions are never granted or finished. Refund updates remove
access. Entitlement snapshot uses currentEntitlements and a revision guard against a
concurrent purchase and a sequence guard against overlapping snapshots. Restore reports
`unconfirmed`, not success, if verification fails or another refresh supersedes it. StoreKit's signed local state supports entitlement restoration
without trusting a locally saved Boolean. Purchases belong to the Apple account, not a
Nineweave screen name; game sign-out/deletion must not cancel an Apple purchase.

## macOS build work still required

1. Pin Godot source/headers and export templates to the same 4.7.2 build. Obtain generated
   Godot headers using the official iOS plugin build workflow. Do not use 4.6 binaries.
2. Create a static framework target named `NineweaveStoreKit`, with these Swift and
   Objective-C++ sources, iOS deployment target >=15, ARC enabled, C++17, StoreKit and
   Foundation linked, Swift 5 language mode. Set `SWIFT_OBJC_INTERFACE_HEADER_NAME` to
   `NineweaveStoreKit-Swift.h` and include it for the `.mm` compilation. Supply the pinned
   Godot source and generated-header include paths/defines used by its iOS template.
3. Archive device arm64 and simulator arm64/x86_64 variants. Use `xcodebuild
   -create-xcframework` to assemble `NineweaveStoreKit.xcframework`. Check Swift runtime
   embedding in the exported app and exported C initialization symbols.
4. Copy the framework and `.gdip.in` renamed `.gdip` into `res://ios/plugins/`, enable
   ONLY the native export preset, and build the exported Xcode app. Do not alter Web.
5. Native compilation and sandbox QA are release blockers. No statement of binary
   compatibility is implied by these source files.

## Required acceptance tests

Run GDScript test with Godot4.7.2: `--headless --path godot --script
res://tests/test_store_entitlement.gd`. Native tests must cover StoreKit configuration and
Apple sandbox: localized product price; verified purchase; declined/unverified purchase;
cancellation; Ask to Buy pending then approval while running and after restart; restore
on reinstall; offline launch; refund/revocation; duplicate updates; kill before finish;
background/resume; wrong product type; missing product; simultaneous Restore/Purchase.
Ads must disappear immediately on delivery and remain disabled when readiness unknown.
Do not send sandbox entitlements to production or grant Android ownership from this state.

Primary references:
- https://developer.apple.com/documentation/storekit/transaction
- https://developer.apple.com/documentation/storekit/transaction/currententitlements
- https://developer.apple.com/documentation/storekit/appstore/sync()
- https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html
