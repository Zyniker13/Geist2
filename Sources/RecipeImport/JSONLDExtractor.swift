import Foundation

/// A parsed JSON-LD recipe block before conversion to a document.
public struct JSONLDRecipe {
    public var name: String?
    public var description: String?
    public var recipeYield: String?
    public var recipeCategory: String?
    public var recipeCuisine: String?
    public var keywords: String?
    public var author: String?
    public var prepTime: String?
    public var cookTime: String?
    public var totalTime: String?
    public var ingredients: [String]
    public var instructions: [String]
    /// Section name → its steps, in order, for HowToSection groups.
    public var instructionSections: [(name: String, steps: [String])]
    public var images: [String]
    public var nutrition: [String: String]

    public init(
        name: String? = nil, description: String? = nil, recipeYield: String? = nil,
        recipeCategory: String? = nil, recipeCuisine: String? = nil,
        keywords: String? = nil, author: String? = nil, prepTime: String? = nil,
        cookTime: String? = nil, totalTime: String? = nil, ingredients: [String] = [],
        instructions: [String] = [],
        instructionSections: [(name: String, steps: [String])] = [],
        images: [String] = [], nutrition: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.recipeYield = recipeYield
        self.recipeCategory = recipeCategory
        self.recipeCuisine = recipeCuisine
        self.keywords = keywords
        self.author = author
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.ingredients = ingredients
        self.instructions = instructions
        self.instructionSections = instructionSections
        self.images = images
        self.nutrition = nutrition
    }
}

/// Finds and flattens recipe data in the JSON-LD blocks of a page.
/// Handles @graph, arrays, and Recipe nodes nested in Article or
/// WebPage objects.
enum JSONLDExtractor {
    static func extract(from html: String) -> JSONLDRecipe? {
        for block in jsonBlocks(in: html) {
            guard let data = block.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            var candidates: [Any] = []
            flatten(json, into: &candidates, insideGraph: false)
            for candidate in candidates {
                guard let object = candidate as? [String: Any] else { continue }
                if let recipe = recipe(from: object) {
                    return recipe
                }
            }
        }
        return nil
    }

