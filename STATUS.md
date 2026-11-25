# Status

- **Current milestone:** M4 Library and Recipe Views — M4.4 nearly
  closed. Core committed `c4c24b0`: two visual themes (Paper/Slate with
  `preferredColorScheme`), Mac menu commands (⌘N New Recipe, ⌘⇧I
  Import…, View→Theme), delete with confirmation, and the AX-size
  editor layout. RecipeLifecycleUITests (edit-from-detail,
  delete-with-confirmation) pass on the simulator
  (`.build/m44/ui.xcresult`); RecipeA11yUITests passes with the
  `-openFirstRecipe` deep-link hook (`a11y6`/`a11y7` in
  `.build/m44/`), AX screenshots in docs/look-dev/m4.4-*.png verified
  by eye. `scripts/check.sh all` green (package tests, iOS 27/27 unit
  tests, macOS build) before each push.
- **Last done:** the M4.1 iPad gap is closed — RootLayout picks
  NavigationSplitView (.regular) vs NavigationStack (.compact) by
  horizontal size class (`0fd198c`, decision 0018); the
  `-openFirstRecipe` hook now sets selection AND the path, so the
  deep link opens the split-view detail pane on iPad (verified by
  screenshot) and still pushes on iPhone; fresh iPad screenshots in
  docs/look-dev/m4.4-ipad-{library,detail}.png. UI-test adaptations
  (tap the add menu) committed `f0e93df`. A11y suite green on record
  (`a11y-final.xcresult`).
- **Next step:** Mac smoke screenshots + Mac UI tests (blocked, see
  below), then M5 shopping lists.
- **Blocked on:** macOS UI tests and Mac smoke screenshots cannot run
  on this Mac without Mahler: the UI-test runner hangs because
  `/var/db/com.apple.dt.automationmode/automation-enabled` is missing
  (root:wheel; `sudo` is deny-blocked here), and `screencapture` has
  no Screen Recording permission. The "Enable UI Automation" password
  prompt never renders (coreautha shows "close of host window (null)"
  and stays windowless for 50+ min), wedging coreauthd's evaluation.
  Fix: `sudo touch
  /var/db/com.apple.dt.automationmode/automation-enabled` (a reboot
  alone clears the wedge but the next run hangs again). Details in
  decision 0017. Everything else proceeds.

## Log

- 2026-11-25: iPad split-view gap closed (`0fd198c`, decision 0018).
  Found via a screenshot: `#if os(iOS)` had given iPad the iPhone
  stack since `1d1799b`. RootLayout now branches on
  horizontalSizeClass; row taps set selection everywhere; the
  deep-link hook sets selection + path together (a size-class branch
  inside a delayed task never took effect on iPad — the unconditional
  write is the fix). Pitfall: a bare `xcodebuild` build without
  CODE_SIGN_ENTITLEMENTS runs but silently loses the App Group —
  containerURL(forSecurityApplicationGroupIdentifier:) returns nil
  and the library reads an empty Documents fallback; always pass
  `CODE_SIGN_ENTITLEMENTS=$(pwd)/App/RecipeApp/RecipeApp.entitlements`
  for simulator installs.
- 2026-11-25: macOS UI-test runner hang root-caused from coreauthd/
  coreautha logs: testmanagerd → `evaluatePolicy:2 "Enable UI
  Automation"` (option 1021 XCTest) because the automation-mode state
  file is missing; the only available mechanism is the account
  password (no Touch ID pairing, no Apple Watch); the password panel
  never appears and the evaluation wedges open (a 06:40 loginwindow
  probe bounced off it with "LostFocus"). Blocked on one `sudo touch`
  from Mahler.
- 2026-11-25: M4.4 core committed `c4c24b0` — themes, Mac menu
  commands, delete UI, AX-size editor layout, RecipeLifecycleUITests +
  RecipeA11yUITests, decision 0017, m4.4 screenshots. iOS lifecycle
  tests green; a11y green via the deep-link hook; check.sh green.
- 2026-11-25: M4.3 editor committed `aac466f` — RecipeEditorModel +
  RecipeEditorView + 9 model tests + RecipeEditorUITests (create
  through the + menu, fill, save, verify the detail round-trip with a
  "10m" timer chip); decision 0016. Pitfalls: xcodegen with an
  explicit --spec/--project pair creates a NESTED project
  (App/RecipeApp.xcodeproj/RecipeApp.xcodeproj) — run `xcodegen
  generate` from App/ instead; Decimal(string: "1 1/2") == 1 (parse
  the fraction form first); a fresh RecipeDocument's empty section
  needs a starter row or editor indices crash; a vertical TextField
  exposes as TextField (not TextView) to XCUITest; a prefilled field
  needs press-for-duration + Select All before typeText.
- 2026-11-25: M4.2 closed. UI-test chain fixed with real evidence:
  ImportFlow tapped a StaticText that no longer navigated (the row is
  a Button — tap the button); RecipeView's check-off taps hit the same
  mismatch ("Automation type mismatch: computed Other from legacy
  attributes vs StaticText"); the tomato line read "1 1/2 lbs" because
  the M2.2 lb rounding step snaps 1.25 to halves — the app was right,
  the test was not. Safari E2E must run via scripts/safari-e2e.sh
  (its test serves its own localhost page; bundling it with other UI
  tests fails it). Pitfall: /tmp pruned the first failure's evidence
  mid-investigation — keep result bundles under the repo's .build/.
- 2026-11-24: M4.2 recipe view committed `bbd0023` — RecipeDisplay
  (RecipeCore, pure) + RecipeViewModel + RecipeDetailView; decision
  0015. Bugs the first screenshot pass exposed and fixed: the step-text
  substitution cascaded ("2 1/2 1/2 cupss" — replaced text was rescanned
  by a shorter alias pattern; now one leftmost-longest pass),
  proseTimers stored minutes as seconds (every chip showed "0m"),
  "1 1/2 hours" double-counted its tokens, and metric lines rendered
  kitchen fractions ("591 1/2 ml"); metric now renders decimals.
  Regression tests added for all four (RecipeScalingTests,
  RecipeDisplayTests, ExtractionTests). Pitfall: the UI test had
  asserted 4→5 servings doubles the recipe — it is ×1.25; expectations
  now match the math.

- 2026-11-23: M4.1 committed `1d1799b` — LibraryQuery values in core +
  6 tests; LibraryView search (searchable bound to the query), sort
  menu (newest/oldest/title/rating), filter menu (tag, category,
  cuisine, max time, min rating), "Showing N of M" footer; RecipeApp
  split view on iPad/Mac (selection in LibraryModel), stack on iPhone;
  `Duration.display` now the one time label (shortLabel removed).
  Pitfall: LibraryQuery first landed under Sources/RecipeCore/Sources/
  RecipeCore/ (still built via SPM recursion) — moved to the canonical
  target dir; macOS has no `navigationBarDrawer` searchable placement,
  so placement is #if-switched (.toolbar on macOS).
- 2026-11-23: M3 closed. Simulator Safari E2E full pass (share sheet →
  Save → 2 recipes in the group container, both listed); E2E made
  self-contained (`81facc9`, decision 0013); extension write test
  moved to a temp root (`63f4889`); full `scripts/test-apple.sh` green
  (EXIT=0) with explicit macOS + iOS simulator re-confirmations; macOS
  share proof added (three ExtensionWriteTests, decision 0014).
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
