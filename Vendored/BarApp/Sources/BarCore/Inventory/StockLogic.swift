import Foundation
import GRDB

/// Low-stock and restock logic: what counts as "on hand", which products
/// are low, which recipe ingredients are missing, and the shopping-list
/// drafts that follow (decision 0012).
///
/// A bottle counts as on hand while its status is `unopened` or `opened`;
/// `finished` bottles are gone (they are the usual reason a product turns
/// low) and `wishlist` entries are wishes, not stock.
public enum StockLogic {
    /// The threshold when neither the product nor any taxonomy ancestor
    /// sets one: keep one bottle on hand.
    public static let defaultThreshold = 1

    /// The resolved threshold for a product: its own setting, else the
    /// nearest taxonomy ancestor's category default, else the built-in
    /// default.
    public static func threshold(
        productId: String,
        productThreshold: Int?,
        productTaxonomyId: String?,
        categoryThresholds: [String: Int],
        parentByNode: [String: String?]
    ) -> Int {
        if let productThreshold {
            return max(0, productThreshold)
        }
        var nodeId = productTaxonomyId
        while let current = nodeId {
            if let threshold = categoryThresholds[current] {
                return max(0, threshold)
            }
            nodeId = parentByNode[current] ?? nil
        }
        return defaultThreshold
    }

    /// Products whose on-hand bottle count is below their resolved
    /// threshold, ordered by name. A product with no bottles at all counts
    /// as zero.
    public static func lowStockProducts(
        products: [ProductRecord],
        items: [InventoryItemRecord],
        categoryThresholds: [String: Int],
        parentByNode: [String: String?]
    ) -> [(product: ProductRecord, threshold: Int, onHand: Int)] {
        let liveItems = items.filter { $0.deletedAt == nil }
        var result: [(ProductRecord, Int, Int)] = []
        for product in products where product.deletedAt == nil {
            let onHand = liveItems.filter {
                $0.productId == product.id && $0.status != .finished && $0.status != .wishlist
            }.count
            let threshold = Self.threshold(
                productId: product.id,
                productThreshold: product.lowStockThreshold,
                productTaxonomyId: product.taxonomyId,
                categoryThresholds: categoryThresholds,
                parentByNode: parentByNode)
            if onHand < threshold {
                result.append((product, threshold, onHand))
            }
        }
        return result.map { (product: $0.0, threshold: $0.1, onHand: $0.2) }
            .sorted {
                $0.product.name.localizedCaseInsensitiveCompare($1.product.name)
                    == .orderedAscending
            }
    }
}

/// One line the restock flow proposes for a shopping list.
public struct RestockDraft: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// On-hand bottles are below the threshold (finished bottles are
        /// the usual driver — they no longer count as stock).
        case lowStock
        /// A chosen recipe (or menu) calls for this and nothing on hand
        /// covers it.
        case missingIngredient(recipeId: String)
    }

    public let taxonomyId: String?
    public let label: String
    public let reason: Reason

    public init(taxonomyId: String?, label: String, reason: Reason) {
        self.taxonomyId = taxonomyId
        self.label = label
        self.reason = reason
    }
}

