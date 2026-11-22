import Foundation
import RecipeCore

/// Converts an extracted recipe block into a RecipeDocument, with the
/// M2 parser handling every ingredient and step-embedded amount.
public enum RecipeAssembler {
    /// Builds a document from a JSON-LD recipe. Nil when the block has
    /// neither a title nor a single usable line.
    public static func document(
        from recipe: JSONLDRecipe, now epochSeconds: Int64, id: String
    ) -> RecipeDocument? {
        let title = recipe.name ?? ""
        let ingredients = recipe.ingredients.map { IngredientParser.parse($0) }
        let steps = instructionSteps(recipe)
        guard !title.isEmpty || !ingredients.isEmpty || !steps.isEmpty else {
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
        document.stepSections = [StepSection(name: "", steps: steps)]
        document.tags = tags(recipe.keywords)
        document.categories = recipe.recipeCategory.map { [$0] } ?? []
        document.cuisine = recipe.recipeCuisine
        document.attribution = recipe.author
        document.nutrition = recipe.nutrition
        return document
    }

    /// Steps in order: HowToSection groups first (they carry their own
    /// order in the JSON), then bare instructions.
    static func instructionSteps(_ recipe: JSONLDRecipe) -> [Step] {
        var steps: [Step] = []
        if !recipe.instructionSections.isEmpty {
            for section in recipe.instructionSections {
                for text in section.steps {
                    steps.append(Step(text: text, timers: timedSteps(from: text)))
                }
            }
        }
        for text in recipe.instructions {
            steps.append(Step(text: text, timers: timedSteps(from: text)))
        }
        return steps
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

    /// "4 servings", "2 dozen", "1 9-inch pie" → amount and unit.
    static func applyYield(_ text: String?, to document: inout RecipeDocument) {
        guard let text else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // "Serves 4" and "serves four".
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("serves ") || lowered.hasPrefix("makes ") {
            let rest = trimmed.drop { !$0.isNumber && $0 != "-" }
            if let amount = Decimal(string: String(rest)) {
                document.yieldAmount = amount
                document.yieldUnit = "servings"
                return
            }
        }
        // Leading number: "24 cookies", "1 9-inch pie".
        var words = trimmed.split(separator: " ")
        var amountText = ""
        if let first = words.first,
            let value = Decimal(string: String(first))
        {
            amountText = String(first)
            words.removeFirst()
            // Mixed number: "1 1/2" spans two tokens.
            if let second = words.first, second.contains("/") {
                let combined = amountText + "-" + second
                if let value = Decimal(string: combined) {
                    amountText = String(second)
                    _ = value
                    document.yieldAmount = Decimal(string: "1.5")
                    words.removeFirst()
                }
            }
        }
        if !amountText.isEmpty, let amount = Decimal(string: amountText) {
            document.yieldAmount = amount
            document.yieldUnit =
                words.joined(separator: " ").isEmpty
                ? "servings" : words.joined(separator: " ")
        } else {
            document.yieldUnit = trimmed
        }
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
}
