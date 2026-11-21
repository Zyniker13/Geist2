import Foundation
import GRDB

/// A taxonomy node as read back from the database, in browse order.
public struct TaxonomyNodeRow: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let parentId: String?
    public let kind: TaxonomyNodeData.Kind
    public let name: String
    public let sortOrder: Int

    public init(
        id: String,
        parentId: String?,
        kind: TaxonomyNodeData.Kind,
        name: String,
        sortOrder: Int
    ) {
        self.id = id
        self.parentId = parentId
        self.kind = kind
        self.name = name
        self.sortOrder = sortOrder
    }
}

extension AppDatabase {
    /// Replaces the stored taxonomy with `document` in one transaction.
    ///
    /// The reference tables are replaceable by design (decision 0004): the
    /// bundled document is the source of truth, and a later version simply
    /// writes over the stored copy. The FTS index follows through the
    /// triggers created beside the tables, so search stays in step without
    /// extra code here. The document must validate; an invalid document
    /// throws and leaves the stored taxonomy untouched.
    public func replaceTaxonomy(with document: TaxonomyDocument) throws {
        let issues = document.validate()
        guard issues.isEmpty else { throw TaxonomyValidationError(issues: issues) }
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM taxonomyAlias")
            try db.execute(sql: "DELETE FROM taxonomyNode")
            for (index, node) in document.nodes.enumerated() {
                // detailFields ride in a JSON array column: the set of
                // fields varies per category, so columns would not fit.
                let detailFieldsJSON =
                    node.detailFields.isEmpty
                    ? nil
                    : try String(
                        decoding: JSONEncoder().encode(node.detailFields),
                        as: UTF8.self
                    )
                // The search index reads aliases from this space-joined
                // column; the relational alias rows below remain the
                // queryable form. Both are written here, in one
                // transaction, so the two copies cannot drift.
                let joinedAliases = node.aliases.joined(separator: " ")
                try db.execute(
                    sql: """
                        INSERT INTO taxonomyNode
                            (id, parentId, kind, name, sortOrder, detailFields, notes, aliases)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        node.id,
                        node.parentId,
                        node.kind.rawValue,
                        node.name,
                        index,
                        detailFieldsJSON,
                        node.notes,
                        node.aliases.isEmpty ? nil : joinedAliases,
                    ]
                )
                for alias in node.aliases {
                    try db.execute(
                        sql: "INSERT INTO taxonomyAlias (nodeId, alias) VALUES (?, ?)",
                        arguments: [node.id, alias]
                    )
                }
            }
            try db.execute(sql: "DELETE FROM taxonomyVersion")
            try db.execute(
                sql: "INSERT INTO taxonomyVersion (id, version) VALUES (1, ?)",
                arguments: [document.version]
            )
        }
    }

    /// The version of the stored taxonomy, or nil when no taxonomy has
    /// been loaded yet.
    public func storedTaxonomyVersion() throws -> Int? {
        try dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM taxonomyVersion WHERE id = 1")
        }
    }

    /// Loads the bundled taxonomy when the stored version is behind, so
    /// taxonomy-dependent queries always have current chains regardless of
    /// which caller opened the database first.
    public func setupTaxonomyIfNeeded() throws {
        let document = try TaxonomyLoader.bundledDocument()
        if try storedTaxonomyVersion() != document.version {
            try replaceTaxonomy(with: document)
        }
    }

    /// One node by its stable id, or nil when no taxonomy is loaded or the
    /// id is unknown.
    public func taxonomyNode(id: String) throws -> TaxonomyNodeRow? {
        try dbWriter.read { db in
            try taxonomyNode(id: id, db: db)
        }
    }

    /// The children of `parentId` in browse order, or the root nodes when
    /// `parentId` is nil.
    public func taxonomyChildren(of parentId: String?) throws -> [TaxonomyNodeRow] {
        try dbWriter.read { db in
            if let parentId {
                let parent = try taxonomyNode(id: parentId, db: db)
                guard parent != nil else { return [] }
            }
            return try taxonomyChildren(of: parentId, db: db)
        }
    }

    /// Nodes whose name or alias matches the search terms, best matches
    /// first. A term matches as a prefix of a word (so "verm" finds
    /// vermouth); every term must match somewhere in the same node or one
    /// of its aliases.
    public func taxonomyNodes(matching query: String) throws -> [TaxonomyNodeRow] {
        let terms =
            query
            .split { $0.isWhitespace }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        // Each term becomes a quoted FTS prefix term; quoting keeps the
        // user's punctuation from being read as FTS syntax.
        let match = terms.map { "\"\($0)\"*" }.joined(separator: " ")
        return try dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT node.id, node.parentId, node.kind, node.name, node.sortOrder
                    FROM taxonomyNode AS node
                    JOIN taxonomyFts ON taxonomyFts.rowid = node.rowid
                    WHERE taxonomyFts MATCH ?
                    ORDER BY node.sortOrder
                    """,
                arguments: [match]
            )
            return rows.map { row in
                TaxonomyNodeRow(
                    id: row["id"],
                    parentId: row["parentId"],
                    kind: TaxonomyNodeData.Kind(rawValue: row["kind"]) ?? .ingredient,
                    name: row["name"],
                    sortOrder: row["sortOrder"]
                )
            }
        }
    }

    // MARK: - Internals (shared by the read APIs above)

    private func taxonomyNode(id: String, db: Database) throws -> TaxonomyNodeRow? {
        try Row.fetchOne(
            db,
            sql: "SELECT id, parentId, kind, name, sortOrder FROM taxonomyNode WHERE id = ?",
            arguments: [id]
        ).map { row in
            TaxonomyNodeRow(
                id: row["id"],
                parentId: row["parentId"],
                kind: TaxonomyNodeData.Kind(rawValue: row["kind"]) ?? .ingredient,
                name: row["name"],
                sortOrder: row["sortOrder"]
            )
        }
    }

    private func taxonomyChildren(of parentId: String?, db: Database) throws
        -> [TaxonomyNodeRow]
    {
        let rows: [Row]
        if let parentId {
            rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, parentId, kind, name, sortOrder FROM taxonomyNode
                    WHERE parentId = ? ORDER BY sortOrder
                    """,
                arguments: [parentId]
            )
        } else {
            rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, parentId, kind, name, sortOrder FROM taxonomyNode
                    WHERE parentId IS NULL ORDER BY sortOrder
                    """
            )
        }
        return rows.map { row in
            TaxonomyNodeRow(
                id: row["id"],
                parentId: row["parentId"],
                kind: TaxonomyNodeData.Kind(rawValue: row["kind"]) ?? .ingredient,
                name: row["name"],
                sortOrder: row["sortOrder"]
            )
        }
    }
}
