import Foundation
import GRDB
import Testing

@testable import BarCore

/// Tests for the versioned taxonomy reference data: the bundled document
/// loads and validates, covers every category the roadmap names, writes
/// into the replaceable reference tables, refuses invalid documents, and
/// answers browse and search queries from the store.
@Suite
struct TaxonomyTests {
    // MARK: - Bundled document

    @Test func bundledDocumentLoadsAndValidates() throws {
        let document = try TaxonomyLoader.bundledDocument()
        #expect(document.version >= 1)
        #expect(!document.nodes.isEmpty)
        let issues = document.validate()
        #expect(
            issues.isEmpty,
            "bundled taxonomy failed validation: \(issues)"
        )
    }

    @Test func bundledDocumentIdsAreUnique() throws {
        let document = try TaxonomyLoader.bundledDocument()
        let ids = document.nodes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func bundledDocumentCoversTheRoadmapCategories() throws {
        let document = try TaxonomyLoader.bundledDocument()
        let ids = Set(document.nodes.map(\.id))
        // Every category the roadmap requires, pinned here so a data edit
        // cannot silently drop one. Whiskey's styles and regions, gin's
        // styles, genever's styles, rum and cane spirits, the agave
        // spirits with tequila and mezcal styles, brandy with cognac
        // grades, vodka's group with baijiu aroma types, liqueurs with the
        // bitter styles, fortified and aromatized wines with sherry styles,
        // bitters, wine, beer, cider and perry, sake grades, non-alcoholic,
        // and mixers and pantry.
        let requiredIds: Set<String> = [
            // Whiskey: scotch styles and regions, Irish styles, American
            // styles, Canadian, Japanese, other.
            "spirit.whiskey",
            "spirit.whiskey.scotch",
            "spirit.whiskey.scotch.single-malt",
            "spirit.whiskey.scotch.blended-malt",
            "spirit.whiskey.scotch.blended",
            "spirit.whiskey.scotch.single-grain",
            "spirit.whiskey.scotch.region.speyside",
            "spirit.whiskey.scotch.region.islay",
            "spirit.whiskey.scotch.region.highlands",
            "spirit.whiskey.scotch.region.lowlands",
            "spirit.whiskey.scotch.region.campbeltown",
            "spirit.whiskey.irish",
            "spirit.whiskey.irish.single-pot-still",
            "spirit.whiskey.irish.single-malt",
            "spirit.whiskey.irish.single-grain",
            "spirit.whiskey.irish.blended",
            "spirit.whiskey.american",
            "spirit.whiskey.american.bourbon",
            "spirit.whiskey.american.tennessee",
            "spirit.whiskey.american.rye",
            "spirit.whiskey.american.wheat",
            "spirit.whiskey.american.corn",
            "spirit.whiskey.american.single-malt",
            "spirit.whiskey.american.light",
            "spirit.whiskey.canadian.canadian",
            "spirit.whiskey.japanese.japanese",
            "spirit.whiskey.other.other",
            // Gin and genever.
            "spirit.gin.gin",
            "spirit.gin.gin.london-dry",
            "spirit.gin.gin.plymouth",
            "spirit.gin.gin.old-tom",
            "spirit.gin.gin.navy-strength",
            "spirit.gin.gin.contemporary",
            "spirit.gin.genever",
            "spirit.gin.genever.oude",
            "spirit.gin.genever.jonge",
            "spirit.gin.genever.korenwijn",
            // Rum and cane spirits.
            "spirit.rum",
            "spirit.rum.pot-still",
            "spirit.rum.column-still",
            "spirit.rum.blended",
            "spirit.rum.rhum-agricole",
            "spirit.rum.cachaca",
            "spirit.rum.aged",
            "spirit.rum.overproof",
            "spirit.rum.spiced",
            // Agave spirits.
            "spirit.agave.tequila",
            "spirit.agave.tequila.blanco",
            "spirit.agave.tequila.reposado",
            "spirit.agave.tequila.anejo",
            "spirit.agave.tequila.extra-anejo",
            "spirit.agave.tequila.cristalino",
            "spirit.agave.mezcal",
            "spirit.agave.mezcal.mezcal",
            "spirit.agave.mezcal.artesanal",
            "spirit.agave.mezcal.ancestral",
            "spirit.agave.raicilla",
            "spirit.agave.bacanora",
            "spirit.agave.sotol",
            // Brandy.
            "spirit.brandy.cognac",
            "spirit.brandy.cognac.vs",
            "spirit.brandy.cognac.vsop",
            "spirit.brandy.cognac.xo",
            "spirit.brandy.cognac.xxo",
            "spirit.brandy.armagnac",
            "spirit.brandy.calvados",
            "spirit.brandy.apple-brandy",
            "spirit.brandy.pisco",
            "spirit.brandy.grappa",
            "spirit.brandy.pomace-brandy",
            "spirit.brandy.eau-de-vie",
            "spirit.brandy.grape-brandy",
            // Vodka, aquavit, and other spirits.
            "spirit.vodka.vodka",
            "spirit.vodka.vodka.grain",
            "spirit.vodka.vodka.potato",
            "spirit.vodka.vodka.grape",
            "spirit.vodka.vodka.corn",
            "spirit.vodka.vodka.other",
            "spirit.vodka.aquavit",
            "spirit.absinthe",
            "spirit.vodka.pastis",
            "spirit.vodka.anise-other",
            "spirit.vodka.baijiu",
            "spirit.vodka.baijiu.strong-aroma",
            "spirit.vodka.baijiu.sauce-aroma",
            "spirit.vodka.baijiu.light-aroma",
            "spirit.vodka.baijiu.rice-aroma",
            "spirit.vodka.baijiu.other",
            "spirit.vodka.shochu",
            "spirit.vodka.soju",
            "spirit.vodka.arrack",
            // Liqueurs.
            "liqueur.orange",
            "liqueur.herbal",
            "liqueur.bitter",
            "liqueur.bitter.aperitivo",
            "liqueur.bitter.alpine",
            "liqueur.bitter.fernet",
            "liqueur.bitter.other-style",
            "liqueur.anise",
            "liqueur.coffee",
            "liqueur.cream",
            "liqueur.nut",
            "liqueur.fruit",
            "liqueur.cacao",
            "liqueur.floral",
            "liqueur.other",
            // Fortified and aromatized wines.
            "fortified-wine.vermouth",
            "fortified-wine.vermouth.dry",
            "fortified-wine.vermouth.blanc",
            "fortified-wine.vermouth.sweet",
            "fortified-wine.quinquina",
            "fortified-wine.aromatized-other",
            "fortified-wine.sherry",
            "fortified-wine.sherry.fino",
            "fortified-wine.sherry.manzanilla",
            "fortified-wine.sherry.amontillado",
            "fortified-wine.sherry.palo-cortado",
            "fortified-wine.sherry.oloroso",
            "fortified-wine.sherry.cream",
            "fortified-wine.sherry.pedro-ximenez",
            "fortified-wine.port",
            "fortified-wine.madeira",
            "fortified-wine.marsala",
            // Bitters.
            "bitters.aromatic",
            "bitters.orange",
            "bitters.other",
            // Wine, beer, cider, sake.
            "wine",
            "wine.red",
            "wine.white",
            "wine.rose",
            "wine.orange",
            "wine.sparkling",
            "wine.dessert",
            "beer.lager",
            "beer.ale",
            "beer.wheat",
            "beer.stout-porter",
            "beer.sour",
            "beer.other",
            "cider",
            "cider.cider",
            "cider.perry",
            "sake",
            "sake.futsu",
            "sake.honjozo",
            "sake.junmai",
            "sake.ginjo",
            "sake.junmai-ginjo",
            "sake.daiginjo",
            "sake.junmai-daiginjo",
            // Non-alcoholic.
            "non-alcoholic.spirit",
            "non-alcoholic.aperitif",
            "non-alcoholic.beer",
            "non-alcoholic.wine",
            // Mixers and pantry.
            "mixer.juice",
            "mixer.juice.lemon",
            "mixer.juice.lime",
            "mixer.juice.orange",
            "mixer.juice.grapefruit",
            "mixer.juice.pineapple",
            "mixer.juice.cranberry",
            "mixer.juice.apple",
            "mixer.juice.tomato",
            "mixer.juice.other",
            "mixer.syrup",
            "mixer.syrup.simple",
            "mixer.syrup.demerara",
            "mixer.syrup.grenadine",
            "mixer.syrup.orgeat",
            "mixer.syrup.honey",
            "mixer.syrup.agave-nectar",
            "mixer.syrup.gum",
            "mixer.syrup.other",
            "mixer.soda",
            "mixer.soda.soda-water",
            "mixer.soda.tonic",
            "mixer.soda.cola",
            "mixer.soda.ginger-ale",
            "mixer.soda.ginger-beer",
            "mixer.soda.other",
            "mixer.other",
            "pantry",
            "pantry.dairy",
            "pantry.dairy.cream",
            "pantry.dairy.heavy-cream",
            "pantry.dairy.milk",
            "pantry.dairy.butter",
            "pantry.egg",
            "pantry.egg.egg",
            "pantry.egg.egg-white",
            "pantry.egg.egg-yolk",
            "pantry.garnish",
            "pantry.garnish.lemon-twist",
            "pantry.garnish.orange-twist",
            "pantry.garnish.lime-wedge",
            "pantry.garnish.lemon-wedge",
            "pantry.garnish.orange-slice",
            "pantry.garnish.cherry",
            "pantry.garnish.olive",
            "pantry.garnish.mint-sprig",
            "pantry.garnish.cucumber",
            "pantry.garnish.salt",
            "pantry.garnish.sugar",
            "pantry.garnish.nutmeg",
            "pantry.homemade",
        ]
        let missing = requiredIds.subtracting(ids).sorted()
        #expect(missing.isEmpty, "taxonomy is missing: \(missing)")
    }

    @Test func roadmapNamedNodesCarryTheirDetailFieldsAndNotes() throws {
        let document = try TaxonomyLoader.bundledDocument()
        let byId = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        // Rum records origin, still type, fermentation, and age.
        #expect(
            byId["spirit.rum"]?.detailFields.sorted() == [
                "age", "fermentation", "origin", "still-type",
            ]
        )
        // Tequila records agave content (mixto versus 100% agave).
        #expect(byId["spirit.agave.tequila"]?.detailFields == ["agave-content"])
        // Wine records grape and region.
        #expect(byId["wine"]?.detailFields == ["grape", "region"])
        // Homemade preparations record a shelf life.
        #expect(byId["pantry.homemade"]?.detailFields == ["shelf-life"])
        // Sotol is marked as not made from agave.
        #expect(byId["spirit.agave.sotol"]?.notes?.contains("not agave") == true)
    }

    // MARK: - Replace and read

    @Test func replaceTaxonomyWritesAndReplaces() throws {
        let appDatabase = try AppDatabase.inMemory()
        let document = try TaxonomyLoader.bundledDocument()
        try appDatabase.replaceTaxonomy(with: document)

        try appDatabase.dbWriter.read { db in
            // Every node and alias lands in the store.
            let nodeCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM taxonomyNode"
            )
            #expect(nodeCount == document.nodes.count)
            let aliasCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM taxonomyAlias"
            )
            let aliasTotal = document.nodes.reduce(0) { $0 + $1.aliases.count }
            #expect(aliasCount == aliasTotal)
        }
        #expect(try appDatabase.storedTaxonomyVersion() == document.version)

        // Replacing the same document again leaves the same counts: the
        // reference tables are replaceable, never appended to.
        try appDatabase.replaceTaxonomy(with: document)
        try appDatabase.dbWriter.read { db in
            let nodeCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM taxonomyNode"
            )
            #expect(nodeCount == document.nodes.count)
        }
    }

    @Test func browseQueries() throws {
        let appDatabase = try AppDatabase.inMemory()
        let document = try TaxonomyLoader.bundledDocument()
        try appDatabase.replaceTaxonomy(with: document)

        // Roots are exactly the top categories.
        let roots = try appDatabase.taxonomyChildren(of: nil)
        #expect(
            roots.map(\.id) == [
                "spirit", "liqueur", "fortified-wine", "bitters", "wine", "beer", "cider", "sake",
                "non-alcoholic", "mixer", "pantry",
            ])

        // Children come back in document (browse) order.
        let styles = try appDatabase.taxonomyChildren(of: "spirit.whiskey.scotch")
        #expect(styles.first?.id == "spirit.whiskey.scotch.single-malt")
        #expect(styles.last?.id == "spirit.whiskey.scotch.region.campbeltown")
        #expect(styles.count == 9)

        // A node resolves by stable id with its kind intact.
        let node = try appDatabase.taxonomyNode(id: "liqueur.bitter.aperitivo")
        #expect(node?.name == "Aperitivo")
        #expect(node?.kind == .ingredient)
        #expect(try appDatabase.taxonomyNode(id: "no.such.id") == nil)

        // Children of an unknown parent are empty, not an error.
        #expect(try appDatabase.taxonomyChildren(of: "no.such.id").isEmpty)
    }

    @Test func searchFindsByNameAndAlias() throws {
        let appDatabase = try AppDatabase.inMemory()
        let document = try TaxonomyLoader.bundledDocument()
        try appDatabase.replaceTaxonomy(with: document)

        // By name, including a prefix of a word.
        #expect(
            try appDatabase.taxonomyNodes(matching: "verm").map(\.id).contains(
                "fortified-wine.vermouth"
            )
        )
        // By alias: curaçao resolves to the orange liqueur node.
        let curacao = try appDatabase.taxonomyNodes(matching: "curacao")
        #expect(curacao.map(\.id) == ["liqueur.orange"])
        // The accented form finds the same node.
        #expect(
            try appDatabase.taxonomyNodes(matching: "curaçao").map(\.id) == ["liqueur.orange"]
        )
        // Every term must match: "dry vermouth" finds dry vermouth.
        let dry = try appDatabase.taxonomyNodes(matching: "dry vermouth")
        #expect(dry.first?.id == "fortified-wine.vermouth.dry")
        // An empty query matches nothing instead of everything.
        #expect(try appDatabase.taxonomyNodes(matching: "   ").isEmpty)
    }

    // MARK: - Validation refusals

    @Test func replaceTaxonomyRejectsInvalidDocumentAndLeavesStoreUntouched() throws {
        let appDatabase = try AppDatabase.inMemory()
        let good = try TaxonomyLoader.bundledDocument()
        try appDatabase.replaceTaxonomy(with: good)

        func rejected(
            _ makeDocument: () -> TaxonomyDocument,
            expecting reason: TaxonomyValidationIssue.Reason
        ) throws {
            let before = try countNodes(appDatabase)
            #expect(throws: TaxonomyValidationError.self) {
                _ = try appDatabase.replaceTaxonomy(with: makeDocument())
            }
            // Unwrap through the API that returns issues for a precise
            // assertion on the reason.
            #expect(makeDocument().validate().contains { $0.reason == reason })
            #expect(try countNodes(appDatabase) == before)
        }

        try rejected(
            { TaxonomyDocument(version: 0, nodes: good.nodes) },
            expecting: .versionBelowOne
        )
        try rejected(
            { TaxonomyDocument(version: 1, nodes: []) },
            expecting: .emptyDocument
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(id: "a.b", parentId: nil, kind: .category, name: "A"),
                        TaxonomyNodeData(id: "a.b", parentId: nil, kind: .category, name: "B"),
                    ]
                )
            },
            expecting: .duplicateId("a.b")
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(
                            id: "orphan", parentId: "nowhere", kind: .category, name: "Orphan"
                        )
                    ]
                )
            },
            expecting: .missingParent("nowhere")
        )
        try rejected(
            {
                // Child before parent in document order: the loader writes
                // in order, so this must be refused.
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(
                            id: "child", parentId: "parent", kind: .category, name: "C"),
                        TaxonomyNodeData(id: "parent", parentId: nil, kind: .category, name: "P"),
                    ]
                )
            },
            expecting: .parentAfterChild("parent")
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(id: "a.b", parentId: "a.c", kind: .category, name: "A"),
                        TaxonomyNodeData(id: "a.c", parentId: "a.b", kind: .category, name: "C"),
                    ]
                )
            },
            expecting: .cycle("a.b")
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(id: "blank", parentId: nil, kind: .category, name: "  ")
                    ]
                )
            },
            expecting: .emptyName
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(
                            id: "dup", parentId: nil, kind: .ingredient, name: "Dup",
                            aliases: ["same", "same"]
                        )
                    ]
                )
            },
            expecting: .duplicateAlias("same")
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(
                            id: "bad.field name", parentId: nil, kind: .category, name: "Bad"
                        )
                    ]
                )
            },
            expecting: .invalidId("bad.field name")
        )
        try rejected(
            {
                TaxonomyDocument(
                    version: 1,
                    nodes: [
                        TaxonomyNodeData(
                            id: "fields", parentId: nil, kind: .category, name: "F",
                            detailFields: ["Not Kebab"]
                        )
                    ]
                )
            },
            expecting: .invalidDetailField("Not Kebab")
        )
    }

    private func countNodes(_ appDatabase: AppDatabase) throws -> Int {
        try appDatabase.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM taxonomyNode") ?? -1
        }
    }
}
