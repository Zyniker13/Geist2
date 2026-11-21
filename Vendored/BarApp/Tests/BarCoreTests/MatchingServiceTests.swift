import Foundation
import GRDB
import Testing

@testable import BarCore

@Suite
struct MatchingServiceTests {
    // MARK: - Fixtures

    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.setupTaxonomy()
        return db
    }

    /// Writes recipes in ONE replaceLibraryRecipes call — the call replaces
    /// the whole test module, so a second call would drop earlier recipes.
    private func recipes(
        _ db: AppDatabase,
        _ list: [(id: String, ingredients: [(taxonomy: String?, optional: Bool, garnish: Bool)])]
    ) throws {
        try db.replaceLibraryRecipes(
            list.enumerated().map { index, entry in
                RecipeRecord(
                    id: entry.id,
                    name: entry.id,
                    instructions: "Build.",
                    tags: ["classic"],
                    ingredients: entry.ingredients.enumerated().map {
                        ordinal, line in
                        RecipeIngredientRecord(
                            ordinal: ordinal,
                            taxonomyId: line.taxonomy,
                            label: line.taxonomy ?? "unnamed",
                            amount: "1",
                            unit: "oz",
                            isOptional: line.optional,
                            isGarnish: line.garnish)
                    })
            },
            moduleId: "test-module", moduleVersion: 1, moduleTitle: "Test")
    }

    private func product(_ db: AppDatabase, id: String, taxonomyId: String) throws {
        let now = Date().timeIntervalSince1970
        try db.saveProduct(
            ProductRecord(
                id: id, taxonomyId: taxonomyId, name: id,
                createdAt: now, modifiedAt: now))
        try db.saveInventoryItem(
            InventoryItemRecord(
                id: "bottle-\(id)", productId: id, status: .unopened,
                createdAt: now, modifiedAt: now))
    }

    /// The substitution fixture: rye can stand in as bourbon's ask, the
    /// other way around, and simple syrup can stand in as demerara's ask.
    private func substitutions() -> [Substitution] {
        [
            Substitution(
                from: "spirit.whiskey.american.rye",
                to: "spirit.whiskey.american.bourbon",
                closeness: .changesTheDrink,
                note: "Sweeter and softer; the rye's edge is gone."),
            Substitution(
                from: "mixer.syrup.demerara",
                to: "mixer.syrup.simple",
                closeness: .close,
                note: "Same sweetness, less molasses depth."),
        ]
    }

    // MARK: Classification

    @Test func makeableNowWhenTheBarCoversEveryRequiredNode() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "gin-sour",
                    ingredients: [
                        (taxonomy: "spirit.gin", optional: false, garnish: false),
                        (taxonomy: "mixer.syrup.simple", optional: false, garnish: false),
                    ]
                )
            ])
        try product(db, id: "p-gin", taxonomyId: "spirit.gin.gin.london-dry")
        try product(db, id: "p-syrup", taxonomyId: "mixer.syrup.simple")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(state == .makeableNow)
    }

    @Test func specificCoversBroadButNotTheReverse() throws {
        // The bar holds a broad gin node; it answers any broader ask but
        // never a more specific one.
        let bar = BarStock(coveredNodes: ["spirit.gin.gin"])
        let parents: [String: String?] = [
            "spirit": nil,
            "spirit.gin": "spirit",
            "spirit.gin.gin": "spirit.gin",
            "spirit.gin.gin.london-dry": "spirit.gin.gin",
            "spirit.whiskey": "spirit",
            "spirit.whiskey.american.rye": "spirit.whiskey.american",
            "spirit.whiskey.american": "spirit.whiskey",
        ]
        #expect(
            MatchingService.covers(
                bar: bar, requested: "spirit.gin", parentByNode: parents))
        #expect(
            !MatchingService.covers(
                bar: bar, requested: "spirit.gin.gin.london-dry", parentByNode: parents))
        #expect(
            !MatchingService.covers(
                bar: bar, requested: "spirit.whiskey.american.rye", parentByNode: parents))
    }

    @Test func oneAwayWhenExactlyOneRequirementIsMissing() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "old-fashioned",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false),
                        (taxonomy: "mixer.syrup.simple", optional: false, garnish: false),
                    ]
                )
            ])
        try product(db, id: "p-syrup", taxonomyId: "mixer.syrup.simple")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(state == .oneAway(missing: "spirit.whiskey.american.rye"))
    }

    @Test func withSubstitutionWhenEveryGapHasOne() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "batched",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false),
                        (taxonomy: "mixer.syrup.demerara", optional: false, garnish: false),
                    ]
                )
            ])
        try product(db, id: "p-bourbon", taxonomyId: "spirit.whiskey.american.bourbon")
        try product(db, id: "p-simple", taxonomyId: "mixer.syrup.simple")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(
            state
                == .withSubstitution(substitutions: [
                    (
                        missing: "spirit.whiskey.american.rye",
                        sub: Substitution(
                            from: "spirit.whiskey.american.rye",
                            to: "spirit.whiskey.american.bourbon",
                            closeness: .changesTheDrink,
                            note: "Sweeter and softer; the rye's edge is gone.")
                    ),
                    (
                        missing: "mixer.syrup.demerara",
                        sub: Substitution(
                            from: "mixer.syrup.demerara",
                            to: "mixer.syrup.simple",
                            closeness: .close,
                            note: "Same sweetness, less molasses depth.")
                    ),
                ]))
    }

    @Test func shortOfIngredientsWhenSomeGapHasNoSubstitution() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "two-away",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false),
                        (taxonomy: "liqueur.bitter.aperitivo", optional: false, garnish: false),
                    ]
                )
            ])
        try product(db, id: "p-bourbon", taxonomyId: "spirit.whiskey.american.bourbon")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(
            state
                == .shortOfIngredients(missing: [
                    "spirit.whiskey.american.rye", "liqueur.bitter.aperitivo",
                ]))
    }

    @Test func oneAwayWinsOverSubstitution() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "rye-drink",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false)
                    ]
                )
            ])
        try product(db, id: "p-bourbon", taxonomyId: "spirit.whiskey.american.bourbon")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(state == .oneAway(missing: "spirit.whiskey.american.rye"))
    }

    @Test func optionalIngredientsNeverBlock() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "flexible",
                    ingredients: [
                        (taxonomy: "spirit.gin", optional: false, garnish: false),
                        (taxonomy: "mixer.soda.soda-water", optional: true, garnish: false),
                    ]
                )
            ])
        try product(db, id: "p-gin", taxonomyId: "spirit.gin.gin")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(state == .makeableNow)
    }

    @Test func garnishesBlockWhenMissing() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "garnished",
                    ingredients: [
                        (taxonomy: "spirit.gin", optional: false, garnish: false),
                        (taxonomy: "pantry.garnish.lemon-twist", optional: false, garnish: true),
                    ]
                )
            ])
        try product(db, id: "p-gin", taxonomyId: "spirit.gin.gin")
        let bar = try MatchingService.loadBar(db: db)
        let needs = try MatchingService.loadNeeds(db: db)
        let state = try MatchingService.classify(
            needs: needs[0], bar: bar, substitutions: substitutions(),
            parentByNode: MatchingService.parentMap(db: db))
        #expect(state == .oneAway(missing: "pantry.garnish.lemon-twist"))
    }

    @Test func recipeWithNoRequirementsIsMakeableNow() throws {
        let needs = RecipeNeeds(recipeId: "empty", requiredNodes: [])
        let state = try MatchingService.classify(
            needs: needs, bar: BarStock(coveredNodes: []), substitutions: [],
            parentByNode: [:])
        #expect(state == .makeableNow)
    }

    // MARK: Summary and unlocks

    @Test func unlockCountsRankNodesByHowManyRecipesTheyUnlock() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "a",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false)
                    ]
                ),
                (
                    id: "b",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false),
                        (taxonomy: "liqueur.bitter.aperitivo", optional: false, garnish: false),
                    ]
                ),
            ])
        let summary = MatchingService.summarize(
            try MatchingService.loadNeeds(db: db),
            bar: BarStock(coveredNodes: []),
            substitutions: [],
            parentByNode: try MatchingService.parentMap(db: db))
        // Buying rye unlocks "a" outright and brings "b" down to one-away;
        // buying aperitivo only helps "b". Rye ranks first.
        #expect(summary.unlockCounts.first?.nodeId == "spirit.whiskey.american.rye")
        #expect(summary.unlockCounts.first?.count == 2)
        #expect(summary.oneAway.count == 1)
        #expect(summary.shortOfIngredients.count == 1)
    }

    // MARK: Bar loading

    @Test func loadBarExcludesFinishedBottles() throws {
        let db = try makeDatabase()
        try product(db, id: "p-done", taxonomyId: "spirit.gin.gin")
        try db.markFinished(itemId: "bottle-p-done")
        try product(db, id: "p-live", taxonomyId: "mixer.syrup.simple")
        let bar = try MatchingService.loadBar(db: db)
        #expect(bar.coveredNodes == ["mixer.syrup.simple"])
    }

    // MARK: Needs loading

    @Test func loadNeedsSkipsDeletedRecipesOptionalAndUntypedIngredients() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "kept",
                    ingredients: [
                        (taxonomy: "spirit.gin", optional: false, garnish: false),
                        (taxonomy: nil, optional: false, garnish: false),
                        (taxonomy: "mixer.soda.soda-water", optional: true, garnish: false),
                    ]
                ),
                (
                    id: "gone",
                    ingredients: [
                        (taxonomy: "spirit.gin", optional: false, garnish: false)
                    ]
                ),
            ])
        try db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE recipe SET deletedAt = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, "gone"])
        }
        let needs = try MatchingService.loadNeeds(db: db)
        #expect(needs.count == 1)
        #expect(needs[0].recipeId == "kept")
        #expect(needs[0].requiredNodes == ["spirit.gin"])
    }

    /// Water comes from the tap: an ask under the water subtree is never a
    /// bar requirement, so a recipe whose only other asks are covered stays
    /// makeable even with no water product in the cellar. (The Old
    /// Fashioned in the bundled library asks for a teaspoon of water.)
    @Test func waterAsksAreNeverBarRequirements() throws {
        let db = try makeDatabase()
        try recipes(
            db,
            [
                (
                    id: "oldfashioned",
                    ingredients: [
                        (taxonomy: "spirit.whiskey.american.rye", optional: false, garnish: false),
                        (taxonomy: "pantry.garnish.sugar", optional: false, garnish: false),
                        (taxonomy: "bitters.aromatic", optional: false, garnish: false),
                        (taxonomy: "mixer.water.still", optional: false, garnish: false),
                    ]
                )
            ])
        try product(db, id: "rye", taxonomyId: "spirit.whiskey.american.rye")
        try product(db, id: "sugar", taxonomyId: "pantry.garnish.sugar")
        try product(db, id: "bitters", taxonomyId: "bitters.aromatic")

        let bar = try MatchingService.loadBar(db: db)
        let parents = try MatchingService.parentMap(db: db)
        let summary = MatchingService.summarize(
            try MatchingService.loadNeeds(db: db), bar: bar,
            substitutions: [], parentByNode: parents)
        #expect(summary.makeableNow == ["oldfashioned"])
    }
}
