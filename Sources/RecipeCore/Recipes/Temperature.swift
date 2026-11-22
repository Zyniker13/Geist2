import Foundation

/// Temperature handling: parsing a temperature from recipe text
/// ("350°F", "180°C", "425 degrees"), converting between Fahrenheit
/// and Celsius, and formatting.
///
/// Temperatures live in step text, not in ingredient lines, so this
/// is a helper the parser and the cook mode both call. The exact
/// conversion (T − 32) × 5/9 is rounded only at display time; storage
/// stays exact.
public enum Temperature {
    public enum Scale: String, Sendable, CaseIterable {
        case fahrenheit = "F"
        case celsius = "C"
    }

    /// A temperature with its scale, exact.
    public struct Value: Hashable, Sendable {
        public let amount: Decimal
        public let scale: Scale

        public init(amount: Decimal, scale: Scale) {
            self.amount = amount
            self.scale = scale
        }
    }

    /// Finds the first temperature in the text ("preheat to 350°F").
    /// Nil when no temperature is present.
    public static func first(in text: String) -> Value? {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        for (index, token) in tokens.enumerated() {
            // The amount may carry its scale ("350°F") or the scale
            // may be the next token ("350 F", "180 C", "180 degrees C").
            // Trailing sentence punctuation stays on the token; the
            // number and scale matchers ignore it.
            let lowered = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if let value = value(from: lowered) {
                return value
            }
            guard isNumberToken(lowered) else { continue }
            guard index + 1 < tokens.count else { continue }
            var scaleWord = tokens[index + 1].lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            // "180 degrees C": the word after "degrees" names the scale.
            if scaleWord == "degrees" || scaleWord == "degree" {
                guard index + 2 < tokens.count else { continue }
                scaleWord = tokens[index + 2].lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)
            }
            guard let next = valueFromScaleWord(scaleWord) else { continue }
            guard
                let amount = Decimal(
                    string: lowered, locale: Locale(identifier: "en_US_POSIX"))
            else { continue }
            return Value(amount: amount, scale: next)
        }
        return nil
    }

    /// "350°f", "180c", "350f" as one token.
    private static func value(from token: String) -> Value? {
        for scale in Scale.allCases {
            let suffix = scale.rawValue.lowercased()
            if token.hasSuffix(suffix) {
                let head = String(
                    token.dropLast(suffix.count)
                        .drop(while: { $0 == "°" || $0 == " " }))
                if let amount = Decimal(
                    string: head, locale: Locale(identifier: "en_US_POSIX"))
                {
                    return Value(amount: amount, scale: scale)
                }
            }
        }
        return nil
    }

    /// A following word that names a scale: "f", "c", "°f", "degrees",
    /// "degrees fahrenheit". "degrees" alone needs the word after it.
    private static func valueFromScaleWord(_ word: String) -> Scale? {
        if word == "f" || word == "°f" { return .fahrenheit }
        if word == "c" || word == "°c" { return .celsius }
        if word == "fahrenheit" { return .fahrenheit }
        if word == "celsius" || word == "centigrade" { return .celsius }
        return nil
    }

    private static func isNumberToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// Converts to the other scale. Exact where the arithmetic is exact;
    /// the 5/9 division is exact Decimal.
    public static func convert(_ value: Value) -> Value {
        switch value.scale {
        case .fahrenheit:
            let celsius = (value.amount - 32) * 5 / 9
            return Value(amount: celsius, scale: .celsius)
        case .celsius:
            let fahrenheit = value.amount * 9 / 5 + 32
            return Value(amount: fahrenheit, scale: .fahrenheit)
        }
    }

    /// Rounds to the nearest five degrees in the target scale — oven
    /// dials are set in fives, so a converted temperature that says
    /// "177°C" would be read as 177 anyway.
    public static func convertedForDisplay(_ value: Value) -> Value {
        let converted = convert(value)
        let fives = (converted.amount / 5)
        var quotient = fives
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        return Value(amount: rounded * 5, scale: converted.scale)
    }

    /// "350°F" / "180°C".
    public static func text(_ value: Value) -> String {
        "\(value.amount)°\(value.scale.rawValue)"
    }
}
