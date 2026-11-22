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

    /// Rounds to the unit's kitchen step; exposed for the conversion
    /// layer, which shares the friendly-amount rule.
    public static func round(_ amount: Decimal, unit: String) -> Decimal {
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

    // MARK: Recipe-level scaling (M2.3)

    /// The factor that turns a recipe's written yield into `target`
    /// servings of the same unit. Nil when the yield is unknown or the
    /// target is not positive.
    public static func factor(
        writtenYield: Decimal?, targetServings: Decimal
    ) throws -> Decimal {
        guard let writtenYield, writtenYield > 0, targetServings > 0 else {
            throw MathError.badFactor
        }
        return targetServings / writtenYield
    }

    /// Scales one ingredient line by `factor` with friendly rounding:
    /// the quantity rounds to the unit's kitchen step, a range scales
    /// both ends, count lines round to whole numbers (eggs to halves),
    /// and unquantified, to-taste and optional flags pass through.
    ///
    /// The original text is not rewritten: the caller renders the scaled
    /// line from the fields.
    public static func scaledLine(
        _ line: IngredientLine, by factor: Decimal, catalog: UnitCatalog = UnitCatalog()
    ) throws -> IngredientLine {
        guard factor > 0 else { throw MathError.badFactor }
        var scaled = line
        scaled.originalText = ""
        guard let quantity = line.quantity else { return scaled }
        let low = round(quantity.amount * factor, unit: line.unitID ?? "")
        scaled.quantity = Quantity(low)
        if let high = line.quantityHigh {
            let highScaled = round(high.amount * factor, unit: line.unitID ?? "")
            scaled.quantityHigh = highScaled > low ? Quantity(highScaled) : nil
        }
        return scaled
    }

    /// Scales every line of every ingredient section.
    public static func scaledSections(
        _ sections: [IngredientSection], by factor: Decimal,
        catalog: UnitCatalog = UnitCatalog()
    ) throws -> [IngredientSection] {
        guard factor > 0 else { throw MathError.badFactor }
        return try sections.map { section in
            IngredientSection(
                name: section.name,
                lines: try section.lines.map {
                    try scaledLine($0, by: factor, catalog: catalog)
                })
        }
    }

    /// Substitutes scaled amounts into step text (M2.3).
    ///
    /// A step that names an ingredient's amount as written ("Stir in 2
    /// cups of the flour") gets the scaled, rounded amount when the step
    /// text contains that amount-and-unit pair verbatim. Numbers the
    /// step does not share with an ingredient line ("simmer for 20
    /// minutes") stay as written.
    public static func stepText(
        _ step: String, lines: [IngredientLine], by factor: Decimal,
        catalog: UnitCatalog = UnitCatalog()
    ) throws -> String {
        guard factor > 0 else { throw MathError.badFactor }
        var result = step
        for line in lines {
            guard let quantity = line.quantity, let unitID = line.unitID else { continue }
            let scaled = try scaledLine(line, by: factor, catalog: catalog)
            guard let scaledQuantity = scaled.quantity else { continue }
            let scaledText = renderAmount(scaledQuantity.amount, unit: unitID, catalog: catalog)
            guard !scaledText.isEmpty else { continue }
            // Recipes write amounts in more forms than the renderer
            // emits ("2 tbsp", "2 tablespoons", "2 T"), so the match
            // is on the number and the unit name in any casing, not
            // on one rendering.
            let patterns = numberUnitPatterns(
                quantity: quantity, unitID: unitID, catalog: catalog)
            for pattern in patterns where result.contains(pattern) {
                result = result.replacingOccurrences(of: pattern, with: scaledText)
            }
        }
        return result
    }

    /// The amount-and-unit forms the step text may contain for one
    /// ingredient line: the written number with every catalog alias of
    /// the unit, case-insensitively distinguishable by the caller.
    private static func numberUnitPatterns(
        quantity: Quantity, unitID: String, catalog: UnitCatalog
    ) -> Set<String> {
        let number = "\(quantity.amount)"
        var patterns: Set<String> = []
        for alias in catalog.definition(matching: unitID)?.aliases ?? [] {
            patterns.insert("\(number) \(alias)")
        }
        patterns.insert("\(number) \(unitID)")
        return patterns
    }

    /// How a Quantity renders in step text: kitchen spelling where the
    /// unit has one, else the decimal.
    private static func renderAmount(
        _ amount: Decimal, unit: String, catalog: UnitCatalog
    ) -> String {
        let fraction = kitchenFraction(of: amount)
        let definition = catalog.definition(matching: unit)
        switch definition?.id {
        case "tbsp": return fraction + " T"
        case "tsp": return fraction + " tsp"
        case "cup": return fraction + " " + kitchenPlural(fraction, "cup", "cups")
        case "lb": return fraction + " " + kitchenPlural(fraction, "lb", "lbs")
        case "ozm": return fraction + " oz"
        case "g": return wholeOrDecimal(amount) + " g"
        case "ml": return wholeOrDecimal(amount) + " ml"
        case "l": return wholeOrDecimal(amount) + " l"
        case "pinch": return fraction + " " + kitchenPlural(fraction, "pinch", "pinches")
        case "clove": return fraction + " " + kitchenPlural(fraction, "clove", "cloves")
        case "stick": return fraction + " " + kitchenPlural(fraction, "stick", "sticks")
        default: return wholeOrDecimal(amount)
        }
    }

    /// The amount as the friendliest kitchen string: whole, or whole
    /// plus a kitchen fraction (halves, thirds, quarters, eighths).
    /// Public: the CLI and the recipe view render scaled amounts with it.
    public static func kitchenFraction(of amount: Decimal) -> String {
        // The integer part, truncated toward zero (not rounded: 0.5 is
        // "1/2", not "1 1/2").
        var truncated = Decimal()
        var source = abs(amount)
        NSDecimalRound(&truncated, &source, 0, .down)
        let sign = amount < 0 ? "-" : ""
        let rounded = sign == "-" ? -truncated : truncated
        let whole = "\(rounded)"
        var remainder = amount - rounded
        if remainder < 0 { remainder = -remainder }
        let eighth = Decimal(1) / 8
        let steps = [
            ("", Decimal(0)), ("1/8", eighth), ("1/4", Decimal(1) / 4),
            ("1/3", Decimal(1) / 3), ("3/8", Decimal(3) / 8),
            ("1/2", Decimal(1) / 2), ("5/8", Decimal(5) / 8),
            ("2/3", Decimal(2) / 3), ("3/4", Decimal(3) / 4),
            ("7/8", Decimal(7) / 8), ("1", Decimal(1)),
        ]
        var best = steps[0]
        var bestDistance = Decimal(string: "999")!
        for candidate in steps {
            let distance = remainder - candidate.1
            let absolute = distance < 0 ? -distance : distance
            if absolute < bestDistance {
                bestDistance = absolute
                best = candidate
            }
        }
        if best.0 == "1" {
            return wholeOrDecimal(rounded + 1)
        }
        if best.0.isEmpty {
            return whole
        }
        if whole == "0" {
            return best.0
        }
        return "\(whole) \(best.0)"
    }

    private static func wholeOrDecimal(_ amount: Decimal) -> String {
        var rounded = Decimal()
        var source = amount
        NSDecimalRound(&rounded, &source, 0, .plain)
        if rounded == amount { return "\(rounded)" }
        var twoDigits = Decimal()
        NSDecimalRound(&twoDigits, &source, 2, .plain)
        return "\(twoDigits)"
    }

    private static func kitchenPlural(_ amount: String, _ one: String, _ many: String) -> String {
        amount == "1" ? one : many
    }
}
