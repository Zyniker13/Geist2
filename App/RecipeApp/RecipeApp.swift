import RecipeCore
import SwiftUI

@main
struct RecipeApp: App {
    @StateObject private var library = LibraryModel()
    @StateObject private var importer = ImportModel()
    @StateObject private var themeStore = ThemeStore()
    @State private var path = NavigationPath()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                NavigationSplitView {
                    LibraryView()
                } detail: {
                    RecipeDetailLoader(recipeID: library.selection ?? "")
                }
                .themed(themeStore.theme)
            #else
                // Split view on iPad (the fixed choice), stack on
                // iPhone: the horizontal size class decides, so the
                // same code also handles iPad split-screen correctly.
                RootLayout(
                    path: $path,
                    selection: $library.selection
                )
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
                    // Set the split view's selection and push onto the
                    // stack in one go: selection drives the iPad/Mac
                    // detail pane, the path drives the iPhone push. A
                    // value the other layout ignores is harmless.
                    library.selection = id
                    path.append(id)
                }
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

/// Chooses the iPad split view over the iPhone stack by the horizontal
/// size class, per the fixed choice "split view on iPad and Mac".
private struct RootLayout: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var path: NavigationPath
    @Binding var selection: String?

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                LibraryView()
            } detail: {
                RecipeDetailLoader(recipeID: selection ?? "")
            }
        } else {
            NavigationStack(path: $path) {
                LibraryView()
                    .navigationDestination(
                        for: String.self,
                        destination: { recipeID in
                            RecipeDetailLoader(recipeID: recipeID)
                        })
            }
        }
    }
}
