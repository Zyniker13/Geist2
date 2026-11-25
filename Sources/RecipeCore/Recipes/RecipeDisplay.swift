import Foundation

/// The recipe view's display pipeline (M4.2): scale, convert, render.
///
/// Storage keeps the recipe exactly as written (decision 0008); the
/// display applies the viewer's choices on top:
///
/// 1. `RecipeMath.scaledLine` scales every quantified line by the
///    yield factor with friendly rounding;
/// 2. `RecipeConversion.convert` moves the scaled line to the requested
///    unit system (nothing happens in `.written`);
/// 3. `text` renders the result from the structured fields — the
///    original text is never rewritten, so an unparseable line
///    round-trips and scaled lines read naturally.
///
/// Everything is a pure function of its inputs: no clock, no locale,
/// no global state. The kitchen-fraction renderer is `RecipeMath`'s.
public enum RecipeDisplay {
    /// The unit system a recipe is shown in.
    public enum UnitSystem: Hashable, Sendable, CaseIterable {
        /// Exactly as stored — no conversion.
        case written
        case metric
        case us

        /// The label the unit toggle shows.
        public var label: String {
            switch self {
            case .written: return "As written"
            case .metric: return "Metric"
            case .us: return "US"
            }
        }
    }

    /// The viewer's choices: a scale factor (1 = as written) and a unit
    /// system.
    public struct Options: Hashable, Sendable {
        public var factor: Decimal
        public var system: UnitSystem

        public init(factor: Decimal = 1, system: UnitSystem = .written) {
            self.factor = factor
            self.system = system
        }

        static let written = Options()
    }

    /// One ingredient line as the view renders it.
    public struct RenderedLine: Hashable, Sendable {
        /// The human text: "1 1/2 cups flour, finely chopped (optional)".
        public let text: String
        /// The line carries a quantity, so scaling applies to it.
        public let scalable: Bool
        /// The line changed unit system under `RecipeConversion`.
        public let converted: Bool

        public init(text: String, scalable: Bool, converted: Bool) {
            self.text = text
            self.scalable = scalable
            self.converted = converted
        }
    }

    /// One ingredient section as the view renders it.
    public struct RenderedSection: Hashable, Sendable {
        public let name: String
        public let lines: [RenderedLine]

        public init(name: String, lines: [RenderedLine]) {
            self.name = name
            self.lines = lines
        }
    }

    /// Renders every ingredient section through the pipeline.
    public static func sections(
        _ sections: [IngredientSection], options: Options, catalog: UnitCatalog = UnitCatalog()
    ) -> [RenderedSection] {
        sections.map { section in
            RenderedSection(
                name: section.name,
                lines: section.lines.map { line($0, options: options, catalog: catalog) })
        }
    }

    /// Renders one line: scale, then convert, then render to text.
    public static func line(
        _ source: IngredientLine, options: Options, catalog: UnitCatalog = UnitCatalog()
    ) -> RenderedLine {
        // "As written" at factor 1 is the recipe's own wording, verbatim:
        // the round-trip guarantee the parser made. Any other choice
        // (scaling, converting) renders from the structured fields.
        if case .written = options.system, options.factor == 1,
            !source.originalText.isEmpty
        {
            return RenderedLine(
                text: source.originalText, scalable: source.quantity != nil, converted: false)
        }
        let scaled: IngredientLine
        do {
            scaled = try RecipeMath.scaledLine(source, by: options.factor, catalog: catalog)
        } catch {
            // Unreachable through the app (the factor is always > 0),
            // but the pipeline degrades to the written line rather than
            // failing a screen.
            scaled = source
        }
        let display: IngredientLine
        let converted: Bool
        switch options.system {
        case .written:
            display = scaled
            converted = false
        case .metric:
            let result = RecipeConversion.convert(scaled, to: .metric, catalog: catalog)
            display = result.line
            converted = result.converted
        case .us:
            let result = RecipeConversion.convert(scaled, to: .us, catalog: catalog)
            display = result.line
            converted = result.converted
        }
        return RenderedLine(
            text: text(of: display),
            scalable: source.quantity != nil,
            converted: converted)
    }

    /// The scaled yield line: "6 servings". Nil when the recipe states
    /// no yield amount.
    public static func yieldText(
        _ recipe: RecipeDocument, options: Options
    ) -> String? {
        guard let amount = recipe.yieldAmount else { return nil }
        let scaled = amount * options.factor
        return "\(RecipeMath.kitchenFraction(of: scaled)) \(recipe.yieldUnit)"
    }

