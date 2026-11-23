import Foundation
import RecipeCore

/// Converts an extracted recipe block into a RecipeDocument, with the
/// M2 parser handling every ingredient and step-embedded amount.
public enum RecipeAssembler {
    /// Strips inline markup tags and wrapping whitespace from a
    /// recipe field, so decoded HTML never reaches a document.
    public static func sanitize(_ text: String) -> String {
        var result = text
        for tag in [
            "<i>", "</i>", "<b>", "</b>", "<em>", "</em>",
            "<strong>", "</strong>", "<span>", "</span>",
            "<small>", "</small>", "<sup>", "</sup>", "<sub>", "</sub>",
            "<u>", "</u>", "<code>", "</code>",
        ] {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a document from a JSON-LD recipe. Nil when the block has
    /// neither a title nor a single usable line.
    public static func document(
        from recipe: JSONLDRecipe, now epochSeconds: Int64, id: String
    ) -> RecipeDocument? {
        let title = titleCase(sanitize(recipe.name ?? ""))
        let ingredients = recipe.ingredients.map { IngredientParser.parse(sanitize($0)) }
        let sections = stepSections(recipe)
        guard !title.isEmpty || !ingredients.isEmpty || !sections.isEmpty else {
            return nil
        }
        var document = RecipeDocument(
            id: id, title: title, createdAt: epochSeconds, modifiedAt: epochSeconds)
        document.summary = recipe.description ?? ""
        applyYield(recipe.recipeYield, to: &document)
        document.prepTime = duration(recipe.prepTime)
        document.cookTime = duration(recipe.cookTime)
        document.totalTime = duration(recipe.totalTime)
        document.ingredientSections = groupedSections(ingredients, from: recipe)
        document.stepSections = sections
        document.tags = tags(recipe.keywords)
        document.categories = recipe.recipeCategory.map { [$0] } ?? []
        document.cuisine = recipe.recipeCuisine
        document.attribution = recipe.author
        document.sourceURL = trimmedURL(recipe.sourceURL)
        document.nutrition = recipe.nutrition
        document.notes = notes(from: recipe)
        return document
    }

    /// Step sections in order: HowToSection groups keep their names,
    /// then any bare instructions go into a final unnamed section. A
    /// recipe with sections but no bare instructions keeps only the
    /// named sections; one with only bare instructions gets the
    /// single unnamed section.
    static func stepSections(_ recipe: JSONLDRecipe) -> [StepSection] {
        var sections: [StepSection] = []
        for section in recipe.instructionSections {
            var steps: [Step] = []
            for text in section.steps {
                let clean = sanitize(text)
                steps.append(Step(text: clean, timers: timedSteps(from: clean)))
            }
            sections.append(StepSection(name: section.name, steps: steps))
        }
        var bare: [Step] = []
        for text in recipe.instructions {
            let clean = sanitize(text)
            bare.append(Step(text: clean, timers: timedSteps(from: clean)))
        }
        if !bare.isEmpty {
            sections.append(StepSection(name: "", steps: bare))
        }
        return sections
    }

    /// "Bake for 45 minutes" carries a timer; ISO durations inside step
    /// text become Step.timers for cook mode.
    static func timedSteps(from text: String) -> [Duration] {
        var timers: [Duration] = []
        var index = text.startIndex
        while let range = text.range(of: "PT", range: index..<text.endIndex) {
            var cursor = range.upperBound
            var token = "PT"
            while cursor < text.endIndex,
                text[cursor].isNumber || text[cursor] == "." || "YMWDHS".contains(text[cursor])
            {
                token.append(text[cursor])
                cursor = text.index(after: cursor)
            }
            if let seconds = ISODuration.parse(token), seconds > 0 {
                timers.append(Duration(seconds: seconds))
            }
            index = cursor
        }
        // Plain-language durations: "45 minutes", "1 1/2 hours".
        timers.append(contentsOf: proseTimers(in: text))
        return timers
    }

    private static func proseTimers(in text: String) -> [Duration] {
        var timers: [Duration] = []
        let lowered = text.lowercased()
        let words = lowered.split(separator: " ")
        for (index, word) in words.enumerated() {
            guard let amount = numberOrFraction(word) else { continue }
            guard index + 1 < words.count else { continue }
            let unit = words[index + 1]
            var seconds: Int?
            if unit.hasPrefix("hour") || unit.hasPrefix("hrs") {
                seconds = Int((Decimal(amount) * 3600 as NSDecimalNumber).doubleValue)
            } else if unit.hasPrefix("minute") || unit.hasPrefix("min") {
                seconds = Int(amount)
            }
            if let seconds, seconds > 0, seconds <= 86_400 {
                timers.append(Duration(seconds: seconds))
            }
        }
        return timers
    }

    private static func numberOrFraction(_ word: Substring) -> Double? {
        let text = String(word)
        if let value = Double(text) { return value }
        // "1 1/2" is two tokens; a bare "1/2" is one.
        let parts = text.split(separator: "/")
        if parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]),
            bottom != 0
        {
            return top / bottom
        }
        return nil
    }

