#!/bin/bash
# check.sh [NATIVE_DIR]
# On a new simulator, Poki's in-process code (NATIVE_DIR, default this checkout's Poki/Native) reads the
# fixture app's element tree, taps its text field, types, and reads the value and keyboard focus back.
# The tree must hold every labelled element that the simulator's own accessibility reader
# (native/simulator.m) reports for the same screen. The simulator is deleted afterwards.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
NATIVE="$(cd "${1:-$REPO/native/ios-app/Poki/Native}" && pwd)"
X="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
TEXT="ESP173 读屏"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/poki-inprocess.XXXXXX")"
UDID=""
cleanup() {
  if [ -n "$UDID" ]; then xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
APP="$WORK/InProcessCheck.app"; mkdir -p "$APP"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" -fobjc-arc -fmodules \
  -Wall -Werror -Wno-deprecated-declarations -I "$NATIVE" \
  "$HERE/main.m" "$NATIVE/InProcess.m" "$NATIVE/RecoveredNative.m" -framework UIKit -o "$APP/InProcessCheck"
cp "$HERE/Info.plist" "$APP/Info.plist"
codesign -s - --force "$APP" >/dev/null 2>&1
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  "$REPO/native/simulator.m" -o "$WORK/simulator"
xcodebuild -project "$REPO/bin/fixture-app/PokiMCPFixture.xcodeproj" -scheme PokiMCPFixture -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$WORK/fixture" CODE_SIGNING_ALLOWED=NO -quiet build
FIXTURE="$WORK/fixture/Build/Products/Debug-iphonesimulator/PokiMCPFixture.app"

read -r RUNTIME TYPE < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
r = [x for x in json.load(sys.stdin)["runtimes"] if x["platform"] == "iOS" and x["isAvailable"]][-1]
print(r["identifier"], next(t["identifier"] for t in r["supportedDeviceTypes"] if t["productFamily"] == "iPhone"))')
UDID="$(xcrun simctl create poki-inprocess-check "$TYPE" "$RUNTIME")"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl install "$UDID" "$FIXTURE"

export SIMCTL_CHILD_POKI_SIMULATOR_DEVELOPER_DIR="$X"
export SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$X/Library/Frameworks:$X/Library/PrivateFrameworks"
export SIMCTL_CHILD_DYLD_LIBRARY_PATH="$X/usr/lib"
xcrun simctl launch "$UDID" local.poki.inprocess-check -mode field -tag field -delay 8 -text "$TEXT" >/dev/null
sleep 3
xcrun simctl launch "$UDID" local.pokimcp.fixture >/dev/null
DOCS="$(xcrun simctl get_app_container "$UDID" local.poki.inprocess-check data)/Documents"
for _ in $(seq 60); do [ -s "$DOCS/field.json" ] && break; sleep 1; done
echo "{\"id\":\"$UDID\",\"op\":\"ax\"}" | "$WORK/simulator" > "$WORK/reference.json"
OUT="${POKI_CHECK_OUT:-}"
if [ -n "$OUT" ]; then mkdir -p "$OUT"; cp "$DOCS"/field* "$WORK/reference.json" "$OUT/"; xcrun simctl io "$UDID" screenshot "$OUT/screen.png" >/dev/null 2>&1 || true; fi
cat "$DOCS/field.json"
python3 - "$DOCS/field.json" "$TEXT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["prepare"].get("ok"), f"no session: {r['prepare']}"
assert "source_code" not in r, f"no element tree: {r['source_code']}"
assert r["front"].get("bundleId") == "local.pokimcp.fixture", f"front app: {r['front']}"
assert r.get("tap") == 1 and r.get("type") == 1, f"tap {r.get('tap')} type {r.get('type')}"
assert r.get("focus", {}).get("value") == sys.argv[2], f"focused field reads {r.get('focus')}"
PY
python3 "$HERE/compare.py" "$DOCS/field-after.xml" "$WORK/reference.json"
echo "in-process read, tap, type and read-back passed"
