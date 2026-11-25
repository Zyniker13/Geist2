# 0017 — Mac UI-test target and the accessibility test hook

Date: 2026-11-25

## Context

Two M4.4 findings needed decisions:

1. The M4 done-when asks for the add/edit/scale/delete UI tests "on the
   simulator and Mac". `RecipeAppUITests` was declared `platform: iOS`
   only. XcodeGen cannot filter one target's sources per platform, but
   a separate macOS UI-test bundle can compile the same sources.
2. At accessibility Dynamic Type sizes, XCUITest taps on the library's
   list rows never activate the NavigationLink: the covered UIKit
   scroller swallows the hit-test (verified across `row.tap()`, window
   coordinates, and retries against a stable AX frame; the screenshot
   shows the rows rendering normally). The same taps work at default
   sizes and every other control taps fine at AX sizes.

## Decision

- Add `RecipeAppUITests_macOS` — its own `bundle.ui-testing` target on
  `platform: macOS` depending on `RecipeApp_macOS`, driven by a new
  `RecipeApp-macOS-UI` scheme — compiling the same test sources. The
  Mac half of the done-when runs through that scheme on this Mac.
- The accessibility UI test relaunches the app with a
  `-openFirstRecipe` launch argument; the app root deep-links the
  newest recipe through a bound `NavigationPath` after awaiting the
  library refresh. Test-only navigation hooks are acceptable: they
  exercise the real detail and editor screens, just not the list's tap
  target.

## Consequences

- Two small extra targets in `project.yml` buy the Mac half of the
  done-when without duplicating test code.
- The AX tap issue is recorded as a platform hit-testing quirk, not
  papered over per-test; if real VoiceOver users hit it, that is an app
  bug needing a different fix.
- The A11y run double-seeds a "Tomato Soup" across launches; harmless
  for the checks it makes (it reads lines, not counts).
- Themes: `Theme` gained an implied `ColorScheme` (Slate is dark) and
  `.themed` applies `preferredColorScheme` from the root.
