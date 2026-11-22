# 0006 — RecipeZip target; export/import format

## Context

M1.2 needs whole-library export and import (the roadmap's "round-trips
through export and import byte for byte"). The ZIP machinery
(`RawDeflate`, `ZIPCRC32`, `ZIPReader`, `ZIPWriter`) was adopted from the
Jigger codebase (decision 0003) into `RecipeModules`. But `RecipeModules`
depends on `RecipeCore` (the module manifests reference core types), and
`RecipeCore`'s library store now needs the ZIP machinery — a cycle.

The upstream Jigger code has no equivalent: there, the ZIP machinery and
the module reader lived in one target. This change is recorded per the
standing note that Jigger-derived code is upstream (it moves into a
shared public package after M2).

## Decision

1. The four generic ZIP files move from `RecipeModules` to a new
   portable target `RecipeZip`, which depends only on `CZlib` (Linux;
   Apple platforms use Compression). `RecipeModules` keeps the
   module-specific code (`CanonicalJSON`, `Digests`, `ModuleManifest`,
   `ModuleReader`, `ModuleSignatures`, `SchemaValidator`) and depends on
   `RecipeZip`.
2. `RecipeCore` depends on `RecipeZip` for library export/import.
3. Library export format: a ZIP (written by `ZIPWriter`, stored entries,
   deterministic) with `manifest.json` (`{version: 1, generatedAt}`) at
   the root, every document as `<kind>s/<id>.json` in the same relative
   layout as the library package on disk, and photos under
   `Photos/<shard>/<hash>` unchanged. Import is a restore: paths are
   overwritten, not merged.

## Consequences

- No cycle: RecipeCore → RecipeZip; RecipeModules → RecipeCore + RecipeZip.
- The 40 fixtures and the signed-module machinery are untouched; only
  their import path changed.
- The export archive is byte-stable for a given library state (sorted
  paths, zeroed ZIP timestamps), which the round-trip test asserts
  indirectly by comparing restored files byte for byte.
- When the Jigger ZIP machinery moves to its shared package after M2, it
  will be sourced from `RecipeZip`.
