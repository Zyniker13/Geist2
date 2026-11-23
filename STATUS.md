# Status

- **Current milestone:** M3 Import — M3.1 extraction core DONE
  (JSON-LD `7cc0d8c`, Microdata `2ce3a5b`, heuristic `1c2e32f`).
  M3.2 app surfaces DONE (`74bc133`): import sheet with text/link/
  photo tabs, isolated browser fallback for JS pages, Vision OCR,
  library + detail views; UI test drives text import end to end,
  screenshots in docs/look-dev/.
  M3.3 share extensions code-complete (`897e897`): iOS + macOS appex
  targets, ShareHandler, App Group `group.com.bristleconeit.geist2`,
  SharedLibrary.root with Documents fallback (decision 0010).
  Proven on simulator: recipe written into the group container by the
  host is listed by the app (docs/look-dev/).
  M3.4 import corpus DONE (`6c1da58`): 70 realistic fixtures prove all
  three extractors end to end (decision 0012); strict numeric yield
  parsing, class-marked zone detection, packed meta-line parsing, and
  a central assembler sanitizer all landed through fix-per-commit work
  on `m3.4-import-wip` (968378a → d70e894 → f82c69d → 6278374).
- **Last done:** `6c1da58` — M3.4 branch merged to main; full `swift
  test` 72 tests / 15 suites green on host before the merge.
- **Last done:** macOS unit suite green after ExtensionWriteTests was
  pointed at a temp root (the real group container needs the
  extension's entitlement; the real write is proven by the Safari E2E):
  7 tests / 3 suites passed on macOS, including OCR and the new
  `testExtractedHTMLWritesIntoAScratchRoot`.
- **Next step:** commit the temp-root test fix, then the full
  `scripts/test-apple.sh`, Safari E2E on the Mac, and close M3.
- **Note from Fleet Management (Mahler, 2026-11-23):** the shutdown-on-
  exit edits to `scripts/safari-e2e.sh` and `scripts/test-apple.sh`
  were already committed inside `81facc9`; nothing pending there.
- **Blocked on:** nothing. (macOS extension embedding may block on a
  signing identity — see decision 0010; not needed yet.)

## Log

- 2026-11-23: M3.4 merged `6c1da58` — 70-fixture corpus green (70/70),
  decision 0012. Fix chain on `m3.4-import-wip`: strict Decimal prefix
  parsing (`d70e894`), yield-unit collection past fillers/ranges
  (`f82c69d`), class zones + meta lines + central sanitizer
  (`6278374`). Frac entities added to the JSON-LD decoder. Pitfall:
  parallel swift test runs in one .build corrupt results — one serial
  run is the source of truth; another: keep zone-marker stand-in lines
  out of the content they introduce.
- 2026-11-22: M3.3 share extensions committed `897e897` — per-platform
  app targets (XcodeGen has no per-platform dependency filter), static
  extension Info.plist (GENERATE_INFOPLIST_FILE NO — the generated one
  had been dropping NSExtension entirely), entitlements files, and
  SharedLibrary as the one extraction+root path for app and extension.
  Simulator proof: host-written recipe in the App Group container
  appears in the app list. Pitfall: the group container UUID regenerates
  on reinstall — seed via the current `simctl get_app_container groups`
  path, and note the root is <group>/Library (not Documents).

- 2026-11-22: M3.2 app surfaces committed `74bc133` — import sheet
  (text/link/photo), browser fallback, Vision OCR, library + detail
  views, end-to-end UI test with screenshots. Default root moved to
  Documents (Application Support hit simulator EIO on shared host).
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
