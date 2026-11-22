import Foundation

/// The ingredient line parser (M2.1).
///
/// Turns a line of recipe text into an `IngredientLine`: quantities
/// (integers, decimals, fractions, unicode fractions, ranges, "a", "half"),
/// units with plurals and abbreviations, sizes ("large"), item,
/// preparation ("finely chopped"), notes in parentheses, "to taste",
/// optional lines and section headers.
///
/// The line that fails to parse is not an error: it round-trips verbatim
/// as an item-only line, so nothing a recipe says is ever lost.
public enum IngredientParser {
    // MARK: Public surface

    /// True when the line is an ingredient section header
    /// ("For the marinade:", "Dressing").
    ///
    /// A header is either a "For the X" phrase (with or without a colon)
    /// or a short name that is not a count item (two words or fewer, no
    /// leading quantity, no known unit).
    public static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix(":") {
            let head = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            // A header names a thing; a line with an amount is not one.
            return quantityAndUnit(in: head) == nil
        }
        // "For the X", without a colon.
        if trimmed.lowercased().hasPrefix("for "),
            trimmed.split(separator: " ").count <= 4
        {
            return true
        }
        // A bare name ("Dressing", "Crust"): short, no quantity, no unit.
        let words = trimmed.split(separator: " ")
        if words.count <= 2, quantityAndUnit(in: trimmed) == nil {
            return true
        }
        return false
    }

    /// Parses one ingredient line.
    public static func parse(_ text: String, catalog: UnitCatalog = UnitCatalog())
        -> IngredientLine
    {
        var line = IngredientLine(item: "", originalText: text)
        var rest = text.trimmingCharacters(in: .whitespaces)

        // Trailing "(optional)" and the optional flag.
        (rest, line.optional) = extractOptional(from: rest)

        // Trailing "to taste": no amount, add to preference.
        if let (without, range) = extractToTaste(from: rest) {
            rest = without
            line.toTaste = range
        }

        // Space-separated mixed numbers ("1 1/2 cups") must glue before
        // quantityAndUnit runs: it would stop after "1" and leave "1/2
        // cups flour" as the item.
        let tokens = tokenize(rest)
        if tokens.count >= 3, plainInteger(tokens[0]) != nil,
            simpleFraction(tokens[1]) != nil || unicodeFraction(tokens[1]) != nil
        {
            rest = "\(tokens[0])-\(tokens[1]) " + tokens[2...].joined(separator: " ")
        }

        // Quantity (with optional range and unit), then the remainder.
        if let (quantity, high, unit, remainder) = quantityAndUnit(in: rest, catalog: catalog) {
            line.quantity = quantity
            line.quantityHigh = high
            line.unitID = unit?.id
            rest = remainder
        }

        // What remains splits into item, preparation, note.
        let (item, preparation, note) = splitItem(from: rest)
        line.item = item
        line.preparation = preparation
        line.note = joinNotes(note, with: line.note)
        return line
    }

    // MARK: Quantity and unit

    /// Exact Decimal values for the common fractions, shared by the
    /// unicode table, string fractions and the bare-ounce rule below.
    static let half = Decimal(1) / 2
    static let third = Decimal(1) / 3
    static let twoThirds = Decimal(2) / 3
    static let quarter = Decimal(1) / 4
    static let threeQuarters = Decimal(3) / 4
    static let eighth = Decimal(1) / 8

    /// Finds the leading quantity (possibly a range) and unit in `text`.
    /// Returns nil when the line does not start with a quantity.
    static func quantityAndUnit(
        in text: String, catalog: UnitCatalog = UnitCatalog()
    ) -> (
        Quantity?, Quantity?, UnitDefinition?, String
    )? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }

        var index = 0
        var first = parseAmount(tokens[index])
        guard first != nil || isArticle(tokens[index]) || isHalfWord(tokens[index]) else {
            return nil
        }
        // An article ("a", "an") counts as one when a unit follows
        // ("a pinch") or when the whole line is short enough to be a
        // bare count item ("an onion", "a lemon", "an apple, cored").
        // At the start of a longer free-text line it is just the letter A
        // ("A handful of whatever you like").
        if first == nil, isArticle(tokens[index]) {
            let nextHasUnit =
                index + 1 < tokens.count
                && catalog.definition(matching: tokens[index + 1]) != nil
            let shortLine = tokens.count <= 3
            guard nextHasUnit || shortLine else { return nil }
            first = Quantity(1)
            index += 1
        } else if first == nil, isHalfWord(tokens[index]) {
            first = Quantity(Decimal(string: "0.5")!)
            index += 1
        } else {
            index += 1
        }

        // Range: "to", "-", "–" followed by another amount.
        var high: Quantity? = nil
        if index < tokens.count, isRangeConnector(tokens[index]) {
            let save = index
            index += 1
            if index < tokens.count, let second = parseAmount(tokens[index]) {
                high = second
                index += 1
            } else {
                index = save
            }
        }

        // Unit: match the following token(s) against the catalog. The
        // number of tokens consumed distinguishes a spelled-out fluid
        // ounce ("fl oz", "fluid ounce", two tokens) from a bare ounce
        // abbreviation ("oz", one token).
        var unit: UnitDefinition? = nil
        var unitTokenCount = 0
        if index < tokens.count {
            // Two-word units first ("fl oz", "fluid ounce").
            if index + 1 < tokens.count,
                let two = catalog.definition(matching: "\(tokens[index]) \(tokens[index + 1])")
            {
                unit = two
                index += 2
                unitTokenCount = 2
            } else if let one = catalog.definition(matching: tokens[index]) {
                unit = one
                index += 1
                unitTokenCount = 1
            }
        }

        // A bare ounce abbreviation is weight (decision 0007): package
        // sizes are weight unless marked "fl oz". After a two-word match
        // the spelling is a fluid ounce by construction and stays one.
        if unit?.id == "oz", unitTokenCount == 1,
            bareOunceAbbreviation(tokens[index - 1])
        {
            unit = catalog.definition(matching: "ozm")
        }

        let remainder = tokens[index...].joined(separator: " ")
        // A bare article with no unit and no remainder is still a quantity.
        return (first, high, unit, remainder)
    }

    /// Whether the token is a bare ounce abbreviation as recipes write it
    /// ("oz", "ozs", "ounce", "ounces"), not a fluid-ounce spelling.
    static func bareOunceAbbreviation(_ token: String) -> Bool {
        let lowered = token.lowercased()
        return ["oz", "ozs", "ounce", "ounces"].contains(lowered)
    }

    // MARK: Tokenization and amounts

    private static func tokenize(_ text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Parses one token as an amount: "2", "1.5", "3/4", "½", "2½",
    /// "1-1/2", "1 1/2" is two tokens handled by the caller gluing below.
    static func parseAmount(_ token: String) -> Quantity? {
        let mixed = mixedNumber(token)
        if let mixed { return mixed }
        if let fraction = simpleFraction(token) { return fraction }
        if let unicode = unicodeFraction(token) { return unicode }
        if let decimal = decimalNumber(token) { return decimal }
        return nil
    }

    /// Mixed numbers: "2½", "1-1/2", "1½".
    private static func mixedNumber(_ token: String) -> Quantity? {
        for (index, character) in token.enumerated() {
            guard character.isNumber else { continue }
            let head = String(token.prefix(index))
            let tail = String(token.dropFirst(index))
            guard !head.isEmpty,
                let whole = Decimal(string: head),
                let part = simpleFraction(tail) ?? unicodeFraction(tail)
            else { continue }
            return Quantity(whole + part.amount)
        }
        return nil
    }

    /// "3/4" as one token; "1/2" via mixedNumber's head/tail split.
    private static func simpleFraction(_ token: String) -> Quantity? {
        guard token.contains("/") else { return nil }
        let parts = token.split(separator: "/")
        guard parts.count == 2, let numerator = Decimal(string: String(parts[0])),
            let denominator = Decimal(string: String(parts[1])),
            denominator != 0
        else { return nil }
        return Quantity(numerator / denominator)
    }

    /// Unicode fractions: ½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞.
    private static func unicodeFraction(_ token: String) -> Quantity? {
        guard token.count == 1, let character = token.first,
            let value = unicodeFractionValues[character]
        else { return nil }
        return Quantity(value)
    }

    static let unicodeFractionValues: [Character: Decimal] = [
        "½": half,
        "⅓": third,
        "⅔": twoThirds,
        "¼": quarter,
        "¾": threeQuarters,
        "⅕": Decimal(1) / 5,
        "⅖": Decimal(2) / 5,
        "⅗": Decimal(3) / 5,
        "⅘": Decimal(4) / 5,
        "⅙": Decimal(1) / 6,
        "⅚": Decimal(5) / 6,
        "⅛": eighth,
        "⅜": Decimal(3) / 8,
        "⅝": Decimal(5) / 8,
        "⅞": Decimal(7) / 8,
    ]

    /// Plain decimals and integers: "2", "1.5", "0.25".
    private static func decimalNumber(_ token: String) -> Quantity? {
        guard !token.isEmpty else { return nil }
        let characters = Array(token)
        guard characters.allSatisfy({ $0.isNumber || $0 == "." }),
            token.contains(where: \.isNumber),
            token.filter({ $0 == "." }).count <= 1,
            !token.hasPrefix("."),
            !token.hasSuffix(".")
        else { return nil }
        return Quantity(Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))!)
    }

    /// A token that is exactly a plain integer (no fraction, no dot).
    private static func plainInteger(_ token: String) -> Decimal? {
        guard !token.isEmpty, token.allSatisfy(\.isNumber) else { return nil }
        return Decimal(string: token)
    }

    private static func isArticle(_ token: String) -> Bool {
        ["a", "an"].contains(token.lowercased())
    }

    private static func isHalfWord(_ token: String) -> Bool {
        ["half", "one-half"].contains(token.lowercased())
    }

    private static func isRangeConnector(_ token: String) -> Bool {
        ["to", "-", "–", "—"].contains(token.lowercased())
    }

    // MARK: Trailing modifiers

    private static func extractOptional(from text: String) -> (String, Bool) {
        // "(optional)" ends with ")"; compare on the closing-stripped text.
        var candidate = text
        var hadParen = false
        if candidate.hasSuffix(")") {
            candidate = String(candidate.dropLast())
            hadParen = true
        }
        guard candidate.lowercased().hasSuffix("optional") else { return (text, false) }
        candidate = String(candidate.dropLast("optional".count))
            .trimmingCharacters(in: .whitespaces)
        if hadParen, candidate.hasSuffix("(") {
            candidate = String(candidate.dropLast())
        }
        let without =
            candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespaces)
        return (without, true)
    }

    private static func extractToTaste(from text: String) -> (String, Bool)? {
        let lowered = text.lowercased()
        guard lowered.hasSuffix("to taste") else { return nil }
        var without = String(text.dropLast("to taste".count))
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespaces)
        if without.isEmpty { without = text }
        return (without, true)
    }

    // MARK: Item, preparation, note

    /// Splits the remainder into item, preparation and note. The note is
    /// any parenthetical anywhere in the remainder; the preparation is a
    /// trailing phrase of comma-separated words that match known
    /// preparation verbs ("finely chopped", "grated", "to serve").
    private static func splitItem(from text: String) -> (String, String?, String?) {
        var rest = text
        var note: String? = nil

        // Every parenthetical becomes the note; usually there is one.
        let parentheses = parentheticals(in: rest)
        if let first = parentheses.first {
            note = first
            rest = rest.replacingOccurrences(
                of: "(\(first))", with: ""
            ).trimmingCharacters(in: .whitespaces)
        }

        // Trailing ", finely chopped" becomes the preparation.
        var preparation: String? = nil
        if let comma = rest.lastIndex(of: ",") {
            let candidate = String(rest[rest.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
            if isPreparationPhrase(candidate) {
                preparation = candidate
                rest = String(rest[..<comma]).trimmingCharacters(in: .whitespaces)
            }
        }

        return (rest, preparation, note)
    }

    /// The contents of every balanced parenthetical group, in order.
    static func parentheticals(in text: String) -> [String] {
        var found: [String] = []
        var depth = 0
        var current = ""
        for character in text {
            if character == "(" {
                depth += 1
                if depth == 1 { current = "" }
                continue
            } else if character == ")" {
                if depth == 1 {
                    found.append(current)
                    depth = 0
                    continue
                } else if depth > 1 {
                    current.append(character)
                    depth -= 1
                    continue
                }
            }
            if depth > 0 { current.append(character) }
        }
        return found
    }

    /// Whether the phrase reads as preparation: the phrase (or its last
    /// word) is in the known preparation set.
    static func isPreparationPhrase(_ phrase: String) -> Bool {
        let lowered = phrase.lowercased()
        let words = lowered.split(separator: " ").map(String.init)
        guard let last = words.last else { return false }
        let endings: Set<String> = [
            "chopped", "diced", "minced", "grated", "shredded", "sliced",
            "melted", "softened", "beaten", "separated",
            "peeled", "halved", "quartered", "crushed", "ground", "torn",
            "packed", "rinsed", "drained", "divided", "trimmed", "toasted",
            "pitted", "smashed", "sifted", "dissolved", "dusted", "blotted",
            "juiced", "zested", "tempered", "bloomed", "cubed", "julienned",
        ]
        let phrases: Set<String> = [
            "at room temperature", "room temperature", "to serve",
            "cut into wedges", "rinsed and drained", "peeled and deveined",
            "stems removed", "torn into pieces", "plus more for garnish",
            "seeded and diced", "zested and juiced", "trimmed and halved",
            "cut into cubes", "cut into florets", "torn into bite-size pieces",
        ]
        if phrases.contains(lowered) { return true }
        if endings.contains(last) { return true }
        if words.count == 2, endings.contains(words.joined(separator: " ")) { return true }
        return false
    }

    private static func joinNotes(_ note: String?, with existing: String?) -> String? {
        switch (note, existing) {
        case (nil, nil): return nil
        case (let only?, nil): return only
        case (nil, let only?): return only
        case (let first?, let second?):
            return first == second ? first : "\(first); \(second)"
        }
    }
}
