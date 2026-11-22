import Foundation

/// Duplicate detection and merging (M1.4).
///
/// Two recipes are duplicates when their normalized source URLs match, or
/// when their normalized titles match AND their ingredient-item sets are
/// similar enough. The merge keeps both sides' fields: non-empty values
/// win over empty ones, lists concatenate with de-duplication, and the
/// photos union by content hash.
public enum Deduplication {
    /// Normalizes a source URL for comparison: lowercase host, no
    /// fragment, no trailing slash, tracking parameters removed.
    public static func sourceKey(_ address: String?) -> String? {
        guard
            let address, !address.isEmpty,
            let url = URL(string: address),
            let host = url.host(), !host.isEmpty,
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        while path.hasSuffix("/") { path.removeLast() }
        let loweredHost = components?.host?.lowercased()
        components?.host = loweredHost
        components?.fragment = nil
        components?.path = path
        let tracking = Set(["fbclid", "gclid", "msclkid", "dclid", "taid", "link_source"])
        let items = components?.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !tracking.contains(name)
        }
        components?.queryItems = items?.isEmpty == false ? items : nil
        return components?.url?.absoluteString
    }

    /// Normalizes a title for comparison: whitespace collapsed, case and
    /// diacritics folded.
    public static func titleKey(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }

    /// The set of normalized ingredient items, for similarity.
    static func itemSet(_ recipe: RecipeDocument) -> Set<String> {
        Set(
            recipe.ingredientSections.flatMap(\.lines)
                .map { titleKey($0.item) }
                .filter { !$0.isEmpty })
    }

    /// Jaccard similarity of two recipes' ingredient items.
    static func similarity(_ a: RecipeDocument, _ b: RecipeDocument) -> Double {
        let setA = itemSet(a)
        let setB = itemSet(b)
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    /// All duplicates of `recipe` within `candidates`.
    public static func duplicates(
        of recipe: RecipeDocument, among candidates: [RecipeDocument]
    ) -> [RecipeDocument] {
        let title = titleKey(recipe.title)
        let source = sourceKey(recipe.sourceURL)
        return candidates.filter { candidate in
            candidate.id == recipe.id
                ? false
                : isDuplicate(
                    recipe, candidate, title: title, source: source)
        }
    }

    static func isDuplicate(
        _ a: RecipeDocument, _ b: RecipeDocument, title: String, source: String?
    ) -> Bool {
        if let source, sourceKey(b.sourceURL) == source { return true }
        if !title.isEmpty, titleKey(b.title) == title, similarity(a, b) >= 0.5 {
            return true
        }
        return false
    }

    /// Merges `incoming` into `target`, keeping both sides' fields.
    ///
    /// Non-empty scalar fields from either side win; when both are
    /// non-empty and different, the target's value is kept unless
    /// `preferIncoming` says otherwise. Lists concatenate with
    /// de-duplication; photos union by hash; the earlier `createdAt`
    /// survives; the merged document keeps the target's ID.
    public static func merge(
        _ incoming: RecipeDocument, into target: RecipeDocument,
        preferIncoming: Bool = false
    ) -> RecipeDocument {
        var merged = target
        let primary = preferIncoming ? incoming : target
        let backup = preferIncoming ? target : incoming

        merged.title = primary.title.isEmpty ? backup.title : primary.title
        merged.summary = primary.summary.isEmpty ? backup.summary : primary.summary
        merged.yieldAmount = primary.yieldAmount ?? backup.yieldAmount
        merged.yieldUnit = primary.yieldUnit.isEmpty ? backup.yieldUnit : primary.yieldUnit
        merged.prepTime = primary.prepTime ?? backup.prepTime
        merged.cookTime = primary.cookTime ?? backup.cookTime
        merged.totalTime = primary.totalTime ?? backup.totalTime
        merged.cuisine = primary.cuisine ?? backup.cuisine
        merged.sourceURL = primary.sourceURL ?? backup.sourceURL
        merged.attribution = primary.attribution ?? backup.attribution
        merged.rating = primary.rating != 0 ? primary.rating : backup.rating
        merged.createdAt = min(target.createdAt, incoming.createdAt)
        merged.nutrition = primary.nutrition.isEmpty ? backup.nutrition : primary.nutrition

        // Sections: concatenate, keeping non-empty section names apart and
        // de-duplicating identical lines by original text.
        merged.ingredientSections = mergeSections(
            primary.ingredientSections, backup.ingredientSections)
        merged.stepSections = mergeStepSections(
            primary.stepSections, backup.stepSections)

        // Tags, categories: union preserving order.
        merged.tags = union(primary.tags, backup.tags)
        merged.categories = union(primary.categories, backup.categories)

        // Photos: union by hash.
        var hashes: [String] = []
        for hash in primary.photoHashes + backup.photoHashes
        where !hashes.contains(hash) {
            hashes.append(hash)
        }
        merged.photoHashes = hashes

        // Notes: concatenate distinct paragraphs.
        let notes = [primary.notes, backup.notes]
            .flatMap { $0.split(separator: "\n\n", omittingEmptySubsequences: true) }
            .map(String.init)
        var seenNotes = Set<String>()
        merged.notes = notes.filter { seenNotes.insert($0).inserted }
            .joined(separator: "\n\n")

        return merged
    }

    static func mergeSections(
        _ primary: [IngredientSection], _ backup: [IngredientSection]
    ) -> [IngredientSection] {
        var result: [IngredientSection] = []
        var seenTexts = Set<String>()
        for section in primary + backup {
            let lines = section.lines.filter { line in
                line.originalText.isEmpty || seenTexts.insert(line.originalText).inserted
            }
            if let index = result.firstIndex(where: { $0.name == section.name }) {
                result[index].lines += lines.filter { line in
                    !result[index].lines.contains(where: { $0.originalText == line.originalText })
                }
            } else {
                result.append(IngredientSection(name: section.name, lines: lines))
            }
        }
        return result
    }

    static func mergeStepSections(
        _ primary: [StepSection], _ backup: [StepSection]
    ) -> [StepSection] {
        var result: [StepSection] = []
        for section in primary + backup {
            if let index = result.firstIndex(where: { $0.name == section.name }) {
                let existing = Set(result[index].steps.map(\.text))
                result[index].steps += section.steps.filter { !existing.contains($0.text) }
            } else {
                result.append(section)
            }
        }
        return result
    }

    static func union(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0).inserted }
    }
}