    /// Yield text → amount and unit, in the shapes the corpus holds:
    /// "4", "4 servings", "24 cookies", "2 dozen cookies", "Makes 6
    /// bowls", "Makes 24 to 30 meatballs", "makes 12 large scones",
    /// "Makes 3 cups, easy to double", "Makes 4 servings of 2 cups
    /// each", "3/4 cup", and prose like "This makes enough for six
    /// hungry people." The first number after a makes/serves/yield
    /// trigger — digits or a spelled-out small number — is the amount;
    /// the noun phrase after it is the unit. Later numbers (ranges,
    /// per-serving sizes), filler words, and adjectives are not unit
    /// words; a comma or period ends the unit.
    static func applyYield(_ text: String?, to document: inout RecipeDocument) {
        guard let text else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let phrase = scanYieldPhrase(trimmed) {
            document.yieldAmount = phrase.amount
            document.yieldUnit = phrase.unit
            return
        }
        // Leading amount: "24 cookies", "4", "3 cups to 4 cups",
        // "about 4 servings", "a dozen mugs" without the "a".
        let cleaned = trimmed
            .replacingOccurrences(of: "about ", with: "", options: [.anchored, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        var words = cleaned.split(separator: " ")
        var amountText = ""
        if let first = words.first, let amount = leadingAmount(in: String(first)) {
            amountText = String(first)
            // Mixed number: "1 1/2" spans two tokens.
            if words.count > 1, words[1].contains("/") {
                let combined = amountText + "-" + words[1]
                if leadingAmount(in: combined) != nil {
                    words.removeFirst(2)
                    amountText = combined
                }
            }
        }
        if !amountText.isEmpty, let amount = leadingAmount(in: amountText) {
            document.yieldAmount = amount
            let rest = words.dropFirst(amountText.split(separator: " ").count)
            // Drop stray numbers and filler words ("12 to 15 rolls"
            // → "rolls") but keep spelled counts ("2 dozen cookies").
            let unitWords = rest.filter { word in
                let bare = word.lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                return strictDecimal(bare) == nil && !yieldFillerWords.contains(bare)
            }
            let unit = unitWords.joined(separator: " ").lowercased()
            document.yieldUnit = unit.isEmpty ? "servings" : unit
        } else {
            // No amount anywhere: keep the text as the unit so the
            // value is not silently lost ("One 9-inch pie").
            document.yieldUnit = trimmed
        }
    }

    private static let yieldFillerWords: Set<String> = [
        "a", "an", "the", "to", "and", "or", "about", "around",
        "roughly", "of", "each", "per", "total", "recipe", "large",
        "small", "medium", "generous", "&middot;", "&bull;", "·", "•",
    ]

    private static let yieldNumberWords: [String: Decimal] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "dozen": 12,
    ]

    /// "Makes 6 bowls", "Serves 4", "makes 12 large scones": the
    /// number after a trigger is the amount and the noun phrase after
    /// it is the unit. Nil when the text has no trigger or the trigger
    /// is followed by no number.
    static func scanYieldPhrase(_ text: String) -> (amount: Decimal, unit: String)? {
        let triggers: Set<String> = [
            "serving", "servings", "serves", "served",
            "make", "makes", "made", "yield", "yields", "yielded",
        ]
        let lowered = text.lowercased()
        let tokens = lowered.split(separator: " ").map(String.init)
        func stripped(_ token: String) -> String {
            token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        }
        func endsUnit(_ token: String) -> Bool {
            token.last.map { ".,;:!?".contains($0) } ?? false
        }
        guard
            let trigger = tokens.firstIndex(where: {
                stripped($0).isEmpty == false && triggers.contains(stripped($0))
            })
        else { return nil }
        var amount: Decimal?
        var cursor = trigger + 1
        while cursor < tokens.count, amount == nil {
            let token = stripped(tokens[cursor])
            if let value = strictDecimal(token) {
                amount = value
            } else if let value = yieldNumberWords[token] {
                amount = value
            } else {
                cursor += 1
            }
        }
        guard let amount else { return nil }
        cursor += 1
        var unitTokens: [String] = []
        var collecting = true
        while cursor < tokens.count, collecting {
            let original = tokens[cursor]
            let token = stripped(original)
            if endsUnit(original) {
                // A comma or period closes the unit, but the word
                // before it still counts ("cups," → "cups").
                if !token.isEmpty { unitTokens.append(token) }
                collecting = false
            } else if strictDecimal(token) != nil || yieldNumberWords[token] != nil {
                // A later number ("24 to 30", "3 cups, easy") ends
                // the unit; it is not a unit word itself.
                collecting = false
            } else if yieldFillerWords.contains(token) {
                // Filler words are skipped without ending the unit;
                // a range connector before another number ("24 to 30
                // meatballs") belongs to the amount, so skip it too.
                if token == "to", cursor + 1 < tokens.count,
                    strictDecimal(stripped(tokens[cursor + 1])) != nil
                {
                    cursor += 2
                } else {
                    cursor += 1
                }
            } else {
                unitTokens.append(token)
                cursor += 1
            }
        }
        let unit = unitTokens.joined(separator: " ")
        return (amount, unit.isEmpty ? "servings" : unit)
    }

    /// Foundation's Decimal(string:) prefix-parses ("3/4" → 3,
    /// "12x" → 12) and even accepts words ("enough" → 0), so a token
    /// must be entirely numeric — a plain number or a "3-4" range —
    /// before it is parsed.
    private static func strictDecimal(_ token: String) -> Decimal? {
        let allowed = CharacterSet(charactersIn: "0123456789.-–—")
        guard !token.isEmpty, token.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return Decimal(string: token)
    }

    private static func isPlainNumber(_ text: String) -> Bool {
        !text.isEmpty
            && text.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// A bare fraction "3/4"; nil for any other shape.
    private static func fraction(in token: String) -> Decimal? {
        let parts = token.split(separator: "/")
        guard parts.count == 2,
            isPlainNumber(String(parts[0])), isPlainNumber(String(parts[1])),
            let top = Decimal(string: String(parts[0])),
            let bottom = Decimal(string: String(parts[1])), bottom != 0
        else { return nil }
        return top / bottom
    }

    /// The leading amount of a token: "4", "1.5", "3-4" (ranges take
    /// the low end), "3/4" (a fraction), "1-1/2" (a mixed number).
    static func leadingAmount(in token: String) -> Decimal? {
        if let value = fraction(in: token) { return value }
        for separator in ["-", "–", "—"] {
            if token.contains(separator) {
                let pieces = token.split(separator: Character(separator))
                if pieces.count == 2 {
                    if let whole = strictDecimal(String(pieces[0])),
                        let part = fraction(in: String(pieces[1]))
                    {
                        return whole + part
                    }
                    if let low = strictDecimal(String(pieces[0])) {
                        return low
                    }
                }
            }
        }
        return strictDecimal(token)
    }

    /// Words after a number keep the recipe's words for the yield
    /// unit ("6 bowls"); a bare "Serves 6" is servings.
    private static func titleCase(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // ALL CAPS source names become title case; mixed-case names
        // are kept as written.
        let letters = trimmed.filter { $0.isLetter }
        let isAllCaps = !letters.isEmpty && letters == letters.uppercased()
        guard isAllCaps, trimmed.count > 3 else { return trimmed }
        return trimmed
            .split(separator: " ")
            .map { word -> String in
                let lowered = word.lowercased()
                if smallWord.contains(lowered), word != trimmed.split(separator: " ").first {
                    return lowered
                }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static let smallWord: Set<String> = [
        "a", "an", "and", "at", "but", "for", "in", "of", "on", "or", "the", "with",
    ]

    /// Strips whitespace and rejects non-URLs.
    static func trimmedURL(_ text: String?) -> String? {
        guard var url = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !url.isEmpty
        else { return nil }
        if url.hasPrefix("//") { url = "https:" + url }
        guard url.contains(".") else { return nil }
        return url
    }

    static func duration(_ iso: String?) -> RecipeCore.Duration? {
        guard let iso, let seconds = ISODuration.parse(iso), seconds > 0 else {
            return nil
        }
        return RecipeCore.Duration(seconds: seconds)
    }

    /// Lines with section-like headers ("For the dressing:") become
    /// separate sections; a leading markdown bullet or digit bullet is
    /// stripped first.
    static func groupedSections(
        _ lines: [IngredientLine], from recipe: JSONLDRecipe
    ) -> [IngredientSection] {
        var sections: [IngredientSection] = [IngredientSection(name: "", lines: [])]
        for line in lines {
            sections[sections.count - 1].lines.append(line)
        }
        return sections.count == 1 && sections[0].lines.isEmpty ? [] : sections
    }

    static func tags(_ keywords: String?) -> [String] {
        guard let keywords, !keywords.isEmpty else { return [] }
        let separator: Character = keywords.contains(",") ? "," : " "
        return
            keywords
            .split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// recipeNotes and recipeTips become the document's notes, joined
    /// in page order.
    static func notes(from recipe: JSONLDRecipe) -> String {
        [recipe.recipeNotes, recipe.recipeTips]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
