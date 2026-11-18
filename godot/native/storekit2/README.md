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
   embedding in the exported app and exported C++ initialization symbols.
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

## Concrete command-line archive build

`../build_ios_bridges.sh` builds static library xcframeworks for device arm64 and both
simulator architectures using xcrun swiftc/clang++/libtool/lipo/xcodebuild. It requires
an exact tagged4.7.2 source checkout with generated headers and Poing's pinned UMP3.1.0
framework. It refuses to overwrite OUT. Example (paths must be local and inspected):

```
GODOT_SOURCE=/path/to/godot-4.7.2 UMP_XCFRAMEWORK=/path/to/UserMessagingPlatform.xcframework OUT=/new/path/bridges MODE=debug bash godot/native/build_ios_bridges.sh
```

Generate Godot headers in a dedicated4.7.2 source checkout using its SCons iOS template
configuration, specifically core/version_generated.gen.h, core/disabled_classes.gen.h,
modules/modules_enabled.gen.h, core/extension/gdextension_interface.gen.h and core/object/gdvirtual.gen.h (and any further generated
header required by that exact tag). This script compiles against them but does not fetch,
install dependencies or mutate Godot source. Run separately for debug and release to
match DEBUG_ENABLED ABI. In exported Xcode app link StoreKit, Foundation, existing UMP
once, and Swift runtime (ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES and a Swift app target
source or equivalent Swift runtime linker settings). Build/app-link verification is still
required; shell syntax validation alone is NOT proof of native build success.

### Official source archive and template ABI

The build script also accepts `GODOT_SOURCE_ARCHIVE` and `GODOT_SOURCE_SHA256` instead
of a Git checkout. Obtain BOTH the `.tar.xz` and its matching checksum from the official
Godot4.7.2-stable release; do not compute an arbitrary downloaded archive's hash and call
it verified. The script checks that checksum, safely extracts regular files/directories
into fresh OUT/source, validates version.py as4.7.2-stable, and checks generated headers.
It does not use or trust a pre-extracted caller directory in archive mode. Missing headers
still block compilation; use the Git checkout path with SCons-generated headers if the
selected official archive lacks them. Identity/checksum is recorded beside artifacts.

Use `MODE=release_debug` for the normal Godot **template_debug** export: DEBUG_ENABLED,
optimized, without DEBUG_MEMORY_ALLOC. `MODE=debug` is reserved for a custom true-debug
engine built with that allocation ABI, NOT the ordinary downloaded debug export template.
Use `MODE=release` for template_release. Match the exact export template's definitions
before linking; a successful compile alone cannot establish ABI compatibility.

### Local native build check (2026-11-17)

Compiled device arm64 and simulator arm64/x86_64 libraries against official Godot tag
4.7.2-stable (ed1daf0bf001b61586d9930840f2f1394092c079), UMP3.1.0 and Xcode27.2.
Plugin initialization/deinitialization must use C++ linkage to match the generated
Godot exporter declarations, not extern C. The full unsigned device app linked
successfully with GoogleMobileAds13.9.0 and UMP3.1.0. All35 Godot regression suites passed.
This proves compile/link only, not purchase/consent/device behavior. The installed
Godot simulator template claimed arm64 but its libgodot.a contained only x86_64,
so simulator arm64 app linking remained blocked until a matching template is built.
No signing, real ads, purchase, account configuration, or publication occurred.

### Simulator follow-up (2026-11-17)

Built the missing arm64 simulator engine from the same official tag without changing
tracked engine source (`platform=ios target=template_debug arch=arm64 simulator=yes
vulkan=no metal=no`); full simulator app then linked. Actual launch on iOS26.5
crashed before game startup at `protocol witness for App.body.getter in conformance
SwiftUIApp +52`. A second launch on iOS27.0 also exited without reaching startup
diagnostics. No gameplay, plugin registration, or consent/purchase runtime pass is
claimed. The first crash matches the report at
https://github.com/godotengine/godot/issues/124919, whose reported workaround uses
Swift6.3.3 instead of Xcode27 Swift6.4. This is an inference from matching crash frames,
not an independently verified compiler diagnosis. All installed simulator runtimes
reported arm64-only; no older Swift toolchain or alternate Xcode was installed.
No additional toolchain was installed and no physical phone was signed or modified.
The official device-template build remains separately preserved and unsigned.
