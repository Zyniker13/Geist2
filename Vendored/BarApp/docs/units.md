# Units and conversion factors

Every amount in BarApp is stored as an exact decimal value plus a unit
identifier (decision 0004: `Sources/BarCore/Units/UnitCatalog.swift`). The
catalog defines three dimensions, each with a canonical unit every other
unit is measured against:

- **Volume** — canonical unit `ml`
- **Mass** — canonical unit `g`
- **Count** — canonical unit `piece`

Conversion only happens within one dimension; converting across dimensions
returns nothing rather than guessing. Exactness is kept as far as the
definitions allow: where a factor is exact by definition it is stored with
all of its digits, and display rounding happens at the edge of the app, not
in stored values.

## Volume (canonical unit: ml)

| Unit | Factor (ml per unit) | Basis |
| --- | --- | --- |
| `ml` | 1 | canonical; aliases: milliliter, millilitre, cc |
| `cl` | 10 | definition of the centiliter |
| `l` | 1000 | definition of the liter |
| `oz` | 29.5735295625 | **exact**: the US fluid ounce derives from the gallon (231 cubic inches) and the inch (exactly 2.54 cm); 231 in³ = 128 fl oz |
| `tsp` | 4.928921595 | **exact**: one sixth of a US fluid ounce |
| `tbsp` | 14.786764785 | **exact**: three teaspoons |
| `barspoon` | 4.928921595 | convention: a bar spoon holds about a teaspoon; treated as exactly one US teaspoon |
| `dash` | 0.616115199375 | convention: one eighth of a US teaspoon; the bitters-dash convention |
| `drop` | 0.05 | convention: twenty drops to the milliliter, the standard dropper convention |
| `pony` | 29.5735295625 | the historical pony glass: 1 US fluid ounce |
| `wineglass` | 59.147059125 | the historical wineglass of the source books: 2 US fluid ounces |
| `gill` | 118.29411825 | the historical gill: 4 US fluid ounces |
| `cup` | 236.5882365 | US cup: 8 US fluid ounces |
| `pint` | 473.176473 | US liquid pint: 16 US fluid ounces |
| `quart` | 946.352946 | US liquid quart: 32 US fluid ounces |
| `fifth` | 757.0823568 | the pre-metric US liquor bottle: 25.6 US fluid ounces, the bottle size named in the historical sources |
| `bottle` | 750 | the modern standard 750 ml wine/liquor bottle |
| `split` | 187.5 | one quarter of a 750 ml bottle |

The historical bar measures (pony, wineglass, gill) varied in real bars by
city and decade. The factors chosen here are the common US definitions of
the same era as the library sources; they are stated plainly so a reader
can see exactly what an amount means.

## Mass (canonical unit: g)

| Unit | Factor (g per unit) | Basis |
| --- | --- | --- |
| `g` | 1 | canonical |
| `kg` | 1000 | definition of the kilogram |
| `ozm` | 28.349523125 | **exact**: avoirdupois ounce, one sixteenth of a pound |
| `lb` | 453.59237 | **exact**: the avoirdupois pound's defined gram value |

The volume `oz` and the mass `ozm` are deliberately different identifiers.
Recipe sources use "ounce" for both; which one an ingredient amount means
is decided when the recipe data is written, never by guessing at lookup
time.

## Count (canonical unit: piece)

| Unit | Factor | Basis |
| --- | --- | --- |
| `piece` | 1 | canonical; aliases: whole, each, unit |

Counts cover garnishes and fruit: "one piece" of a lemon, expressed as
fractions when a source says a quarter lemon.

## Invariants tested in `Tests/BarCoreTests/UnitTests.swift`

- Factors are positive, finite decimals, parsed with a fixed locale so
  every machine computes identical values.
- Every alias is lowercase and trimmed, because lookup normalizes input
  the same way.
- Every dimension's canonical unit is defined.
- Converting an amount to another unit of the same dimension and back
  returns the original value within a tiny tolerance (decimal arithmetic
  rounds at the 38th significant digit).
- Cross-dimension and unknown-unit conversions return nil.
