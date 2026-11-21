# Roadmap

A recipe manager for iPhone, iPad and Mac (working title). It does for food what a good home bar app does for drinks: your own recipes, imported from anywhere, scaled and converted, matched against what's in your pantry, turned into shopping lists, cooked step by step, and planned across the week. It works fully offline, and later syncs between your own devices for free over the local network.

Version 0.1.0 is done when every milestone below is done and `v0.1.0` is tagged with every script green.

---

## 0. Fixed Choices (Do Not Re-Decide)

| Concern | Decision |
| --- | --- |
| Platforms | iOS 18+, iPadOS 18+ and macOS 15+ from one SwiftUI codebase, with a split view on iPad and Mac. Swift 6 language mode, strict concurrency. |
| Project | A Swift package for the portable targets, plus an XcodeGen `project.yml` for the apps, widget and share extensions. Placeholder bundle ID `com.bristleconeit.geist2` (the real one comes with the name). Automatic local signing only. |
| Portable targets | `RecipeCore` (model, ingredient parser, units, scaling, shopping aggregation, pantry matching, meal plan), `RecipeImport` (JSON-LD, Microdata and heuristic recipe extraction from HTML, plain-text recipe parsing), `RecipeModules` (signed collection files), `recipe-cli` (import, parse, scale and validate from the command line). All build and test on Linux. |
| Recipe model | Each recipe is one document: title, summary, yield (amount and unit), prep, cook and total times as durations, ingredient sections of structured lines (quantity or range, unit, item, preparation, note, optional flag, original text), step sections (text, optional timers), tags, categories, cuisine, source URL and attribution, notes, rating, photos by content hash, and nutrition when the source gives it. Every document has a stable ID, a schema version, and created, modified and deleted (soft delete) times. |
| Storage | A library is a local file package: one JSON document per recipe, plan, list and pantry, and photos stored once by content hash. Writes are per document and atomic. A local SQLite index (GRDB, FTS5) is rebuilt from the documents and never the source of truth. |
| Sync | Documents are shaped so each maps one to one onto a sync document (maps of fields, lists of lines), and every change goes through a `SyncPort` protocol in RecipeCore. The shared sync kit is adopted later, outside this roadmap (§2); until then a test transport proves two libraries converge. No CloudKit. |
| Units and scaling | Exact decimal factors with ml, g and piece as base units; US and metric volume and mass, kitchen units (pinch, clove, can, stick, sprig, bunch), temperatures, and a density table for volume-to-weight conversion of common ingredients. Scaling rounds to friendly amounts (quarters, thirds, whole eggs) and never rounds to zero. |
| Integrations | Reminders through EventKit. zDocket through its `zdocket://` URL scheme (the Things verbs: `add` and `json`, with `x-callback-url`) and App Intents. Shortcuts, Spotlight and widgets through App Intents. |
| Collections | Signed module files: a ZIP with canonical JSON, SHA-256 digests and Ed25519 signatures, validated against a published schema, with hostile-archive tests. The app has its own trust store; the project's signing key is never in the repository. |
| Dependencies | Apple SDKs, plus GRDB 7, `swift-crypto`, `swift-argument-parser` and `swift-collections`. Anything else needs a decision record that names its licence and why. |
| CI | GitHub Actions: Linux tests the portable targets in the `swift:6` container; GitHub-hosted macOS builds the apps and runs unit tests. Actions pinned to SHAs, read-only permissions, a coverage gate on the portable targets. |
| Out of scope | Apple account steps, App Store work, CloudKit, server code, paid content, and public recipe pages (zFolio, later). Food data you didn't write needs a public-domain or permissive source named in a decision record. |

---

## 1. Milestones

Each milestone is done only when its **Done when** line is met and shown with real command output in `STATUS.md`.

### M0. Bootstrap

- M0.1 Layout: `Sources/{RecipeCore,RecipeImport,RecipeModules,recipe-cli}`, `App/` (shared SwiftUI plus iOS and macOS targets), `Tests/`, `docs/decisions/`, `scripts/`.
- M0.2 Sort the imports in `Vendored/`. Move what you keep into your own targets (units, scaling, CSV, module format, taxonomy machinery, CI and scripts, the icon script, the web and OCR import, the Reminders export, duplicate detection) and delete the rest. Record where each piece came from and what changed in a decision record.
- M0.3 `Package.swift`, `project.yml`, `scripts/check.sh`, `scripts/test-linux.sh` and `scripts/test-apple.sh`; the app launches to an empty library on iPhone, iPad and Mac.
- M0.4 CI (Linux and macOS), and decision records for the fixed choices and the layout.

**Done when:** every script is green locally, CI is green, and `Vendored/` is gone.

### M1. The Recipe Model and Library

- M1.1 The recipe, plan, list and pantry documents as value types with `Codable` and a schema version; migrations are explicit functions with tests.
- M1.2 The library file package: atomic per-document writes, content-hashed photos with thumbnails, soft delete and a Recently Deleted view, export and import of a whole library.
- M1.3 The GRDB index: full-text search over title, ingredients, steps, tags and notes; filters by tag, category, cuisine, time and rating; rebuilt from documents on demand.
- M1.4 Duplicate detection (normalized source URL and title plus ingredient similarity) and a merge that keeps both sides' fields.

**Done when:** a 5,000-recipe generated library opens, searches in under 50 ms on the Mac, survives a kill mid-write without losing a document, and round-trips through export and import byte for byte.

### M2. Ingredients, Units and Scaling

