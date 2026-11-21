# Status

- **Current milestone:** M0 Bootstrap — layout laid, vendored pieces
  adopted into the portable targets, scripts and CI written; app shell
  and CLI build, package tests green locally.
- **Last done:** `Sources/{RecipeCore,RecipeImport,RecipeModules,recipe-cli}`
  laid out; units, scaling math, CSV, taxonomy validation and the whole
  signed-module machinery moved in from the sibling bar app and adapted
  (decision 0003); `Package.swift`, `App/project.yml`, `check.sh`,
  `test-linux.sh`, `test-apple.sh` and CI written (decision 0004);
  `swift build` and `swift test` green (9 tests).
- **Next step:** finish M0.3 — prove the app launches to an empty library
  on iPhone, iPad and Mac (simulator smoke run + screenshot), then
  `check.sh` end to end; delete `Vendored/` (M0.4); push and confirm CI.
- **Blocked on:** nothing.

## Log

- 2026-11-21: repository created; roadmap and imports added.
- 2026-11-21: M0 in progress — package layout, first portable code
  (unit catalog with exact US volume ladder, friendly-scaling math, CSV,
  module machinery), scripts and CI drafts, decisions 0001–0004.
