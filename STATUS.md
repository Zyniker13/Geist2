# Status

- **Current milestone:** M3 Import — M3.1 extraction core DONE. JSON-LD
  (`7cc0d8c`), Microdata with the HTML tree reader (`2ce3a5b`, CI
  green), heuristic fallback (`1c2e32f`, CI queued). Three extractors
  share `JSONLDRecipe` and `RecipeAssembler`; 106 tests in 16 suites
  green on host.
- **Last done:** `1c2e32f` — heuristic fallback: title near the top,
  ingredient/step zones by headings, inline "Ingredients: …" lists,
  yield and time declarations parsed to ISO 8601, named step sections,
  img-tag images; list-marker lines are content, never headings.
- **Next step:** check CI on `1c2e32f`; then M3.2 app surfaces (paste
  link, browser fallback, paste text, photos, OCR) behind the
  Extraction.swift result types, then M3.3 share extensions, M3.4 the
  40-fixture corpus.
- **Blocked on:** nothing.

## Log

- 2026-11-22: heuristic fallback committed `1c2e32f` (8 tests; 106
  total green on host). Microdata committed `2ce3a5b`, CI green (14
  tests) — HTMLTree rewritten to a flat node array assembled bottom-up
  (value-type stack copies lost nested children), text flushed before
  close tags, schema-cased nutrition keys, image dedupe.
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
