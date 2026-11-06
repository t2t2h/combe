#!/bin/bash
# Standalone build: needs only macOS + Xcode command line tools (no Theos).
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OUT=build/TheosDylib.dylib
mkdir -p build

xcrun --sdk iphoneos clang++ \
  -arch arm64 -miphoneos-version-min=14.0 -isysroot "$SDK" \
  -std=c++17 -fobjc-arc -O2 -IHeaders -Wno-deprecated-declarations \
  -dynamiclib -install_name @rpath/TheosDylib.dylib \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -framework Network -framework CoreGraphics \
  Sources/*.mm -o "$OUT"

strip -x "$OUT"
codesign -f -s - "$OUT"        # ad-hoc; ESign re-signs it anyway

echo "--- linked libraries ---"
otool -L "$OUT"
if otool -L "$OUT" | grep -qiE "substrate|ellekit|substitute|libhooker"; then
  echo "ERROR: dylib depends on a hooking library"; exit 1
fi
echo "OK -> $OUT"
