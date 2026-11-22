import RecipeCore
import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var importer = ImportModel()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(importer)
        }
    }
}
