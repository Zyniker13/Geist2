# Status

- **Current milestone:** M1 Recipe model + library — DONE pending CI.
  Documents (recipe/plan/list/pantry, schema v1, tested migrations),
  SyncPort wired from the first commit (decision 0005), library store
  with atomic writes + SHA-256 photo dedup + soft delete, GRDB FTS5
  index, duplicate detection and merge, whole-library ZIP export and
  import, and the scale proof: 5,000 recipes, searches under 50 ms
  (`LibraryScaleTests`, 31 tests in 9 suites green on host).
- **Last done:** `4dff953` — `RecipeZip` target extracted from
  `RecipeModules` (decision 0006, recorded per the upstream note),
  library export/import round-trip byte for byte, 5,000-recipe
  generated library searches in single-digit ms.
- **Next step:** confirm CI green on `4dff953`, then start M2.1 (the
  ingredient line parser) with the M2.4 corpus alongside.
- **Blocked on:** nothing.

## Log

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
