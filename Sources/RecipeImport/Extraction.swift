import Foundation
import RecipeCore

/// One recipe field extracted from a source, with how confident the
/// extractor is. A field the extractor is unsure about is still kept:
/// the app can show it for review instead of silently dropping it.
public struct ExtractedField<Value> {
    /// The extracted value.
    public var value: Value
    /// How the value was found.
    public var source: FieldSource
    /// True when the extractor trusts the value outright (a structured
    /// JSON-LD or Microdata field). False for heuristic guesses.
    public var confident: Bool

    public init(_ value: Value, from source: FieldSource, confident: Bool = true) {
        self.value = value
        self.source = source
        self.confident = confident
    }
}

/// How an extracted value was found.
public enum FieldSource: Equatable, Sendable {
    /// A schema.org JSON-LD block.
    case jsonLd
    /// A schema.org Microdata attribute.
    case microdata
    /// A common HTML pattern (meta tags, Open Graph, plain markup).
    case htmlPattern
    /// A structural guess from plain text.
    case heuristic
}

/// The whole extraction result: a document, or a partial result the
/// caller can offer to fix up by hand.
public struct ExtractionResult {
    public var document: RecipeDocument?
    /// Fields extracted without a complete document (for previews and
    /// manual review).
    public var partialFields: [PartialField]

    public init(document: RecipeDocument?, partialFields: [PartialField] = []) {
        self.document = document
        self.partialFields = partialFields
    }
}

/// One named field held aside for review.
public struct PartialField {
    public enum Kind: String, Sendable {
        case title, summary, yieldAmount, yieldUnit
        case prepTime, cookTime, totalTime
        case ingredients, steps, tags, image
    }
    public var kind: Kind
    public var text: String
    public var source: FieldSource

    public init(kind: Kind, text: String, source: FieldSource) {
        self.kind = kind
        self.text = text
        self.source = source
    }
}

/// Errors extraction can report.
public enum ExtractionError: Error, Equatable {
    /// No recipe-shaped content at all.
    case notARecipe
    /// The HTML could not be read.
    case unreadableHTML
}
