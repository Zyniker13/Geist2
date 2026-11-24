import Foundation
import RecipeCore

/// One recipe as the detail screen shows it: the stored document plus
/// the viewer's choices (yield factor, unit system, ingredient
/// check-offs, photo display). The document itself is never mutated for
/// display; a check-off or a rating change goes through LibraryStore.
@MainActor
final class RecipeViewModel: ObservableObject {
    /// The recipe as stored.
    @Published private(set) var recipe: RecipeDocument

    /// The yield factor the viewer has chosen (1 = as written).
    @Published var factor: Decimal = 1

    /// The unit system the viewer has chosen.
    @Published var system: RecipeDisplay.UnitSystem = .written

    /// Which ingredient lines are checked off while cooking, by section
    /// index and line index. Resets when the recipe changes.
    @Published private(set) var checked: Set<LineKey> = []

    struct LineKey: Hashable {
        let section: Int
        let line: Int
    }

    /// The library the recipe lives in (photo bytes, writes).
    private let library: LibraryModel

    init(recipe: RecipeDocument, library: LibraryModel) {
        self.recipe = recipe
        self.library = library
    }

    // MARK: Display

    /// The options the screen renders with.
    var options: RecipeDisplay.Options {
        RecipeDisplay.Options(factor: factor, system: system)
    }

    /// Ingredient sections through the display pipeline.
    var renderedSections: [RecipeDisplay.RenderedSection] {
        RecipeDisplay.sections(recipe.ingredientSections, options: options)
    }

    /// The scaled yield text ("6 servings"), nil when the recipe states
    /// no yield.
    var yieldText: String? {
        RecipeDisplay.yieldText(recipe, options: options)
    }

    /// Step text with scaled amounts substituted.
    func stepText(_ step: Step) -> String {
        RecipeDisplay.stepText(
            step,
            lines: recipe.ingredientSections.flatMap(\.lines),
            options: options)
    }

    /// The factor the yield stepper implies from a target yield amount.
    /// The written amount anchors it; nil when the recipe has no yield.
    func factor(forTargetYield target: Decimal) -> Decimal? {
        guard let written = recipe.yieldAmount, written > 0, target > 0 else { return nil }
        return target / written
    }

    /// The current target yield the viewer is looking at.
    var targetYield: Decimal? {
        recipe.yieldAmount.map { $0 * factor }
    }

    // MARK: Check-offs

    /// Whether one line is checked off.
    func isChecked(section: Int, line: Int) -> Bool {
        checked.contains(LineKey(section: section, line: line))
    }

    /// Toggles one line's check-off.
    func toggleCheck(section: Int, line: Int) {
        let key = LineKey(section: section, line: line)
        if checked.contains(key) {
            checked.remove(key)
        } else {
            checked.insert(key)
        }
    }

    /// Clears every check-off (when the viewer reopens the recipe).
    func clearChecks() {
        checked.removeAll()
    }

    // MARK: Photos

    /// The raw bytes of a stored photo, nil when the reference dangles
    /// (tolerated: the view shows a placeholder).
    func photoData(hash: String) -> Data? {
        library.photos.data(for: hash)
    }

    // MARK: Edits through the store

    /// Sets the rating (0–5) and writes it through the library. The
    /// document refreshes to the stored copy.
    func setRating(_ value: Int) async {
        let clamped = max(0, min(5, value))
        guard clamped != recipe.rating else { return }
        var updated = recipe
        updated.rating = clamped
        try? await library.store.write(updated)
        await library.refresh()
        if let stored = library.recipes.first(where: { $0.id == recipe.id }) {
            recipe = stored
        }
    }

    /// Appends a note paragraph to the recipe's notes.
    func appendNote(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recipe
        updated.notes =
            updated.notes.isEmpty ? trimmed : updated.notes + "\n\n" + trimmed
        try? await library.store.write(updated)
        await library.refresh()
        if let stored = library.recipes.first(where: { $0.id == recipe.id }) {
            recipe = stored
        }
    }
}
