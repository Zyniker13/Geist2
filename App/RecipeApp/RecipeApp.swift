import RecipeCore
import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var importer = ImportModel()
    @StateObject private var themeStore = ThemeStore()
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
                NavigationStack(path: $path) {
                    LibraryView()
                        .navigationDestination(
                            for: String.self,
                            destination: { recipeID in
                                RecipeDetailLoader(recipeID: recipeID)
                            })
                }
                .themed(themeStore.theme)
                .task {
                    // UI-test hook: a launch argument deep-links the
                    // detail screen, so accessibility checks do not
                    // depend on list-tap coordinates.
                    guard ProcessInfo.processInfo.arguments.contains("-openFirstRecipe")
                    else { return }
                    // Load the library before deep-linking; the task can
                    // fire before the refresh in LibraryView finishes.
                    await library.refresh()
                    guard
                        let id =
                            (library.recipes.first { $0.deletedAt == nil }
                            ?? library.recipes.first)?.id
                    else { return }
                    // Push after the frame settles so the stack exists.
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    path.append(id)
                }
            #else
                NavigationSplitView {
                    LibraryView()
                } detail: {
                    RecipeDetailLoader(recipeID: library.selection ?? "")
                }
                .themed(themeStore.theme)
            #endif
        }
        .environmentObject(library)
        .environmentObject(importer)
        .commands {
            #if os(macOS)
                CommandGroup(replacing: .newItem) {
                    Button("New Recipe") {
                        NotificationCenter.default.post(name: .newRecipeRequested, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    Button("Import…") {
                        NotificationCenter.default.post(name: .importRequested, object: nil)
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                }
                CommandMenu("View") {
                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { themeStore.themeName },
                            set: { themeStore.themeName = $0 }
                        )
                    ) {
                        ForEach(Theme.all, id: \.name) { theme in
                            Text(theme.label).tag(theme.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }
            #else
                CommandGroup(replacing: .newItem) {
                    Button("New Recipe") {
                        NotificationCenter.default.post(name: .newRecipeRequested, object: nil)
                    }
                }
            #endif
        }
    }
}

extension Notification.Name {
    /// The Mac menu's New Recipe / Import commands.
    static let newRecipeRequested = Notification.Name("newRecipeRequested")
    static let importRequested = Notification.Name("importRequested")
}
