import Foundation

/// One HTML element from the microdata scanner: its tag, attributes,
/// direct text, and children. Malformed markup is tolerated: a close
/// tag ends the nearest open element of that name, and anything else
/// is ignored.
struct HTMLElement {
    var tag: String
    var attributes: [String: String]
    var text: String
    var children: [HTMLElement]
    /// Unique within one parsed tree; assigned by the parser.
    var id: Int = 0

    init(tag: String, attributes: [String: String] = [:], text: String = "") {
        self.tag = tag
        self.attributes = attributes
        self.text = text
        self.children = []
    }

    /// The first attribute value for a name, case-insensitive.
    func attribute(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    /// Puts a child first: the tree assembles back-to-front, so each
    /// pass prepends to keep document order.
    mutating func insert(_ child: HTMLElement, at position: Int) {
        children.insert(child, at: position)
    }
}

/// A small HTML reader for microdata extraction. It parses the tag
/// structure and text, not a full DOM: enough to find itemscope trees
/// and the values schema.org recipes carry.
enum HTMLTree {
    /// Elements that never have children.
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "source", "track", "wbr",
    ]

    /// Elements whose content is not page text.
    private static let skippedContent: Set<String> = ["script", "style", "head"]

    static func parse(_ html: String) -> HTMLElement {
        // The tree is built as a flat array of nodes with parent links,
        // then assembled top-down. HTMLElement is a value type, so a
        // stack of copies cannot carry nested mutations back into the
        // nodes already appended to their parents.
        var nodes: [HTMLElement] = [HTMLElement(tag: "#root")]
        // parentIndices[n] is the parent index of node n; the root has
        // a dummy -1 so the arrays stay parallel.
        var parentIndices: [Int] = [-1]
        var stack: [Int] = [0]
        var index = html.startIndex
        var pendingText = ""
        var elementCounter = 0

        func flushText() {
            if !pendingText.isEmpty {
                nodes[stack[stack.count - 1]].text += pendingText
                pendingText = ""
            }
        }

        while index < html.endIndex {
            guard html[index] == "<" else {
                pendingText.append(html[index])
                index = html.index(after: index)
                continue
            }
            // A comment, a doctype, or a closing tag.
            let afterOpen = html.index(after: index)
            if afterOpen == html.endIndex {
                // A trailing "<": treat it as text.
                pendingText.append("<")
                index = afterOpen
                continue
            }
            if html[afterOpen] == "!" {
                if html[afterOpen...].hasPrefix("!--"),
                    let commentEnd = html.range(of: "-->", range: afterOpen..<html.endIndex)
                {
                    index = commentEnd.upperBound
                } else {
                    // A doctype or CDATA marker: skip to its closing ">"
                    // so none of it leaks into the visible text.
                    if let close = html.range(of: ">", range: afterOpen..<html.endIndex) {
                        index = close.upperBound
                    } else {
                        index = html.endIndex
                    }
                }
                continue
            }
            if html[afterOpen] == "/" {
                if let closeEnd = html.range(
                    of: ">", range: afterOpen..<html.endIndex)
                {
                    let name = String(html[html.index(after: afterOpen)..<closeEnd.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    // Flush first: the pending text belongs to the
                    // element about to close.
                    flushText()
                    closeTag(name, stack: &stack, nodes: nodes)
                    index = closeEnd.upperBound
                } else {
                    index = afterOpen
                }
                continue
            }
            // An opening tag: read to the matching ">", honoring quoted
            // attribute values that may contain it.
            flushText()
            var cursor = afterOpen
            var quote: Character?
            var tagEnd: String.Index?
            while cursor < html.endIndex {
                let character = html[cursor]
                if let active = quote {
                    if character == active { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    tagEnd = cursor
                    break
                }
                cursor = html.index(after: cursor)
            }
            let end = tagEnd ?? html.endIndex
            let tagBody = String(html[afterOpen..<end])
            let (tag, attributes, selfClosed) = readTag(tagBody)
            var element = HTMLElement(tag: tag, attributes: attributes)
            elementCounter += 1
            element.id = elementCounter
            let selfIndex = nodes.count
            nodes.append(element)
            let parentIndex = stack[stack.count - 1]
            parentIndices.append(parentIndex)
            if !voidElements.contains(tag) && !selfClosed {
                stack.append(selfIndex)
            }
            if skippedContent.contains(tag) {
                // Skip to the matching close tag; its content is data,
                // not markup or text.
                if let close = html.range(
                    of: "</\(tag)", options: .caseInsensitive,
                    range: end..<html.endIndex
                ),
                    let closeEnd = html.range(
                        of: ">", range: close.lowerBound..<html.endIndex)
                {
                    // The open element is already on the stack; the
                    // close tag below will pop it.
                    index = closeEnd.upperBound
                    closeTag(tag, stack: &stack, nodes: nodes)
                    continue
                }
                // Unterminated script/style: treat the rest as data.
                index = html.endIndex
                closeTag(tag, stack: &stack, nodes: nodes)
                continue
            }
            index = tagEnd.map { html.index(after: $0) } ?? html.endIndex
        }
        flushText()
        // Assemble the tree from the leaves up: assign children to the
        // deepest parents first. Because HTMLElement is a value type, a
        // parent placed into its own parent's children array must
        // already carry its complete subtree, or the subtree is lost.
        // Document order guarantees a child's index is always greater
        // than its parent's, so walking indices in reverse finishes
        // every child before its parent is captured.
        for position in stride(from: nodes.count - 1, through: 1, by: -1) {
            nodes[parentIndices[position]].insert(nodes[position], at: 0)
        }
        return nodes[0]
    }

    /// Pops the nearest open element with this name; unknown names are
    /// ignored (malformed pages).
    private static func closeTag(_ name: String, stack: inout [Int], nodes: [HTMLElement]) {
        guard name != "#root" else { return }
        if let position = stack.lastIndex(where: { nodes[$0].tag == name }),
            position > 0
        {
            stack.removeSubrange(position...)
        }
    }

    /// Tag name and attributes from the inside of a tag.
    private static func readTag(_ body: String) -> (String, [String: String], Bool) {
        var characters = Substring(body)
        var name = ""
        while let first = characters.first, !first.isWhitespace, first != "/" {
            name.append(first)
            characters = characters.dropFirst()
        }
        var attributes: [String: String] = [:]
        var selfClosed = false
        while !characters.isEmpty {
            characters = characters.drop(while: { $0.isWhitespace })
            // Read the attribute name.
            var key = ""
            while let first = characters.first, !first.isWhitespace, first != "=",
                first != "/"
            {
                key.append(first)
                characters = characters.dropFirst()
            }
            guard !key.isEmpty else {
                if characters.first == "/" {
                    selfClosed = true
                    characters = characters.dropFirst()
                } else if !characters.isEmpty {
                    characters = characters.dropFirst()
                }
                continue
            }
            characters = characters.drop(while: { $0.isWhitespace })
            if characters.first == "/" {
                selfClosed = true
                characters = characters.dropFirst()
                attributes[key.lowercased()] = ""
                continue
            }
            guard characters.first == "=" else {
                // Boolean attribute: itemscope has no value.
                attributes[key.lowercased()] = ""
                continue
            }
            characters = characters.dropFirst()
            characters = characters.drop(while: { $0.isWhitespace })
            var value = ""
            if let quote = characters.first, quote == "\"" || quote == "'" {
                characters = characters.dropFirst()
                while let next = characters.first, next != quote {
                    value.append(next)
                    characters = characters.dropFirst()
                }
                if characters.first == quote { characters = characters.dropFirst() }
            } else {
                while let next = characters.first, !next.isWhitespace, next != "/" {
                    value.append(next)
                    characters = characters.dropFirst()
                }
                if characters.first == "/" { selfClosed = true }
            }
            attributes[key.lowercased()] = value
        }
        return (name.lowercased(), attributes, selfClosed)
    }
}

/// Extracts a recipe from schema.org Microdata attributes.
enum MicrodataExtractor {
    /// The property values one itemscope carries, in document order.
    struct Item {
        var type: String
        var properties: [(name: String, value: Value)]

        enum Value {
            case text(String)
            case url(String)
            case item(Item)
        }
    }

    static func extract(from html: String) -> JSONLDRecipe? {
        let root = HTMLTree.parse(html)
        var items: [Item] = []
        collectItems(in: root, into: &items)
        for item in items where item.type == "recipe" {
            return recipe(from: item)
        }
        return nil
    }

    /// Depth-first walk; an itemscope element becomes an Item whose
    /// properties are its own itemprop descendants (nearest scope).
    private static func collectItems(
        in element: HTMLElement, into items: inout [Item]
    ) {
        if element.attribute("itemscope") != nil {
            var item = Item(type: itemType(of: element), properties: [])
            collectProperties(in: element, into: &item)
            items.append(item)
            return
        }
        for child in element.children {
            collectItems(in: child, into: &items)
        }
    }

    /// The type's short name: "https://schema.org/Recipe" → "recipe".
    private static func itemType(of element: HTMLElement) -> String {
        let raw = element.attribute("itemtype") ?? ""
        let parts = raw.split(separator: " ").map(String.init)
        guard let last = parts.last else { return "" }
        let name = last.split(separator: "/").last.map(String.init) ?? last
        return name.lowercased()
    }

    /// Properties bound to this scope: descendants with itemprop whose
    /// nearest itemscope ancestor is this element.
    private static func collectProperties(
        in scope: HTMLElement, into item: inout Item
    ) {
        for child in scope.children {
            collectProperties(in: child, into: &item, scopeID: scope.id)
        }
    }

    /// The scope's identity: since HTMLElement is a value type, the
    /// scope is tracked by the position where its subtree starts; an
    /// itemscope child found inside the subtree is nested.
    private static func collectProperties(
        in element: HTMLElement, into item: inout Item, scopeID: Int
    ) {
        if element.attribute("itemscope") != nil, element.id != scopeID {
            // A nested item: it is the property's value.
            if let names = propertyNames(of: element) {
                var nested = Item(type: itemType(of: element), properties: [])
                collectProperties(in: element, into: &nested, scopeID: element.id)
                for name in names {
                    item.properties.append((name, .item(nested)))
                }
            }
            return
        }
        if let names = propertyNames(of: element) {
            let value = value(of: element)
            for name in names {
                item.properties.append((name, value))
            }
        }
        for child in element.children {
            collectProperties(in: child, into: &item, scopeID: scopeID)
        }
    }

    /// itemprop is a space-separated list.
    private static func propertyNames(of element: HTMLElement) -> [String]? {
        guard let raw = element.attribute("itemprop") else { return nil }
        let names = raw.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    /// The property's value by element kind, per the microdata rules.
    private static func value(of element: HTMLElement) -> Item.Value {
        if let content = element.attribute("content") {
            return .text(content)
        }
        if element.tag == "time", let dt = element.attribute("datetime"),
            !dt.isEmpty {
            // <time datetime="PT20M">20 minutes</time>: the machine
            // readable ISO duration wins over the display text.
            return .text(dt)
        }
        switch element.tag {
        case "link", "a", "area":
            if let href = element.attribute("href"), !href.isEmpty {
                return .url(href)
            }
        case "img", "audio", "video", "source", "embed", "track":
            if let src = element.attribute("src"), !src.isEmpty {
                return .url(src)
            }
        case "data", "meter":
            if let raw = element.attribute("value"), !raw.isEmpty {
                return .text(raw)
            }
        default:
            break
        }
        return .text(element.text)
    }

    /// Microdata item → the same JSONLDRecipe the JSON-LD path produces,
    /// so one assembler serves both.
    static func recipe(from item: Item) -> JSONLDRecipe? {
        var recipe = JSONLDRecipe()
        var ingredients: [String] = []
        var instructionTexts: [String] = []
        var images: [String] = []

        func use(_ name: String, _ value: Item.Value) {
            switch (name, value) {
            case ("name", .text(let text)): recipe.name = first(recipe.name, text)
            case ("description", .text(let text)):
                recipe.description = first(recipe.description, text)
            case ("recipeyield", .text(let text)):
                recipe.recipeYield = first(recipe.recipeYield, text)
            case ("yield", .text(let text)):
                recipe.recipeYield = first(recipe.recipeYield, text)
            case ("recipecategory", .text(let text)):
                recipe.recipeCategory = first(recipe.recipeCategory, text)
            case ("recipecuisine", .text(let text)):
                recipe.recipeCuisine = first(recipe.recipeCuisine, text)
            case ("keywords", .text(let text)):
                recipe.keywords = first(recipe.keywords, text)
            case ("author", .text(let text)):
                recipe.author = first(recipe.author, text)
            case ("author", .item(let nested)):
                if let authorName = nested.textValue("name") {
                    recipe.author = first(recipe.author, authorName)
                }
            case ("preptime", .text(let text)): recipe.prepTime = text
            case ("preptime", .item(let nested)):
                if let iso = nested.textValue("name") { recipe.prepTime = iso }
            case ("cooktime", .text(let text)): recipe.cookTime = text
            case ("cooktime", .item(let nested)):
                if let iso = nested.textValue("name") { recipe.cookTime = iso }
            case ("totaltime", .text(let text)): recipe.totalTime = text
            case ("totaltime", .item(let nested)):
                if let iso = nested.textValue("name") { recipe.totalTime = iso }
            case ("performtime", .text(let text)): recipe.cookTime = text
            case ("performtime", .item(let nested)):
                if let iso = nested.textValue("name") { recipe.cookTime = iso }
            case ("recipeingredient", .text(let text)) where !text.isEmpty:
                ingredients.append(text)
            case ("recipeingredients", .text(let text)) where !text.isEmpty:
                ingredients.append(text)
            case ("ingredient", .text(let text)) where !text.isEmpty:
                ingredients.append(text)
            case ("ingredients", .text(let text)) where !text.isEmpty:
                ingredients.append(text)
            case ("recipeinstructions", .text(let text)) where !text.isEmpty:
                instructionTexts.append(text)
            case ("recipeinstruction", .text(let text)) where !text.isEmpty:
                instructionTexts.append(text)
            case ("instructions", .text(let text)) where !text.isEmpty:
                instructionTexts.append(text)
            case ("step", .text(let text)) where !text.isEmpty:
                instructionTexts.append(text)
            case ("recipeinstructions", .item(let nested)):
                addInstruction(nested, into: &recipe, texts: &instructionTexts)
            case ("image", .text(let text)) where !text.isEmpty:
                images.append(text)
            case ("image", .url(let url)):
                images.append(url)
            case ("thumbnailurl", .url(let url)), ("thumbnailurl", .text(let url)):
                // One element can carry both itemprop="image
                // thumbnailUrl"; the same URL must not be listed twice.
                if !images.contains(url) { images.append(url) }
            case ("nutrition", .item(let nested)):
                for (key, text) in nested.nutritionFields() {
                    recipe.nutrition[key] = text
                }
            case ("url", .text(let text)), ("url", .url(let text)):
                recipe.sourceURL = first(recipe.sourceURL, text)
            case ("recipenotes", .text(let text)):
                recipe.recipeNotes = first(recipe.recipeNotes, text)
            case ("recipetips", .text(let text)):
                recipe.recipeTips = first(recipe.recipeTips, text)
            default:
                break
            }
        }

        for property in item.properties {
            use(property.name.lowercased(), property.value)
        }
        recipe.ingredients = ingredients
        recipe.instructions = instructionTexts
        recipe.images = images
        if recipe.name == nil, ingredients.isEmpty, instructionTexts.isEmpty {
            return nil
        }
        return recipe
    }

    /// HowToSection and HowToStep items inside instructions.
    private static func addInstruction(
        _ item: Item, into recipe: inout JSONLDRecipe, texts: inout [String]
    ) {
        if item.type == "howtosection" {
            var name = ""
            var steps: [String] = []
            for property in item.properties {
                switch (property.name.lowercased(), property.value) {
                case ("name", .text(let text)): name = text
                case ("itemlistelement", .text(let text)) where !text.isEmpty:
                    steps.append(text)
                case ("itemlistelement", .item(let nested)):
                    if nested.type == "howtostep", let text = nested.textValue("text") {
                        steps.append(text)
                    } else if let text = nested.textValue("name") {
                        steps.append(text)
                    }
                default: break
                }
            }
            if !steps.isEmpty {
                recipe.instructionSections.append((name: name, steps: steps))
            }
        } else if item.type == "howtostep" {
            if let text = item.textValue("text") {
                texts.append(text)
            } else if let text = item.textValue("name") {
                texts.append(text)
            }
        } else if let text = item.textValue("text") {
            texts.append(text)
        }
    }

    private static func first(_ existing: String?, _ candidate: String) -> String? {
        if existing != nil { return existing }
        return candidate.isEmpty ? nil : candidate
    }
}

/// Item helpers shared by the extractor.
extension MicrodataExtractor.Item {
    /// The first text value for a property name.
    func textValue(_ name: String) -> String? {
        for property in properties where property.name.lowercased() == name {
            switch property.value {
            case .text(let text) where !text.isEmpty:
                return text
            case .url(let url) where !url.isEmpty:
                return url
            default:
                continue
            }
        }
        return nil
    }

    /// NutritionInformation fields, keyed by their canonical schema
    /// names so the keys match what the JSON-LD path produces.
    func nutritionFields() -> [(String, String)] {
        var result: [(String, String)] = []
        for property in properties {
            if let text = valueText(of: property.value), !text.isEmpty {
                result.append((Self.nutritionKey(property.name), text))
            }
        }
        return result
    }

    /// Maps a raw property name to the canonical schema.org nutrition
    /// key when it matches one case-insensitively.
    private static func nutritionKey(_ raw: String) -> String {
        let canonical = [
            "calories", "carbohydrateContent", "proteinContent",
            "fatContent", "saturatedFatContent", "sugarContent",
            "sodiumContent", "fiberContent", "cholesterolContent",
            "transFatContent", "unsaturatedFatContent", "servingSize",
        ]
        let lowered = raw.lowercased()
        for name in canonical where name.lowercased() == lowered {
            return name
        }
        return lowered
    }

    private func valueText(of value: Value) -> String? {
        switch value {
        case .text(let text): return text
        case .url(let url): return url
        case .item: return nil
        }
    }
}
