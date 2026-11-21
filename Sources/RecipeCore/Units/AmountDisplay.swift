import Foundation

/// Display formatting for ingredient amounts.
///
/// The storage layer keeps amounts as the strings the recipes were written
/// with: plain decimals ("0.5"), fractions ("1/2"), or mixed numbers
/// ("1 1/2"), with a unit id beside them. The detail screen can show them
/// as written or converted to the dimension's canonical metric unit. This
/// type holds that conversion so package tests cover it.
public enum AmountDisplay {
    /// Parses an amount string in the shapes recipe data uses. Returns nil
    /// for anything else (including a zero denominator).
    public static func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A mixed number is a whole part, a space, and a fraction.
        var whole = Decimal.zero
        var rest = trimmed
        if trimmed.contains(" ") {
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2,
                let wholePart = Decimal(
                    string: String(parts[0]),
                    locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            whole = wholePart
            rest = String(parts[1])
        }

        if rest.contains("/") {
            let halves = rest.split(separator: "/", omittingEmptySubsequences: true)
            guard halves.count == 2,
                let numerator = Int(halves[0]),
                let denominator = Int(halves[1]),
                denominator != 0
            else { return nil }
            let fraction = Decimal(numerator) / Decimal(denominator)
            return whole + fraction
        }

        return Decimal(string: rest, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Converts one amount to the canonical metric unit of its dimension
    /// (ml for volume, g for mass), rounded to two fraction digits for
    /// display. Count units, amounts the parser cannot read, and units the
    /// catalog does not know return nil, and the caller shows the amount as
    /// written instead.
    public static func metricText(
        amount: String, unit: String, in catalog: UnitCatalog = UnitCatalog()
    ) -> String? {
        guard
            let definition = catalog.definition(matching: unit),
            definition.dimension != .count,
            let value = parseAmount(amount),
            let canonical = catalog.convert(
                value, from: definition.id, to: definition.dimension.canonicalUnitId)
        else { return nil }

        // Two fraction digits is enough for a displayed amount; the stored
        // value stays exact.
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false)
        let rounded = NSDecimalNumber(decimal: canonical)
            .rounding(accordingToBehavior: handler).decimalValue
        return "\(rounded) \(definition.dimension.canonicalUnitId)"
    }
}
