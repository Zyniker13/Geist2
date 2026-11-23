import RecipeCore
import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var importer = ImportModel()

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
                NavigationStack {
                    LibraryView()
                        .navigationDestination(
                            for: String.self,
                            destination: { recipeID in
                                RecipeDetailLoader(recipeID: recipeID)
                            })
                }
            #else
                NavigationSplitView {
                    LibraryView()
                } detail: {
                    RecipeDetailLoader(recipeID: library.selection ?? "")
                }
            #endif
        }
        .environmentObject(library)
        .environmentObject(importer)
    }
}