    /// All <script type="application/ld+json"> block contents, unescaped.
    static func jsonBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var searchRange = html.startIndex..<html.endIndex
        let openTag = "<script"
        let closeTag = "</script>"
        while let open = html.range(of: openTag, range: searchRange) {
            guard let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex)
            else { break }
            guard
                let close = html.range(
                    of: closeTag, range: tagEnd.upperBound..<html.endIndex)
            else { break }
            let content = String(html[tagEnd.upperBound..<close.lowerBound])
            if content.contains("application/ld+json") || looksLikeJSON(content) {
                blocks.append(htmlUnescape(content))
            }
            searchRange = close.upperBound..<html.endIndex
        }
        return blocks
    }

    /// A script block without a type attribute can still be JSON-LD
    /// when the page writes it bare; content starting with "{" or "["
    /// after trimming counts.
    private static func looksLikeJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    /// Walks the JSON tree collecting dictionaries; @graph entries and
    /// array elements are visited too.
    private static func flatten(
        _ node: Any, into candidates: inout [Any], insideGraph: Bool
    ) {
        switch node {
        case let dictionary as [String: Any]:
            candidates.append(dictionary)
            if let graph = dictionary["@graph"] {
                flatten(graph, into: &candidates, insideGraph: true)
            }
            // An object whose @type is a list still holds recipe fields
            // at its own level.
            for (_, value) in dictionary {
                if let array = value as? [Any], !isPlainScalarArray(array) {
                    for element in array {
                        flatten(element, into: &candidates, insideGraph: insideGraph)
                    }
                }
            }
        case let array as [Any]:
            for element in array {
                flatten(element, into: &candidates, insideGraph: insideGraph)
            }
        default:
            break
        }
    }

    /// Arrays of strings or numbers stay where they are; arrays of
    /// objects are walked.
    private static func isPlainScalarArray(_ array: [Any]) -> Bool {
        array.allSatisfy { $0 is String || $0 is NSNumber }
    }

    /// Builds a recipe from one object when it looks like a Recipe.
    static func recipe(from object: [String: Any]) -> JSONLDRecipe? {
        let types = typeNames(of: object)
        guard types.contains("Recipe") || looksLikeRecipe(object) else { return nil }
        var recipe = JSONLDRecipe(
            name: string(object["name"]),
            description: string(object["description"] ?? object["headline"]),
            recipeYield: yieldText(of: object),
            recipeCategory: string(object["recipeCategory"]),
            recipeCuisine: string(object["recipeCuisine"]),
            keywords: string(object["keywords"]),
            author: author(of: object),
            prepTime: string(object["prepTime"]),
            cookTime: string(object["cookTime"]),
            totalTime: string(object["totalTime"] ?? object["duration"]),
            ingredients: ingredients(of: object),
            instructions: [],
            instructionSections: [],
            images: images(of: object),
            nutrition: nutrition(of: object)
        )
        extractInstructions(from: object["recipeInstructions"], into: &recipe)
        if recipe.name == nil, recipe.ingredients.isEmpty, recipe.instructions.isEmpty {
            return nil
        }
        return recipe
    }

    /// An object without an explicit @type is treated as a Recipe when
    /// it carries recipe field names.
    private static func looksLikeRecipe(_ object: [String: Any]) -> Bool {
        let recipeFields = [
            "recipeIngredient", "recipeInstructions", "recipeYield",
            "recipeCuisine", "cookTime",
        ]
        return recipeFields.contains { object[$0] != nil }
    }

    private static func typeNames(of object: [String: Any]) -> Set<String> {
        guard let type = object["@type"] else { return [] }
        switch type {
        case let text as String: return [text]
        case let list as [Any]:
            return Set(list.compactMap { $0 as? String })
        default: return []
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        case let list as [Any]:
            return list.compactMap { string($0) }.first
        default: return nil
        }
    }

    /// recipeYield, yield, or the output of a HowToSupply-style yield.
    private static func yieldText(of object: [String: Any]) -> String? {
        string(object["recipeYield"] ?? object["yield"])
    }

    private static func author(of object: [String: Any]) -> String? {
        switch object["author"] {
        case let text as String: return text
        case let object as [String: Any]: return string(object["name"])
        case let list as [Any]:
            return list.compactMap { entry -> String? in
                if let text = entry as? String { return text }
                if let dict = entry as? [String: Any] { return string(dict["name"]) }
                return nil
            }.first
        default: return nil
        }
    }

    private static func ingredients(of object: [String: Any]) -> [String] {
        var lines: [String] = []
        func add(_ value: Any?) {
            switch value {
            case let text as String where !text.isEmpty: lines.append(text)
            case let number as NSNumber: lines.append(number.stringValue)
            case let list as [Any]: for element in list { add(element) }
            default: break
            }
        }
        add(object["recipeIngredient"])
        add(object["ingredients"])
        return lines
    }

    /// HowToStep lists, plain strings, and HowToSections in order.
    private static func extractInstructions(from value: Any?, into recipe: inout JSONLDRecipe) {
        switch value {
        case let text as String where !text.isEmpty:
            recipe.instructions.append(text)
        case let object as [String: Any]:
            addInstructionObject(object, into: &recipe)
        case let list as [Any]:
            for element in list { extractInstructions(from: element, into: &recipe) }
        default: break
        }
    }

    private static func addInstructionObject(
        _ object: [String: Any], into recipe: inout JSONLDRecipe
    ) {
        let types = typeNames(of: object)
        if types.contains("HowToSection") {
            let name = string(object["name"]) ?? ""
            var steps: [String] = []
            if let list = object["itemListElement"] as? [Any] {
                for element in list {
                    if let text = element as? String, !text.isEmpty {
                        steps.append(text)
                    } else if let dict = element as? [String: Any] {
                        // item: { "@type": "HowToStep", "text": ... }
                        if let item = dict["item"] as? [String: Any],
                            let text = string(item["text"])
                        {
                            steps.append(text)
                        } else if let text = string(dict["text"]) {
                            steps.append(text)
                        }
                    }
                }
            }
            if !steps.isEmpty {
                recipe.instructionSections.append((name: name, steps: steps))
            }
        } else if types.contains("HowToStep") {
            if let text = string(object["text"] ?? object["itemListElement"]) {
                recipe.instructions.append(text)
            }
        } else if let text = string(object["text"]) {
            recipe.instructions.append(text)
        } else if let text = string(object["name"]) {
            // Some sites put the whole step in "name".
            recipe.instructions.append(text)
        }
    }

    private static func images(of object: [String: Any]) -> [String] {
        var urls: [String] = []
        func add(_ value: Any?) {
            switch value {
            case let text as String where !text.isEmpty: urls.append(text)
            case let object as [String: Any]:
                if let url = string(object["url"]) { urls.append(url) }
            case let list as [Any]: for element in list { add(element) }
            default: break
            }
        }
        add(object["image"])
        add(object["thumbnailUrl"])
        return urls
    }

    private static func nutrition(of object: [String: Any]) -> [String: String] {
        guard let nutrition = object["nutrition"] as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        let wanted = [
            "calories", "carbohydrateContent", "proteinContent",
            "fatContent", "saturatedFatContent", "sugarContent",
            "sodiumContent", "fiberContent", "cholesterolContent",
            "transFatContent", "unsaturatedFatContent", "servingSize",
        ]
        for key in wanted {
            if let value = string(nutrition[key]) {
                result[key] = value
            }
        }
        return result
    }

    /// Minimal entity decoding so JSON text survives extraction; JSON
    /// itself cannot contain raw < or &, but pages escape inside the
    /// block more often than not.
    static func htmlUnescape(_ text: String) -> String {
        var result = text
        let entities = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // Numeric entities.
        if result.contains("&#") {
            result = replaceNumericEntities(in: result)
        }
        return result
    }

    /// "&#" + decimal digits + ";" → the Unicode character.
    private static func replaceNumericEntities(in text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&",
                index < text.endIndex,
                text.index(after: index) < text.endIndex,
                text[text.index(after: index)] == "#"
            else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            var digits = ""
            var cursor = text.index(index, offsetBy: 2)
            var hex = false
            if cursor < text.endIndex, text[cursor] == "x" || text[cursor] == "X" {
                hex = true
                cursor = text.index(after: cursor)
            }
            while cursor < text.endIndex, text[cursor].isNumber || (hex && text[cursor].isHexDigit)
            {
                digits.append(text[cursor])
                cursor = text.index(after: cursor)
            }
            guard !digits.isEmpty,
                cursor < text.endIndex, text[cursor] == ";"
            else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let radix = hex ? 16 : 10
            if let code = UInt32(digits, radix: radix),
                let scalar = UnicodeScalar(code)
            {
                result.append(Character(scalar))
            }
            index = text.index(after: cursor)
        }
        return result
    }
}
