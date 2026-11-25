import RecipeCore
import SwiftUI

/// The library screen: search, filters, sort, and the recipe list.
/// Lives inside a NavigationSplitView on iPad and Mac (RecipeApp),
/// and a plain NavigationStack on iPhone.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @StateObject private var themeStore = ThemeStore()
    @State private var showingImport = false
    @State private var showingEditor = false
    @State private var recipePendingDelete: RecipeDocument?

    var body: some View {
        List {
            LibraryControls()
            ForEach(library.visibleRecipes) { recipe in
                NavigationLink(
                    value: recipe.id,
                    label: { RecipeRow(recipe: recipe) }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        #if os(macOS)
                            library.selection = recipe.id
                        #endif
                    }
                )
                .contextMenu {
                    Button(role: .destructive) {
                        recipePendingDelete = recipe
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if !library.visibleRecipes.isEmpty
                && library.visibleRecipes.count
                    < library.recipes.count
            {
                EmptyListFooter(
                    visible: library.visibleRecipes.count,
                    total: library.recipes.count)
            }
        }
        .listStyle(.plain)
        .searchable(
            text: Binding(
                get: { library.query.text },
                set: { library.query.text = $0 }),
            placement: searchablePlacement,
            prompt: "Search title, ingredient, tag"
        )
        .autocorrectionDisabled()
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingEditor = true
                    } label: {
                        Label("New recipe", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("addRecipeMenu")
                .accessibilityLabel("Add a recipe")
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(Theme.all, id: \.name) { theme in
                        Button {
                            themeStore.themeName = theme.name
                        } label: {
                            if themeStore.themeName == theme.name {
                                Label(theme.label, systemImage: "checkmark")
                            } else {
                                Text(theme.label)
                            }
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }
                .accessibilityLabel("Theme")
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportView()
        }
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(recipe: nil)
        }
        .alert(
            "Delete “\(recipePendingDelete?.title ?? "")”?",
            isPresented: Binding(
                get: { recipePendingDelete != nil },
                set: { if !$0 { recipePendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let recipe = recipePendingDelete {
                    Task { await library.delete(recipe) }
                }
                recipePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                recipePendingDelete = nil
            }
        } message: {
            Text("The recipe moves to Recently Deleted.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newRecipeRequested)) { _ in
            showingEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in
            showingImport = true
        }
        .task { await library.refresh() }
    }

    /// iOS keeps the search field always visible in a nav bar drawer;
    /// macOS has no drawer and uses the toolbar field.
    private var searchablePlacement: SearchFieldPlacement {
        #if os(macOS)
            return .toolbar
        #else
            return .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

/// Search/filter state lives in the query; this row keeps the controls
/// out of the list rows.
private struct LibraryControls: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        HStack(spacing: 8) {
            SortMenu()
            FilterMenu()
            Spacer()
        }
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// The sort picker: segmented control over the core sort enum.
struct SortMenu: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        Picker(
            "Sort",
            selection: Binding(
                get: { library.query.sort },
                set: { library.query.sort = $0 })
        ) {
            ForEach(LibraryQuery.Sort.allCases) { sort in
                Text(sort.label).tag(sort)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("Sort recipes")
    }
}

/// The filter menu: tag, category, cuisine, max time, min rating.
/// Only offers values the library actually has.
struct FilterMenu: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        Menu {
            if !library.allTags.isEmpty {
                Section("Tag") {
                    ForEach(library.allTags, id: \.self) { tag in
                        Button {
                            library.query.tag = library.query.tag == tag ? nil : tag
                        } label: {
                            if library.query.tag == tag {
                                Label(tag, systemImage: "checkmark")
                            } else {
                                Text(tag)
                            }
                        }
                    }
                }
            }
            if !library.allCategories.isEmpty {
                Section("Category") {
                    ForEach(library.allCategories, id: \.self) { category in
                        Button {
                            library.query.category =
                                library.query.category == category ? nil : category
                        } label: {
                            if library.query.category == category {
                                Label(category, systemImage: "checkmark")
                            } else {
                                Text(category)
                            }
                        }
                    }
                }
            }
            if !library.allCuisines.isEmpty {
                Section("Cuisine") {
                    ForEach(library.allCuisines, id: \.self) { cuisine in
                        Button {
                            library.query.cuisine =
                                library.query.cuisine == cuisine ? nil : cuisine
                        } label: {
                            if library.query.cuisine == cuisine {
                                Label(cuisine, systemImage: "checkmark")
                            } else {
                                Text(cuisine)
                            }
                        }
                    }
                }
            }
            Section("Max time") {
                ForEach(
                    [
                        (30, "30 minutes"), (60, "1 hour"), (120, "2 hours"),
                    ], id: \.0
                ) { seconds, label in
                    Button {
                        library.query.maxTotalSeconds =
                            library.query.maxTotalSeconds == seconds ? nil : seconds
                    } label: {
                        if library.query.maxTotalSeconds == seconds {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
            Section("Rating") {
                ForEach(3...4, id: \.self) { stars in
                    Button {
                        library.query.minRating =
                            library.query.minRating == stars ? nil : stars
                    } label: {
                        if library.query.minRating == stars {
                            Label("\(stars) stars or more", systemImage: "checkmark")
                        } else {
                            Text("\(stars) stars or more")
                        }
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                library.query = LibraryQuery(sort: library.query.sort)
            } label: {
                Text("Clear filters")
            }
            .disabled(library.query.filters.isEmpty)
        } label: {
            Image(
                systemName: library.query.filters.isEmpty
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter recipes")
    }
}

/// "Showing 3 of 12" footer under a narrowed list.
private struct EmptyListFooter: View {
    let visible: Int
    let total: Int

    var body: some View {
        Text("Showing \(visible) of \(total)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// One row in the recipe list: title and the yield/time line.
struct RecipeRow: View {
    let recipe: RecipeDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recipe.title.isEmpty ? "Untitled" : recipe.title)
                .font(.headline)
            HStack(spacing: 6) {
                if recipe.yieldAmount != nil {
                    Text("\(recipe.yieldAmount!) \(recipe.yieldUnit)")
                }
                if let total = recipe.totalTime {
                    Text(total.display)
                }
                ForEach(recipe.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension RecipeDocument: Identifiable {}
