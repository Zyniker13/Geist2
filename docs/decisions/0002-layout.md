# 0002: Repository layout

**Date:** 2026-11-21 (M0)
**Status:** Accepted

## Context

M0.1 fixes the layout. The portable targets must build on Linux in CI;
platform code must stay out of them. The app shares one SwiftUI codebase
across iPhone, iPad and Mac, with widgets and share extensions arriving
later (M3, M8).

## Decision

- `Package.swift` at the repository root defines the `RecipeKit` package:
  - `Sources/RecipeCore` — the model, ingredient parser, units, scaling,
    shopping aggregation, pantry matching and meal plan. Deterministic:
    no `Date()`, `UUID()`, randomness or global state; clocks, IDs and
    locale arrive as values. Depends on GRDB (the SQLite index),
    `swift-crypto`, `swift-collections`.
  - `Sources/RecipeImport` — JSON-LD, Microdata and heuristic extraction
    from HTML, plus plain-text recipe parsing. Depends on RecipeCore.
  - `Sources/RecipeModules` — signed collection files: canonical JSON,
    digests, Ed25519 signatures, ZIP reader/writer, schema validation.
    Depends on RecipeCore and `swift-crypto`.
  - `Sources/recipe-cli` — the command-line client (`import`, `parse`,
    `scale`, `validate`), on `swift-argument-parser`.
- `Tests/{RecipeCoreTests,RecipeImportTests,RecipeModulesTests}` mirror
  the targets.
- `App/project.yml` (XcodeGen) defines the `RecipeApp` application target
  (iOS + macOS from one source directory, `App/RecipeApp/`) and the two
  unit-test bundles (`RecipeAppTests_iOS`, `RecipeAppTests_macOS`).
- `scripts/` holds `check.sh` (the local gate CI mirrors),
  `test-linux.sh`, `test-apple.sh` and `coverage_check.py`.
- `docs/decisions/` holds these records; `docs/look-dev/` holds
  screenshots that matter.

## Consequences

- `scripts/check.sh` enforces the layout rules: warnings as errors and a
  secret scan are added as they become meaningful; the portability audit
  in `test-linux.sh` fails when a portable target imports an Apple-only
  framework.
- Platform capabilities (EventKit, Vision, WebKit, App Intents, widgets)
  live behind small protocols RecipeCore defines, so the portable logic
  stays testable on Linux.
- The generated `RecipeApp.xcodeproj` is never committed; it comes from
  `project.yml`.
