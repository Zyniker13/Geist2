# 0004: Storage library, schema approach, and migrations

**Date:** 2026-11-14 (M0, pass 2)
**Status:** Accepted

## Context

All user data lives in SQLite on the device. The storage layer must support: numbered migrations tested from every earlier version, full-text search over recipes, ingredients, bottles, and notes, a clean split between read-only reference data and user data, and the fields later sync and backup libraries will need (stable identifiers, created/modified times, soft deletes). It must build and test on Linux with the Swift toolchain (portable core, decision 0001), and work with Swift 6 language mode.

## Decision

- **Library:** [GRDB](https://github.com/groue/GRDB.swift) — a well-known, actively maintained Swift SQLite wrapper with first-class migrations, FTS5 support, record types, and Linux support. Added through Swift Package Manager; recorded here as the project's one storage dependency because it sits under all user data.
- **Schema approach:** every schema change is a numbered migration in code (`migrations` array with an identifier per step). A fresh database runs all migrations in order; a test database upgrades from a fixture of every earlier schema version, seeded with representative rows, and the upgrade is checked for no loss (row counts and spot-checked values). Fixtures live with the migration tests.
- **User/reference split:** reference tables (taxonomy nodes, bundled recipes, module contents) are keyed by stable string identifiers from the data files and are replaceable. User tables (inventory, ratings, notes, user recipes, overlays, shopping lists, menus) use UUID primary keys, carry `created_at`/`modified_at` timestamps and a `deleted_at` soft-delete column, and never reference reference rows by row id — only by the stable identifier.
- **User edits to library or module recipes** are overlay rows keyed by the recipe's stable identifier, so updating the library or a module never overwrites them.
- **Full-text search:** FTS5 virtual tables kept in step with their source tables inside the same migration that creates or changes the source table.
- **Units and amounts** are stored as an exact decimal value plus a unit identifier; display conversion happens at the edge with documented factors (tested in M2).
- Sync and backup themselves are out of scope for v1.0.0; the fields above exist from schema v1 so the shared libraries added later can work without a rewrite. A package test (from M9) fails if any user table lacks a stable identifier, modified time, or soft-delete column.

## Consequences

- GRDB is a real dependency under all user data: it is pinned to a known version, added only from its upstream repository, and re-reviewed on major upgrades. If it ever fails on Linux or with Swift 6 language mode at M2, the fallback is a thin hand-written layer over the system `sqlite3` C API (more code, no dependency); that switch must happen before schema v1 ships, not after.
- Migrations are append-only in practice: shipped migrations are never edited, only added, or the tested-from-every-version guarantee breaks for real users.
- The stable-identifier rule costs a little upfront design (string IDs for taxonomy, UUIDs for user rows) and buys straightforward undo, export, and later sync.
