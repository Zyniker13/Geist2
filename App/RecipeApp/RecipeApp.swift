import SwiftUI

@main
struct RecipeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your recipe library",
                systemImage: "book.closed",
                description: Text("Recipes you add or import will appear here."))
        }
    }
}
