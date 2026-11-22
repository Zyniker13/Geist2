# Status

- **Current milestone:** M1 Recipe model + library — nearly done.
  Documents (recipe/plan/list/pantry, schema v1, tested migrations),
  SyncPort wired from the first commit (decision 0005), library store
  with atomic writes + SHA-256 photo dedup + soft delete, GRDB FTS5
  index with filters, duplicate detection and merge. M1.3/M1.4 tests
  green on host (29 tests in 8 suites).
- **Last done:** M1.3 `RecipeIndex` (GRDB, FTS5 external-content table,
  prefix search, tag/category/cuisine/time/rating filters) and M1.4
  `Deduplication` (URL/title normalization, Jaccard ingredient
  similarity, field-preserving merge) written and tested; lint clean.
- **Next step:** run `check.sh` end-to-end, commit M1.3/M1.4, then M1.5
  (index hooks into the store: rebuild after every write) if the
  roadmap splits it that way, else close M1 and start M2 (ingredient
  parser, unit conversion, 500-line corpus).
- **Blocked on:** nothing.

## Log

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
