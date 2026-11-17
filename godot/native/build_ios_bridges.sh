#!/bin/bash
# Builds unsigned source-only bridges; never installs/enables plugins or publishes.
set -euo pipefail
if [[ $(uname -s) != Darwin ]]; then echo 'Requires macOS and full Xcode.' >&2; exit 2; fi
: "${UMP_XCFRAMEWORK:?Set to existing pinned UserMessagingPlatform3.1.0.xcframework}"
: "${OUT:?Set to a NEW empty output directory outside the game}"
MODE=${MODE:-release}
[[ $MODE == debug || $MODE == release_debug || $MODE == release ]] || exit 2
[[ ! -e "$OUT" ]] || { echo 'OUT must not exist; no artifacts overwritten.' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
if [[ -n ${GODOT_SOURCE_ARCHIVE:-} ]]; then
 : "${GODOT_SOURCE_SHA256:?Provide SHA256 verified against official Godot release checksums}"
 [[ $GODOT_SOURCE_SHA256 =~ ^[0-9a-fA-F]{64}$ ]] || exit 2
 ACTUAL=$(shasum -a 256 "$GODOT_SOURCE_ARCHIVE" | awk '{print $1}')
 [[ $ACTUAL == "$GODOT_SOURCE_SHA256" ]] || { echo 'Godot archive checksum mismatch.' >&2; exit 2; }
 # Extract ONLY regular files/directories to our fresh private output, no links/traversal.
 python3 - "$GODOT_SOURCE_ARCHIVE" "$OUT/source" <<'PYARCHIVE'
import ast, pathlib, sys, tarfile
root = pathlib.Path(sys.argv[2]); root.mkdir()
with tarfile.open(sys.argv[1], "r:*") as archive:
    members = archive.getmembers()
    prefixes = set()
    for item in members:
        path = pathlib.PurePosixPath(item.name)
        if path.is_absolute() or ".." in path.parts or not (item.isfile() or item.isdir()):
            raise SystemExit("Unsafe/nonregular archive member: " + item.name)
        prefixes.add(path.parts[0])
    if len(prefixes) != 1: raise SystemExit("Expected single source root")
    archive.extractall(root)
source = root / next(iter(prefixes))
values = {}
for node in ast.parse((source / "version.py").read_text()).body:
    if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
        try: values[node.targets[0].id] = ast.literal_eval(node.value)
        except (ValueError, TypeError): pass
if tuple(values.get(k) for k in ("major", "minor", "patch", "status")) != (4, 7, 2, "stable"):
    raise SystemExit("Archive version is not Godot4.7.2-stable")
(root / "selected-path.txt").write_text(str(source))
PYARCHIVE
 GODOT_SOURCE=$(cat "$OUT/source/selected-path.txt")
 printf 'Official source archive SHA256: %s\n' "$ACTUAL" > "$OUT/source-identity.txt"
else
 : "${GODOT_SOURCE:?Set exact Git source, or GODOT_SOURCE_ARCHIVE and its official SHA256}"
 [[ $(git -C "$GODOT_SOURCE" describe --tags --exact-match HEAD) == 4.7.2-stable ]] || { echo 'Godot source must be exact4.7.2-stable.' >&2; exit 2; }
 git -C "$GODOT_SOURCE" diff --quiet HEAD -- || { echo 'Tracked Godot source is modified.' >&2; exit 2; }
 git -C "$GODOT_SOURCE" rev-parse HEAD > "$OUT/source-identity.txt"
fi
for h in core/version_generated.gen.h core/disabled_classes.gen.h modules/modules_enabled.gen.h; do
 [[ -f "$GODOT_SOURCE/$h" ]] || { echo "Missing generated $h; run Godot SCons header targets first." >&2; exit 2; }
done
xcodebuild -version > "$OUT/toolchain.txt"
cat "$OUT/source-identity.txt" >> "$OUT/toolchain.txt"
FLAGS=(-std=c++17 -fobjc-arc -fblocks -fmodules -fno-exceptions -fno-rtti -DPTRCALL_ENABLED -DUNIX_ENABLED -DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -I"$GODOT_SOURCE" -I"$GODOT_SOURCE/platform/ios")
if [[ $MODE == debug ]]; then
 FLAGS+=(-DDEBUG_ENABLED -DDEBUG_MEMORY_ALLOC -O0 -g)
elif [[ $MODE == release_debug ]]; then
 FLAGS+=(-DDEBUG_ENABLED -O2 -DNDEBUG -DNS_BLOCK_ASSERTIONS=1)
else
 FLAGS+=(-O2 -DNDEBUG)
fi
for slice in device-arm64 simulator-arm64 simulator-x86_64; do
 ARCH=${slice##*-}; SDK=iphoneos; TRIPLE="$ARCH-apple-ios15.0"; UMP_SLICE=ios-arm64
 if [[ $slice == simulator-* ]]; then SDK=iphonesimulator; TRIPLE="$ARCH-apple-ios15.0-simulator"; UMP_SLICE=ios-arm64_x86_64-simulator; fi
 DIR="$OUT/$slice"; mkdir -p "$DIR"
 SDKROOT=$(xcrun --sdk "$SDK" --show-sdk-path)
 [[ -d "$UMP_XCFRAMEWORK/$UMP_SLICE/UserMessagingPlatform.framework" ]] || { echo "Missing UMP slice $UMP_SLICE" >&2; exit 2; }
 xcrun --sdk "$SDK" swiftc -swift-version 5 -parse-as-library -whole-module-optimization -emit-object -emit-objc-header -module-name NineweaveStoreKit -emit-objc-header-path "$DIR/NineweaveStoreKit-Swift.h" -target "$TRIPLE" -sdk "$SDKROOT" "$ROOT/storekit2/NineweaveStoreKit.swift" -o "$DIR/storekit-swift.o"
 xcrun --sdk "$SDK" clang++ "${FLAGS[@]}" -target "$TRIPLE" -isysroot "$SDKROOT" -I"$DIR" -c "$ROOT/storekit2/nineweave_storekit.mm" -o "$DIR/storekit-bridge.o"
 xcrun --sdk "$SDK" clang++ "${FLAGS[@]}" -target "$TRIPLE" -isysroot "$SDKROOT" -F"$UMP_XCFRAMEWORK/$UMP_SLICE" -c "$ROOT/ump/nineweave_consent.mm" -o "$DIR/consent.o"
 xcrun libtool -static -o "$DIR/libNineweaveStoreKit.a" "$DIR/storekit-swift.o" "$DIR/storekit-bridge.o"
 xcrun libtool -static -o "$DIR/libNineweaveConsent.a" "$DIR/consent.o"
done
for name in NineweaveStoreKit NineweaveConsent; do
 mkdir -p "$OUT/simulator"
 xcrun lipo -create "$OUT/simulator-arm64/lib$name.a" "$OUT/simulator-x86_64/lib$name.a" -output "$OUT/simulator/lib$name.a"
 xcodebuild -create-xcframework -library "$OUT/device-arm64/lib$name.a" -library "$OUT/simulator/lib$name.a" -output "$OUT/$name.xcframework"
done
find "$OUT" -type f -name '*.a' -exec shasum -a 256 {} \; > "$OUT/archive-sha256.txt"
echo 'Unsigned archives built. Not installed or activated. Exported app must still link and pass sandbox/device QA.'
