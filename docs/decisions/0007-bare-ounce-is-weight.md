# 0007 — The bare ounce is weight; fluid ounces are spelled out

Date: 2026-11-22

## Context

The unit catalog has two ounces: `oz` (US fluid ounce, 29.5735295625 ml,
inherited from the sibling bar project where fluid is the default) and
`ozm` (avoirdupois weight ounce, 28.349523125 g). A bare "oz" in an
ingredient line has to resolve to one of them, and the corpus itself
disagreed with the parser test about which: "8 oz cream cheese" was
expected as fluid, "3.5 oz chocolate" and "4 oz cream cheese (softened)"
as weight.

## Decision

When an ingredient line uses a bare ounce abbreviation — "oz", "ozs",
"ounce", "ounces" — the parser resolves it to **weight** (`ozm`). Fluid
ounces must be spelled "fl oz" or "fluid ounce(s)" and resolve to `oz`.

This is the US nutrition-label and grocery convention: package sizes are
weight unless marked "fl oz". In cooking prose weight ounces dominate
(chocolate, cheese, meat), and where a volume is meant the density table
(M2.2) converts weight back to volume without loss. The bar project's
fluid-default convention stays in the bar code, not here.

The catalog is unchanged: `oz` remains the fluid-ounce identifier and
`ozm` the weight identifier. The disambiguation lives in the ingredient
parser, because it is about reading recipe text, not about the units
themselves. "tspns" (an older abbreviation) is added to the teaspoon's
aliases at the same time.

## Consequences

- "8 oz cream cheese" parses as 8 `ozm` (227 g), matching the package.
- "1 fl oz vanilla" parses as 1 `oz` (29.6 ml).
- Corpus rows and parser tests now agree on this rule; the parser test
  that expected bare "oz" to be fluid is updated.
- A recipe that genuinely means fluid ounces but writes bare "oz"
  ("12 ozs beer" in the corpus) parses as weight; the density table and
  the editor can correct the dimension. Documented, not magical.
