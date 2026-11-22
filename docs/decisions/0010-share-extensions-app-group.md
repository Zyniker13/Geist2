# 0010 — Share extensions and the App Group

## Context

M3.3 adds share extensions on iOS and macOS. They must save a recipe
into the same library the app reads. On iOS the standard mechanism is
an App Group container. The repository builds with automatic local
signing only (AGENTS.md; no Apple account), and on macOS an App Group
entitlement requires a real development certificate — ad-hoc signing
(`CODE_SIGN_IDENTITY: "-"`) rejects the build with "entitlements that
require signing with a development certificate".

## Decision

- Both share extensions and the app declare the App Group
  `group.com.bristleconeit.geist2` in entitlements, applied on iOS.
- `SharedLibrary.root` resolves the App Group container when the
  entitlement allows it, and falls back to the app sandbox's
  `Documents/Library` otherwise. The macOS targets build ad-hoc today;
  the macOS extension therefore writes through the fallback path into
  the containing app's sandbox… which a sandboxed extension cannot do
  without the group. So on macOS the extension target also carries the
  entitlements file, with hardened runtime off and no injected base
  entitlements; if ad-hoc signing still rejects it at build time, the
  macOS extension is left un-embedded until a signing identity exists,
  and the app's paste-link/text/photo surfaces cover the same job.
- The app's library root is `Documents/Library` (not Application
  Support): Application Support writes hit simulator EIO on this
  shared host.
- Extraction for both surfaces goes through `SharedLibrary.extract`,
  one code path; each surface writes through its own `LibraryStore`.

## Consequences

- On the iOS simulator the extension and app share the library, and
  the "share from Safari saves a recipe" done-when is testable.
- On macOS the done-when may be blocked by signing, not by code; if
  so, that part of M3's done-when is recorded as blocked on a signing
  identity (a Mahler item), with the app surfaces demonstrating the
  same import path.
- When v0.1.0 gets its real bundle ID and signing, the App Group
  applies everywhere and the fallback stays as the test path.
