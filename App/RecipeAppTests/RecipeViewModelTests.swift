import Foundation
import RecipeCore
import Testing

@testable import RecipeApp

/// M4.2: the recipe view model — display options, check-offs, and the
/// rating/note edits — against a real temporary library.
@MainActor
struct RecipeViewModelTests {
    private func makeWorld() async throws -> (LibraryModel, RecipeDocument) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("g2-vm-\(UUID().uuidString)")
        let model = LibraryModel(
            root: root,
            clock: LibraryClock(now: { 1_800_000_000 }, newID: { UUID().uuidString }))
        var recipe = RecipeDocument(id: "vm-1", createdAt: 1_800_000_000, modifiedAt: 1_800_000_000)
        recipe.title = "Lentil Soup"
        recipe.yieldAmount = 4
        recipe.yieldUnit = "servings"
        recipe.ingredientSections = [
            IngredientSection(
                name: "",
                lines: [
                    IngredientParser.parse("1 cup brown lentils"),
                    IngredientParser.parse("2 carrots, diced"),
                    IngredientParser.parse("salt to taste"),
                ])
        ]
        recipe.stepSections = [
            StepSection(
                name: "",
                steps: [
                    Step(text: "Sweat the carrots."),
                    Step(text: "Add 1 cup lentils and simmer 30 minutes."),
                ])
        ]
        try await model.save(recipe)
        return (model, recipe)
    }
    @Test func displayOptionsFlowThroughThePipeline() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        // As written at factor 1: the source wording, verbatim.
        #expect(viewModel.renderedSections[0].lines[0].text == "1 cup brown lentils")
        // Scaled: friendly amounts, count lines pluralized.
        viewModel.factor = 2
        #expect(viewModel.renderedSections[0].lines[0].text == "2 cups brown lentils")
        #expect(viewModel.renderedSections[0].lines[1].text == "4 carrots, diced")
        // The yield line scales.
        #expect(viewModel.yieldText == "8 servings")
        // To taste stays put.
        #expect(viewModel.renderedSections[0].lines[2].text == "salt, to taste")
    }

    @Test func unitSystemSwitchesAndCountsStay() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        viewModel.system = .metric
        let lines = viewModel.renderedSections[0].lines
        #expect(lines[0].converted)
        #expect(lines[0].text.contains("ml"))
        #expect(!lines[1].converted)
        #expect(lines[1].text == "2 carrots, diced")
        // Back to written, the source wording returns.
        viewModel.system = .written
        #expect(viewModel.renderedSections[0].lines[0].text == "1 cup brown lentils")
    }

    @Test func factorFromTargetYieldAnchorsOnTheWrittenYield() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        #expect(try viewModel.factor(forTargetYield: 6) == 1.5)
        #expect(viewModel.targetYield == 4)
        viewModel.factor = try #require(viewModel.factor(forTargetYield: 6))
        #expect(viewModel.targetYield == 6)
    }

    @Test func stepTextScalesAndRestores() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        let scaledStep = recipe.stepSections[0].steps[1]
        viewModel.factor = 2
        let scaled = viewModel.stepText(scaledStep)
        #expect(scaled.contains("2 cups"))
        viewModel.factor = 1
        #expect(viewModel.stepText(scaledStep) == "Add 1 cup lentils and simmer 30 minutes.")
    }

    @Test func checkOffsToggleAndReset() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        #expect(!viewModel.isChecked(section: 0, line: 0))
        viewModel.toggleCheck(section: 0, line: 0)
        viewModel.toggleCheck(section: 0, line: 2)
        #expect(viewModel.isChecked(section: 0, line: 0))
        #expect(viewModel.isChecked(section: 0, line: 2))
        #expect(!viewModel.isChecked(section: 0, line: 1))
        viewModel.toggleCheck(section: 0, line: 0)
        #expect(!viewModel.isChecked(section: 0, line: 0))
        viewModel.clearChecks()
        #expect(viewModel.checked.isEmpty)
    }

    @Test func ratingWritesThroughTheLibrary() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        await viewModel.setRating(4)
        #expect(viewModel.recipe.rating == 4)
        let reloaded = try await library.store.loadRecipe(id: recipe.id)
        #expect(reloaded.rating == 4)
        // Clamp and idempotence.
        await viewModel.setRating(9)
        #expect(viewModel.recipe.rating == 5)
        await viewModel.setRating(5)
        #expect(viewModel.recipe.rating == 5)
    }

    @Test func notesAppendAsParagraphs() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        await viewModel.appendNote("Made with vegetable stock.")
        await viewModel.appendNote("Double the carrots.")
        #expect(viewModel.recipe.notes.contains("vegetable stock"))
        #expect(viewModel.recipe.notes.contains("\n\nDouble the carrots."))
        let reloaded = try await library.store.loadRecipe(id: recipe.id)
        #expect(reloaded.notes.contains("Double the carrots."))
    }

    @Test func photosReadThroughTheLibrary() async throws {
        let (library, recipe) = try await makeWorld()
        let viewModel = RecipeViewModel(recipe: recipe, library: library)
        #expect(viewModel.photoData(hash: "nope") == nil)
        let hash = try await library.store.storePhoto(Data("jpeg-ish".utf8))
        #expect(viewModel.photoData(hash: hash) != nil)
    }
}
