# 0001: Fixed choices

**Date:** 2026-11-21 (M0)
**Status:** Accepted

## Context

The roadmap (§0) fixes the project's platform, packaging, dependency and
scope decisions. This record states them once, so later records can refer
to "the fixed choices" without re-arguing them.

## Decision

The fixed choices are exactly those in `ROADMAP.md` §0:

- **Platforms:** iOS 18+, iPadOS 18+ and macOS 15+ from one SwiftUI
  codebase with a split view on iPad and Mac; Swift 6 language mode with
  strict concurrency.
- **Project:** a Swift package for the portable targets plus XcodeGen
  `project.yml` for the apps, widget and share extensions; placeholder
  bundle ID `com.bristleconeit.geist2`; automatic local signing only.
- **Portable targets:** `RecipeCore`, `RecipeImport`, `RecipeModules`,
  `recipe-cli`; all build and test on Linux.
- **Recipe model:** one document per recipe with title, summary, yield,
  durations, structured ingredient lines, step sections with timers,
  tags, categories, cuisine, source URL and attribution, notes, rating,
  photos by content hash, nutrition when the source gives it, stable ID,
  schema version, created/modified/deleted times.
- **Storage:** a library is a local file package — one JSON document per
  recipe, plan, list and pantry, photos stored once by content hash,
  atomic per-document writes, and a local SQLite index (GRDB, FTS5)
  rebuilt from the documents, never the source of truth.
- **Sync:** documents map one to one onto sync documents; every change
  goes through a `SyncPort` protocol in RecipeCore. The shared sync kit
  is adopted later, outside this roadmap; until then a test transport
  proves two libraries converge. No CloudKit.
- **Units and scaling:** exact decimal factors with ml, g and piece as
  base units; US and metric volume and mass, kitchen units (pinch, clove,
  can, stick, sprig, bunch), temperatures, a density table for
  volume-to-weight conversion of common ingredients. Scaling rounds to
  friendly amounts and never rounds to zero.
- **Integrations:** Reminders through EventKit; zDocket through its
  `zdocket://` URL scheme (`add` and `json` with `x-callback-url`) and
  App Intents; Shortcuts, Spotlight and widgets through App Intents.
- **Collections:** signed module files — a ZIP with canonical JSON,
  SHA-256 digests and Ed25519 signatures, validated against a published
  schema, with hostile-archive tests. The app has its own trust store;
  the project's signing key is never in the repository.
- **Dependencies:** Apple SDKs, plus GRDB 7, `swift-crypto`,
  `swift-argument-parser` and `swift-collections`. Anything else needs a
  decision record naming its licence and why.
- **CI:** GitHub Actions; Linux tests the portable targets in the
  `swift:6` container; GitHub-hosted macOS builds the apps and runs unit
  tests; actions pinned to SHAs, read-only permissions, a coverage gate
  on the portable targets.
- **Out of scope:** Apple account steps, App Store work, CloudKit,
  server code, paid content, and public recipe pages (zFolio, later).
  Food data not written by this project needs a public-domain or
  permissive source named in a decision record.

## Consequences

- Any proposal that contradicts one of these is a decision record
  amending this one, not a quiet code change.
- The placeholder bundle ID and product name stay until the product is
  named (M11 at the earliest, outside this roadmap's scope for code).