- M2.1 Ingredient line parser: quantities (integers, decimals, fractions, unicode fractions, ranges, "a", "half"), units with plurals and abbreviations, sizes ("large"), item, preparation ("finely chopped"), notes in parentheses, "to taste", optional lines and section headers.
- M2.2 Units and conversion, including volume to weight through the density table, and the user's preferred system.
- M2.3 Scaling by servings or by factor, with friendly rounding, scaled amounts inside step text, and "convert to metric" or "to US" for a whole recipe.
- M2.4 A corpus of at least 500 ingredient lines you wrote, covering every form above, with expected parses.

**Done when:** at least 98% of the corpus parses exactly, every scaling and conversion test passes on Linux, and `recipe-cli scale` shows a recipe at 0.5x, 2x and 3x.

### M3. Import

- M3.1 Web import in `RecipeImport`: JSON-LD (every schema.org Recipe field, ISO 8601 durations in full, `HowToSection` and `HowToStep`), then Microdata, then a heuristic fallback; images captured into the library.
- M3.2 In the app: paste a link, the browser fallback for pages that need scripts (non-persistent, isolated), paste text, photos, and OCR of printed pages, all going through the M2 parser.
- M3.3 Share extensions on iOS and macOS that take a link or text and save a recipe.
- M3.4 Fixtures: at least 40 reduced, rewritten pages covering the extraction paths, all tested without the network.

**Done when:** every fixture imports with the expected fields, the share extension saves a recipe from Safari on the simulator and on the Mac, and OCR imports a photographed recipe card from a test image you made.

### M4. Library and Recipe Views

- M4.1 Library: grid and list, search, filters, sort, tags and categories; split view on iPad and Mac, stacks on iPhone.
- M4.2 Recipe view: photos, yield stepper that scales live, unit toggle, ingredient check-off, step list, notes, rating, source attribution.
- M4.3 Editor with structured ingredient rows (and a "paste lines" mode that parses), sections, steps, timers, photos.
- M4.4 Accessibility (VoiceOver, Dynamic Type, keyboard and menu commands on Mac) and two visual themes.

**Done when:** a smoke run screenshots every screen on iPhone, iPad and Mac into `docs/look-dev/`, and the UI tests for add, edit, scale and delete pass on the simulator and Mac.

### M5. Shopping Lists and Reminders

- M5.1 Lists built from recipes or plans: combined quantities across recipes (with unit conversion), grouped by aisle, minus what's in the pantry, plus free items.
- M5.2 Reminders export through EventKit: pick a list, group by aisle or recipe, and update existing reminders instead of duplicating them on a second send.
- M5.3 Checking items off in the app, and moving bought items into the pantry.

**Done when:** a three-recipe list combines correctly in tests, and sending it to Reminders twice on the simulator leaves one reminder per item.

### M6. Cook Mode and Timers

- M6.1 Step-by-step view with large type, the screen kept awake, scaled amounts in each step, and ingredients for the current step.
- M6.2 Timers detected from step text ("simmer for 20 minutes") and added by hand; several at once, with notifications and a Live Activity on iPhone.

**Done when:** cook mode runs a recipe end to end in a UI test, and timers fire notifications on the simulator.

### M7. Pantry, "What Can I Cook" and Meal Planning

- M7.1 Pantry: items with optional amounts and use-by dates, kept in a small original ingredient tree (taxonomy) so "chicken thighs" satisfies "chicken".
- M7.2 Matching: recipes you can make now, with one or two missing, required versus optional ingredients, and substitutions.
- M7.3 Meal planner: a week view, drag recipes onto days and meals, servings per entry, leftovers, and "make a shopping list for this week".

**Done when:** matching tests pass on Linux over a generated pantry and library, and a planned week produces the expected combined shopping list.

### M8. zDocket, Shortcuts, Spotlight and Widgets

- M8.1 zDocket: "Send to zDocket" for a shopping list or a plan's prep tasks ("Thaw chicken" the evening before), through `zdocket:///json` with `x-callback-url`; items carry the title, a link back into the app and the date, never personal notes. If zDocket isn't installed, say so and offer Reminders.
- M8.2 App Intents: add a recipe from a link, show a recipe, today's meals, add to the shopping list; Shortcuts actions and Siri phrases.
- M8.3 Spotlight indexing and a widget for today's meals and the shopping list.

**Done when:** the zDocket URLs are built and tested in RecipeCore, a UI test sends a list through the scheme to a stub handler, and the intents run in Shortcuts on the simulator.

### M9. Collections and Exchange

- M9.1 Signed module files for recipe collections: create, sign, validate, install, update and remove, with the trust store and the schema published in `docs/`.
- M9.2 Share one recipe as a module file, as text, or as Markdown; import CSV and Markdown recipe files.
- M9.3 `recipe-cli` validates and signs collections.

**Done when:** the hostile-archive suite passes, and a collection made with the CLI installs in the app and updates in place.

### M10. Sync Readiness

- M10.1 Every library change goes through `SyncPort`, as field-level changes per document.
- M10.2 A test transport between two in-process libraries: concurrent edits to different fields of one recipe both survive, and both libraries converge after offline edits.
- M10.3 `docs/sync.md`: how each document maps onto a sync document, so the shared kit can be adopted without changing the model.

**Done when:** the convergence tests pass for 1,000 seeded runs on Linux.

### M11. Release 0.1.0

- M11.1 Accessibility and localization pass (English plus string catalogs ready for more), empty states, onboarding, and an About screen with licences.
- M11.2 Performance: the 5,000-recipe library scrolls at 120 Hz on iPad and Mac.
- M11.3 Final look-dev screenshots, CHANGELOG, and the tag.

**Done when:** `v0.1.0` is tagged with every script and CI green.

---

## 2. Later, Outside This Roadmap

- Sync between your own devices through the shared sync kit, starting with free local-network sync, then optional cloud sync.
- Public recipe pages and sharing through zFolio.
- The product name, bundle ID, App Store and TestFlight.
