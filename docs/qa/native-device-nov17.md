# Local iOS device test, 2026-11-17

- Native source: `plax/ios-test-ads`, account UI integration `25ffd73`.
- All 36 headless suites passed, including account entry and native bridge state tests.
- Xcode 27.2 (27B52), Apple Swift 6.4.2. No toolchain downgrade or update.
- Signed development build with existing local Apple Development identity and Xcode-managed wildcard profile. Automatic signing without provisioning updates succeeded. No Apple portal changes or upload.
- Separate diagnostic bundle `com.boothgames.nineweave.devcheck`; not a production bundle decision.
- Full PCK preflight passed: 64 videos byte-identical to source, excluded tests/tools/raw assets.
- Installed and launched on owner's connected PiPhone Duex. Process remained running and reached OpenGL ES3.0 setup. Visual/UI and StoreKit/UMP runtime outcomes still require verification; don't infer from process existence.
- No real ad load, purchase, account creation, or App Store publication performed.
- Second phone still pending identification/connection.

## Simulator investigation

Official rebuilt Godot4.7.2 simulator engine and Escape's cached4.7.2 universal engine both linked, but both crashed at SwiftUIApp App.body getter+52 before game startup. Escape engine required release-mode plugin copies in isolated export for ABI compatibility. No changes to Escape source or installed tools. My Mac destination built unsigned using temporary SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=YES; normal open rejected executable format. Not runtime validation.

Matching upstream report: https://github.com/godotengine/godot/issues/124919 . One reporter, archived due to authorship policy, not a maintainer-confirmed fix. User declined older Swift; no older toolchain installed.
