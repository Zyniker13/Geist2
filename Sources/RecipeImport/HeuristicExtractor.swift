import Foundation
import RecipeCore

/// The last-resort extractor: pages with no JSON-LD and no microdata.
/// It reads the visible text and looks for recipe-shaped patterns —
/// a title near the top, an ingredient list with quantities, numbered
/// or timed steps. Every field it produces is marked unconfident; the
/// app shows the result for review rather than trusting it.
enum HeuristicExtractor {
    /// A line of visible text with its rough position in the page.
    private struct Line {
        var text: String
        /// 0-based position among the page's text lines.
        var position: Int
    }

    /// The pieces a page's visible text can be cut into.
    private struct Candidates {
        var title: String?
        var summary: String?
        var ingredients: [String]
        var steps: [String]
        var sections: [(name: String, steps: [String])]
        var yield: String?
        var times: [String: String]
        var images: [String]
    }

    /// Words a heading must contain to be treated as a list heading.
    private static let ingredientHeadings: Set<String> = [
        "ingredient", "ingredients", "what you need", "you'll need",
        "you will need", "shopping list", "materials",
    ]
    private static let stepHeadings: Set<String> = [
        "instruction", "instructions", "direction", "directions",
        "method", "preparation", "steps", "how to make", "how to cook",
        "procedure", "assembly",
    ]
    private static let timeHeadings: [String: String] = [
        "prep time": "prep", "preparation time": "prep", "prepare time": "prep",
        "cook time": "cook", "cooking time": "cook", "bake time": "cook",
        "chill time": "cook", "rest time": "cook",
        "total time": "total", "time required": "total",
    ]

    static func extract(from html: String) -> JSONLDRecipe? {
        let candidates = scan(html)
        guard let title = candidates.title, !title.isEmpty,
            !candidates.ingredients.isEmpty || !candidates.steps.isEmpty
        else {
            return nil
        }
        var recipe = JSONLDRecipe()
        recipe.name = title
        recipe.description = candidates.summary
        recipe.recipeYield = candidates.yield
        for (kind, iso) in candidates.times {
            switch kind {
            case "prep": recipe.prepTime = iso
            case "cook": recipe.cookTime = iso
            default: recipe.totalTime = iso
            }
        }
        recipe.ingredients = candidates.ingredients
        recipe.instructions = candidates.steps
        recipe.instructionSections = candidates.sections.map {
            (name: $0.name, steps: $0.steps)
        }
        recipe.images = candidates.images
        return recipe
    }

    // MARK: Scanning

