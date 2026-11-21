import Testing

@testable import RecipeModules

struct RecipeModulesPlaceholderTests {
    @Test func formatVersionIsDeclared() {
        #expect(RecipeModules.currentFormatVersion == 1)
    }
}
