# 0013 — Self-contained Safari share E2E

## Context

`safari-e2e.sh` originally booted the simulator, started a `python3 -m
http.server` on the host, drove Safari through the share sheet, and then
proved the write by inspecting the App Group container from the host.
That had three problems:

1. The host server was independent of the test, so the test could not
   know when the extension had finished fetching; once the test moved to
   its own in-runner server, the runner's teardown beat the extension's
   fetch (connection refused, no recipe written, yet the test "passed"
   because Safari's page text was already visible).
2. The proof lived in shell-land while the test asserted only the
   visible half — a run could pass while nothing was written (this
   actually happened).
3. The script edited its own trap/shutdown behavior, so it drifted from
   what it printed.

The simulator's group-container UUID also regenerates whenever the
simulator is erased (it was erased on 2026-11-23 by Fleet Management),
so any host-side hardcoded path is fragile.

## Decision

- The UI test is self-sufficient: it starts `TinyHTTPServer` on 8123
  inside the test runner process, opens the page in Safari, drives
  Safari's Page Menu → Share → Recipe app, and then proves the data
  half through the app itself: it launches
  `com.bristleconeit.geist2` and asserts the recipe title appears in
  the library list. The app reads the same App Group the extension
  writes, so a passing run shows the whole chain (extension fetched
  the page, parsed it, wrote the group; app read the group).
- The runner does NOT get an App Group entitlement. An attempt to add
  one (`CODE_SIGN_ENTITLEMENTS` on the UI-test target) does not reach
  the runner binary xcodebuild builds — it ships with empty
  entitlements, so `containerURL(forSecurityApplicationGroupIdentifier:)`
  returns nil there and the probe would silently fall back to tmp.
  Reading the group from the app, which already has the entitlement,
  avoids the problem entirely.
- `scripts/safari-e2e.sh` no longer serves anything and no longer holds
  port 8123; it builds the `RecipeApp-E2E` scheme for testing, runs the
  UI test with `test-without-building`, boots the sim if needed for
  screenshot collection, exports screenshots from the result bundle,
  and shuts the simulator down on exit.
- The extension keeps fetching URL-only shares itself
  (`ShareHandler.fetchHTML`, decision 0009's fetch branch); the test
  serves the page the extension fetches.

## Consequences

- The E2E proves the real flow with no external fixtures and no
  host-side state, and the sim erase no longer invalidates it. The
  visible and data halves are asserted in one place, so a run cannot
  pass while nothing was written.
- `RecipeAppUITests` is excluded from the plain `RecipeApp-iOS` test
  scheme (unit tests only); the dedicated `RecipeApp-E2E` scheme owns
  it, so routine `test` runs and CI never drive Safari.
- If the extension's fetch ever fails, the test fails with the group
  contents in the assertion message instead of silently passing.
- The runner entitlement is simulator-ad-hoc only (no signing team);
  on-device this pattern would need the real team — out of scope for
  the simulator E2E.