    private static func scan(_ html: String) -> Candidates {
        let lines = visibleLines(html)
        var candidates = Candidates(
            title: nil, summary: nil, ingredients: [], steps: [],
            sections: [], yield: nil, times: [:], images: [])
        candidates.images = imageUrls(html)

        var mode: Mode = .preamble
        var currentSection = ""
        var sectionSteps: [String] = []
        var sawIngredientHeading = false
        var sawStepHeading = false

        for line in lines {
            let text = line.text
            let lowered = text.lowercased()

            // An inline list: "Ingredients: 1 box pasta, 2 cups
            // cheese" opens the ingredient zone and carries its list
            // on the same line.
            if lowered.hasPrefix("ingredient"), lowered.contains(":"),
                mode == .preamble
            {
                mode = .ingredients
                sawIngredientHeading = true
                if let colon = text.firstIndex(of: ":") {
                    let rest = text[text.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty {
                        for piece in splitInlineList(rest) {
                            candidates.ingredients.append(piece)
                        }
                    }
                }
                continue
            }

            if let heading = headingKind(lowered) {
                flushSection(into: &candidates, name: &currentSection, steps: &sectionSteps)
                var handled = true
                switch heading {
                case .ingredients:
                    mode = .ingredients
                    sawIngredientHeading = true
                case .steps:
                    mode = .steps
                    sawStepHeading = true
                case .section:
                    // A short heading after the ingredient zone begins
                    // a named step section; before any list starts it
                    // is just page furniture or the title, so it is
                    // processed like any other line.
                    if mode == .steps || mode == .ingredients {
                        mode = .steps
                        currentSection = text
                    } else {
                        handled = false
                    }
                case .time(let kind, let value):
                    storeTime(kind, value, into: &candidates.times)
                }
                if handled { continue }
            }

            // A "time" line can appear anywhere ("Prep time: 20 min").
            if let (kind, value) = timeDeclaration(lowered, original: text) {
                storeTime(kind, value, into: &candidates.times)
                if timeDeclarationOnly(lowered) { continue }
            }

            if let yield = yieldDeclaration(lowered, original: text) {
                candidates.yield = yield
                if yieldOnly(lowered) { continue }
            }

            switch mode {
            case .preamble:
                if candidates.title == nil, isTitleLike(text, position: line.position) {
                    candidates.title = text
                } else if candidates.title != nil, candidates.summary == nil,
                    text.count >= 30, !looksLikeYield(lowered),
                    !looksLikeIngredient(text)
                {
                    candidates.summary = text
                }
            case .ingredients:
                let cleaned = cleanBullet(text)
                guard !cleaned.isEmpty else { continue }
                if looksLikeStep(cleaned) {
                    // A step wandered into the ingredient zone; the
                    // mode flips when steps clearly start.
                    mode = .steps
                    sawStepHeading = true
                    sectionSteps.append(cleaned)
                } else {
                    candidates.ingredients.append(cleaned)
                }
            case .steps:
                let cleaned = cleanBullet(text)
                guard !cleaned.isEmpty else { continue }
                if looksLikeIngredient(cleaned), !looksLikeStep(cleaned) {
                    // A stray ingredient among steps: keep it with the
                    // ingredients rather than inventing a step.
                    candidates.ingredients.append(cleaned)
                } else if currentSection.isEmpty {
                    candidates.steps.append(cleaned)
                } else {
                    sectionSteps.append(cleaned)
                }
            }
        }
        flushSection(into: &candidates, name: &currentSection, steps: &sectionSteps)
        _ = sawIngredientHeading || sawStepHeading
        return candidates
    }

    private enum Mode { case preamble, ingredients, steps }

    /// Collects an open named section into the recipe.
    private static func flushSection(
        into candidates: inout Candidates,
        name: inout String, steps: inout [String]
    ) {
        if !name.isEmpty, !steps.isEmpty {
            candidates.sections.append((name: name, steps: steps))
        }
        name = ""
        steps = []
    }

    // MARK: Heading classification

    private enum Heading {
        case ingredients
        case steps
        case section
        case time(kind: String, value: String)
    }

    private static func headingKind(_ lowered: String) -> Heading? {
        let trimmed = cleanBullet(lowered)
        if trimmed.count <= 40 {
            if ingredientHeadings.contains(trimmed) { return .ingredients }
            if stepHeadings.contains(trimmed) { return .steps }
        }
        for (phrase, kind) in timeHeadings {
            if trimmed.hasPrefix(phrase), let value = timeValue(in: trimmed, after: phrase) {
                return .time(kind: kind, value: value)
            }
        }
        if trimmed.count <= 40, !trimmed.isEmpty,
            trimmed.last!.isLetter,
            !trimmed.hasSuffix("."),
            // A line that starts with a bullet or list number is
            // content, whatever follows: check the raw line, since
            // cleanBullet has already stripped the marker here.
            !looksLikeBulletList(lowered),
            !looksLikeIngredient(trimmed)
        {
            return .section
        }
        return nil
    }

    // MARK: Title, yield and times

    /// A leading list marker: bullets, numbers with separators, or
    /// "Step 3:" markers.
    private static func looksLikeBulletList(_ text: String) -> Bool {
        var characters = Substring(text)
        while let first = characters.first,
            "-•·*​●".contains(first)
        {
            characters = characters.dropFirst()
        }
        characters = characters.drop(while: { $0 == " " })
        if let first = characters.first, first.isNumber {
            let after = characters.drop(while: { $0.isNumber })
            if let marker = after.first, marker == "." || marker == ")" {
                return true
            }
        }
        let lowered = characters.prefix(6).lowercased()
        return lowered.hasPrefix("step ")
    }

    private static func isTitleLike(_ text: String, position: Int) -> Bool {
        guard text.count >= 3, text.count <= 80, position <= 25 else { return false }
        let lowered = text.lowercased()
        if looksLikeYield(lowered) { return false }
        // Headings and page furniture are short and rarely end with a
        // period; sentences do.
        if text.hasSuffix(".") && text.contains(", ") { return false }
        return true
    }

    private static func looksLikeYield(_ lowered: String) -> Bool {
        let patterns = [
            "serving", "servings", "serves", "makes", "yield", "yields",
        ]
        return patterns.contains { lowered.contains($0) }
    }

    private static func yieldDeclaration(_ lowered: String, original: String) -> String? {
        guard looksLikeYield(lowered), lowered.count <= 60 else { return nil }
        // Keep the original casing but drop a leading label.
        var text = original
        for label in ["yield:", "yields:", "makes:", "serves:"] {
            if lowered.hasPrefix(label) {
                text = String(original.dropFirst(label.count))
                break
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func yieldOnly(_ lowered: String) -> Bool {
        let words = lowered.split(separator: " ").count
        return words <= 5
    }

    private static func timeDeclaration(_ lowered: String, original: String) -> (String, String)? {
        for (phrase, kind) in timeHeadings {
            if lowered.hasPrefix(phrase),
                let value = timeValue(in: lowered, after: phrase)
            {
                var text = original
                let index = original.index(original.startIndex, offsetBy: phrase.count)
                if index <= original.endIndex {
                    text = String(original[index...])
                        .trimmingCharacters(in: .whitespaces)
                    if text.hasPrefix(":") { text.removeFirst() }
                    text = text.trimmingCharacters(in: .whitespaces)
                }
                return (kind, text)
            }
        }
        return nil
    }

    private static func timeDeclarationOnly(_ lowered: String) -> Bool {
        for (phrase, _) in timeHeadings {
            if lowered.hasPrefix(phrase) {
                let rest = lowered.dropFirst(phrase.count)
                    .trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix(":") {
                    let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return true }
                }
            }
        }
        return false
    }

    /// A duration inside a heading line, converted to ISO 8601.
    private static func timeValue(in text: String, after phrase: String) -> String? {
        let rest = text.dropFirst(phrase.count).drop(while: { $0 == ":" || $0 == " " })
        let words = Array(rest.split(separator: " ").prefix(6))
        var hours: Int?
        var minutes: Int?
        var pending: Double?
        for word in words {
            let number = word.prefix { $0.isNumber || $0 == "." }
            if let amount = Double(number), amount > 0 {
                if pending != nil {
                    pending = amount
                }  // two numbers, no unit between: keep the last
                else {
                    pending = amount
                }
                let glued = word.dropFirst(number.count)
                    .drop(while: { $0 == " " })
                    .drop(while: { $0 == "s" })
                    .lowercased()
                if applyUnit(glued, amount, to: &hours, into: &minutes) {
                    pending = nil
                }
                continue
            }
            // A bare word: a unit for the pending number, or noise.
            let unit = word.drop(while: { $0 == "s" }).lowercased()
            if let amount = pending, applyUnit(unit, amount, to: &hours, into: &minutes) {
                pending = nil
            } else if hours != nil || minutes != nil {
                break
            }
        }
        guard hours != nil || minutes != nil else { return nil }
        var iso = "PT"
        if let hours { iso += "\(hours)H" }
        if let minutes { iso += "\(minutes)M" }
        return iso == "PT" ? nil : iso
    }

    /// Splits an inline ingredient list on commas, but only when
    /// every piece stands alone as an ingredient with a quantity;
    /// otherwise the line stays whole ("salt and pepper, to taste").
    private static func splitInlineList(_ rest: String) -> [String] {
        let pieces = rest.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard pieces.count > 1,
            pieces.allSatisfy({ IngredientParser.parse($0).quantity != nil })
        else {
            return [rest]
        }
        return pieces
    }

    /// Applies a unit word to an amount; true when it was a time unit.
    private static func applyUnit(
        _ unit: String, _ amount: Double,
        to hours: inout Int?, into minutes: inout Int?
    ) -> Bool {
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
            hours = Int(amount)
            return true
        }
        if unit.hasPrefix("min") {
            minutes = Int(amount)
            return true
        }
        if unit.hasPrefix("sec") {
            minutes = Int(max(1, (amount / 60).rounded()))
            return true
        }
        return false
    }

    private static func storeTime(
        _ kind: String, _ iso: String, into times: inout [String: String]
    ) {
        guard times[kind] == nil else { return }
        times[kind] = iso
    }

    // MARK: Lines and cleaning

    /// The page's visible text, one entry per non-empty line, with
    /// script, style and head content removed. Chunks come in true
    /// document order: an element's direct text before its children.
    private static func visibleLines(_ html: String) -> [Line] {
        let root = HTMLTree.parse(stripHead(html))
        var lines: [Line] = []
        collectLines(from: root, into: &lines, skipSelf: false)
        return lines
    }

    /// Removes the head element entirely; its title is metadata, not a
    /// recipe title candidates want.
    private static func stripHead(_ html: String) -> String {
        var result = html
        if let head = result.range(of: "<head", options: .caseInsensitive) {
            let after = head.upperBound
            if let end = result.range(
                of: "</head>", options: .caseInsensitive, range: after..<result.endIndex)
            {
                result.removeSubrange(head.lowerBound..<end.upperBound)
            }
        }
        return result
    }

    private static func collectLines(
        from element: HTMLElement, into lines: inout [Line], skipSelf: Bool
    ) {
        if !skipSelf && element.tag == "script" || element.tag == "style" {
            return
        }
        let direct = element.text
            .split(separator: "\n", omittingEmptySubsequences: true)
        for part in direct {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(Line(text: trimmed, position: lines.count)) }
        }
        for child in element.children {
            collectLines(from: child, into: &lines, skipSelf: false)
        }
    }

    private static func cleanBullet(_ text: String) -> String {
        var result = Substring(text)
        // Bullet markers and list numbers.
        while let first = result.first, "-•·*\u{2022}\u{25CF}".contains(first) {
            result = result.dropFirst()
        }
        result = result.drop(while: { $0 == " " })
        // "1." "2)" "Step 3:" markers.
        if let match = result.prefix(4).firstIndex(where: { $0 == "." || $0 == ")" }),
            result[result.startIndex..<match].allSatisfy({ $0.isNumber })
        {
            result = result[result.index(after: match)...]
            result = result.drop(while: { $0 == " " })
        }
        if loweredHasStepMarker(result) {
            let after = result.firstIndex(of: ":").map { result.index(after: $0) }
            if let after { result = result[after...].drop(while: { $0 == " " }) }
        }
        return String(result).trimmingCharacters(in: .whitespaces)
    }

    private static func loweredHasStepMarker(_ text: Substring) -> Bool {
        let lowered = text.prefix(12).lowercased()
        for marker in ["step ", "step:"] where lowered.hasPrefix(marker) {
            return true
        }
        return false
    }

    /// A step is a sentence addressed to the cook: starts with a verb
    /// shape or an imperative cue, or is long and ends with a period.
    private static func looksLikeStep(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let cues = [
            "preheat", "heat ", "stir", "mix", "whisk", "bake", "add ",
            "pour", "place", "combine", "cook", "boil", "simmer", "fold",
            "knead", "chop", "dice", "slice", "serve", "season", "brush",
            "spread", "cover", "remove", "reduce", "let ", "allow ",
            "sprinkle", "drizzle", "transfer", "rest", "rest", "top ",
            "turn ", "flip", "set aside", "meanwhile", "once ", "when ",
            "until", "for ", "then",
        ]
        if cues.contains(where: { lowered.hasPrefix($0) }) { return true }
        return text.count >= 25 && text.hasSuffix(".")
    }

    /// An ingredient line has a quantity or unit, and is short.
    private static func looksLikeIngredient(_ text: String) -> Bool {
        guard text.count <= 90 else { return false }
        let lowered = text.lowercased()
        if IngredientParser.parse(text).quantity != nil { return true }
        let units = [
            "cup", "cups", "tbsp", "tablespoon", "tsp", "teaspoon",
            "gram", "grams", "g ", "kg", "ml", "l ", "oz", "ounce",
            "pound", "lb", "pinch", "clove", "cloves", "can", "cans",
            "package", "pack", "stick", "sticks", "bunch", "handful",
        ]
        return units.contains { lowered.contains($0) }
    }

    /// Image URLs from img tags in the visible body.
    private static func imageUrls(_ html: String) -> [String] {
        var urls: [String] = []
        var index = html.startIndex
        while let open = html.range(
            of: "<img", options: .caseInsensitive, range: index..<html.endIndex)
        {
            guard let close = html.range(of: ">", range: open.upperBound..<html.endIndex) else {
                break
            }
            let tag = String(html[open.lowerBound..<close.upperBound])
            if let src = attribute("src", in: tag), src.hasPrefix("http") {
                urls.append(src)
            } else if let data = attribute("data-src", in: tag), data.hasPrefix("http") {
                urls.append(data)
            }
            index = close.upperBound
        }
        var unique: [String] = []
        for url in urls where !unique.contains(url) { unique.append(url) }
        return unique
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            let pattern = "\(name)=\(quote)"
            if let range = tag.range(of: pattern, options: .caseInsensitive) {
                let rest = tag[range.upperBound...]
                if let end = rest.firstIndex(of: Character(quote)) {
                    return String(rest[rest.startIndex..<end])
                }
            }
        }
        // Unquoted value.
        let pattern = "\(name)="
        if let range = tag.range(of: pattern, options: .caseInsensitive) {
            let rest = tag[range.upperBound...]
            let end = rest.firstIndex(where: { $0.isWhitespace || $0 == ">" }) ?? rest.endIndex
            let value = String(rest[rest.startIndex..<end]).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
