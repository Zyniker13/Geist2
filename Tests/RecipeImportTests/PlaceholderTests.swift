import Testing

@testable import RecipeImport

struct RecipeImportPlaceholderTests {
    @Test func moduleDescriptionIsPresent() {
        #expect(!RecipeImportPlaceholder.moduleDescription.isEmpty)
    }
}
