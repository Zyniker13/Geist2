import Foundation
import GRDB

/// What the bar can satisfy, reduced to the taxonomy node ids of products
/// with at least one on-hand bottle (unopened or opened; finished bottles
/// and wishlist entries don't count).
public struct BarStock: Sendable, Equatable {
    public let coveredNodes: Set<String>

    public init(coveredNodes: Set<String>) {
        self.coveredNodes = coveredNodes
    }
}

/// One recipe's required ingredient asks: the taxonomy node ids of every
/// non-optional ingredient, in recipe order, deduplicated. Optional
/// ingredients never block; ingredients without a taxonomy node are ignored
/// (they are ice, water, or method notes the matcher cannot reason about).
public struct RecipeNeeds: Sendable, Equatable {
    public let recipeId: String
    public let requiredNodes: [String]

    public init(recipeId: String, requiredNodes: [String]) {
        self.recipeId = recipeId
        self.requiredNodes = requiredNodes
    }
}

/// How close a substitution keeps the drink to the recipe as written.
public enum SubstitutionCloseness: String, Sendable, Equatable, Codable {
    /// The drink stays recognizably the same; most people wouldn't notice.
    case close
    /// The drink is recognizably different, but still worth making.
    case changesTheDrink
}

/// One documented stand-in: `to` can play the role `from` is asked for.
/// Both sides are taxonomy node ids; the substitute must itself be in the
/// bar (directionally, per the shared coverage rule) for a match.
public struct Substitution: Sendable, Equatable, Hashable, Codable {
    public let from: String
    public let to: String
    public let closeness: SubstitutionCloseness
    public let note: String

    public init(
        from: String, to: String, closeness: SubstitutionCloseness, note: String
    ) {
        self.from = from
        self.to = to
        self.closeness = closeness
        self.note = note
    }
}

/// How a recipe stands against the bar.
public enum MatchState: Sendable, Equatable {
    case makeableNow
    /// Exactly one required node is missing — buying it unlocks the drink.
    case oneAway(missing: String)
    /// More than one gap, but every gap has a substitution in the bar.
    case withSubstitution(
        substitutions: [(missing: String, sub: Substitution)])
    /// Some gap has neither the bottle nor a substitution.
    case shortOfIngredients(missing: [String])
}

extension MatchState: Hashable {
    public static func == (lhs: MatchState, rhs: MatchState) -> Bool {
        switch (lhs, rhs) {
        case (.makeableNow, .makeableNow):
            return true
        case (.oneAway(let a), .oneAway(let b)):
            return a == b
        case (.withSubstitution(let a), .withSubstitution(let b)):
            return a.count == b.count
                && zip(a, b).allSatisfy {
                    $0.missing == $1.missing && $0.sub == $1.sub
                }
        case (.shortOfIngredients(let a), .shortOfIngredients(let b)):
            return a == b
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .makeableNow:
            hasher.combine(0)
        case .oneAway(let missing):
            hasher.combine(1)
            hasher.combine(missing)
        case .withSubstitution(let subs):
            hasher.combine(2)
            for (missing, sub) in subs {
                hasher.combine(missing)
                hasher.combine(sub)
            }
        case .shortOfIngredients(let missing):
            hasher.combine(3)
            hasher.combine(missing)
        }
    }
}

/// What the bar can make, aggregated over the whole library.
public struct MatchSummary: Sendable, Equatable {
    public let makeableNow: [String]
    public let oneAway: [(recipeId: String, missing: String)]
    public let withSubstitution:
        [(
            recipeId: String, substitutions: [(missing: String, sub: Substitution)]
        )]
    public let shortOfIngredients: [(recipeId: String, missing: [String])]
    /// Nodes whose purchase unlocks the most recipes, best first. Counts a
    /// node for every non-makeable recipe that is missing it.
    public let unlockCounts: [(nodeId: String, count: Int)]

    public static func == (lhs: MatchSummary, rhs: MatchSummary) -> Bool {
        // Spelled as early-return comparisons rather than one && chain:
        // CI's toolchain times out type-checking the long chain while the
        // local toolchain accepts it.
        if lhs.makeableNow != rhs.makeableNow { return false }
        if lhs.oneAway.count != rhs.oneAway.count { return false }
        for (l, r) in zip(lhs.oneAway, rhs.oneAway) where l != r { return false }
        if lhs.withSubstitution.count != rhs.withSubstitution.count { return false }
        for (l, r) in zip(lhs.withSubstitution, rhs.withSubstitution) {
            if l.recipeId != r.recipeId { return false }
            if l.substitutions.count != r.substitutions.count { return false }
            for (ls, rs) in zip(l.substitutions, r.substitutions) {
                if ls.missing != rs.missing || ls.sub != rs.sub { return false }
            }
        }
        if lhs.shortOfIngredients.count != rhs.shortOfIngredients.count {
            return false
        }
        for (l, r) in zip(lhs.shortOfIngredients, rhs.shortOfIngredients) {
            if l.recipeId != r.recipeId || l.missing != r.missing { return false }
        }
        if lhs.unlockCounts.count != rhs.unlockCounts.count { return false }
        for (l, r) in zip(lhs.unlockCounts, rhs.unlockCounts) where l != r {
            return false
        }
        return true
    }
}

/// Matches the bar against the library using the shared directional
/// coverage rule: a specific bottle satisfies a broader ask, never the
/// reverse. The classification priority is makeable now, then one away
/// (buy the real thing — it beats substituting), then substitution-only,
/// then short of ingredients.
public enum MatchingService {
    /// True when the bar covers the requested node (directly, or via any
    /// node below it in the taxonomy).
    public static func covers(
        bar: BarStock, requested: String, parentByNode: [String: String?]
    ) -> Bool {
        TaxonomyCoverage.covers(
            bar.coveredNodes, requested, parentByNode: parentByNode)
    }

