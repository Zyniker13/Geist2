import Foundation

/// Scaling a recipe's amounts by a factor, with friendly rounding.
///
/// The rounding steps here are documented decisions, checked by hand in
/// `RecipeMathTests`:
///
/// - Volume and mass units round to kitchen-friendly fractions of
///   themselves (cups to quarters, teaspoons to halves, grams to fives),
///   count units round to whole counts, eggs to halves;
/// - any nonzero result keeps at least one step of its unit, so a
///   scaled-down pinch never disappears.
///
/// Adapted from the sibling home bar project's `RecipeMath` (commit
/// d8dbede, Apache-2.0/MIT): the rounding steps are the kitchen's.
public enum RecipeMath {
    /// One recipe ingredient as the scaler sees it: the amount for the
    /// recipe's current yield and its unit.
    public struct Ingredient: Sendable, Equatable {
        public let label: String
        public let amount: Decimal
        public let unit: String

        public init(label: String, amount: Decimal, unit: String) {
            self.label = label
            self.amount = amount
            self.unit = unit
        }
    }

    public enum MathError: Error, Equatable {
        case badFactor
    }

    public struct ScaledIngredient: Sendable, Equatable {
        public let label: String
        public let amount: Decimal
        public let unit: String
    }

    /// Scales the recipe by `factor`, rounding per unit.
    public static func scale(
        _ ingredients: [Ingredient], by factor: Decimal
    ) throws -> [ScaledIngredient] {
        guard factor > 0 else { throw MathError.badFactor }
        return ingredients.map { ingredient in
            ScaledIngredient(
                label: ingredient.label,
                amount: round(ingredient.amount * factor, unit: ingredient.unit),
                unit: ingredient.unit)
        }
    }

    // MARK: Helpers

    /// The documented rounding step for a unit, nil for unlisted units
    /// (those round to two decimals instead of snapping).
    private static func step(for unit: String) -> Decimal? {
        switch unit {
        case "cup", "oz": return Decimal(string: "0.25")
        case "tbsp": return Decimal(string: "0.5")
        case "tsp", "lb", "stick": return Decimal(string: "0.5")
        case "clove", "piece", "sprig", "bunch", "can", "pinch": return 1
        case "g": return 5
        case "ml", "l", "kg": return Decimal(string: "0.5")
        default: return nil
        }
    }

    /// Rounds to the unit's step, keeping at least one step when the input
    /// was nonzero. Unlisted units round to two decimals.
    private static func round(_ amount: Decimal, unit: String) -> Decimal {
        let zero = Decimal(0)
        if amount == zero {
            return zero
        }
        guard let step = step(for: unit) else {
            return decimalRounded(amount * 100, scale: 0) / 100
        }
        let quotient = decimalRounded(amount / step, scale: 0)
        let result = quotient * step
        return result == zero ? step : result
    }

    /// Plain rounding of a decimal to a fixed number of fraction digits.
    private static func decimalRounded(_ value: Decimal, scale: Int) -> Decimal {
        var rounded = Decimal(0)
        var source = value
        NSDecimalRound(&rounded, &source, scale, .plain)
        return rounded
    }
}
