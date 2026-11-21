# AGENTS.md

Conventions for anyone, human or agent, working in this repository.

## The Contract

- `ROADMAP.md` is the build order, and its §0 Fixed Choices are not re-decided. `STATUS.md` is the live state: read it first and keep it current (current milestone, last done, next step, blocked on, a log line).
- Every significant decision goes in `docs/decisions/NNNN-slug.md` (Context, Decision, Consequences), numbered in order.
- A milestone is done only when its "Done when" line is met and shown with real output from the scripts below, and CI is green.

## Commands

```sh
scripts/check.sh               # exactly what CI runs: format check, build with warnings as errors, secret scan, tests
scripts/test-linux.sh          # portable targets in the swift:6 container (Docker), else a portability audit
scripts/test-apple.sh          # package tests, xcodegen, app builds and unit tests on the iOS simulator and macOS
scripts/test-apple.sh --smoke  # also boot your own simulator, install, launch, screenshot into docs/look-dev/
```

Never commit the generated `.xcodeproj`; it comes from `project.yml`. Simulator work goes through the host's simulator lock and your own named simulator.

## Layout Rules

- Portable targets (`Sources/RecipeCore`, `Sources/RecipeModules`, `Sources/RecipeImport`, `Sources/recipe-cli`) use Foundation, the standard library and the dependencies §0 allows. They build and test on Linux. `scripts/check.sh` enforces this.
- RecipeCore is deterministic: no `Date()`, `UUID()`, randomness or global state inside it. Clocks, IDs and locale come in as values.
- Platform code (UI, EventKit, Vision, WebKit, App Intents, widgets, share extensions) lives in the app targets only, behind small protocols RecipeCore defines.
- Code under `Vendored/` or marked with a `VENDORED.md` came from another project at a named commit. Change it freely once you've moved it into your own targets; note the origin in the decision record that adopts it.

## House Rules

- Small, green commits on `main`, or a short-lived branch merged with a normal push once green. Never force-push, rewrite pushed history, or delete `main` or a tag.
- Commit messages describe the code: `recipecore: fraction parsing`, `app: cook mode timers`. No ticket numbers and no mention of agents.
- Never commit secrets, tokens, keys, certificates, provisioning profiles, team IDs, email addresses, personal names, hostnames, IP addresses, local paths outside the repository, or anything about who runs the project. Test data uses obviously fake values (`alice`, `example.com`).
- Recipe fixtures are original or clearly public domain, and saved web pages used as test fixtures are reduced to the markup the test needs, with the source site's text replaced by your own.
- The design is original. Don't copy another app's name, icons, artwork, layouts or sounds; use SF Symbols and art you draw (the icon comes from a checked-in vector script).
- Screenshots that matter go to `docs/look-dev/`.
