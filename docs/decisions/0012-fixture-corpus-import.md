# Decision 0012 — Fixture corpus for import (M3.4)

## Context

M3.4 called for a curated set of realistic recipe pages to prove the
extractors (JSON-LD, microdata, heuristic) end to end. Earlier decisions
already fixed how a page becomes a RecipeDocument; what was missing was
breadth: the three extractors were proven only against hand-written unit
tests, and importing from the web would meet dozens of small page
shapes no unit test anticipated.

The corpus is 70 small HTML fixtures (f01–f70) plus one test file that
extracts each through the full `RecipeExtractor.extract` chain and
asserts title, yield, times, categories, ingredients, and steps. Each
fixture is reduced to the markup a test needs, with original text —
the fixtures are entirely original or clearly public-domain, per
AGENTS.md.

## Decision

- **70 fixtures, one corpus test.** Each fixture is a single realistic
  page shape (full JSON-LD, microdata, heuristic lists, classed divs,
  packed meta lines, entities, mixed markup). `FixtureCorpusTests`
  runs them all serially (`--no-parallel`) so a crash attributes to a
  single fixture.
- **The corpus drives fixes, not the reverse.** Fixtures encode page
  shapes; extractor changes serve them. During this milestone the
  corpus exposed and directed fixes for: fraction-yield parsing,
  strict numeric yield tokens, yield-unit collection past fillers and
  ranges, French headings, microdata nested Duration itemscopes, packed
  meta-line parsing (category/cuisine/yield/short time labels, with and
  without colons), classed zone detection (ingredients/steps/directions/
  yield/serves/ing), and a central sanitizer in RecipeAssembler that
  strips inline tags and trims every field before it becomes a document.
- **Extraction-time sanitize, once, centrally.** Rather than stripping
  markup in each extractor, RecipeAssembler.sanitize(_:) is applied to
  titles, ingredients, and steps as a document is assembled; the
  heuristic extractor delegates to it for its own lines. Tests assert
  both the cleaned `originalText` and the parsed quantities, so a
  regression either way fails.
- **WIP on a branch, fixes one at a time.** The corpus work ran on
  `m3.4-import-wip` with a commit per fix, per the maintainer's
  direction; the branch merges to main only once the whole suite and
  full `swift test` are green.

## Consequences

- Import quality is now asserted against 70 page shapes on every run of
  `scripts/check.sh`; any extractor change that breaks a shape fails CI
  immediately.
- The central sanitizer means new extractors need not duplicate
  markup-stripping logic, but they must emit decoded-entity text (the
  JSON-LD entity table handles `&frac12;` and friends).
- Packed meta lines are heuristic: the segment reader only fires in the
  preamble and on lines with separators, so prose steps still flow to
  the normal scan.
