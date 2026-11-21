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
/// convention-based (a dash, a drop, a bar spoon) the convention this
/// project documents is stated in `summary` and in `docs/units.md`.
public struct UnitDefinition: Hashable, Sendable {
    /// The stable unit identifier stored in the database.
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
        let ml = decimal("29.5735295625")  // exact: one US fluid ounce
        let tsp = decimal("4.928921595")  // exact: 1/6 US fluid ounce
        let definitions: [UnitDefinition] = [
            // Volume, canonical unit ml.
            UnitDefinition(
                id: "ml",
                dimension: .volume,
                perCanonical: 1,
                aliases: ["milliliter", "millilitre", "cc"],
                summary: "1 ml; the canonical volume unit."
            ),
            UnitDefinition(
                id: "cl",
                dimension: .volume,
                perCanonical: 10,
                aliases: ["centiliter", "centilitre"],
                summary: "1 cl = 10 ml exactly."
            ),
            UnitDefinition(
                id: "l",
                dimension: .volume,
                perCanonical: 1000,
                aliases: ["liter", "litre"],
                summary: "1 l = 1000 ml exactly."
            ),
            UnitDefinition(
                id: "oz",
                dimension: .volume,
                perCanonical: ml,
                aliases: ["ounce", "ounces", "fl oz", "fluid ounce", "us fl oz"],
                summary:
                    "1 US fluid ounce = 29.5735295625 ml exactly "
                    + "(231 cu in per gallon, 128 fl oz per gallon, 1 in = 2.54 cm)."
            ),
            UnitDefinition(
                id: "tsp",
                dimension: .volume,
                perCanonical: tsp,
                aliases: ["teaspoon", "teaspoons"],
                summary:
                    "1 US teaspoon = 4.928921595 ml exactly (1/6 US fluid ounce)."
            ),
            UnitDefinition(
                id: "tbsp",
                dimension: .volume,
                perCanonical: decimal("14.786764785"),
                aliases: ["tablespoon", "tablespoons"],
                summary:
                    "1 US tablespoon = 14.786764785 ml exactly (3 teaspoons)."
            ),
            UnitDefinition(
                id: "barspoon",
                dimension: .volume,
                perCanonical: tsp,
                aliases: ["bar spoon", "barspoon", "b spoon", "barspoonful"],
                summary:
                    "1 bar spoon treated as 1 US teaspoon (4.928921595 ml); "
                    + "the convention this project documents for layered barspoons."
            ),
            UnitDefinition(
                id: "dash",
                dimension: .volume,
                perCanonical: tsp / 8,
                aliases: ["dashes"],
                summary:
                    "1 dash = 1/8 US teaspoon (0.616115199375 ml); "
                    + "the bitters-dash convention."
            ),
            UnitDefinition(
                id: "drop",
                dimension: .volume,
                perCanonical: decimal("0.05"),
                aliases: ["drops"],
                summary:
                    "1 drop = 0.05 ml; 20 drops to the milliliter, "
                    + "the standard dropper convention."
            ),
            UnitDefinition(
                id: "pony",
                dimension: .volume,
                perCanonical: ml,
                aliases: ["ponies"],
                summary: "1 pony = 1 US fluid ounce (29.5735295625 ml)."
            ),
            UnitDefinition(
                id: "wineglass",
                dimension: .volume,
                perCanonical: ml * 2,
                aliases: ["wine glass", "wineglasses"],
                summary: "1 wineglass = 2 US fluid ounces (59.147059125 ml)."
            ),
            UnitDefinition(
                id: "gill",
                dimension: .volume,
                perCanonical: ml * 4,
                aliases: ["gills"],
                summary: "1 gill = 4 US fluid ounces (118.29411825 ml)."
            ),
            UnitDefinition(
                id: "cup",
                dimension: .volume,
                perCanonical: ml * 8,
                aliases: ["cups"],
                summary: "1 US cup = 8 US fluid ounces (236.5882365 ml)."
            ),
            UnitDefinition(
                id: "pint",
                dimension: .volume,
                perCanonical: ml * 16,
                aliases: ["pints"],
                summary: "1 US liquid pint = 16 US fluid ounces (473.176473 ml)."
            ),
            UnitDefinition(
                id: "quart",
                dimension: .volume,
                perCanonical: ml * 32,
                aliases: ["quarts"],
                summary: "1 US liquid quart = 32 US fluid ounces (946.352946 ml)."
            ),
            UnitDefinition(
                id: "fifth",
                dimension: .volume,
                perCanonical: ml * decimal("25.6"),
                aliases: ["fifths"],
                summary:
                    "1 fifth = 25.6 US fluid ounces (757.0823568 ml), "
                    + "the pre-metric liquor bottle of the historical sources."
            ),
            UnitDefinition(
                id: "bottle",
                dimension: .volume,
                perCanonical: 750,
                aliases: ["bottles"],
                summary: "1 bottle = 750 ml, the modern standard wine/liquor bottle."
            ),
            UnitDefinition(
                id: "split",
                dimension: .volume,
                perCanonical: decimal("187.5"),
                aliases: ["splits"],
                summary: "1 split = 187.5 ml, one quarter of a 750 ml bottle."
            ),

            // Mass, canonical unit g.
            UnitDefinition(
                id: "g",
                dimension: .mass,
                perCanonical: 1,
                aliases: ["gram", "grams", "gramme"],
                summary: "1 g; the canonical mass unit."
            ),
            UnitDefinition(
                id: "kg",
                dimension: .mass,
                perCanonical: 1000,
                aliases: ["kilogram", "kilograms", "kilo"],
                summary: "1 kg = 1000 g exactly."
            ),
            UnitDefinition(
                id: "ozm",
                dimension: .mass,
                perCanonical: decimal("28.349523125"),
                aliases: ["ounce weight", "oz wt", "avoirdupois ounce"],
                summary:
                    "1 avoirdupois ounce = 28.349523125 g exactly "
                    + "(1 lb = 453.59237 g, 16 oz to the lb)."
            ),
            UnitDefinition(
                id: "lb",
                dimension: .mass,
                perCanonical: decimal("453.59237"),
                aliases: ["pound", "pounds", "lbm"],
                summary: "1 avoirdupois pound = 453.59237 g exactly."
            ),

            // Count, canonical unit piece.
            UnitDefinition(
                id: "piece",
                dimension: .count,
                perCanonical: 1,
                aliases: ["each", "unit"],
                summary: "1 piece; the canonical count unit for garnishes and fruit."
            ),
            UnitDefinition(
                id: "whole",
                dimension: .count,
                perCanonical: 1,
                aliases: ["piece", "each", "unit"],
                summary: "1 whole; the canonical count unit for garnishes and fruit."
            ),
            UnitDefinition(
                id: "leaves",
                dimension: .count,
                perCanonical: 1,
                aliases: ["leaf", "leaves"],
                summary: "1 leaf; the canonical count unit for herb leaves."
            ),
        ]
        return Dictionary(
            uniqueKeysWithValues: definitions.map { ($0.id, $0) }
        )
    }
}
