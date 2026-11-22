# Status

- **Current milestone:** M2 Ingredients, units, scaling — nearly done.
  M2.1 parser (committed `069ae9d`) with the M2.4 517-line exact corpus
  (100% exact, gate 98%); M2.2 conversion layer done locally: per-line
  metric/US conversion (`RecipeConversion`), grams-per-ml density table
  (`IngredientDensity`), temperature parsing/conversion
  (`Temperature`); M2.3 recipe-level scaling done locally
  (`RecipeMath.factor/scaledLine/scaledSections/stepText`,
  `kitchenFraction` public); `recipe-cli scale` renders the demo soup
  scaled 0.5x/2x/3x with step text rescaled ("Heat 4 T olive oil" at 2x).
  72 tests in 15 suites green on host; Linux container green (72/15);
  lint strict-clean; decision 0008 records the RecipeMath/Jigger changes.
- **Last done:** M2.2/M2.3 tests written and green, two conversion bugs
  fixed on the way (US conversion branches set the new `unitID`;
  density factors parse from strings because Decimal float literals
  carry a Double's binary tail), `stepText` verified in the CLI demo.
- **Next step:** check.sh all (running, proc_d0823222ff86) → commit
  M2.2/M2.3 with decision 0008 and refreshed STATUS → CI check → M3
  (import: JSON-LD/Microdata/heuristic extraction, share extensions,
  40 fixtures).
- **Blocked on:** nothing.

## Log

- 2026-11-22: M2.2 + M2.3 done locally — temperature/density/conversion
  and recipe-level scaling with tests (72 in 15 suites, Linux green);
  `stepText` matches unit aliases so "2 tbsp" rescales in step text;
  decision 0008 written.
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