extension AppDatabase {
    /// Builds restock drafts: one per low-stock product, plus one per
    /// missing ingredient of the chosen recipes. Drafts for the same
    /// taxonomy id merge (low stock wins over a missing-ingredient note,
    /// since the bottle covers both needs).
    public func restockDrafts(chosenRecipeIds: [String]) throws -> [RestockDraft] {
        try dbWriter.read { db in
            let productRows = try Row.fetchAll(
                db,
                sql:
                    "SELECT id, taxonomyId, name, lowStockThreshold FROM product WHERE deletedAt IS NULL"
            )
            let itemRows = try Row.fetchAll(
                db, sql: "SELECT productId, status FROM inventoryItem WHERE deletedAt IS NULL")
            let thresholdRows = try Row.fetchAll(
                db, sql: "SELECT taxonomyId, threshold FROM stockThreshold")
            let parentRows = try Row.fetchAll(
                db, sql: "SELECT id, parentId FROM taxonomyNode")

            var categoryThresholds: [String: Int] = [:]
            for row in thresholdRows {
                categoryThresholds[row["taxonomyId"] as String] = row["threshold"] as Int
            }
            var parentByNode: [String: String?] = [:]
            for row in parentRows {
                parentByNode[row["id"] as String] = row["parentId"] as String?
            }

            let products = productRows.map { row -> ProductRecord in
                ProductRecord(
                    id: row["id"],
                    taxonomyId: row["taxonomyId"],
                    name: row["name"],
                    lowStockThreshold: row["lowStockThreshold"],
                    createdAt: 0,
                    modifiedAt: 0)
            }
            let items = itemRows.map { row -> InventoryItemRecord in
                InventoryItemRecord(
                    id: "",
                    productId: row["productId"],
                    status: InventoryItemRecord.Status(rawValue: row["status"]) ?? .unopened,
                    createdAt: 0,
                    modifiedAt: 0)
            }

            var drafts: [RestockDraft] = []
            for low in StockLogic.lowStockProducts(
                products: products,
                items: items,
                categoryThresholds: categoryThresholds,
                parentByNode: parentByNode)
            {
                drafts.append(
                    RestockDraft(
                        taxonomyId: low.product.taxonomyId,
                        label: low.product.name,
                        reason: .lowStock))
            }

            // Missing ingredients: for each chosen recipe, every required
            // (non-optional, non-garnish, non-nil-id) ingredient that no
            // on-hand bottle covers. A specific bottle satisfies a broader
            // ask (decision 0012 keeps the taxonomy direction: descendant
            // covers ancestor, never the reverse).
            let coveredNodes = Set(
                items
                    .filter { $0.status != .finished && $0.status != .wishlist }
                    .compactMap { item -> String? in
                        products.first { $0.id == item.productId }?.taxonomyId
                    })
            for recipeId in chosenRecipeIds {
                let ingredientRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT taxonomyId, label, amount, unit
                        FROM recipeIngredient
                        JOIN recipe ON recipe.id = recipeIngredient.recipeId
                        WHERE recipe.id = ?
                          AND recipe.deletedAt IS NULL
                          AND (isOptional = 0 AND isGarnish = 0)
                          AND taxonomyId IS NOT NULL
                        ORDER BY recipeIngredient.ordinal
                        """,
                    arguments: [recipeId])
                for row in ingredientRows {
                    let requested: String = row["taxonomyId"]
                    if coveredContains(coveredNodes, requested, parentByNode) {
                        continue
                    }
                    let node = try Row.fetchOne(
                        db, sql: "SELECT name FROM taxonomyNode WHERE id = ?",
                        arguments: [requested])
                    drafts.append(
                        RestockDraft(
                            taxonomyId: requested,
                            label: (node?["name"] as String?) ?? (row["label"] as String?)
                                ?? requested,
                            reason: .missingIngredient(recipeId: recipeId)))
                }
            }

            // Merge duplicates by taxonomy id, low-stock first.
            var seen: [String: RestockDraft] = [:]
            var ordered: [RestockDraft] = []
            for draft in drafts {
                guard let key = draft.taxonomyId else {
                    ordered.append(draft)
                    continue
                }
                if let existing = seen[key] {
                    if existing.reason != .lowStock && draft.reason == .lowStock {
                        let index = ordered.firstIndex { $0 == existing } ?? ordered.count
                        if index < ordered.count {
                            ordered[index] = draft
                        }
                        seen[key] = draft
                    }
                } else {
                    seen[key] = draft
                    ordered.append(draft)
                }
            }
            return ordered
        }
    }

    /// True when any covered node satisfies the requested node; the rule
    /// lives in `TaxonomyCoverage` so deduction shares it.
    private func coveredContains(
        _ covered: Set<String>,
        _ requested: String,
        _ parentByNode: [String: String?]
    ) -> Bool {
        TaxonomyCoverage.covers(covered, requested, parentByNode: parentByNode)
    }

    /// Adds restock drafts to a list, skipping entries the list already
    /// has unchecked (by taxonomy id, or by label when no id). Returns the
    /// number of items actually added.
    @discardableResult
    public func addRestockDrafts(
        _ drafts: [RestockDraft],
        toListId listId: String
    ) throws -> Int {
        let now = Date().timeIntervalSince1970
        var added = 0
        try dbWriter.write { db in
            let existing = try Row.fetchAll(
                db,
                sql: """
                    SELECT taxonomyId, label FROM shoppingListItem
                    WHERE listId = ? AND deletedAt IS NULL AND isChecked = 0
                    """,
                arguments: [listId])
            var existingIds = Set(existing.compactMap { $0["taxonomyId"] as String? })
            var existingLabels = Set(existing.compactMap { $0["label"] as String? })
            let maxOrdinal =
                try Int.fetchOne(
                    db,
                    sql:
                        "SELECT COALESCE(MAX(ordinal), -1) FROM shoppingListItem WHERE listId = ? AND deletedAt IS NULL",
                    arguments: [listId]) ?? -1
            var ordinal = maxOrdinal + 1
            for draft in drafts {
                let duplicate =
                    (draft.taxonomyId != nil && existingIds.contains(draft.taxonomyId!))
                    || existingLabels.contains(draft.label)
                guard !duplicate else { continue }
                try db.execute(
                    sql: """
                        INSERT INTO shoppingListItem
                            (id, listId, taxonomyId, label, isChecked, ordinal,
                             createdAt, modifiedAt)
                        VALUES (?, ?, ?, ?, 0, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString, listId, draft.taxonomyId, draft.label,
                        ordinal, now, now,
                    ])
                if let id = draft.taxonomyId {
                    existingIds.insert(id)
                }
                existingLabels.insert(draft.label)
                ordinal += 1
                added += 1
            }
        }
        return added
    }
}
