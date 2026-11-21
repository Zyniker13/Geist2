# 0003: Vendored imports adopted (units, scaling, CSV)

**Date:** 2026-11-21 (M0)
**Status:** Accepted

## Context

The repository started with two imports under `Vendored/`: a scrubbed
personal recipe app (`Vendored/RecipeApp/`) and storage-independent
pieces of a sibling home bar app (`Vendored/BarApp/`, whose
`VENDORED.md` records original paths and a dual Apache-2.0/MIT licence
by the same owner). M0.2 sorts them: what this project keeps is moved
into its own targets, changed freely, and the rest is deleted with the
folder.

## Decision

Adopted into `RecipeCore` (all Apache-2.0/MIT from the sibling project at
commit `d8dbede`, per `Vendored/BarApp/VENDORED.md`):

- `UnitCatalog` → `Sources/RecipeCore/Units/UnitCatalog.swift`. Changes:
  bar-only volume units removed (dash, drop, pony, wineglass, gill,
  fifth, bottle, split, barspoon); kitchen units added (clove, stick,
  sprig, bunch, can, pinch, gallon); alias sets widened for recipe text
  (plurals, "T"/"t." abbreviations); the US volume ladder (cup, pint,
  quart, gallon) re-derived from the exact tablespoon factor so
  same-dimension conversions are exact decimals (a cup is exactly 16
  tablespoons by definition; expressing cup = 8 × fl-oz-in-ml produced a
  rounding tail that made 1 cup → 16 tbsp come out as
  15.9999999959…). `docs/units.md` will be re-published with the
  kitchen conventions at M2.
- `RecipeMath` → `Sources/RecipeCore/Recipes/RecipeMath.swift`. Changes:
  rounding steps retuned for the kitchen (cups to quarters, tablespoons
  and teaspoons to halves, grams to fives, counts to whole; the bar's
  dash step dropped, a pinch is a count unit); the bar's batching,
  dilution, strength and cost calculators were already removed upstream.
- `AmountDisplay` → `Sources/RecipeCore/Units/AmountDisplay.swift`,
  unchanged; its parsing role is absorbed by the M2 ingredient parser,
  after which it will be retired.
- `CSVCodec` → `Sources/RecipeCore/CSV/CSVCodec.swift`, unchanged; it
  serves M9's CSV import.

Adopted into `RecipeModules` (same licence and commit):

- The whole signed-module machinery (canonical JSON, digests, Ed25519
  signatures, manifest, reader, ZIP reader/writer with the raw-DEFLATE
  path, CRC-32, schema validator, hostile schemas) →
  `Sources/RecipeModules/`, with the enum renamed `BarModules` →
  `RecipeModules` and the schema `$id`s already pointing at a
  placeholder `example.com` URL. The recipe-content schema will be
  rewritten for the recipe document format at M9; the archive and
  signature machinery is format-agnostic and unchanged.

Kept as references for later milestones, then deleted with `Vendored/`
(M0.4): the RecipeApp's duplicate detection and merge (`Cookbook.swift`
— ported to RecipeCore at M1.4 with the structured model), its
plain-text recipe extraction and OCR/web intake (`Intake.swift` —
superseded by the M3 RecipeImport implementation), its Reminders export
(`Groceries.swift` — reimplemented at M5.2 against the new list model),
and the sibling project's CI/scripts templates (adapted now — see
decision 0004).

Everything else in `Vendored/` (the bar app's GRDB-bound services, its
app UI, the RecipeApp's UI and assets) is deleted unread in M0.4; the
design is original.

## Consequences

- The licence obligation is attribution text shown in the app's About
  screen (M11) naming Apache-2.0/MIT for the adopted portions.
- The exactness change in the unit catalog is behaviour: conversions the
  old numbers got within a rounding tail are now exact, and tests pin
  the cup→tablespoon ladder.
