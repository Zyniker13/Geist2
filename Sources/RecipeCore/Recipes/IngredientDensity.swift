import Foundation

/// The density table: converting between volume and weight for common
/// ingredients (M2.2).
///
/// A cup of flour is not a cup of honey. The table states, for common
/// ingredients, how many grams one milliliter (or equivalently one
/// cubic centimeter) of the ingredient weighs. Factors come from
/// standard kitchen references and are stated per ingredient; where
/// references disagree the middle value is taken and rounded to three
/// decimals — the display rounds to two anyway.
///
/// Conversion is exact Decimal arithmetic; the table is data. An
/// ingredient the table does not list has no conversion, and callers
/// show the amount as written instead of inventing one.
public enum IngredientDensity {
    /// Grams per milliliter for one ingredient.
    public struct Factor: Hashable, Sendable {
        public let gramsPerMl: Decimal

        /// Takes the factor as text: Decimal float literals carry a
        /// Double's binary tail (0.53 becomes
        /// 0.5300000000000001024), and the conversions here are
        /// compared exactly.
        public init(_ gramsPerMl: String) {
            self.gramsPerMl = Decimal(
                string: gramsPerMl, locale: Locale(identifier: "en_US_POSIX"))!
        }
    }

    /// The table. Keys are folded item names ("all-purpose flour");
    /// lookup folds the item the same way, so case and spacing do not
    /// matter. A word like "chopped" is not part of the key.
    public static let gramsPerMl: [String: Factor] = [
        "water": Factor("1.0"),
        "milk": Factor("1.03"),
        "buttermilk": Factor("1.03"),
        "heavy cream": Factor("0.994"),
        "half-and-half": Factor("1.02"),
        "yogurt": Factor("1.03"),
        "sour cream": Factor("1.02"),
        "olive oil": Factor("0.912"),
        "vegetable oil": Factor("0.915"),
        "canola oil": Factor("0.915"),
        "coconut oil": Factor("0.92"),
        "sesame oil": Factor("0.92"),
        "honey": Factor("1.42"),
        "maple syrup": Factor("1.33"),
        "corn syrup": Factor("1.38"),
        "molasses": Factor("1.45"),
        "all-purpose flour": Factor("0.53"),
        "bread flour": Factor("0.55"),
        "whole wheat flour": Factor("0.54"),
        "cake flour": Factor("0.48"),
        "almond flour": Factor("0.42"),
        "cornmeal": Factor("0.69"),
        "granulated sugar": Factor("0.85"),
        "brown sugar": Factor("0.9"),
        "powdered sugar": Factor("0.56"),
        "cocoa powder": Factor("0.41"),
        "baking powder": Factor("0.9"),
        "baking soda": Factor("0.92"),
        "salt": Factor("1.2"),
        "kosher salt": Factor("0.72"),
        "sea salt": Factor("1.2"),
        "butter": Factor("0.96"),
        "shortening": Factor("0.92"),
        "milk chocolate chips": Factor("0.68"),
        "chocolate chips": Factor("0.68"),
        "rolled oats": Factor("0.38"),
        "rice": Factor("0.85"),
        "white rice": Factor("0.85"),
        "brown rice": Factor("0.88"),
        "quinoa": Factor("0.75"),
        "lentils": Factor("0.85"),
        "chickpeas": Factor("0.87"),
        "black beans": Factor("0.87"),
        "corn kernels": Factor("0.72"),
        "walnuts": Factor("0.55"),
        "pecans": Factor("0.53"),
        "almonds": Factor("0.47"),
        "peanut butter": Factor("1.1"),
        "mayonnaise": Factor("0.91"),
        "mustard": Factor("1.05"),
        "soy sauce": Factor("1.1"),
        "vinegar": Factor("1.0"),
        "apple cider vinegar": Factor("1.0"),
        "lemon juice": Factor("1.0"),
        "orange juice": Factor("1.04"),
        "tomato sauce": Factor("1.02"),
        "tomato paste": Factor("1.12"),
        "chicken broth": Factor("1.0"),
        "chicken stock": Factor("1.0"),
        "vegetable stock": Factor("1.0"),
        "beef broth": Factor("1.0"),
        "whole milk": Factor("1.03"),
        "skim milk": Factor("1.03"),
    ]

    /// Folds an item name the way the table's keys are written.
    public static func key(for item: String) -> String {
        let words = item.lowercased()
            .split(separator: " ")
            .filter { !isDescriptor(String($0)) }
        return words.joined(separator: " ")
    }

    private static func isDescriptor(_ word: String) -> Bool {
        [
            "fresh", "frozen", "dried", "whole", "large", "medium", "small",
            "chopped", "grated", "shredded", "packed", "sifted", "melted",
            "softened", "toasted", "raw", "cooked", "finely", "roughly",
            "coarsely", "thinly", "a", "of", "the",
        ].contains(word)
    }

    /// Looks up a factor by the line's item text. Nil when the table has
    /// no entry; the caller then leaves the amount alone.
    public static func factor(for item: String) -> Factor? {
        gramsPerMl[key(for: item)]
            ?? gramsPerMl[lastWords(item, 2)]
            ?? gramsPerMl[lastWords(item, 1)]
    }

    private static func lastWords(_ item: String, _ count: Int) -> String {
        let words = key(for: item).split(separator: " ")
        guard words.count > count else { return key(for: item) }
        return words.suffix(count).joined(separator: " ")
    }

    /// Converts a volume amount to grams, nil when the ingredient is not
    /// in the table or the unit is not a volume unit.
    public static func grams(
        amount: Decimal, unitID: String, item: String,
        in catalog: UnitCatalog = UnitCatalog()
    ) -> Decimal? {
        guard let factor = factor(for: item) else { return nil }
        guard let definition = catalog.definition(matching: unitID),
            definition.dimension == .volume
        else { return nil }
        let ml = amount * definition.perCanonical
        return ml * factor.gramsPerMl
    }

    /// Converts a weight amount to the named volume unit, nil when the
    /// ingredient is not in the table or the target is not volume.
    public static func volume(
        grams: Decimal, targetUnitID: String, item: String,
        in catalog: UnitCatalog = UnitCatalog()
    ) -> Decimal? {
        guard let factor = factor(for: item) else { return nil }
        guard let definition = catalog.definition(matching: targetUnitID),
            definition.dimension == .volume
        else { return nil }
        let ml = grams / factor.gramsPerMl
        return ml / definition.perCanonical
    }
}
