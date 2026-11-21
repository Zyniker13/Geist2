# Testing

The app holds people's inventory, ratings, and notes, and it reads module files from anywhere, so testing is a first-class part of the design, not a step at the end. This file describes every test suite, what it proves, and how to run it. Keep it true: when a suite is added, changed, or moved, update this file in the same commit.

## The Rules

1. **Every behavior has a test.** Logic lives in the Swift package, where it is tested with `swift test`; the app's user interface is tested with UI tests in CI.
2. **Every bug gets a regression test** before it is fixed, with a comment saying what it caught.
3. **User data is never lost.** Every schema migration and export format has tests that upgrade or round-trip real data from every earlier version.
4. **Local and CI are the same.** `scripts/check.sh` runs what CI runs. Jobs that need Xcode run there when Xcode is present and are skipped with a clear message when it is not.
5. **No test is skipped to get green.** A failing test is fixed, or the behavior it checks is changed by a decision record. A disabled test needs a reason in a comment and an issue.

## Suites

Paths and commands are the plan; fill in the real ones as each suite is built.

| Suite | Proves | Where | Runs |
| --- | --- | --- | --- |
| Package unit tests | Each model, rule, conversion, and calculator on its own | `Tests/` (Swift Testing) | every CI run, macOS and Linux |
| Worked examples | Calculators, scaling, batching, and dilution match hand-checked answers | `Tests/RecipesTests/` | every CI run |
| Migrations | Every schema version upgrades to the current one with no loss | `Tests/CoreTests/Migrations/` | every CI run |
| Library data | Every bundled recipe validates, every ingredient resolves, and every recipe has provenance | `data/`, checked by `barmod validate` | every CI run |
| Module conformance | Valid modules load; broken ones give exactly the expected errors | `docs/modules/conformance/` | every CI run |
| Hostile modules | Oversized, malformed, and tampered archives are rejected cleanly | `Tests/ModulesTests/Hostile/` | every CI run |
| Property tests | No input crashes the reader, matcher, or importers; round trips are lossless | `Tests/Properties/` | every CI run, more cases locally |
| Storage readiness | Every user table has a stable identifier, modified time, and soft-delete flag, ready for sync and backup later | `Tests/CoreTests/` | every CI run |
| UI tests | Main flows work end to end in the simulator | the app's UI test target | every CI run on macOS |
| Accessibility audits | Every screen passes automated accessibility checks | the app's UI test target | every CI run on macOS |
| Performance | Cold start, search, and matching stay within budget | package benchmarks and UI test metrics | every CI run |
| Coverage | Which lines no test reaches | `swift test --enable-code-coverage` | every CI run, threshold enforced for the package |

## Running Everything

```sh
scripts/check.sh            # what CI runs
```

Document each other command here as it exists (long property runs, benchmarks, and screenshot generation), with the time it takes.

## Results

Record the latest results here: coverage per package target, benchmark numbers against the budgets, the manual accessibility pass, and the date of each.
