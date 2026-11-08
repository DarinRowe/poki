#!/bin/bash
# Builds Poki Setup.app and its DMG on a Mac: the SwiftUI shell plus the Rust bridge.
#   desktop/mac/scripts/bundle.sh [universal|native] [out-dir]
# Needs Xcode (swift) and Rust. Signs ad hoc unless MAC_SIGN_IDENTITY is set.
set -euo pipefail
MODE="${1:-native}"
OUT="${2:-$(pwd)/dist}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DESKTOP="$(cd "$HERE/.." && pwd)"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$DESKTOP/Cargo.toml" | head -1)"
BUILD="${BUILD_NUMBER:-$(git -C "$DESKTOP" rev-list --count HEAD 2>/dev/null || echo 1)}"
mkdir -p "$OUT"

echo "== Rust bridge ($MODE)"
if [ "$MODE" = universal ]; then
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
  (cd "$DESKTOP" && cargo build --release -p poki-setup-bridge --target aarch64-apple-darwin && cargo build --release -p poki-setup-bridge --target x86_64-apple-darwin)
  lipo -create -output "$OUT/poki-setup-bridge" "$DESKTOP/target/aarch64-apple-darwin/release/poki-setup-bridge" "$DESKTOP/target/x86_64-apple-darwin/release/poki-setup-bridge"
  SWIFT_ARCHS=(--arch arm64 --arch x86_64)
else
  (cd "$DESKTOP" && cargo build --release -p poki-setup-bridge)
  cp "$DESKTOP/target/release/poki-setup-bridge" "$OUT/poki-setup-bridge"
  SWIFT_ARCHS=()
fi

echo "== SwiftUI app"
(cd "$HERE" && swift build -c release ${SWIFT_ARCHS[@]+"${SWIFT_ARCHS[@]}"})
BIN="$(cd "$HERE" && swift build -c release ${SWIFT_ARCHS[@]+"${SWIFT_ARCHS[@]}"} --show-bin-path)/PokiSetup"

APP="$OUT/Poki Setup.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PokiSetup"
cp "$OUT/poki-setup-bridge" "$APP/Contents/MacOS/poki-setup-bridge"
cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$HERE/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "== Sign"
IDENTITY="${MAC_SIGN_IDENTITY:--}"
# A Developer ID signature needs a secure timestamp for notarization; an ad hoc one cannot have it.
if [ "$IDENTITY" = "-" ]; then TS=--timestamp=none; else TS=--timestamp; fi
KC=()
if [ -n "${MAC_SIGN_KEYCHAIN:-}" ]; then KC=(--keychain "$MAC_SIGN_KEYCHAIN"); fi
codesign --force --options runtime "$TS" ${KC[@]+"${KC[@]}"} -s "$IDENTITY" "$APP/Contents/MacOS/poki-setup-bridge"
codesign --force --options runtime "$TS" ${KC[@]+"${KC[@]}"} -s "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== DMG"
DMG="$OUT/PokiSetup-$VERSION-macos.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Poki Setup" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp ${KC[@]+"${KC[@]}"} -s "$IDENTITY" "$DMG"
fi
echo "$DMG"