    /// Classifies one recipe against the bar.
    public static func classify(
        needs: RecipeNeeds,
        bar: BarStock,
        substitutions: [Substitution],
        parentByNode: [String: String?]
    ) -> MatchState {
        // Required nodes in order, deduplicated, with the first occurrence
        // kept so missing lists stay in recipe order.
        var missing: [String] = []
        var seen = Set<String>()
        for node in needs.requiredNodes where !seen.contains(node) {
            if !covers(bar: bar, requested: node, parentByNode: parentByNode) {
                missing.append(node)
            }
            seen.insert(node)
        }
        if missing.isEmpty {
            return .makeableNow
        }
        if missing.count == 1 {
            return .oneAway(missing: missing[0])
        }
        var stands: [(missing: String, sub: Substitution)] = []
        for node in missing {
            // The substitution applies when the bar covers the substitute's
            // target node (directionally).
            guard
                let sub = substitutions.first(where: {
                    $0.from == node
                        && covers(
                            bar: bar, requested: $0.to,
                            parentByNode: parentByNode)
                })
            else {
                return .shortOfIngredients(missing: missing)
            }
            stands.append((missing: node, sub: sub))
        }
        return .withSubstitution(substitutions: stands)
    }

    /// Aggregates classifications over the library and ranks the unlocks.
    public static func summarize(
        _ allNeeds: [RecipeNeeds],
        bar: BarStock,
        substitutions: [Substitution],
        parentByNode: [String: String?]
    ) -> MatchSummary {
        var makeable: [String] = []
        var oneAway: [(recipeId: String, missing: String)] = []
        var withSub:
            [(
                recipeId: String, substitutions: [(missing: String, sub: Substitution)]
            )] = []
        var short: [(recipeId: String, missing: [String])] = []
        var unlockTally: [String: Int] = [:]
        for needs in allNeeds {
            switch classify(
                needs: needs, bar: bar, substitutions: substitutions,
                parentByNode: parentByNode)
            {
            case .makeableNow:
                makeable.append(needs.recipeId)
            case .oneAway(let missing):
                oneAway.append((recipeId: needs.recipeId, missing: missing))
                unlockTally[missing, default: 0] += 1
            case .withSubstitution(let subs):
                withSub.append((recipeId: needs.recipeId, substitutions: subs))
                for (missing, _) in subs {
                    unlockTally[missing, default: 0] += 1
                }
            case .shortOfIngredients(let missing):
                short.append((recipeId: needs.recipeId, missing: missing))
                for node in missing {
                    unlockTally[node, default: 0] += 1
                }
            }
        }
        let unlocks =
            unlockTally
            .map { (nodeId: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.nodeId < rhs.nodeId
            }
        return MatchSummary(
            makeableNow: makeable, oneAway: oneAway, withSubstitution: withSub,
            shortOfIngredients: short, unlockCounts: unlocks)
    }

    // MARK: Database-facing loads

    /// The taxonomy parent map the coverage rule walks.
    public static func parentMap(db: AppDatabase) throws -> [String: String?] {
        var map: [String: String?] = [:]
        try db.dbWriter.read { reader in
            let rows = try Row.fetchAll(
                reader, sql: "SELECT id, parentId FROM taxonomyNode")
            for row in rows {
                map[row["id"] as String] = row["parentId"] as String?
            }
        }
        return map
    }

    /// Every live recipe's required asks, ordered by recipe name so lists
    /// are stable across calls.
    public static func loadNeeds(db: AppDatabase) throws -> [RecipeNeeds] {
        try db.dbWriter.read { reader in
            let rows = try Row.fetchAll(
                reader,
                sql: """
                    SELECT recipe.id, recipeIngredient.taxonomyId, recipeIngredient.isOptional
                    FROM recipe JOIN recipeIngredient
                        ON recipeIngredient.recipeId = recipe.id
                    WHERE recipe.deletedAt IS NULL
                    ORDER BY recipe.name, recipeIngredient.ordinal
                    """)
            var nodesByRecipe: [String: [String]] = [:]
            var order: [String] = []
            for row in rows {
                let recipeId: String = row["id"]
                if nodesByRecipe[recipeId] == nil {
                    nodesByRecipe[recipeId] = []
                    order.append(recipeId)
                }
                let optional: Bool = row["isOptional"]
                let taxonomyId: String? = row["taxonomyId"]
                guard !optional, let taxonomyId else { continue }
                // Water comes from the tap; a water ask is never a bar
                // requirement (the bundled Old Fashioned asks for a
                // teaspoon of water alongside its spirit).
                if taxonomyId.hasPrefix("mixer.water") { continue }
                nodesByRecipe[recipeId]!.append(taxonomyId)
            }
            return order.map {
                RecipeNeeds(
                    recipeId: $0, requiredNodes: nodesByRecipe[$0] ?? [])
            }
        }
    }

    /// The bar: taxonomy nodes of products holding at least one bottle that
    /// is on hand (unopened or opened — not finished, not wishlist, not
    /// soft-deleted).
    public static func loadBar(db: AppDatabase) throws -> BarStock {
        try db.dbWriter.read { reader in
            let rows = try Row.fetchAll(
                reader,
                sql: """
                    SELECT DISTINCT product.taxonomyId
                    FROM product
                    JOIN inventoryItem ON inventoryItem.productId = product.id
                        AND inventoryItem.deletedAt IS NULL
                        AND inventoryItem.status IN ('unopened', 'opened')
                    WHERE product.deletedAt IS NULL AND product.taxonomyId IS NOT NULL
                    """)
            return BarStock(coveredNodes: Set(rows.compactMap { $0["taxonomyId"] as String? }))
        }
    }
}
