import Foundation

/// Whole-recipe unit conversion (M2.3): show the recipe in metric or in
/// US units.
///
/// The conversion works line by line through the unit catalog:
///
/// - volume converts exactly within itself (cup → ml);
/// - mass converts exactly within itself (lb → g);
/// - a volume line whose ingredient is in the density table converts to
///   grams; a mass line converts to grams and, where the table knows the
///   ingredient, also shows the volume in parentheses;
/// - count units and lines without a quantity pass through unchanged;
/// - temperatures in step text convert with Temperature.
///
/// Conversion is one-way per call ("to metric" or "to US"), never a
/// round trip on the document: the stored recipe stays as written and
/// the display converts. This mirrors AmountDisplay's rule that storage
/// keeps the source spelling.
public enum RecipeConversion {
    /// The system a recipe is shown in.
    public enum System: Sendable, Equatable {
        case metric
        case us
    }

    /// One converted line as the recipe view renders it.
    public struct ConvertedLine: Hashable, Sendable {
        public let line: IngredientLine
        /// Where the line could not convert (count units, unknown
        /// ingredients), the amount as written passes through and this
        /// says so.
        public let converted: Bool
    }

    /// Converts a recipe's ingredient sections to `system`.
    public static func sections(
        _ sections: [IngredientSection], to system: System,
        catalog: UnitCatalog = UnitCatalog()
    ) -> [ConvertedLine] {
        sections.map { section in
            ConvertedSection(
                name: section.name,
                lines: section.lines.map { line in convert(line, to: system, catalog: catalog) }
            )
        }.flatMap(\.lines)
    }

    private struct ConvertedSection {
        let name: String
        let lines: [ConvertedLine]
    }

    /// Converts one line. The returned line keeps item, preparation,
    /// note, optional and to-taste; only quantity and unit change.
    public static func convert(
        _ line: IngredientLine, to system: System,
        catalog: UnitCatalog = UnitCatalog()
    ) -> ConvertedLine {
        guard let quantity = line.quantity, let unitID = line.unitID,
            let definition = catalog.definition(matching: unitID)
        else {
            return ConvertedLine(line: line, converted: false)
        }

        switch (system, definition.dimension) {
        case (.metric, .volume):
            return converted(
                line, amount: quantity.amount * definition.perCanonical,
                unit: definition.dimension.canonicalUnitId,
                high: line.quantityHigh.map { $0.amount * definition.perCanonical },
                catalog: catalog)
        case (.metric, .mass):
            return converted(
                line, amount: quantity.amount * definition.perCanonical,
                unit: definition.dimension.canonicalUnitId,
                high: line.quantityHigh.map { $0.amount * definition.perCanonical },
                catalog: catalog)
        case (.metric, .count):
            return ConvertedLine(line: line, converted: false)
        case (.us, .volume):
            return toUS(line, definition: definition, catalog: catalog)
        case (.us, .mass):
            // Weight in US units; where the density table knows the
            // ingredient, the friendly unit is the volume ("227 g" of
            // butter is "1 cup"). The volume form wins because it is
            // how US recipes are written.
            if let cup = IngredientDensity.volume(
                grams: definition.perCanonical * quantity.amount,
                targetUnitID: "cup", item: line.item)
            {
                var volumeLine = line
                volumeLine.quantity = Quantity(RecipeMath.round(cup, unit: "cup"))
                volumeLine.quantityHigh = nil
                volumeLine.unitID = "cup"
                return ConvertedLine(line: volumeLine, converted: true)
            }
            return converted(
                line, amount: quantity.amount * definition.perCanonical,
                unit: "ozm",
                high: line.quantityHigh.map { $0.amount * definition.perCanonical },
                catalog: catalog)
        case (.us, .count):
            return ConvertedLine(line: line, converted: false)
        }
    }

    private static func toUS(
        _ line: IngredientLine, definition: UnitDefinition, catalog: UnitCatalog
    ) -> ConvertedLine {
        // Metric volume to US kitchen units: cups over a quarter, then
        // tablespoons and teaspoons. Milliliters and liters become cups
        // when they are cup-sized, tablespoons below that.
        guard let amount = line.quantity?.amount else {
            return ConvertedLine(line: line, converted: false)
        }
        let ml = amount * definition.perCanonical
        let cupMl = catalog.definition(matching: "cup")!.perCanonical
        if ml >= cupMl / 4 {
            let cups = ml / cupMl
            var convertedLine = line
            convertedLine.quantity = Quantity(RecipeMath.round(cups, unit: "cup"))
            convertedLine.quantityHigh = nil
            convertedLine.unitID = "cup"
            return ConvertedLine(line: convertedLine, converted: true)
        }
        let tbspMl = catalog.definition(matching: "tbsp")!.perCanonical
        if ml >= tbspMl / 2 {
            let tbsps = ml / tbspMl
            var convertedLine = line
            convertedLine.quantity = Quantity(RecipeMath.round(tbsps, unit: "tbsp"))
            convertedLine.quantityHigh = nil
            convertedLine.unitID = "tbsp"
            return ConvertedLine(line: convertedLine, converted: true)
        }
        let tspMl = catalog.definition(matching: "tsp")!.perCanonical
        let teaspoons = ml / tspMl
        var convertedLine = line
        convertedLine.quantity = Quantity(RecipeMath.round(teaspoons, unit: "tsp"))
        convertedLine.quantityHigh = nil
        convertedLine.unitID = "tsp"
        return ConvertedLine(line: convertedLine, converted: true)
    }

    private static func converted(
        _ line: IngredientLine, amount: Decimal, unit: String, high: Decimal?,
        catalog: UnitCatalog
    ) -> ConvertedLine {
        var result = line
        result.quantity = Quantity(round2(amount))
        result.quantityHigh = high.map { Quantity(round2($0)) }
        result.unitID = unit
        return ConvertedLine(line: result, converted: true)
    }

    /// Two fraction digits: a displayed conversion, not a stored value.
    private static func round2(_ value: Decimal) -> Decimal {
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded
    }
}
