# 0004: CI, scripts and the check gate

**Date:** 2026-11-21 (M0)
**Status:** Accepted

## Context

The fixed choices require CI with a Linux job for the portable targets
and a macOS job for the apps, actions pinned to SHAs, read-only
permissions, and a coverage gate. The sibling project's CI and scripts
(under `Vendored/BarApp/`) are a proven template.

## Decision

- `.github/workflows/ci.yml` runs on push to `main` and pull requests,
  with `permissions: contents: read`:
  - **linux** on `ubuntu-24.04`, container `swift:6.4.2`, installs the
    SQLite headers GRDB's bundled shim needs, then `swift test`.
  - **macos** on `macos-15`, installs XcodeGen 2.46.0 (pinned),
    `swift test`, generates the project, builds the macOS app with
    signing disabled. The iOS-simulator job is added when M0.3's app
    builds locally (the shared simulator lock means CI uses its own
    default simulator there).
- Actions are pinned to commit SHAs (`actions/checkout@11bd…`).
- `scripts/check.sh` is the local gate mirroring CI: `swift-format lint
  --recursive --strict` over `Sources Tests App`, `swift build`,
  `swift test`, then the app builds. Modes let CI run pieces per job.
- `scripts/test-linux.sh` prefers the swift:6 container through Docker
  and falls back to a portability audit when Docker is unavailable; the
  audit fails when a portable target imports an Apple-only framework.
- `scripts/test-apple.sh` runs the package tests, regenerates the
  project, and runs app tests on macOS and the iPhone simulator;
  `--smoke` boots the named simulator, installs, launches and
  screenshots into `docs/look-dev/`.
- Simulator work on the shared host goes through the host's simulator
  lock and this project's own named simulator.

## Consequences

- CI stays the arbiter; `check.sh` locally should never pass when CI
  would fail.
- The coverage gate (`scripts/coverage_check.py`, adopted unchanged from
  the sibling project) is wired into `check.sh package` once the test
  count is large enough for per-target floors to be meaningful (M1).
