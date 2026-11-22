# Status

- **Current milestone:** M2 Ingredients, units, scaling — DONE (CI
  green on `b44a59b`). Parser with the 517-line exact corpus (100%,
  gate 98%); per-line metric/US conversion (`RecipeConversion`), density
  table (`IngredientDensity`), temperature parsing/conversion
  (`Temperature`); recipe-level scaling (`factor/scaledLine/scaledSections/
  stepText`); `recipe-cli scale` shows the demo soup at 0.5x/2x/3x with
  rescaled step text. 72 tests in 15 suites green on host, Linux
  container, and CI; decisions 0007 (bare ounce) and 0008 (scaling and
  conversion) recorded.
- **Last done:** `7cc0d8c` — M3.1 first third: JSON-LD extraction
  (Recipe blocks in @graph/arrays, HowToSection/HowToStep, images,
  nutrition), full ISO 8601 durations (parse + render + round-trip),
  `RecipeAssembler` (yield forms, keywords→tags, prose timers inside
  steps, M2 parser on every line). 17 new tests; 89 total green on host
  and Linux; CI green.
- **Next step:** M3.1 continued — Microdata extractor, then the
  heuristic fallback; then M3.2 app surfaces, M3.3 share extensions,
  M3.4 the 40-fixture corpus.
- **Blocked on:** nothing.

## Log

- 2026-11-22: M3.1 part 1 committed `7cc0d8c` — JSON-LD extractor,
  ISO durations, recipe assembly (17 tests; 89 total, host+Linux green,
  CI green). Next: Microdata, heuristic, fixtures.
- 2026-11-22: M2 CLOSED — CI green (`b44a59b`); corpus 517/517, 72
  tests in 15 suites across host/Linux/CI; `recipe-cli scale` 0.5x/2x/3x
  verified with step text.
- 2026-11-22: M2.2 + M2.3 committed `5c445d2` — temperature, density,
  conversion, recipe-level scaling with tests; decision 0008; two
  conversion bugs fixed (US branches had not set the new unitID; density
  factors parse from strings, Decimal float literals carry Double tails).
- 2026-11-22: M2.1 + M2.4 committed `069ae9d` — ingredient line parser,
  517-line exact corpus, bare-ounce decision (0007), Linux libsqlite3-dev
  install fix in test-linux.sh.
- 2026-11-22: M1 closed pending CI — `RecipeZip` split (decision 0006),
  export/import byte-for-byte round-trip, 5,000-recipe scale test green
  (31 tests in 9 suites).
- 2026-11-22: M1.3 + M1.4 — `RecipeIndex` (GRDB FTS5, filters) and
  `Deduplication` (dedup keys, similarity, merge); 29 tests in 8 suites
  green on host; lint clean.
- 2026-11-21: M1.1 + M1.2 pushed (`3244078`, CI green): recipe/plan/
  list/pantry documents with schema version + migrations, SyncPort,
  ZIP machinery (Compression on Apple, zlib on Linux via CZlib), then
  `LibraryStore` + `PhotoStore` + sync field mapping (`f73bb21`).
- 2026-11-21: M0 DONE — app launches empty on iPhone/iPad/Mac targets,
  smoke screenshot in `docs/look-dev/`, `check.sh` all-mode green,
  pushed for CI (`e08b1ce`).
- 2026-11-21: repository created; roadmap and imports added.
