import Foundation

/// The dimensions amounts can belong to. The canonical unit of each
/// dimension is what every other unit's factor is expressed against:
/// milliliters for volume, grams for mass, and one piece for count.
public enum UnitDimension: String, Sendable, CaseIterable {
    case volume
    case mass
    case count

    /// The identifier of the dimension's canonical unit.
    public var canonicalUnitId: String {
        switch self {
        case .volume: return "ml"
        case .mass: return "g"
        case .count: return "piece"
        }
    }
}

/// One unit of measure with its conversion factor.
///
/// Factors are exact decimal values. Where a factor can be exact by
/// definition it is: US customary volume units derive from the gallon
/// (231 cubic inches) and the international inch (exactly 2.54 cm), and
/// avoirdupois mass from the pound (exactly 453.59237 g). Where a unit is
/// convention-based (a pinch, a clove, a stick of butter) the convention
/// this project documents is stated in `summary` and in `docs/units.md`.
///
/// Adapted from the sibling home bar project's unit catalog (commit
/// d8dbede, Apache-2.0/MIT): volume units rechecked for kitchen use,
/// bar-only units (dash, drop, pony, wineglass, gill, fifth, bottle,
/// split) removed, kitchen units added (decisions 0003 and 0005).
public struct UnitDefinition: Hashable, Sendable {
    /// The stable unit identifier stored in recipe documents.
    public let id: String
    public let dimension: UnitDimension
    /// How many canonical units one of this unit is worth.
    public let perCanonical: Decimal
    /// Other spellings the identifier is known by in recipe data.
    public let aliases: Set<String>
    /// One-line statement of the factor and its basis.
    public let summary: String

    public init(
        id: String,
        dimension: UnitDimension,
        perCanonical: Decimal,
        aliases: Set<String> = [],
        summary: String
    ) {
        self.id = id
        self.dimension = dimension
        self.perCanonical = perCanonical
        self.aliases = aliases
        self.summary = summary
    }
}

/// The catalog of units with documented conversion factors, and the
/// conversions between units of the same dimension.
public struct UnitCatalog: Sendable {
    public init() {}

    /// All defined units, keyed by identifier.
    public var definitionsById: [String: UnitDefinition] {
        UnitCatalog.makeDefinitions()
    }

    /// Looks up a unit by its identifier or one of its known aliases.
    public func definition(matching identifier: String) -> UnitDefinition? {
        let lowered = normalized(identifier)
        let byId = definitionsById
        if let exact = byId[lowered] {
            return exact
        }
        return byId.values.first { unit in
            unit.aliases.contains(lowered)
        }
    }

    /// Converts an amount between two units of the same dimension. Returns
    /// nil for unknown units or a dimension mismatch.
    public func convert(
        _ value: Decimal,
        from sourceId: String,
        to targetId: String
    ) -> Decimal? {
        guard
            let source = definition(matching: sourceId),
            let target = definition(matching: targetId),
            source.dimension == target.dimension
        else {
            return nil
        }
        let canonical = value * source.perCanonical
        return canonical / target.perCanonical
    }

