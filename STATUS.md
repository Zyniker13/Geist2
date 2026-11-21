# Status

- **Current milestone:** M0 Bootstrap — DONE pending CI. Layout laid,
  vendored pieces adopted into the portable targets, `Vendored/`
  deleted, scripts and CI written, app launches to an empty library on
  iPhone (smoke screenshot), all local gates green.
- **Last done:** M0 closed out: `check.sh` end-to-end green (format,
  package tests 9/9, iOS app build+tests on the simulator, macOS app
  build); `test-apple.sh --smoke` green with the empty-library
  screenshot in `docs/look-dev/m0-empty-library.png`; `Vendored/`
  removed after adopting units, scaling, CSV, taxonomy validation and
  the signed-module machinery (decision 0003); decisions 0001–0004
  written.
- **Next step:** push and confirm CI green, then M1.1 — the recipe,
  plan, list and pantry documents as `Codable` value types with a schema
  version and explicit migration functions.
- **Blocked on:** nothing.

## Log

- 2026-11-21: repository created; roadmap and imports added.
- 2026-11-21: M0 in progress — package layout, first portable code
  (unit catalog with exact US volume ladder, friendly-scaling math, CSV,
  module machinery), scripts and CI drafts, decisions 0001–0004.
- 2026-11-21: M0 DONE — app launches empty on iPhone/iPad/Mac targets
  (`RecipeApp-iOS`/`RecipeApp-macOS` schemes, hosted unit tests),
  smoke screenshot captured, `Vendored/` deleted, `check.sh` all-mode
  green (`CHECK_EXIT=0`), pushed for CI.