    /// Step text with scaled amounts substituted (M2.3's stepText).
    /// At factor 1 the step shows as written — substitution is skipped
    /// so a step that merely names an amount is never reworded.
    public static func stepText(
        _ step: Step, lines: [IngredientLine], options: Options,
        catalog: UnitCatalog = UnitCatalog()
    ) -> String {
        guard options.factor != 1 else { return step.text }
        let scaled =
            (try? RecipeMath.stepText(
                step.text, lines: lines, by: options.factor, catalog: catalog)) ?? step.text
        return scaled
    }

    // MARK: Rendering

    /// Renders a line from its structured fields.
    static func text(of line: IngredientLine) -> String {
        var text = amountsAndItem(of: line)
        if let preparation = line.preparation, !preparation.isEmpty {
            text += ", \(preparation)"
        }
        if line.toTaste {
            text += text.isEmpty ? "to taste" : ", to taste"
        }
        if let note = line.note, !note.isEmpty {
            text += " (\(note))"
        }
        if line.optional {
            text += " (optional)"
        }
        return text
    }

    /// The quantity, optional range high end, unit, and item.
    private static func amountsAndItem(of line: IngredientLine) -> String {
        var parts: [String] = []
        if let quantity = line.quantity {
            parts.append(amountText(quantity.amount, unitID: line.unitID))
        }
        if let high = line.quantityHigh {
            parts.append("–")
            parts.append(amountText(high.amount, unitID: line.unitID))
        }
        if let unitID = line.unitID, !unitID.isEmpty {
            // The unit label pluralizes on the amount the line shows:
            // the high end of a range ("2 – 3 cups") is the visible top.
            let shown = line.quantityHigh?.amount ?? line.quantity?.amount ?? 1
            parts.append(unitLabel(unitID, amount: shown))
        }
        // Count units ("2 eggs") carry no unit id; the item itself
        // pluralizes and depluralizes with the amount ("1 egg").
        let item = itemCountUnit(line)
        parts.append(item)
        return parts.joined(separator: " ")
    }

    /// An item that carries a count quantity but no unit ("2 eggs")
    /// reads as a count: it gets a simple singular/plural form. The
    /// amount the item name must agree with is the line's visible top.
    static func itemCountUnit(_ line: IngredientLine) -> String {
        let item = line.item
        guard line.unitID == nil, line.quantity != nil, !line.toTaste else { return item }
        let shown = line.quantityHigh?.amount ?? line.quantity?.amount ?? 1
        guard shown == 1 else { return item }
        // A simple trailing-s depluralize ("eggs" → "egg"); irregulars
        // and anything else pass through untouched.
        if item.hasSuffix("ies") && item.count > 3 {
            return String(item.dropLast(3)) + "y"
        }
        if item.hasSuffix("ses") || item.hasSuffix("xes") || item.hasSuffix("zes")
            || item.hasSuffix("ches") || item.hasSuffix("shes")
        {
            return String(item.dropLast(2))
        }
        if item.hasSuffix("s") && item.count > 1 {
            return String(item.dropLast())
        }
        return item
    }

    /// The unit as a recipe reads it: kitchen spellings for the catalog's
    /// identifiers, pluralized when the amount calls for it. Unknown
    /// identifiers pass through unchanged (a stored custom unit shows as
    /// written).
    /// The amount as its unit reads it: metric units show a decimal
    /// ("591.5 ml"), kitchen units a fraction ("2 1/2 cups").
    static func amountText(_ amount: Decimal, unitID: String?) -> String {
        switch unitID {
        case "ml", "l", "g", "kg":
            return RecipeMath.wholeOrDecimal(amount)
        default:
            return RecipeMath.kitchenFraction(of: amount)
        }
    }

    /// The unit as a recipe reads it: kitchen spellings for the catalog's
    /// identifiers, pluralized when the amount calls for it. Unknown
    /// identifiers pass through unchanged (a stored custom unit shows as
    /// written).
    public static func unitLabel(_ id: String, amount: Decimal) -> String {
        let plural = amount > 1
        switch id {
        case "cup": return plural ? "cups" : "cup"
        case "tbsp": return "tbsp"
        case "tsp": return "tsp"
        case "ml": return "ml"
        case "cl": return "cl"
        case "l": return "l"
        case "oz", "ozm": return "oz"
        case "lb": return plural ? "lbs" : "lb"
        case "g": return "g"
        case "kg": return "kg"
        case "quart": return plural ? "quarts" : "quart"
        case "pint": return plural ? "pints" : "pint"
        case "gallon": return plural ? "gallons" : "gallon"
        case "clove": return plural ? "cloves" : "clove"
        case "stick": return plural ? "sticks" : "stick"
        case "sprig": return plural ? "sprigs" : "sprig"
        case "bunch": return plural ? "bunches" : "bunch"
        case "can": return plural ? "cans" : "can"
        case "pinch": return plural ? "pinches" : "pinch"
        case "piece": return plural ? "pieces" : "piece"
        default: return id
        }
    }
}
