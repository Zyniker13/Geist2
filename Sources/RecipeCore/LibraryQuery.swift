import Foundation

/// One library query, as values: everything the library screen needs to
/// ask the index for. Sorting happens on the documents after the index
/// narrows the pool, so the order is stable and testable without SQL.
public struct LibraryQuery: Equatable, Sendable {
    /// Free text the user typed; matched against the full-text index.
    public var text: String
    /// Show only recipes carrying this tag.
    public var tag: String?
    /// Show only recipes in this category.
    public var category: String?
    /// Show only recipes of this cuisine.
    public var cuisine: String?
    /// Keep recipes with a total time at or under this many seconds.
    public var maxTotalSeconds: Int?
    /// Keep recipes rated this many stars or higher.
    public var minRating: Int?
    /// Sort order; the library defaults to newest first.
    public var sort: Sort

    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case newest, oldest, title, rating

        public var id: String { rawValue }

        /// The segmented-control label, computed here so callers don't
        /// embed strings in the UI layer for a core decision.
        public var label: String {
            switch self {
            case .newest: return "Newest"
            case .oldest: return "Oldest"
            case .title: return "Title"
            case .rating: return "Rating"
            }
        }
    }

    public init(
        text: String = "",
        tag: String? = nil,
        category: String? = nil,
        cuisine: String? = nil,
        maxTotalSeconds: Int? = nil,
        minRating: Int? = nil,
        sort: Sort = .newest
    ) {
        self.text = text
        self.tag = tag
        self.category = category
        self.cuisine = cuisine
        self.maxTotalSeconds = maxTotalSeconds
        self.minRating = minRating
        self.sort = sort
    }

    /// True when no field narrows the pool (search text counts; the
    /// sort alone does not).
    public var isNarrowed: Bool {
        !text.isEmpty || tag != nil || category != nil || cuisine != nil
            || maxTotalSeconds != nil || minRating != nil
    }

    /// Alias for the filter state the UI checks to show the active
    /// filter affordance and enable "Clear filters".
    public var filters: [String] {
        var names: [String] = []
        if !text.isEmpty { names.append("text") }
        if tag != nil { names.append("tag") }
        if category != nil { names.append("category") }
        if cuisine != nil { names.append("cuisine") }
        if maxTotalSeconds != nil { names.append("time") }
        if minRating != nil { names.append("rating") }
        return names
    }
}

/// The library-side application of a query: filters and sorts whole
/// documents, mirroring what the index narrows to IDs. Kept as pure
/// functions so the UI model and the SQL index stay provably in step.
public enum LibraryQuerying {
    /// Filters and sorts `recipes` according to `query`.
    public static func apply(
        _ query: LibraryQuery, to recipes: [RecipeDocument]
    ) -> [RecipeDocument] {
        var result = recipes.filter { recipe in
            if recipe.deletedAt != nil { return false }
            if let tag = query.tag, !recipe.tags.contains(tag) { return false }
            if let category = query.category,
                !recipe.categories.contains(category)
            {
                return false
            }
            if let cuisine = query.cuisine, recipe.cuisine != cuisine {
                return false
            }
            if let maxTotal = query.maxTotalSeconds,
                let total = recipe.totalTime, total.seconds > maxTotal
            {
                return false
            }
            if let maxTotal = query.maxTotalSeconds,
                recipe.totalTime == nil
            {
                return false
            }
            if let minRating = query.minRating, recipe.rating < minRating {
                return false
            }
            if !query.text.isEmpty {
                let haystack = [
                    recipe.title, recipe.summary, recipe.notes,
                    recipe.ingredientSections.flatMap(\.lines)
                        .map(\.originalText).joined(separator: "\n"),
                    recipe.tags.joined(separator: " "),
                ].joined(separator: "\n").lowercased()
                // Every whitespace-separated term must appear.
                for term in query.text.lowercased()
                    .split(whereSeparator: \.isWhitespace)
                {
                    guard haystack.contains(term) else { return false }
                }
            }
            return true
        }
        switch query.sort {
        case .newest:
            // Ties break to title ascending so equal timestamps stay
            // in a stable, predictable order.
            result.sort {
                $0.modifiedAt != $1.modifiedAt
                    ? $0.modifiedAt > $1.modifiedAt
                    : $0.title.localizedLowercase < $1.title.localizedLowercase
            }
        case .oldest:
            result.sort {
                $0.modifiedAt != $1.modifiedAt
                    ? $0.modifiedAt < $1.modifiedAt
                    : $0.title.localizedLowercase < $1.title.localizedLowercase
            }
        case .title:
            result.sort { $0.title.localizedLowercase < $1.title.localizedLowercase }
        case .rating:
            result.sort {
                $0.rating != $1.rating
                    ? $0.rating > $1.rating
                    : $0.title.localizedLowercase < $1.title.localizedLowercase
            }
        }
        return result
    }
}
