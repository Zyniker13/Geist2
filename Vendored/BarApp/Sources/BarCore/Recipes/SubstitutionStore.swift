import Foundation
import GRDB

/// A user-defined substitution: one taxonomy node standing in for another,
/// stored in the `userSubstitution` table (schema v5). Targets are plain
/// stable strings per decision 0011; the store validates them against the
/// taxonomy when saving, so everything the table holds is resolvable.
public struct UserSubstitutionRecord: Sendable, Equatable {
    public let id: String
    public let fromNode: String
    public let toNode: String
    public let closeness: SubstitutionCloseness
    public let note: String?
    public let createdAt: Double
    public let modifiedAt: Double
    public let deletedAt: Double?

    public init(
        id: String,
        fromNode: String,
        toNode: String,
        closeness: SubstitutionCloseness,
        note: String? = nil,
        createdAt: Double,
        modifiedAt: Double,
        deletedAt: Double? = nil
    ) {
        self.id = id
        self.fromNode = fromNode
        self.toNode = toNode
        self.closeness = closeness
        self.note = note
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

extension UserSubstitutionRecord: FetchableRecord {
    public init(row: Row) {
        id = row["id"]
        fromNode = row["fromNode"]
        toNode = row["toNode"]
        closeness = SubstitutionCloseness(rawValue: row["closeness"])!
        note = row["note"]
        createdAt = row["createdAt"]
        modifiedAt = row["modifiedAt"]
        deletedAt = row["deletedAt"]
    }

    static let columns = """
        id, fromNode, toNode, closeness, note, createdAt, modifiedAt, deletedAt
        """
}

extension AppDatabase {
    /// Saves one user substitution, replacing any prior version of the
    /// same id. The store stamps the times itself and validates both nodes
    /// against the taxonomy at the write, so stored rows always resolve.
    public func saveUserSubstitution(_ record: UserSubstitutionRecord) throws {
        let now = Date().timeIntervalSince1970
        try dbWriter.write { db in
            let known =
                try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS (SELECT 1 FROM taxonomyNode WHERE id = ?)",
                    arguments: [record.fromNode]) ?? false
            guard known else {
                throw SubstitutionLoader.ValidationError.unknownNode(record.fromNode)
            }
            let targetKnown =
                try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS (SELECT 1 FROM taxonomyNode WHERE id = ?)",
                    arguments: [record.toNode]) ?? false
            guard targetKnown else {
                throw SubstitutionLoader.ValidationError.unknownNode(record.toNode)
            }
            guard record.fromNode != record.toNode else {
                throw SubstitutionLoader.ValidationError.selfLoop(record.fromNode)
            }
            try db.execute(
                sql: """
                    INSERT INTO userSubstitution
                        (id, fromNode, toNode, closeness, note,
                         createdAt, modifiedAt, deletedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        fromNode = excluded.fromNode,
                        toNode = excluded.toNode,
                        closeness = excluded.closeness,
                        note = excluded.note,
                        modifiedAt = excluded.modifiedAt,
                        deletedAt = excluded.deletedAt
                    """,
                arguments: [
                    record.id, record.fromNode, record.toNode,
                    record.closeness.rawValue, record.note,
                    record.createdAt, now, record.deletedAt,
                ])
        }
    }

    /// Soft-deletes one user substitution by id.
    public func softDeleteUserSubstitution(_ id: String) throws {
        let now = Date().timeIntervalSince1970
        try dbWriter.write { db in
            try db.execute(
                sql: "UPDATE userSubstitution SET deletedAt = ? WHERE id = ?",
                arguments: [now, id])
        }
    }

    /// Every live (non-deleted) user substitution, oldest insert first.
    public func loadUserSubstitutions() throws -> [UserSubstitutionRecord] {
        try dbWriter.read { db in
            try UserSubstitutionRecord
                .fetchAll(
                    db,
                    sql: """
                        SELECT \(UserSubstitutionRecord.columns)
                            FROM userSubstitution
                        WHERE deletedAt IS NULL
                        ORDER BY createdAt, id
                        """)
        }
    }

    /// The live user substitutions as matching-engine values.
    public func userSubstitutionValues() throws -> [Substitution] {
        try loadUserSubstitutions().map { record in
            Substitution(
                from: record.fromNode, to: record.toNode,
                closeness: record.closeness, note: record.note ?? "")
        }
    }
}

/// Merges the bundled curated table with the user's own entries: for any
/// (from, to) pair the user defined, the user's entry wins; every other
/// bundled entry stays; user-only entries are added.
public enum SubstitutionMerging {
    public static func merge(
        bundled: [Substitution], user: [Substitution]
    ) -> [Substitution] {
        var userPairs: [Substitution] = []
        var overridden = Set<SubstitutionPairKey>()
        for entry in user {
            userPairs.append(entry)
            overridden.insert(SubstitutionPairKey(from: entry.from, to: entry.to))
        }
        var merged: [Substitution] = userPairs
        for entry in bundled
        where !overridden.contains(SubstitutionPairKey(from: entry.from, to: entry.to)) {
            merged.append(entry)
        }
        return merged
    }

    /// A from/to pair, hashable so overrides are cheap to spot.
    private struct SubstitutionPairKey: Hashable {
        let from: String
        let to: String
    }
}
