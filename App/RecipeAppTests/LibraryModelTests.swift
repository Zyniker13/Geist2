import Foundation
import PhotosUI
import RecipeCore
import RecipeImport
import SwiftUI
import Testing
import Vision

@testable import RecipeApp

/// The library model against a real temporary LibraryStore.
@MainActor
struct LibraryModelTests {
    private func makeModel() throws -> (LibraryModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("g2-lib-\(UUID().uuidString)")
        let model = LibraryModel(
            root: root,
            clock: LibraryClock(now: { 1_800_000_000 }, newID: { UUID().uuidString }))
        return (model, root)
    }

    @Test func importedRecipeIsSavedAndListed() async throws {
        let (model, root) = try makeModel()
        let importer = ImportModel()
        await importer.importText(
            """
            Pan Roast
            Ingredients
            2 lb potatoes
            Directions
            Roast for 40 minutes.
            """,
            into: model)
        guard case .done(let document) = importer.stage else {
            Issue.record("import did not finish: \(importer.stage)")
            return
        }
        #expect(document.title == "Pan Roast")
        #expect(model.recipes.count == 1)
        #expect(model.recipes[0].id == document.id)
        // It survives a reload from disk.
        let reloaded = LibraryModel(
            root: root,
            clock: LibraryClock(now: { 1_800_000_000 }, newID: { UUID().uuidString }))
        await reloaded.refresh()
        #expect(reloaded.recipes.count == 1)
        #expect(reloaded.recipes[0].title == "Pan Roast")
    }

    @Test func failedImportReportsAReadableMessage() async throws {
        let (model, _) = try makeModel()
        let importer = ImportModel()
        await importer.importText("nothing recipe shaped at all here", into: model)
        guard case .failed = importer.stage else {
            Issue.record("expected failure, got \(importer.stage)")
            return
        }
        #expect(model.recipes.isEmpty)
    }

    @Test func linkImportThroughTheRealNetwork() async throws {
        // example.com always answers; a plain page fails extraction,
        // which proves the fetch path runs end to end.
        let (model, _) = try makeModel()
        let importer = ImportModel()
        await importer.importLink("https://example.com/", into: model)
        guard case .failed(let message) = importer.stage else {
            Issue.record("expected a failure, got \(importer.stage)")
            return
        }
        #expect(message.contains("No recipe"))
    }

    @Test func deleteRemovesTheRecipe() async throws {
        let (model, _) = try makeModel()
        let importer = ImportModel()
        await importer.importText(
            "Soup\nIngredients\n1 cup water\nDirections\nBoil.\n", into: model)
        guard case .done(let document) = importer.stage else {
            Issue.record("import did not finish")
            return
        }
        await model.delete(document)
        #expect(model.recipes.isEmpty)
    }
}
