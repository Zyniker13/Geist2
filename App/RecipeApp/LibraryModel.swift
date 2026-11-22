import RecipeCore
import RecipeImport
import SwiftUI

/// The app's library handle: owns the on-disk library and the recipe
/// list the UI reads. Writes go through LibraryStore, which emits
/// DocumentChanges on the SyncPort (decision 0005).
@MainActor
final class LibraryModel: ObservableObject {
    /// The library directory the app reads: the App Group container
    /// when the group exists (so share extensions write into the same
    /// library), else the app sandbox's Documents/Library. Tests pass
    /// their own root. Documents (not Application Support) because
    /// Application Support writes have hit simulator EIO on this
    /// shared host.
    static let defaultRoot = SharedLibrary.root

    let store: LibraryStore
    let photos: PhotoStore

    @Published private(set) var recipes: [RecipeDocument] = []

    /// Creates the model over a library root. Tests pass their own
    /// directory and fixed clock values.
    init(root: URL? = nil, clock: LibraryClock = .live) {
        let root = root ?? Self.defaultRoot
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        self.store = LibraryStore(root: root)
        self.photos = PhotoStore(root: root.appendingPathComponent("Photos"))
        self.clock = clock
    }

    private let clock: LibraryClock

    /// Reloads the recipe list from the store, newest first.
    func refresh() async {
        do {
            let ids = try await store.listIDs(kind: .recipe)
            var loaded: [RecipeDocument] = []
            for id in ids {
                if let recipe = try? await store.loadRecipe(id: id),
                    recipe.deletedAt == nil
                {
                    loaded.append(recipe)
                }
            }
            loaded.sort { $0.modifiedAt > $1.modifiedAt }
            recipes = loaded
        } catch {
            // A missing or unreadable index leaves the list as-is; the
            // store rebuilds it on next launch.
        }
    }

    /// Saves an extracted recipe into the library and refreshes.
    @discardableResult
    func save(_ document: RecipeDocument) async throws -> RecipeDocument {
        try await store.write(document)
        await refresh()
        return document
    }

    /// Deletes a recipe (soft; Recently Deleted empties it later).
    func delete(_ recipe: RecipeDocument) async {
        try? await store.deleteRecipe(id: recipe.id)
        await refresh()
    }
}
