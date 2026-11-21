import Foundation
import GRDB
import Testing

@testable import BarCore

/// User-defined substitutions live in the `userSubstitution` table
/// (schema v5) and merge over the bundled curated table: a user entry
/// wins for its exact pair, everything else from the bundle stays.
/// Nodes are validated against the taxonomy at save time (decision
/// 0011's pattern: plain strings in the schema, validation at the edge).
@Suite
struct SubstitutionStoreTests {
    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.setupTaxonomy()
        return db
    }

    private func taxonomyIdSet(_ db: AppDatabase) throws -> Set<String> {
        Set(
            try db.dbWriter.read { db in
                try Set(String.fetchAll(db, sql: "SELECT id FROM taxonomyNode"))
            })
    }

    @Test func saveAndLoadRoundTrip() throws {
        let db = try makeDatabase()
        let ids = try taxonomyIdSet(db)
        let genever = try #require(ids.first { $0.hasPrefix("spirit.gin.genever") })
        let gin = try #require(ids.first { $0 == "spirit.gin" })

        let first = UserSubstitutionRecord(
            id: "us-1", fromNode: genever, toNode: gin,
            closeness: .changesTheDrink, note: "my choice",
            createdAt: 100, modifiedAt: 100)
        try db.saveUserSubstitution(first)
        let second = UserSubstitutionRecord(
            id: "us-2", fromNode: "mixer.syrup.demerara", toNode: "mixer.syrup.simple",
            closeness: .close, note: nil, createdAt: 100, modifiedAt: 100)
        try db.saveUserSubstitution(second)

        let loaded = try db.loadUserSubstitutions()
        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.id == "us-1" && $0.fromNode == genever })
        #expect(loaded.contains { $0.id == "us-2" && $0.closeness == .close })
    }

    @Test func softDeletedRowsDropOutOfLoad() throws {
        let db = try makeDatabase()
        let first = UserSubstitutionRecord(
            id: "us-1", fromNode: "spirit.gin.genever", toNode: "spirit.gin",
            closeness: .close, note: nil, createdAt: 100, modifiedAt: 100)
        try db.saveUserSubstitution(first)
        try db.softDeleteUserSubstitution("us-1")
        let loaded = try db.loadUserSubstitutions()
        #expect(loaded.isEmpty)
    }

    @Test func saveRefusesUnknownTaxonomyNode() throws {
        let db = try makeDatabase()
        #expect(throws: SubstitutionLoader.ValidationError.self) {
            try db.saveUserSubstitution(
                UserSubstitutionRecord(
                    id: "us-x", fromNode: "spirit.not-a-node", toNode: "spirit.gin",
                    closeness: .close, note: nil, createdAt: 100, modifiedAt: 100))
        }
    }

    @Test func saveRefusesSelfLoop() throws {
        let db = try makeDatabase()
        #expect(throws: SubstitutionLoader.ValidationError.self) {
            try db.saveUserSubstitution(
                UserSubstitutionRecord(
                    id: "us-y", fromNode: "spirit.gin", toNode: "spirit.gin",
                    closeness: .close, note: nil, createdAt: 100, modifiedAt: 100))
        }
    }

    @Test func mergePrefersUserEntriesPerPair() throws {
        let bundled = [
            Substitution(
                from: "spirit.gin.genever", to: "spirit.gin",
                closeness: .changesTheDrink, note: "bundled note"),
            Substitution(
                from: "spirit.whiskey.american.rye",
                to: "spirit.whiskey.american.bourbon",
                closeness: .changesTheDrink, note: "bundled rye"),
        ]
        let user = [
            Substitution(
                from: "spirit.gin.genever", to: "spirit.gin",
                closeness: .close, note: "user note"),
            Substitution(
                from: "liqueur.bitter.aperitivo", to: "liqueur.bitter.amaro",
                closeness: .close, note: "user only"),
        ]
        let merged = SubstitutionMerging.merge(bundled: bundled, user: user)
        // Three entries: one user-overridden pair, one user-only pair, one
        // bundled pair the user did not touch.
        #expect(merged.count == 3)
        let genever = merged.first { $0.from == "spirit.gin.genever" }
        #expect(genever?.closeness == .close)
        #expect(genever?.note == "user note")
        #expect(merged.contains { $0.from == "liqueur.bitter.aperitivo" })
        #expect(
            merged.contains {
                $0.from == "spirit.whiskey.american.rye" && $0.note == "bundled rye"
            })
    }

    @Test func storeSubstitutionsConvertToMatchingType() throws {
        let db = try makeDatabase()
        try db.saveUserSubstitution(
            UserSubstitutionRecord(
                id: "us-1", fromNode: "mixer.syrup.demerara",
                toNode: "mixer.syrup.simple", closeness: .close, note: "in a pinch",
                createdAt: 100, modifiedAt: 100))
        let asSubstitutions = try db.userSubstitutionValues()
        #expect(
            asSubstitutions == [
                Substitution(
                    from: "mixer.syrup.demerara", to: "mixer.syrup.simple",
                    closeness: .close, note: "in a pinch")
            ])
    }
}
