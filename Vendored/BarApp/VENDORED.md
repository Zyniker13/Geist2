# Vendored: BarApp

Storage-independent pieces copied from a sibling project (a home bar app) at commit `d8dbede`, as starting points for this repository. Each path below is the file's path in this folder; its original path in the sibling project is the same unless noted. Nothing here is built: there is no `Package.swift` yet, and the workflows under `.github/workflows/` in this folder are inert because GitHub only runs workflows from the repository root.

Milestone M0.2 sorts these files: move what you keep into your own targets, delete the rest, and record the origin and changes in a decision record.

The sibling project's code is dual licensed Apache-2.0 or MIT, by the same owner.

| File | Original path | Notes |
| --- | --- | --- |
| `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | copied from a sibling project at commit d8dbede; modified: codename replaced; the in-app purchase test steps removed. Inert here: workflows only run from `.github/workflows/` at the repository root |
| `.github/workflows/release.yml` | `.github/workflows/release.yml` | copied from a sibling project at commit d8dbede; modified: codename replaced. Inert here, as above |
| `.swift-format` | `.swift-format` | copied from a sibling project at commit d8dbede; unchanged |
| `App/LicensesView.swift` | `App/LicensesView.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `App/PlatformNav.swift` | `App/PlatformNav.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/CSV/CSVCodec.swift` | `Sources/BarCore/CSV/CSVCodec.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/Inventory/StockLogic.swift` | `Sources/BarCore/Inventory/StockLogic.swift` | copied from a sibling project at commit d8dbede; reference only (GRDB) |
| `Sources/BarCore/Recipes/MatchingService.swift` | `Sources/BarCore/Recipes/MatchingService.swift` | copied from a sibling project at commit d8dbede; reference only (depends on GRDB tables that are not copied) |
| `Sources/BarCore/Recipes/RecipeMath.swift` | `Sources/BarCore/Recipes/RecipeMath.swift` | copied from a sibling project at commit d8dbede; modified: batching, dilution, strength (ABV) and cost calculators removed; `scale(_:drinks:)` became `scale(_:by:)` |
| `Sources/BarCore/Recipes/SubstitutionStore.swift` | `Sources/BarCore/Recipes/SubstitutionStore.swift` | copied from a sibling project at commit d8dbede; reference only (GRDB) |
| `Sources/BarCore/Taxonomy/AppDatabase+Taxonomy.swift` | `Sources/BarCore/Taxonomy/AppDatabase+Taxonomy.swift` | copied from a sibling project at commit d8dbede; reference only (GRDB); the taxonomy data files are not copied |
| `Sources/BarCore/Taxonomy/TaxonomyDocument.swift` | `Sources/BarCore/Taxonomy/TaxonomyDocument.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/Taxonomy/TaxonomyLoader.swift` | `Sources/BarCore/Taxonomy/TaxonomyLoader.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/Taxonomy/TaxonomyValidation.swift` | `Sources/BarCore/Taxonomy/TaxonomyValidation.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/Units/AmountDisplay.swift` | `Sources/BarCore/Units/AmountDisplay.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarCore/Units/UnitCatalog.swift` | `Sources/BarCore/Units/UnitCatalog.swift` | copied from a sibling project at commit d8dbede; modified: the bar-only 1.5 oz pour unit (and its `shot` alias) removed |
| `Sources/BarModules/BarModules.swift` | `Sources/BarModules/BarModules.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/CanonicalJSON.swift` | `Sources/BarModules/CanonicalJSON.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/Digests.swift` | `Sources/BarModules/Digests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ModuleManifest.swift` | `Sources/BarModules/ModuleManifest.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ModuleReader.swift` | `Sources/BarModules/ModuleReader.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ModuleSignatures.swift` | `Sources/BarModules/ModuleSignatures.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/RawDeflate.swift` | `Sources/BarModules/RawDeflate.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/Resources/Schemas/module-ingredient-v1.schema.json` | `Sources/BarModules/Resources/Schemas/module-ingredient-v1.schema.json` | copied from a sibling project at commit d8dbede; modified: schema `$id` moved to a placeholder `example.com` URL |
| `Sources/BarModules/Resources/Schemas/module-manifest-v1.schema.json` | `Sources/BarModules/Resources/Schemas/module-manifest-v1.schema.json` | copied from a sibling project at commit d8dbede; modified: as above |
| `Sources/BarModules/Resources/Schemas/recipe-v1.schema.json` | `Sources/BarModules/Resources/Schemas/recipe-v1.schema.json` | copied from a sibling project at commit d8dbede; modified: as above |
| `Sources/BarModules/SchemaValidator.swift` | `Sources/BarModules/SchemaValidator.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ZIPCRC32.swift` | `Sources/BarModules/ZIPCRC32.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ZIPReader.swift` | `Sources/BarModules/ZIPReader.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Sources/BarModules/ZIPWriter.swift` | `Sources/BarModules/ZIPWriter.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `TESTING.md` | `TESTING.md` | copied from a sibling project at commit d8dbede; template: codename replaced; the in-app purchase row removed |
| `Tests/BarCoreTests/AmountDisplayTests.swift` | `Tests/BarCoreTests/AmountDisplayTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/CSVCodecTests.swift` | `Tests/BarCoreTests/CSVCodecTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/MatchingServiceTests.swift` | `Tests/BarCoreTests/MatchingServiceTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/RecipeMathTests.swift` | `Tests/BarCoreTests/RecipeMathTests.swift` | copied from a sibling project at commit d8dbede; modified: only the scaling tests kept, adapted to `scale(_:by:)` |
| `Tests/BarCoreTests/StockLogicTests.swift` | `Tests/BarCoreTests/StockLogicTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/SubstitutionStoreTests.swift` | `Tests/BarCoreTests/SubstitutionStoreTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/TaxonomyTests.swift` | `Tests/BarCoreTests/TaxonomyTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarCoreTests/UnitTests.swift` | `Tests/BarCoreTests/UnitTests.swift` | copied from a sibling project at commit d8dbede; modified: the 1.5 oz pour-unit conversion test removed |
| `Tests/BarModulesTests/BarModulesTests.swift` | `Tests/BarModulesTests/BarModulesTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/CanonicalJSONTests.swift` | `Tests/BarModulesTests/CanonicalJSONTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/HostileArchiveTests.swift` | `Tests/BarModulesTests/HostileArchiveTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/ModuleReaderTests.swift` | `Tests/BarModulesTests/ModuleReaderTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/ModuleSignatureTests.swift` | `Tests/BarModulesTests/ModuleSignatureTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/SchemaValidatorTests.swift` | `Tests/BarModulesTests/SchemaValidatorTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/ZIPTests.swift` | `Tests/BarModulesTests/ZIPTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/ZIPWriterTests.swift` | `Tests/BarModulesTests/ZIPWriterTests.swift` | copied from a sibling project at commit d8dbede; unchanged |
| `Tests/BarModulesTests/deflate-sample.zip` | `Tests/BarModulesTests/deflate-sample.zip` | copied from a sibling project at commit d8dbede; unchanged |
| `docs/decisions/0004-storage.md` | `docs/decisions/0004-storage.md` | copied from a sibling project at commit d8dbede; example of the decision-record format (Context, Decision, Consequences); codename replaced |
| `docs/decisions/0006-test-strategy.md` | `docs/decisions/0006-test-strategy.md` | copied from a sibling project at commit d8dbede; example of the decision-record format; codename and in-app purchase mentions removed |
| `docs/units.md` | `docs/units.md` | copied from a sibling project at commit d8dbede; modified: codename replaced; the 1.5 oz pour-unit row removed |
| `project.yml` | `project.yml` | copied from a sibling project at commit d8dbede; template only: codename replaced, placeholder `com.example` IDs, entitlements and the in-app purchase test target and scheme removed |
| `scripts/check.sh` | `scripts/check.sh` | copied from a sibling project at commit d8dbede; modified: codename replaced; the in-app purchase test mode removed |
| `scripts/coverage_check.py` | `scripts/coverage_check.py` | copied from a sibling project at commit d8dbede; unchanged |
| `scripts/make-icons.swift` | `scripts/make-icons.swift` | copied from a sibling project at commit d8dbede; template: codename replaced; draws the sibling project's icon, so redraw before use |
