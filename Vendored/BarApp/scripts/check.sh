#!/usr/bin/env bash
# scripts/check.sh — the local gate, identical to what CI runs.
#
# Usage: scripts/check.sh [mode]
#   mode: all (default) | format | package | app-ios | app-macos
#
# Each part is skipped with a clear message when its tool is unavailable
# (for example on Linux, which has no Xcode and no swift-format in the
# container image). CI runs the same script per job; locally, run "all".
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-all}"

find_swift_format() {
    if command -v swift-format >/dev/null 2>&1; then
        command -v swift-format
        return 0
    fi
    if command -v xcrun >/dev/null 2>&1; then
        xcrun -f swift-format 2>/dev/null && return 0
    fi
    return 1
}

if [ "$MODE" = "all" ] || [ "$MODE" = "format" ]; then
    if SWIFT_FORMAT="$(find_swift_format)"; then
        echo "== swift-format lint =="
        "$SWIFT_FORMAT" lint --recursive --strict Sources Tests App UITests
    else
        echo "== swift-format not available here; skipping format check =="
    fi
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "package" ]; then
    echo "== swift build =="
    swift build
    echo "== swift test with coverage =="
    swift test --enable-code-coverage --build-system native
    echo "== per-target coverage gate (decision 0008) =="
    python3 scripts/coverage_check.py
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "package" ] || [ "$MODE" = "data" ]; then
    echo "== recipe data checks =="
    swift run barmod check-data
    echo "== localization catalog check =="
    python3 scripts/update_localization.py --check
fi

run_app_ios() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "== Xcode not available; skipping the iOS app build/test =="
        return 0
    fi
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: app-ios needs xcodegen (brew install xcodegen, or install the pinned release from yonaskolb/XcodeGen)" >&2
        exit 1
    fi
    echo "== xcodegen generate =="
    xcodegen generate
    if [ -n "${BAR_SIMULATOR:-}" ]; then
        DEVICE="$BAR_SIMULATOR"
    else
        DEVICE="$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/^[[:space:]]+//; s/ \(.*//')"
    fi
    if [ -z "$DEVICE" ]; then
        echo "error: no available iPhone simulator found" >&2
        exit 1
    fi
    echo "== iOS app build (iPhone simulator: $DEVICE) =="
    xcodebuild build -scheme BarApp-iOS -destination "platform=iOS Simulator,name=$DEVICE" -quiet
    echo "== iOS app tests (includes the cold-start budget check) =="
    if [ -e /tmp/app-ios.xcresult ]; then
        rm -rf /tmp/app-ios.xcresult
    fi
    xcodebuild test -scheme BarApp-iOS -destination "platform=iOS Simulator,name=$DEVICE" -quiet  \
        -resultBundlePath /tmp/app-ios.xcresult
}

run_app_macos() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "== Xcode not available; skipping the macOS app build =="
        return 0
    fi
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: app-macos needs xcodegen (brew install xcodegen, or install the pinned release from yonaskolb/XcodeGen)" >&2
        exit 1
    fi
    echo "== xcodegen generate =="
    xcodegen generate
    echo "== macOS app build =="
    xcodebuild build -scheme BarApp-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet
}


case "$MODE" in
    app-ios) run_app_ios ;;
    app-macos) run_app_macos ;;
    all)
        run_app_ios
        run_app_macos
        ;;
    format | package | data) ;;
    *)
        echo "usage: scripts/check.sh [all|format|package|data|app-ios|app-macos]" >&2
        exit 2
        ;;
esac

echo "== check.sh: done (mode: $MODE) =="