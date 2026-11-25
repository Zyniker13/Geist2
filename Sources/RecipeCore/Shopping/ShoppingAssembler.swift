import Foundation

/// Builds a shopping list from recipes: combines amounts across
/// recipes, converts to a common unit, subtracts what the pantry
/// already has, and groups the lines by aisle.
///
/// Deterministic throughout: names come in, lines come out, no clocks
/// or identifiers are minted here (the caller stamps the document).
public enum ShoppingAssembler {

    /// One assembled list line before it becomes a `ListLine`.
    public struct Draft: Equatable, Sendable {
        /// The shown item name, in the plural-ish form the first
        /// recipe used.
        public var item: String
        /// The combined amount, nil for to-taste/free lines.
        public var quantity: Decimal?
        /// The unit the combination settled on, nil with quantity nil.
        public var unitID: String?
        /// The aisle grouping label.
        public var aisle: String
        /// True when the line is a to-taste or unitless "some" line.
        public var free: Bool
        /// True when the pantry covered the whole amount.
        public var coveredByPantry: Bool

        init(
            item: String, quantity: Decimal? = nil, unitID: String? = nil,
            aisle: String, free: Bool = false, coveredByPantry: Bool = false
        ) {
            self.item = item
            self.quantity = quantity
            self.unitID = unitID
            self.aisle = aisle
            self.free = free
            self.coveredByPantry = coveredByPantry
        }
    }

    /// One pantry entry the assembler matches against: the name and an
    /// optional amount in a unit. Names match as a whole word at the
    /// start or after a separator ("chicken" covers "chicken thighs"
    /// and "ground chicken", not "chickenstock").
    public struct PantryStock: Equatable, Sendable {
        public var name: String
        public var amount: Decimal?
        public var unitID: String?

        public init(name: String, amount: Decimal? = nil, unitID: String? = nil) {
            self.name = name
            self.amount = amount
            self.unitID = unitID
        }
    }

    /// Assembles list drafts from recipe ingredient lines, scaled to
    /// each recipe's share. Lines with the same normalized item name
    /// and convertible units combine; different units that cannot
    /// convert stay as separate lines.
    public static func assemble(
        lines: [(recipe: RecipeDocument, servings: Decimal)],
        pantry: [PantryStock] = [],
        catalog: UnitCatalog = UnitCatalog()
    ) -> [Draft] {
        // Scale each recipe's lines to the wanted servings.
        var scaled: [(item: String, quantity: Decimal, unit: String, free: Bool)] = []
        for (recipe, servings) in lines {
            let yield = recipe.yieldAmount ?? 1
            guard yield > 0, servings > 0 else { continue }
            let factor = servings / yield
            for section in recipe.ingredientSections {
                for line in section.lines where !line.optional {
                    let aisleItem = normalizedItem(line.item)
                    if line.toTaste || line.quantity == nil || line.unitID == nil {
                        scaled.append((aisleItem, 0, "", true))
                        continue
                    }
                    scaled.append(
                        (
                            aisleItem,
                            (line.quantity?.amount ?? 0) * factor,
                            line.unitID ?? "",
                            false
                        ))
                }
            }
        }

        // Combine by item: same name, convertible unit -> one line in
        // the first unit seen; otherwise parallel lines accumulate.
        var order: [String] = []
        var buckets: [String: [(quantity: Decimal, unit: String, free: Bool)]] = [:]
        for entry in scaled {
            if buckets[entry.item] == nil { order.append(entry.item) }
            buckets[entry.item, default: []].append(
                (entry.quantity, entry.unit, entry.free))
        }

        var drafts: [Draft] = []
        for item in order {
            let entries = buckets[item] ?? []
            let freeEntries = entries.filter(\.free)
            let measured = entries.filter { !$0.free }

            // Free lines (to taste / no amount) collapse to one.
            if let first = freeEntries.first {
                drafts.append(
                    Draft(
                        item: item, aisle: AisleCatalog.aisle(for: item),
                        free: true))
            }

            // Combine measured amounts by unit dimension, converting
            // into the first entry's unit when possible.
            var combined: [(quantity: Decimal, unit: String)] = []
            for entry in measured {
                var merged = false
                for index in combined.indices {
                    if let converted = catalog.convert(
                        entry.quantity, from: entry.unit, to: combined[index].unit)
                    {
                        combined[index].quantity += converted
                        merged = true
                        break
                    }
                }
                if !merged {
                    combined.append((entry.quantity, entry.unit))
                }
            }

            // Subtract the pantry. A pantry entry covers a line when
            // its name is a prefix word of the item (or vice versa);
            // with amounts, it subtracts what it can in the same
            // dimension, converting units first.
            var pantryLeft = pantry
            for index in combined.indices {
                var amount = combined[index].quantity
                var unit = combined[index].unit
                for stockIndex in pantryLeft.indices where amount > 0 {
                    let stock = pantryLeft[stockIndex]
                    guard covers(stock.name, item) else { continue }
                    if stock.amount == nil {
                        // An unmeasured pantry item covers the line.
                        amount = 0
                        pantryLeft.remove(at: stockIndex)
                        break
                    }
                    guard let stockUnit = stock.unitID else { continue }
                    var stockAmount = stock.amount!
                    if let converted = catalog.convert(stockAmount, from: stockUnit, to: unit) {
                        stockAmount = converted
                    } else if let converted = catalog.convert(amount, from: unit, to: stockUnit) {
                        // Convert the line into the pantry's unit instead.
                        amount = converted
                        unit = stockUnit
                        stockAmount = stock.amount!
                    } else {
                        continue
                    }
                    if stockAmount >= amount {
                        amount = 0
                        pantryLeft.remove(at: stockIndex)
                        break
                    } else {
                        amount -= stockAmount
                        pantryLeft[stockIndex] = PantryStock(
                            name: stock.name, amount: 0, unitID: stockUnit)
                    }
                }
                combined[index] = (amount, unit)
            }

            for entry in combined {
                let covered = entry.quantity <= 0
                let rounded = RecipeMath.round(max(entry.quantity, 0), unit: entry.unit)
                let tiny = rounded == 0 && entry.quantity > 0
                drafts.append(
                    Draft(
                        item: item,
                        // A nonzero want that rounds to zero keeps a
                        // token amount so it stays on the list.
                        quantity: covered
                            ? nil : (tiny ? Decimal(string: "0.01") : rounded),
                        unitID: covered ? nil : entry.unit,
                        aisle: AisleCatalog.aisle(for: item),
                        coveredByPantry: covered))
            }
        }
        return drafts
    }

