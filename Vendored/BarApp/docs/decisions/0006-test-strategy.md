# 0006: Test strategy summary

**Date:** 2026-11-14 (M0, pass 1)
**Status:** Accepted

## Context

`TESTING.md` describes the suites. This record fixes the framework choices, the enforcement points, and the one number CI will hold the package to from M2 on, so the rules are checkable rather than aspirational.

## Decision

- **Framework:** Swift Testing (`#expect`, `#require`, suites, parameterized tests) for all package and app unit tests; XCTest only where the platform requires it (UI tests, performance metrics, accessibility audits).
- **Enforcement points:** `scripts/check.sh` runs the same package checks CI runs; CI adds the Xcode-dependent jobs (app build, UI tests, accessibility, performance). A milestone is done only when its "Done when" line is shown with real output from these checks.
- **Coverage threshold:** from M2 on, CI enforces a minimum of **60% line coverage** for each logic target in the package (`BarCore`, `BarRecipes`, `BarModules`), measured with `swift test --enable-code-coverage` and enforced by a script that parses the coverage report. The threshold may be raised in a decision record as the package stabilizes; it is never lowered. Data files and generated code are excluded.
- **Bug fixes:** every bug gets a regression test before the fix (TESTING.md rule 2). Every schema migration is tested from an empty database and from every earlier schema version (rule 3).
- **No skipped tests:** a disabled test needs a reason in a comment and a tracked issue (rule 5).

## Consequences

- The 60% threshold is deliberately modest so it is honest from the first enforced run; raising it later is cheap, lowering it is not allowed.
- Swift Testing keeps test code small, which matters because this project writes a lot of tests (migrations, conformance, hostile archives, property tests).
- XCTest-only features tie some suites to macOS CI; that is accepted and already reflected in the suite table.
