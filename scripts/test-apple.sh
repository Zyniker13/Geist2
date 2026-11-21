#!/bin/sh
# test-apple.sh — package tests, xcodegen, app builds and unit tests on the
# iOS simulator and macOS. --smoke also boots the bot's own simulator,
# installs, launches and screenshots into docs/look-dev/.
#
# Run through ~/.hermes/bin/sim-lock on the shared machine so only one bot
# uses the simulators at a time.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${RECIPE_SIMULATOR:-zGeist2_bot-iPhone-17}"
DERIVED="$(pwd)/.build/App"
SIM_DERIVED="$(pwd)/.build/App-Sim"

# Pick the real Xcode when the default developer directory cannot run
# xcodebuild (CommandLineTools has no XCTest).
if ! xcodebuild -version >/dev/null 2>&1; then
    XCODE_APP="$(ls -d /Applications/Xcode*.app | head -n 1)"
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

echo "==> package tests (macOS)"
swift test

echo "==> xcodegen"
(cd App && xcodegen generate)

echo "==> app + unit tests, macOS"
xcodebuild -project App/RecipeApp.xcodeproj -scheme RecipeApp \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    test -quiet

echo "==> app + unit tests, iOS simulator ($DEVICE)"
xcodebuild -project App/RecipeApp.xcodeproj -scheme RecipeApp \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$SIM_DERIVED" \
    test -quiet

if [ "${1:-}" = "--smoke" ]; then
    echo "==> smoke: boot, install, launch, screenshot"
    if ! xcrun simctl list devices booted | grep -q "$DEVICE"; then
        xcrun simctl boot "$DEVICE"
        BOOTED=1
    fi
    APP_PATH="$(find "$SIM_DERIVED/Build/Products" -maxdepth 3 -name 'RecipeApp.app' -path '*iphonesimulator*' | head -n 1 || true)"
    if [ -z "$APP_PATH" ]; then
        echo "could not find RecipeApp.app under $SIM_DERIVED" >&2
        exit 1
    fi
    xcrun simctl install "$DEVICE" "$APP_PATH"
    xcrun simctl launch "$DEVICE" com.bristleconeit.geist2
    sleep 3
    mkdir -p docs/look-dev
    xcrun simctl io "$DEVICE" screenshot "docs/look-dev/m0-empty-library.png"
    if [ "${BOOTED:-0}" = "1" ]; then
        xcrun simctl shutdown "$DEVICE"
    fi
    echo "smoke screenshot: docs/look-dev/m0-empty-library.png"
fi

echo "test-apple OK"