    /// Turns drafts into document lines, dropping pantry-covered ones.
    public static func listLines(
        from drafts: [Draft], recipeID: String? = nil
    ) -> [ListLine] {
        drafts.compactMap { draft in
            guard !draft.coveredByPantry else { return nil }
            var line = ListLine(text: text(for: draft), item: draft.item)
            if let quantity = draft.quantity {
                line.quantity = Quantity(quantity)
                line.unitID = draft.unitID
            }
            line.aisle = draft.aisle == AisleCatalog.fallback ? nil : draft.aisle
            line.recipeID = recipeID
            line.checked = false
            line.movedToPantry = false
            return line
        }
    }

    /// The shown text: "2 cups vegetable stock", "olive oil to taste".
    public static func text(for draft: Draft) -> String {
        if draft.free { return "\(draft.item) to taste" }
        guard let quantity = draft.quantity, let unit = draft.unitID else {
            return draft.item
        }
        let rounded = RecipeMath.round(quantity, unit: unit)
        let amount = RecipeDisplay.amountText(rounded, unitID: unit)
        return "\(amount) \(RecipeDisplay.unitLabel(unit, amount: rounded)) \(draft.item)"
    }

    // MARK: Matching

    /// The normalized item name: lowercase, preparation stripped.
    ///
    /// A leading tail ("grated parmesan") is also normalized because
    /// the parser often leaves the preparation inside the item; both
    /// orders must reduce to "parmesan" for lines to combine.
    static func normalizedItem(_ item: String) -> String {
        let lowered = item.lowercased().trimmingCharacters(in: .whitespaces)
        // Common preparation words that may sit before or after the
        // item: "grated parmesan" and "parmesan, grated" both reduce
        // to "parmesan".
        let fillers = [
            "finely chopped", "roughly chopped", "chopped", "diced",
            "grated", "shredded", "minced", "sliced", "crushed",
            "to taste", "optional", "fresh", "freshly", "large",
            "small", "finely", "roughly",
        ]
        var text = lowered
        for filler in fillers {
            text = text.replacingOccurrences(of: ", \(filler)", with: "")
            text = text.replacingOccurrences(of: " \(filler)", with: "")
            text = text.replacingOccurrences(of: "\(filler) ", with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a pantry name covers a wanted item: word-prefix match
    /// on the normalized names, either direction.
    static func covers(_ pantryName: String, _ item: String) -> Bool {
        let a = normalizedItem(pantryName)
        let b = item
        if a == b { return true }
        if b.hasPrefix("\(a) ") || a.hasPrefix("\(b) ") { return true }
        return false
    }
}
