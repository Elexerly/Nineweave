# Lexerly native test, 2026-11-18

- Isolated source branch plax/lexerly-native-nov18, based on cb2ac17.
- 48 Godot suites passed across initial run and corrected count-only reruns; 38 Lexerly checks. Remaining visible captions subsequently changed with five affected suites passing. Test backend routing followed by 4 account suite reruns passing.
- Native PCK contains 70 video clips byte-identical to source, 35 heroes (32 default + Nick/Professor/JB hidden). Test/tool/raw sources excluded.
- Original gold title shader retained; full 6.84s Lexerly announcement. JB audio independently demuxed using existing native pipeline. No live ad IDs or ads enabled.
- Xcode 27.2 / Godot 4.7.2, no toolchain changes. Signed build and codesign verification pass.
- Local Xcode configuration copied from known working six-second-intros build into build/ios; bundle changed to com.boothgames.lexerly.test and label Lexerly Test. This installs side-by-side and has separate local account state.
- iOS preset custom feature lexerly_test selects dedicated empty test backend; normal builds retain original API. Feature verified embedded in PCK. Test backend intentionally does not send verification emails.
- App: build/DerivedData/Build/Products/Debug-iphoneos/NineweaveDeviceTest.app.
- Installation attempted; device connection unavailable (CoreDevice 4016). Nothing installed. Must reconnect/unlock phone before retry. Device UI, audio, and network runtime not yet verified.
- No production publish, app upload, database change, or existing app replacement performed.

## Later owner-directed routing change

Patrick explicitly chose to test against the existing live API and accounts. iOS export no longer enables lexerly_test. The optional isolated routing remains in source, inactive. Separate bundle and local state remain, so existing installed game is preserved. Read-only live capabilities report protocol 2, email and account unlocks. Live roster lacks jb_circuit/jb_rocker and still lists Professor publicly; compatible backend update is required for full new-character online/unlock testing. No production API mutations were made by this build task.
