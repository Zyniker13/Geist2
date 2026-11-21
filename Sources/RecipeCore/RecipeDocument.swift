import Foundation

/// One structured ingredient line: what the parser produces (M2) and
/// what the editor edits.
///
/// The original text is kept verbatim so an unparseable line round-trips
/// unchanged and the recipe's source wording is never lost.
public struct IngredientLine: Codable, Hashable, Sendable {
    /// The quantity, or the low end of a range ("2 to 3").
    public var quantity: Quantity?
    /// The high end of a range; nil when the line is not a range.
    public var quantityHigh: Quantity?
    /// The unit's stable identifier ("cup", "g"), nil for count-less
    /// items ("1 onion" has quantity 1 and no unit) and for unquantified
    /// lines ("salt to taste").
    public var unitID: String?
    /// The item: "butter", "chicken thighs", "olive oil".
    public var item: String
    /// Preparation ("finely chopped"), separated from the item.
    public var preparation: String?
    /// A parenthetical or trailing note ("(optional)", "room temperature").
    public var note: String?
    /// The line says "optional".
    public var optional: Bool
    /// The line says "to taste" or similar: no amount, add to preference.
    public var toTaste: Bool
    /// The line as written in the source.
    public var originalText: String

    public init(
        quantity: Quantity? = nil,
        quantityHigh: Quantity? = nil,
        unitID: String? = nil,
        item: String,
        preparation: String? = nil,
        note: String? = nil,
        optional: Bool = false,
        toTaste: Bool = false,
        originalText: String = ""
    ) {
        self.quantity = quantity
        self.quantityHigh = quantityHigh
        self.unitID = unitID
        self.item = item
        self.preparation = preparation
        self.note = note
        self.optional = optional
        self.toTaste = toTaste
        self.originalText = originalText
    }
}

/// An ingredient quantity: an exact decimal amount, or a range's endpoint.
///
/// Fractions are stored exactly ("1/2" is 0.5); the original spelling is
/// kept in `IngredientLine.originalText`.
public struct Quantity: Codable, Hashable, Sendable {
    /// The amount, exact.
    public var amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }
}

/// One step of a recipe: text, and optional timers the step mentions.
public struct Step: Codable, Hashable, Sendable {
    /// The instruction text. Scaled amounts are substituted at display
    /// time from the ingredient lines; the stored text is as written.
    public var text: String
    /// Timers detected in or added to the step ("simmer for 20 minutes").
    public var timers: [Duration]

    public init(text: String, timers: [Duration] = []) {
        self.text = text
        self.timers = timers
    }
}

/// A section of steps ("For the dressing:") or of ingredients.
public struct Section: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// A duration with a unit the app can run as a timer.
public struct Duration: Codable, Hashable, Sendable {
    /// Total seconds; minutes and hours are stored as-is in the text.
    public var seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public static func minutes(_ value: Int) -> Duration {
        Duration(seconds: value * 60)
    }

    public static func hours(_ value: Int) -> Duration {
        Duration(seconds: value * 3600)
    }

    /// ISO 8601-like display: "20m", "1h 30m".
    public var display: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
