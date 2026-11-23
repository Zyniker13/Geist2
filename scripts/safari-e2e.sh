#!/bin/sh
# safari-e2e.sh — proves the share extension end to end from Safari on
# the simulator: serves a recipe page on localhost, boots the bot's own
# simulator, installs app + appex, runs the Safari share UI test, then
# inspects the App Group container for the written recipe. Screenshots
# land in docs/look-dev/.
#
# Run through ~/.hermes/bin/sim-lock. Not part of check.sh; a slow,
# interactive proof run on demand.
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICE="zGeist2_bot-iPhone-17"
DERIVED="$(pwd)/.build/App-E2E"
PORT=8123
GROUP_LOG="$(pwd)/.build/e2e-group.log"

# This machine needs the full Xcode developer directory for xcodebuild,
# simctl and XCTest (CommandLineTools lacks them).
XCODE_APP="$(ls -d /Applications/Xcode*.app | head -n 1)"
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

echo "==> build app + appex + UI tests (iOS)"
xcodebuild -project App/RecipeApp.xcodeproj -scheme RecipeApp-iOS \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation -skipMacroValidation \
    build-for-testing -quiet || exit 1

echo "==> boot + install"
if ! xcrun simctl list devices booted | grep -q "$DEVICE"; then
    xcrun simctl boot "$DEVICE"
    BOOTED=1
fi
APP_PATH="$(find "$DERIVED/Build/Products" -maxdepth 3 -name 'RecipeApp.app' -path '*iphonesimulator*' | head -n 1)"
APPX_PATH="$(find "$DERIVED/Build/Products" -maxdepth 3 -name '*.appex' -path '*iphonesimulator*' | head -n 1)"
[ -n "$APP_PATH" ] && [ -n "$APPX_PATH" ] || { echo "app or appex missing" >&2; exit 1; }

xcrun simctl install "$DEVICE" "$APP_PATH"
# The appex rides inside the app bundle; install the app and the
# extension is registered (it is embedded).
if [ ! -d "$APP_PATH/PlugIns" ]; then
    echo "appex not embedded in RecipeApp.app" >&2
    exit 1
fi

echo "==> serve $PORT"
mkdir -p .build/e2e-root
cp docs/e2e/e2e-recipe.html .build/e2e-root/
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory .build/e2e-root >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null; [ "${BOOTED:-0}" = 1 ] && xcrun simctl shutdown "$DEVICE"; true' EXIT INT TERM

echo "==> UI test: Safari share"
# One test selected by name keeps this run tight.
xcodebuild -project App/RecipeApp.xcodeproj -scheme RecipeApp-iOS \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation -skipMacroValidation \
    -only-testing:RecipeAppUITests/SafariShareUITests \
    test-without-building -quiet || { echo "UI test failed" >&2; exit 1; }

echo "==> prove the group container"
# `get_app_container <device> <group-id> groups` prints "groupID<TAB>path";
# the path is the second field. Needs the device booted.
xcrun simctl boot "$DEVICE" 2>/dev/null || true
if xcrun simctl get_app_container "$DEVICE" com.bristleconeit.geist2 groups >"$GROUP_LOG" 2>&1; then
    GROUP_BASE="$(awk 'NR==1{print $2}' "$GROUP_LOG")"
    if [ -z "$GROUP_BASE" ]; then
        echo "E2E FAIL: no group container" >&2
        exit 1
    fi
    COUNT="$(find "$GROUP_BASE/Library/recipes" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    MISO_COUNT="$(grep -rl 'Miso Glazed Carrots' "$GROUP_BASE/Library/recipes" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$COUNT" -ge 1 ] && [ "$MISO_COUNT" -ge 1 ]; then
        echo "E2E OK: $COUNT recipe file(s) in the group container, $MISO_COUNT from this page"
    else
        echo "E2E FAIL: $COUNT recipe file(s), $MISO_COUNT from this page" >&2
        exit 1
    fi
else
    echo "E2E FAIL: get_app_container failed:" >&2
    cat "$GROUP_LOG" >&2
    exit 1
fi

echo "==> export screenshots"
RESULT="$(ls -dt "$DERIVED/Logs/Test/"*.xcresult | head -n 1)"
rm -rf .build/e2e-attach
xcrun xcresulttool export attachments --path "$RESULT" --output-path .build/e2e-attach >/dev/null 2>&1
n=0
for f in .build/e2e-attach/*.png; do
    [ -e "$f" ] || continue
    n=$((n+1))
    cp "$f" "docs/look-dev/m3.4-safari-e2e-$n.png"
done
echo "exported $n screenshot(s) to docs/look-dev/"
