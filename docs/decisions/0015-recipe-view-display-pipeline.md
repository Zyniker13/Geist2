# 0015 — The recipe view renders through a core display pipeline

## Context

M4.2 builds the real recipe view: photos, a yield stepper that scales
live, a unit toggle, ingredient check-off, the step list, notes,
rating, source. The scaling math (`RecipeMath`) and the unit
conversion (`RecipeConversion`) already exist in RecipeCore from M2,
but each caller composes them itself, and the CLI renders lines with
its own ad-hoc concatenation. The view needs one path that applies
scale → convert → text, and the app has no per-recipe display state.

## Decision

- A new core type, `RecipeDisplay`, owns the whole display pipeline as
  pure functions: `Options` (a scale factor and a `UnitSystem`:
  written / metric / US) in, rendered sections and step text out. No
  clock, no locale, no global state — RecipeCore stays deterministic.
- "As written" at factor 1 shows `originalText` verbatim: the
  parser's round-trip guarantee reaches the screen. Any scaling or
  converting renders from the structured fields instead.
- Rendering composes the existing primitives — `RecipeMath.scaledLine`
  for friendly rounding, `RecipeConversion.convert` for unit systems,
  `RecipeMath.kitchenFraction` for spelling — rather than duplicating
  any of them. `RecipeDisplay` adds only composition and presentation:
  unit labels with pluralization, item singulars for count lines
  ("1 egg"), and paragraph joining.
- Step text scales through the existing `RecipeMath.stepText`
  (amount-and-unit substitution) only when the factor differs from 1;
  at factor 1 the step shows as written.
- The app keeps viewer state in a `RecipeViewModel` per recipe
  (factor, unit system, check-offs by section/line index), created by
  the detail view's holder. The stored document is never mutated for
  display; rating and notes edits write through `LibraryStore`, and
  check-offs are view state (they are a cooking aid, not data).
- Photos come from `PhotoStore` by content hash; a dangling hash shows
  a placeholder. Ratings clamp to 0...5, 0 meaning unrated.

## Consequences

- The view cannot drift from the CLI or from tests: one pipeline, one
  rounding rule, one set of conversion decisions.
- Linux CI covers the pipeline directly (`RecipeDisplayTests`), so
  display bugs surface in `check.sh`, not only on a simulator.
- Check-off state is intentionally not persisted; if cooking progress
  should survive app switches, that is M6 (cook mode) work with its
  own decision.
- Count-line singularization is a simple rule (trailing -s/-ies and
  the common -es families); irregular plurals pass through unchanged.
  The corpus is the referee if real recipes trip it.
