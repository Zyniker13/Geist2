# 0008 — Recipe-level scaling, conversion, temperature, density

Date: 2026-11-22

## Context

M2.3 adds recipe-level scaling and M2.2 adds system conversion to
`RecipeMath` and two new RecipeCore files. `RecipeMath` is Jigger-derived
upstream code (decision 0003), and the Fleet instruction for M2 is to
record every change to it, because it will move into the shared
`bits-recipe-kit` package after M2. `Temperature` and `IngredientDensity`
are new files written for Geist2, recorded here for the same reason.

## Decision

- `RecipeMath` (upstream) gains a recipe-scaling layer on top of the
  existing single-amount rounding: `factor(writtenYield:targetServings:)`
  (factor = target ÷ written yield, `badFactor` for yield nil or ≤ 0),
  `scaledLine(_:by:catalog:)`, `scaledSections(_:by:catalog:)` and
  `stepText(_:lines:by:catalog:)`. Friendly rounding reuses the upstream
  `round(_:unit:)` step table with one new rule: a nonzero amount never
  rounds to less than one step, so a pinch scaled by 0.25 stays a pinch.
  Ranges scale both ends and collapse when the rounded ends meet.
  `kitchenFraction(of:)` and `round(_:unit:)` become public so the CLI
  and the conversion layer can render with the same rules. Upstream
  behavior is otherwise unchanged; the single-amount and unit tests from
  M2.1 still pass untouched.
- Step-text substitution matches the written amount-and-unit pair by
  number plus any catalog alias of the unit ("2 tbsp", "2 tablespoons",
  "2 T" all match a line whose unit is tbsp). Numbers that are not an
  ingredient's written amount ("knead 10 minutes") are never touched,
  because only ingredient lines drive substitution.
- `RecipeConversion` (new, `Sources/RecipeCore/Recipes/`): per-line
  conversion to metric (ml/g via the catalog's exact `perCanonical`,
  rounded to two fraction digits for display) and to US (metric volume
  becomes cups/tablespoons/teaspoons by size; metric mass becomes cups
  through the density table when the ingredient is in it, ounces
  otherwise). Count lines, to-taste and unquantified lines pass through
  unchanged. Whole-recipe conversion composes this per line
  (`RecipeConversion.sections`).
- `Temperature` (new): first temperature in step text ("350°F",
  "180 C", "425 degrees F"), exact (T − 32) × 5/9 conversion between
  scales, and display rounding to fives. Parsing trims sentence
  punctuation from tokens; trailing periods ("350°F.") do not block a
  match.
- `IngredientDensity` (new): grams-per-milliliter factors for common
  recipe ingredients, keyed by folded item names with a two-word and
  one-word fallback so "chopped walnuts" finds "walnuts". Table values
  are parsed from text (`Factor("0.53")`), not Decimal float literals:
  a Decimal float literal carries the Double's binary tail
  (0.53 → 0.5300000000000001024) and the tests compare exactly.
  An unlisted ingredient converts to nothing; the caller keeps the
  amount as written.
- The cup factor in the density tests is the catalog's documented
  ladder value (16 exact tablespoons = 236.58823656 ml), not the
  fluid-ounce product (236.5882365 ml); same-dimension conversion stays
  exact per decision 0003.

## Consequences

- Scaling and conversion share one rounding table; a scaled recipe and
  a converted recipe look consistent in the UI and the CLI.
- After M2, `bits-recipe-kit` takes `RecipeMath`, `Temperature`,
  `IngredientDensity` and `RecipeConversion` unchanged; nothing in them
  references app targets or sync.
- The step-text matcher is intentionally conservative: it substitutes
  only when the written number and a unit alias appear together. It is
  not a general natural-language rescaler.
