#!/usr/bin/env bash
# scripts/test-linux.sh — build and test the portable targets on Linux.
#
# Prefers the swift:6 container (what CI runs); falls back to a portability
# audit when Docker is unavailable. The audit checks that the portable
# targets import only Foundation/stdlib/allowed dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFT_IMAGE="${SWIFT_IMAGE:-swift:6.4.2}"

if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    echo "==> building and testing in the swift:6 container"
    docker run --rm -v "$PWD:/workspace" -w /workspace "$SWIFT_IMAGE" \
        bash -c 'swift test 2>&1 | tail -20'
    echo "test-linux OK"
    exit 0
fi

echo "==> docker unavailable; running the portability audit"
missing=0
for target in RecipeCore RecipeImport RecipeModules recipe-cli; do
    echo "--- $target imports ---"
    # Allowed: Foundation, stdlib, sibling targets, allowed dependencies.
    if grep -rE "^import (UIKit|AppKit|SwiftUI|Vision|WebKit|EventKit|CoreGraphics$|Photos|UniformTypeIdentifiers|Observation$)" \
        "Sources/$target" 2>/dev/null; then
        echo "ERROR: $target imports an Apple-only framework" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "portability audit FAILED" >&2
    exit 1
fi
echo "portability audit OK (no Apple-only imports in portable targets)"
echo "test-linux OK (audit only; container run skipped)"
