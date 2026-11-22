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

    /// True when every field came from structured data, not guesses.
    public var allConfident: Bool {
        document != nil && partialFields.isEmpty
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

/// The import entry point: run the extractors in order of trust and
/// stop at the first hit. Every path ends in the M2 parser.
public enum RecipeExtractor {
    /// Which extractor produced the result.
    public struct Report: Sendable {
        public var source: FieldSource
        public var document: RecipeDocument

        init(source: FieldSource, document: RecipeDocument) {
            self.source = source
            self.document = document
        }
    }

    /// Extract from an HTML page. `now` is the creation timestamp the
    /// caller supplies (RecipeCore is deterministic); `id` is the new
    /// document's identity.
    public static func extract(
        fromHTML html: String, now epochSeconds: Int64, id: String
    ) -> Report? {
        let sources: [(FieldSource, JSONLDRecipe?)] = [
            (.jsonLd, JSONLDExtractor.extract(from: html)),
            (.microdata, MicrodataExtractor.extract(from: html)),
            (.heuristic, HeuristicExtractor.extract(from: html)),
        ]
        for (source, recipe) in sources {
            guard let recipe,
                let document = RecipeAssembler.document(
                    from: recipe, now: epochSeconds, id: id)
            else { continue }
            return Report(source: source, document: document)
        }
        return nil
    }

    /// Extract from plain text a user pasted: line-structured recipe
    /// text, no HTML.
    public static func extract(
        fromText text: String, now epochSeconds: Int64, id: String
    ) -> Report? {
        guard let recipe = HeuristicExtractor.extractText(text),
            let document = RecipeAssembler.document(
                from: recipe, now: epochSeconds, id: id)
        else { return nil }
        return Report(source: .heuristic, document: document)
    }

    /// Fetch a page over the network and extract from it. The caller
    /// supplies the fetch: RecipeImport stays synchronous and offline
    /// for tests, and the app injects its own session.
    public static func extract(
        from url: String,
        fetching: (String) async throws -> String,
        now epochSeconds: Int64, id: String
    ) async throws -> Report {
        let html = try await fetching(url)
        guard !html.isEmpty else { throw ExtractionError.unreadableHTML }
        guard let report = extract(fromHTML: html, now: epochSeconds, id: id) else {
            throw ExtractionError.notARecipe
        }
        return report
    }
}
