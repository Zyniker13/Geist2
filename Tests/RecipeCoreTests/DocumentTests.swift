import Foundation
import Testing
@testable import RecipeCore

struct SyncPortTests {
    @Test func recordingPortKeepsOrder() async {
        let port = RecordingSyncPort()
        let change1 = DocumentChange(
            kind: .recipe, documentID: "a", changedFieldIDs: ["title"],
            fields: ["title": .string("Soup")], modifiedAt: 1)
        let change2 = DocumentChange(
            kind: .recipe, documentID: "a", changedFieldIDs: ["rating"],
            fields: ["rating": .int(4)], modifiedAt: 2)
        await port.apply(change1)
        await port.apply(change2)
        let recorded = await port.changes
        #expect(recorded.map(\.changedFieldIDs) == [["title"], ["rating"]])
    }

    @Test func nullPortAcceptsAnything() async {
        let port = NullSyncPort()
        await port.apply(DocumentChange(
            kind: .list, documentID: "l", changedFieldIDs: ["lines"],
            fields: [:], modifiedAt: 1))
    }
}

struct MigrationTests {
    @Test func currentVersionPassesThroughUnchanged() throws {
        let recipe = RecipeDocument(id: "r1", title: "Test", createdAt: 1, modifiedAt: 1)
        let data = try JSONEncoder().encode(recipe)
        let out = try Migrations.upgrade(data, kind: .recipe, from: DocumentSchema.current)
        let back = try JSONDecoder().decode(RecipeDocument.self, from: out)
        #expect(back == recipe)
    }

    @Test func futureVersionIsRefused() throws {
        let json = Data("{\"schemaVersion\":99}".utf8)
        #expect(throws: SchemaError.unsupportedVersion(99)) {
            try Migrations.upgrade(json, kind: .recipe, from: 99)
        }
    }
}

struct RecipeDocumentTests {
    @Test func recipeRoundTripsThroughCodable() throws {
        var recipe = RecipeDocument(id: "r1", title: "Tomato Soup", createdAt: 100, modifiedAt: 200)
        recipe.summary = "A simple soup"
        recipe.yieldAmount = Decimal(string: "4")
        recipe.yieldUnit = "servings"
        recipe.prepTime = Duration.minutes(10)
        recipe.cookTime = Duration.minutes(30)
        recipe.totalTime = Duration.minutes(40)
        recipe.ingredientSections = [
            IngredientSection(name: "", lines: [
                IngredientLine(
                    quantity: Quantity(Decimal(string: "2")!), unitID: "cup",
                    item: "chicken stock", note: "(or vegetable)",
                    originalText: "2 cups chicken stock (or vegetable)"),
                IngredientLine(item: "salt", toTaste: true, originalText: "Salt to taste"),
            ])
        ]
        recipe.stepSections = [
            StepSection(name: "", steps: [
                Step(text: "Simmer for 20 minutes.", timers: [Duration.minutes(20)])
            ])
        ]
        recipe.tags = ["soup", "winter"]
        recipe.categories = ["Dinner"]
        recipe.rating = 4
        recipe.photoHashes = ["abc123"]
        recipe.nutrition = ["calories": "180"]

        let data = try JSONEncoder().encode(recipe)
        let back = try JSONDecoder().decode(RecipeDocument.self, from: data)
        #expect(back == recipe)
    }

    @Test func planListPantryRoundTrip() throws {
        var plan = PlanDocument(id: "p1", createdAt: 1, modifiedAt: 1)
        plan.entries = [PlanEntry(day: "2026-11-24", meal: "dinner", recipeID: "r1", servings: 4)]
        var list = ListDocument(id: "l1", name: "Week", createdAt: 1, modifiedAt: 1)
        var line = ListLine(text: "2 cups flour", item: "flour")
        line.quantity = Quantity(2)
        line.unitID = "cup"
        list.lines = [line]
        var pantry = PantryDocument(id: "pan1", createdAt: 1, modifiedAt: 1)
        var item = PantryItem(name: "olive oil")
        item.useBy = 1_799_000_000_000
        pantry.items = [item]

        let planData = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(PlanDocument.self, from: planData) == plan)
        let listData = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode(ListDocument.self, from: listData) == list)
        let pantryData = try JSONEncoder().encode(pantry)
        #expect(try JSONDecoder().decode(PantryDocument.self, from: pantryData) == pantry)
    }
}
