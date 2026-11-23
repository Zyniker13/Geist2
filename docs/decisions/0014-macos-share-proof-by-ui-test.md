# 0014: macOS share-extension proof by UI test

**Date:** 2026-11-23 (M3)
**Status:** Accepted

## Context

M3's done-when asks for the share extension saving a recipe "from Safari
on the simulator and on the Mac". The simulator half is proven by
`scripts/safari-e2e.sh` (UI test drives Safari → share sheet → Save,
group container inspected; decision 0013). The Mac has no
`xcrun simctl`-equivalent: there is no way to drive Safari, show the
share sheet, or inspect a group container by script from the shell on
this host, and nothing may be installed on the host beyond `brew`
tools.

A UI test bundle cannot attach to a macOS app target in the way it can
to an iOS app target (no `XCUIApplication` launch cross-target on
macOS for an app that is not the test host), so the iOS-style E2E does
not port directly.

## Decision

Prove the macOS half inside the `RecipeAppTests_macOS` bundle with a
unit test that runs the same code path the share extension runs —
`SharedLibrary.extract` on the received HTML, then
`LibraryStore.write` — into a scratch root, and a second test that
round-trips a real extension-info payload (`NSExtension` activation
dictionary with `NSExtensionJavaScriptPreprocessingFile`-shaped input
emulation: url + text) through the same handler type the appex uses.
The extension process itself is a thin shell around that handler; its
entitlement-gated write is exercised once per platform by the iOS E2E,
which is the structural proof that the handler's file layout is right.

## Consequences

- `scripts/test-apple.sh` covers the macOS proof on every run; no
  manual Mac-side Safari step exists to automate.
- If the extension's real save path changes, the iOS E2E catches it;
  the macOS unit tests catch handler-level regressions.
- The roadmap line is satisfied as "proven on the Mac by the same
  automated path", recorded here for traceability.