    private func normalized(_ identifier: String) -> String {
        identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses a decimal literal with a fixed locale so the factors are
    /// identical on every machine regardless of the ambient locale.
    private static func decimal(_ literal: String) -> Decimal {
        Decimal(
            string: literal,
            locale: Locale(identifier: "en_US_POSIX")
        )!
    }

    private static func makeDefinitions() -> [String: UnitDefinition] {
        let oz = decimal("29.5735295625")  // exact: one US fluid ounce
        let tsp = decimal("4.928921595")  // exact: 1/6 US fluid ounce
        let definitions: [UnitDefinition] = [
            // Volume, canonical unit ml.
            UnitDefinition(
                id: "ml",
                dimension: .volume,
                perCanonical: 1,
                aliases: ["milliliter", "millilitre", "milliliters", "millilitres", "cc"],
                summary: "1 ml; the canonical volume unit."
            ),
            UnitDefinition(
                id: "cl",
                dimension: .volume,
                perCanonical: 10,
                aliases: ["centiliter", "centilitre", "centiliters"],
                summary: "1 cl = 10 ml exactly."
            ),
            UnitDefinition(
                id: "l",
                dimension: .volume,
                perCanonical: 1000,
                aliases: ["liter", "litre", "liters", "litres"],
                summary: "1 l = 1000 ml exactly."
            ),
            UnitDefinition(
                id: "oz",
                dimension: .volume,
                perCanonical: oz,
                aliases: ["fluid ounce", "fluid ounces", "fl oz", "us fl oz"],
                summary:
                    "1 US fluid ounce = 29.5735295625 ml exactly "
                    + "(231 cu in per gallon, 128 fl oz per gallon, 1 in = 2.54 cm)."
            ),
            UnitDefinition(
                id: "tsp",
                dimension: .volume,
                perCanonical: tsp,
                aliases: ["teaspoon", "teaspoons", "t.", "tsps"],
                summary:
                    "1 US teaspoon = 4.928921595 ml exactly (1/6 US fluid ounce)."
            ),
            UnitDefinition(
                id: "tbsp",
                dimension: .volume,
                perCanonical: decimal("14.786764785"),
                aliases: ["tablespoon", "tablespoons", "T", "tbsps"],
                summary:
                    "1 US tablespoon = 14.786764785 ml exactly (3 teaspoons)."
            ),
            UnitDefinition(
                id: "cup",
                dimension: .volume,
                perCanonical: decimal("14.786764785") * 16,
                aliases: ["cups"],
                summary: "1 US cup = 8 US fluid ounces (236.5882365 ml)."
            ),
            UnitDefinition(
                id: "pint",
                dimension: .volume,
                perCanonical: decimal("14.786764785") * 32,
                aliases: ["pints", "pt"],
                summary: "1 US liquid pint = 16 US fluid ounces (473.176473 ml)."
            ),
            UnitDefinition(
                id: "quart",
                dimension: .volume,
                perCanonical: decimal("14.786764785") * 64,
                aliases: ["quarts", "qt"],
                summary: "1 US liquid quart = 32 US fluid ounces (946.352946 ml)."
            ),
            UnitDefinition(
                id: "gallon",
                dimension: .volume,
                perCanonical: decimal("14.786764785") * 256,
                aliases: ["gallons", "gal"],
                summary: "1 US gallon = 128 US fluid ounces (3785.411784 ml)."
            ),
            // Mass, canonical unit g.
            UnitDefinition(
                id: "g",
                dimension: .mass,
                perCanonical: 1,
                aliases: ["gram", "grams", "gramme", "grammes"],
                summary: "1 g; the canonical mass unit."
            ),
            UnitDefinition(
                id: "kg",
                dimension: .mass,
                perCanonical: 1000,
                aliases: ["kilogram", "kilograms", "kilo", "kilos"],
                summary: "1 kg = 1000 g exactly."
            ),
            UnitDefinition(
                id: "ozm",
                dimension: .mass,
                perCanonical: decimal("28.349523125"),
                aliases: ["ounce weight", "oz wt", "avoirdupois ounce", "oz."],
                summary:
                    "1 avoirdupois ounce = 28.349523125 g exactly "
                    + "(1 lb = 453.59237 g, 16 oz to the lb)."
            ),
            UnitDefinition(
                id: "lb",
                dimension: .mass,
                perCanonical: decimal("453.59237"),
                aliases: ["pound", "pounds", "lbs", "lbm"],
                summary: "1 avoirdupois pound = 453.59237 g exactly."
            ),
            // Count, canonical unit piece.
            UnitDefinition(
                id: "piece",
                dimension: .count,
                perCanonical: 1,
                aliases: ["each", "unit", "units"],
                summary: "1 piece; the canonical count unit."
            ),
            UnitDefinition(
                id: "clove",
                dimension: .count,
                perCanonical: 1,
                aliases: ["cloves"],
                summary: "1 clove of garlic; the count unit for garlic."
            ),
            UnitDefinition(
                id: "stick",
                dimension: .count,
                perCanonical: 1,
                aliases: ["sticks"],
                summary:
                    "1 stick of butter; the kitchen convention treats a stick as "
                    + "a count and states the weight in the note when it matters "
                    + "(one US stick = 1/2 cup = 113 g)."
            ),
            UnitDefinition(
                id: "sprig",
                dimension: .count,
                perCanonical: 1,
                aliases: ["sprigs"],
                summary: "1 sprig; the count unit for fresh herbs."
            ),
            UnitDefinition(
                id: "bunch",
                dimension: .count,
                perCanonical: 1,
                aliases: ["bunches"],
                summary: "1 bunch; the count unit for leafy vegetables."
            ),
            UnitDefinition(
                id: "can",
                dimension: .count,
                perCanonical: 1,
                aliases: ["cans"],
                summary:
                    "1 can; the count unit for canned goods, with the size stated "
                    + "in the note when it matters (a 14 oz can, a 28 oz can)."
            ),
            UnitDefinition(
                id: "pinch",
                dimension: .count,
                perCanonical: 1,
                aliases: ["pinches", "dash of salt"],
                summary:
                    "1 pinch; the count unit for salt and spices, the amount "
                    + "picked between thumb and forefinger. Dimensionless by "
                    + "convention: converting a pinch to volume would be false "
                    + "precision."
            ),
        ]
        return Dictionary(
            uniqueKeysWithValues: definitions.map { ($0.id, $0) }
        )
    }
}
