# 0005: SyncPort from M1; upstream discipline for Jigger-derived code

**Date:** 2026-11-21 (M1, on note from Fleet Management)
**Status:** Accepted

## Context

Three standing constraints arrived while M1 was starting:

1. Every library change must go through `SyncPort` — the roadmap put
   this at M10.1, but the library's write path is being designed now,
   and retrofitting a protocol under every write would be a rewrite.
2. The private sync and backup kits from sibling projects must not be
   copied into this repository while it is public.
3. The units, scaling, CSV and module code adopted from Jigger (the
   sibling home bar project, decision 0003) is **upstream**: it moves
   into a shared public package (`bits-recipe-kit`) after M2, so every
   change this project makes to it must be recorded in
   `docs/decisions/`, keeping the eventual reconciliation a diff
   against records rather than an archaeology dig.

## Decision

- `SyncPort` is defined in RecipeCore at M1, not M10: a protocol that
  receives one field-level change per document mutation. The library
  store routes every write through it from its first commit. M10 then
  adds only the test transport, the seeded convergence runs, and
  `docs/sync.md`.
- No private sync or backup kit is copied into this repository, now or
  later; the sync surface is `SyncPort` plus this repo's own test
  transport.
- Files adopted from Jigger (`UnitCatalog`, `RecipeMath`, `CSVCodec`,
  the `RecipeModules` machinery) are treated as upstream: divergence is
  kept minimal and necessary, and every further change to those files
  gets a decision record (or an amendment to decision 0003) naming what
  changed and why, so `bits-recipe-kit` can absorb or reject each
  divergence explicitly.

## Consequences

- The M1 library store carries a `syncPort` dependency from day one;
  tests use a recording port, and the app ships with a no-op port until
  real sync exists.
- After M2, a reconciliation pass diffs this repo's copies of the
  upstream files against Jigger's, guided by the decision records, and
  feeds the result into `bits-recipe-kit`.
- RecipeCore's own model code (recipe/plan/list/pantry documents) is
  this project's, not upstream, and evolves freely.
