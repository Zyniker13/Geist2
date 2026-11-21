import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import PhotosUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case simple = "Simple"
    case cookbook = "Cookbook"
    var id: Self { self }

    func tint(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.simple, .light): Color(red: 0.26, green: 0.42, blue: 0.28)
        case (.cookbook, .light): Color(red: 0.19, green: 0.27, blue: 0.20)
        default: Color(red: 0.68, green: 0.77, blue: 0.61)
        }
    }

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.13, green: 0.15, blue: 0.12) : Color(red: 0.97, green: 0.96, blue: 0.93)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.18, green: 0.20, blue: 0.17) : Color(red: 1, green: 0.99, blue: 0.97)
    }

    static func sage(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.22, green: 0.28, blue: 0.20) : Color(red: 0.90, green: 0.92, blue: 0.86)
    }
}

private struct AppAppearanceKey: EnvironmentKey {
    static let defaultValue = AppAppearance.simple
}

extension EnvironmentValues {
    var appAppearance: AppAppearance {
        get { self[AppAppearanceKey.self] }
        set { self[AppAppearanceKey.self] = newValue }
    }
}

private struct AppSurface: ViewModifier {
    @Environment(\.appAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(appearance == .cookbook ? .hidden : .automatic)
            .background {
                if appearance == .cookbook { AppAppearance.paper(scheme).ignoresSafeArea() }
            }
    }
}

extension View {
    func appSurface() -> some View { modifier(AppSurface()) }
}

@main struct RecipeApp: App {
    @State private var cookbook = Cookbook()
    @AppStorage("geist2.appearance") private var appearance = AppAppearance.simple
    var body: some Scene {
        WindowGroup("Recipe app") {
            LibraryView(book: cookbook, appearance: $appearance)
                .environment(\.appAppearance, appearance)
                #if os(macOS)
                .frame(minWidth: 580, minHeight: 520)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 840, height: 680)
        #endif
    }
}

struct LibraryView: View {
    let book: Cookbook
    @Binding var appearance: AppAppearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var category = ""
    @State private var sort = Sort.recent
    @State private var sheet: Sheet?
    @State private var showImporter = false
    @State private var importingSharedRecipe = false
    @State private var exportBackup = false
    @State private var pendingBackup: Library?

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recently added", rating = "Highest rated", name = "Name A–Z"
        var id: Self { self }
    }
    enum Sheet: Identifiable {
        case editor(Recipe), importLink, scan, groceries
        var id: String {
            switch self {
            case .editor(let recipe): "editor-" + recipe.id
            case .importLink: "import"
            case .scan: "scan"
            case .groceries: "groceries"
            }
        }
    }

    private var categories: [String] {
        Recipe.uniqueNames(book.library.recipes.flatMap(\.categories)).sorted()
    }

    private var recipes: [Recipe] {
        book.library.recipes.filter { recipe in
            (category.isEmpty || !categories.contains(category) || recipe.categories.contains { Recipe.nameKey($0) == Recipe.nameKey(category) }) &&
            (search.trimmed.isEmpty || ([recipe.title] + recipe.categories + recipe.ingredients)
                .joined(separator: " ").localizedCaseInsensitiveContains(search.trimmed))
        }.sorted { a, b in
            switch sort {
            case .recent: a.created > b.created
            case .rating: a.rating == b.rating ? a.created > b.created : a.rating > b.rating
            case .name: a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    HStack {
                        Text("Your recipes")
                            .font(appearance == .cookbook ? .system(.title, design: .serif, weight: .semibold) : .title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Menu {
                            Picker("Category", selection: $category) {
                                Text("All categories").tag("")
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: { Label(category.isEmpty ? "Filter & sort" : category, systemImage: "line.3.horizontal.decrease") }
                    }
                    if recipes.isEmpty {
                        ContentUnavailableView(
                            book.library.recipes.isEmpty ? "Your cookbook is empty" : "No recipes found",
                            systemImage: "book.closed",
                            description: Text(book.library.recipes.isEmpty ? "Add, import, or scan a recipe to get started." : "Try a different search or category.")
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(recipes) { recipe in
                                NavigationLink(value: recipe.id) { card(recipe) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1060)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .appSurface()
            .navigationTitle("Recipe app")
            .searchable(text: $search, prompt: "Recipes, categories, or ingredients")
            .navigationDestination(for: String.self) { id in
                RecipeDetail(book: book, id: id) { sheet = .editor($0) }
            }
            .toolbar {
                ToolbarItem {
                    Button { sheet = .groceries } label: { Label("Groceries", systemImage: "cart") }
                }
                ToolbarItem {
                    Menu {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { style in Text(style.rawValue).tag(style) }
                        }
                        .pickerStyle(.menu)
                        Divider()
                        Button("Download backup", systemImage: "square.and.arrow.down") { exportBackup = true }
                        Button("Import shared recipe", systemImage: "person.crop.circle.badge.plus") {
                            importingSharedRecipe = true
                            showImporter = true
                        }
                        Button("Restore backup", systemImage: "arrow.up.document") {
                            importingSharedRecipe = false
                            showImporter = true
                        }
                    } label: { Label("Cookbook actions", systemImage: "ellipsis.circle") }
                }
            }
        }
        .tint(appearance.tint(scheme))
        .sheet(item: $sheet) { selected in
            Group {
                switch selected {
                case .editor(let recipe): RecipeEditor(recipe: recipe, book: book)
                case .importLink: IntakeView(scan: false) { sheet = .editor($0) }
                case .scan: IntakeView(scan: true) { sheet = .editor($0) }
                case .groceries: GroceryView(book: book)
                }
            }
            .tint(appearance.tint(scheme))
            #if os(macOS)
            .frame(minWidth: 540, minHeight: 525)
            #endif
        }
        .fileExporter(isPresented: $exportBackup, document: Backup(library: book.library),
                      contentType: .json, defaultFilename: "recipes-backup") {
            if case .failure(let error) = $0 { book.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if importingSharedRecipe {
                    sheet = .editor(try SharedRecipe.importRecipe(from: data))
                } else {
                    pendingBackup = try Library.decode(data)
                }
            } catch { book.error = error.localizedDescription }
        }
        .confirmationDialog("Restore backup?", isPresented: Binding(
            get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }
        ), titleVisibility: .visible) {
            Button("Replace this cookbook", role: .destructive) {
                if let pendingBackup { book.replace(with: pendingBackup) }
                pendingBackup = nil
                category = ""
            }
        } message: { Text("This replaces the recipes and groceries saved in this app.") }
        .alert("Recipe app", isPresented: Binding(
            get: { book.error != nil }, set: { if !$0 { book.error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(book.error ?? "") }
    }

    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        return [GridItem(.adaptive(minimum: appearance == .cookbook ? 248 : 235), spacing: 14)]
    }

    @ViewBuilder private var header: some View {
        if appearance == .cookbook {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    cookbookIntro.frame(minWidth: 365)
                    heroPhoto.frame(width: 280, height: 235)
                }
                VStack(spacing: 0) {
                    heroPhoto.frame(height: 145)
                    cookbookIntro
                }
            }
            .background(AppAppearance.sage(scheme), in: RoundedRectangle(cornerRadius: 19))
            .clipShape(RoundedRectangle(cornerRadius: 19))
        } else {
            VStack(alignment: .leading, spacing: 11) {
                Text("Recipes worth keeping.").font(.system(.largeTitle, design: .serif, weight: .semibold))
                responsiveActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 19))
        }
    }

    private var cookbookIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR PERSONAL COOKBOOK")
                .font(.caption2.weight(.semibold))
                .tracking(1.7)
                .foregroundStyle(appearance.tint(scheme))
            Text("Recipes worth keeping.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            responsiveActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var responsiveActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { actions }
            VStack(alignment: .leading, spacing: 8) { actions }
        }
        .controlSize(.large)
    }

    private var heroPhoto: some View {
        // Placeholder until the app has artwork of its own.
        Color.clear.overlay {
            Image(systemName: "fork.knife")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var actions: some View {
        Button("Add recipe", systemImage: "plus") { sheet = .editor(Recipe()) }.buttonStyle(.borderedProminent)
        Button("Import link", systemImage: "link") { sheet = .importLink }.buttonStyle(.bordered)
        Button("Scan photo", systemImage: "text.viewfinder") { sheet = .scan }.buttonStyle(.bordered)
    }

    private func card(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            if appearance == .cookbook { recipeCover(recipe) }
            cardContents(recipe)
        }
        .background {
            if appearance == .cookbook { AppAppearance.card(scheme) }
            else { Rectangle().fill(.regularMaterial) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay {
            if appearance == .cookbook {
                RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func recipeCover(_ recipe: Recipe) -> some View {
        let coverURL = recipe.image.flatMap { RecipeIntake.photoURL($0) }
        return AppAppearance.sage(scheme)
            .frame(height: 105)
            .overlay {
                if let image = RecipePhoto.embeddedImage(recipe.photoData) {
                    image.resizable().scaledToFill()
                } else if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { coverMark(recipe) }
                    }
                } else {
                    coverMark(recipe)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private func coverMark(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife").font(.title3)
            Text(String(recipe.title.prefix(1)).uppercased()).font(.system(.largeTitle, design: .serif))
        }
        .foregroundStyle(appearance.tint(scheme))
    }

    private func cardContents(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.categories.isEmpty ? "Uncategorized" : recipe.categories.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(recipe.title).font(.system(.title2, design: .serif, weight: .semibold))
            HStack {
                Text(recipe.time ?? "").foregroundStyle(.secondary)
                Spacer()
                if recipe.rating > 0 {
                    Text(String(repeating: "★", count: recipe.rating)).foregroundStyle(.orange)
                        .accessibilityLabel("\(recipe.rating) out of 5 stars")
                }
            }.font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .padding(15)

    }
}

struct RecipeEditor: View {
    @State var recipe: Recipe
    let book: Cookbook
    @Environment(\.dismiss) private var dismiss
    @State private var ingredientText = ""
    @State private var saveFailed = false
    @State private var directionDrafts: [DirectionDraft] = []
    @State private var choosePhoto = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var mergedOrSaved = false
    @State private var photoError = ""
    @State private var photoAddress = ""
    @State private var newCategory = ""
    @State private var chooseCategories = false
    @State private var showMerge = false
    @State private var mergeTarget = ""
    @State private var useIncomingRecipe = false

    private var duplicateCandidates: [Recipe] { book.duplicates(of: recipe) }

    private struct DirectionDraft: Identifiable {
        let id = UUID()
        var text = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Recipe name", text: $recipe.title)
                    Button {
                        chooseCategories = true
                    } label: {
                        LabeledContent("Categories", value: recipe.categories.isEmpty ? "Choose categories" : recipe.categories.joined(separator: ", "))
                    }
                    TextField("Total time", text: field(\.time))
                    TextField("Source URL", text: field(\.source))
                }
                Section("Recipe photos") {
                    ForEach(Array(recipe.photos.enumerated()), id: \.offset) { index, photo in
                        VStack(alignment: .leading) {
                            RecipePhoto(photo: photo)
                            HStack {
                                if index == 0 {
                                    Text("Cover photo").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Button("Make cover") { recipe.photos.swapAt(0, index) }
                                        .buttonStyle(.borderless)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) { recipe.photos.remove(at: index) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove photo \(index + 1)")
                            }
                        }
                    }
                    HStack {
                        TextField("Photo URL", text: $photoAddress)
                        Button("Add URL") {
                            guard let url = RecipeIntake.photoURL(photoAddress) else {
                                photoError = "Enter an HTTPS photo URL."
                                return
                            }
                            appendPhoto(RecipeImage(url: url.absoluteString))
                            photoAddress = ""
                        }.disabled(photoAddress.trimmed.isEmpty)
                    }
                    PhotosPicker("Choose from Photos", selection: $pickedPhotos, maxSelectionCount: 12, matching: .images)
                        .disabled(loadingPhotos)
                    Button("Choose photo files", systemImage: "photo") { choosePhoto = true }
                        .disabled(loadingPhotos)
                    if loadingPhotos { ProgressView("Adding photos…") }
                    if !photoError.isEmpty { Text(photoError).foregroundStyle(.red) }
                }
                Section("Ingredients · one per line") {
                    TextEditor(text: $ingredientText).frame(minHeight: 105).accessibilityLabel("Ingredients")
                }
                Section("Directions") {
                    ForEach(Array(directionDrafts.enumerated()), id: \.element.id) { index, draft in
                        HStack(alignment: .top, spacing: 10) {
                            StepNumber(number: index + 1)
                            TextField("Step \(index + 1)", text: Binding(
                                get: { directionDrafts.first(where: { $0.id == draft.id })?.text ?? "" },
                                set: { value in
                                    if let row = directionDrafts.firstIndex(where: { $0.id == draft.id }) {
                                        directionDrafts[row].text = value
                                    }
                                }
                            ), axis: .vertical)
                            .lineLimit(2...8)
                            Button(role: .destructive) {
                                directionDrafts.removeAll { $0.id == draft.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove step \(index + 1)")
                        }.padding(.vertical, 4)
                    }
                    Button("Add step", systemImage: "plus") { directionDrafts.append(DirectionDraft()) }
                }
                if let candidate = duplicateCandidates.first, book.library.recipes.contains(where: { $0.id == recipe.id }) {
                    Button("Merge with duplicate", systemImage: "arrow.triangle.merge") {
                        prepareRecipe()
                        mergeTarget = candidate.id
                        useIncomingRecipe = false
                        showMerge = true
                    }
                }
                if saveFailed { Text("Could not save this recipe. Try again.").foregroundStyle(.red) }
                Section("Notes") {
                    TextEditor(text: field(\.notes)).frame(minHeight: 55).accessibilityLabel("Notes")
                }
            }
            .formStyle(.grouped)
            .appSurface()
            .navigationTitle("Recipe details")
            .fileImporter(isPresented: $choosePhoto, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                do {
                    let urls = try result.get()
                    photoError = ""
                    var failures = 0
                    for url in urls {
                        do { appendPhoto(RecipeImage(data: try loadPhoto(url))) }
                        catch { failures += 1 }
                    }
                    if failures > 0 { photoError = "Could not read \(failures) of the selected photos." }
                } catch { photoError = error.localizedDescription }
            }
            .sheet(isPresented: $chooseCategories) { categoryPicker }
            .sheet(isPresented: $showMerge, onDismiss: {
                if mergedOrSaved { dismiss() }
            }) { mergeReview }
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                loadingPhotos = true
                Task {
                    defer { pickedPhotos = []; loadingPhotos = false }
                    var failures = 0
                    for item in items {
                        do {
                            guard let bytes = try await item.loadTransferable(type: Data.self) else {
                                throw RecipeError.message("Could not read this photo.")
                            }
                            appendPhoto(RecipeImage(data: try compressedPhoto(CGImageSourceCreateWithData(bytes as CFData, nil))))
                        } catch { failures += 1 }
                    }
                    if failures > 0 { photoError = "Could not read \(failures) of the selected photos." }
                }
            }
            .task {
                ingredientText = recipe.ingredients.joined(separator: "\n")
                directionDrafts = recipe.directionSteps.map { DirectionDraft(text: $0) }
                if directionDrafts.isEmpty { directionDrafts.append(DirectionDraft()) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        prepareRecipe()
                        if let candidate = duplicateCandidates.first, !book.library.recipes.contains(where: { $0.id == recipe.id }) {
                            mergeTarget = candidate.id
                            useIncomingRecipe = false
                            showMerge = true
                        } else { saveRecipe() }
                    }.disabled(recipe.title.trimmed.isEmpty || loadingPhotos)
                }
            }
        }
    }

    private var categoryPicker: some View {
        NavigationStack {
            Form {
                Section("Add a category") {
                    TextField("Category name", text: $newCategory)
                    Button("Add category") {
                        guard let name = book.addCategory(newCategory.trimmed) else { return }
                        recipe.categories.append(name)
                        newCategory = ""
                    }.disabled(newCategory.trimmed.isEmpty)
                }
                Section("Select categories") {
                    ForEach(Recipe.uniqueNames(book.categoryOptions + recipe.categories), id: \.self) { name in
                        let key = Recipe.nameKey(name)
                        Toggle(name, isOn: Binding(
                            get: { recipe.categories.contains { Recipe.nameKey($0) == key } },
                            set: { selected in
                                if selected { recipe.categories.append(name) }
                                else { recipe.categories.removeAll { Recipe.nameKey($0) == key } }
                            }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Categories")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chooseCategories = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 470)
        #endif
    }

    private var mergeReview: some View {
        NavigationStack {
            Form {
                Section("Merge with") {
                    Picker("Saved recipe", selection: $mergeTarget) {
                        ForEach(duplicateCandidates) { candidate in
                            Text(candidate.title + " · " + Date(timeIntervalSince1970: candidate.created / 1000)
                                .formatted(date: .abbreviated, time: .shortened)).tag(candidate.id)
                        }
                    }
                    Picker("Ingredients and directions", selection: $useIncomingRecipe) {
                        Text("Use saved recipe").tag(false)
                        Text("Use this recipe").tag(true)
                    }
                    Text("Merging combines categories, photos, and notes and keeps the saved rating when it has one.")
                        .foregroundStyle(.secondary)
                    Button("Merge recipes") {
                        let target = duplicateCandidates.first { $0.id == mergeTarget } ?? duplicateCandidates.first
                        if let target, book.merge(recipe, into: target.id, useIncomingRecipe: useIncomingRecipe) {
                            finishMerge()
                        } else {
                            saveFailed = true
                            showMerge = false
                        }
                    }.buttonStyle(.borderless)
                    if !book.library.recipes.contains(where: { $0.id == recipe.id }) {
                        Button("Save as separate recipe") {
                            if book.save(recipe) { finishMerge() }
                            else { saveFailed = true; showMerge = false }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Possible duplicate")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { showMerge = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 310)
        #endif
    }

    private func prepareRecipe() {
        recipe.title = recipe.title.trimmed
        recipe.ingredients = ingredientText.recipeLines
        recipe.directions = directionDrafts.flatMap { $0.text.recipeLines }.joined(separator: "\n")
    }

    private func saveRecipe() {
        if book.save(recipe) { dismiss() } else { saveFailed = true }
    }

    private func finishMerge() {
        mergedOrSaved = true
        showMerge = false
    }

    private func appendPhoto(_ photo: RecipeImage) {
        photoError = ""
        if !recipe.photos.contains(photo) { recipe.photos.append(photo) }
    }

    private func loadPhoto(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try compressedPhoto(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    private func compressedPhoto(_ source: CGImageSource?) throws -> Data {
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { throw RecipeError.message("Could not read this photo.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RecipeError.message("Could not save this photo.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecipeError.message("Could not save this photo.") }
        return data as Data
    }

    private func field(_ key: WritableKeyPath<Recipe, String?>) -> Binding<String> {
        Binding(get: { recipe[keyPath: key] ?? "" }, set: { recipe[keyPath: key] = $0 })
    }
}

struct RecipeDetail: View {
    let book: Cookbook
    let id: String
    let edit: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var omitted: Set<Int> = []
    @State private var confirmDelete = false
    @State private var showShare = false
    @Environment(\.appAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme
    @State private var added = false

    var body: some View {
        if let recipe = book.library.recipes.first(where: { $0.id == id }) {
            List {
                if appearance == .cookbook {
                    Text(recipe.title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.vertical, 8)
                        .listRowBackground(AppAppearance.sage(scheme))
                }
                if !recipe.photos.isEmpty {
                    Section("Recipe photos") {
                        ForEach(Array(recipe.photos.enumerated()), id: \.offset) { _, photo in RecipePhoto(photo: photo) }
                    }
                }
                Section {
                    if !recipe.categories.isEmpty { Text(recipe.categories.joined(separator: " · ")) }
                    if let time = recipe.time, !time.isEmpty { Label(time, systemImage: "clock") }
                    if let source = recipe.source, let url = RecipeIntake.webURL(source) { Link("Original recipe", destination: url) }
                    HStack {
                        ForEach(1...5, id: \.self) { stars in
                            Button {
                                var next = recipe
                                next.rating = recipe.rating == stars ? 0 : stars
                                book.save(next)
                            } label: {
                                Image(systemName: stars <= recipe.rating ? "star.fill" : "star")
                                    .foregroundStyle(.orange).padding(4)
                            }.buttonStyle(.borderless).accessibilityLabel("Rate \(stars) out of 5")
                        }
                    }
                }
                Section("Ingredients") {
                    if recipe.ingredients.isEmpty { Text("No ingredients saved.").foregroundStyle(.secondary) }
                    ForEach(recipe.ingredients.indices, id: \.self) { index in
                        Toggle(recipe.ingredients[index], isOn: Binding(
                            get: { !omitted.contains(index) },
                            set: { selected in
                                if selected { omitted.remove(index) } else { omitted.insert(index) }
                                added = false
                            }
                        ))
                    }
                    if !recipe.ingredients.isEmpty {
                        Button(added ? "Added to groceries" : "Add selected to groceries", systemImage: "cart.badge.plus") {
                            book.add(recipe.ingredients.indices.filter { !omitted.contains($0) }.map { recipe.ingredients[$0] })
                            added = book.error == nil
                        }.disabled(added || recipe.ingredients.indices.allSatisfy { omitted.contains($0) })
                    }
                }
                Section("Directions") {
                    if recipe.directionSteps.isEmpty { Text("No directions saved.").foregroundStyle(.secondary) }
                    ForEach(Array(recipe.directionSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            StepNumber(number: index + 1)
                            Text(step).lineSpacing(4).textSelection(.enabled)
                        }.padding(.vertical, 6)
                    }
                }
                if let notes = recipe.notes, !notes.isEmpty { Section("Notes") { Text(notes).textSelection(.enabled) } }
            }
            .appSurface()
            .navigationTitle(recipe.title)
            .toolbar {
                ToolbarItem {
                    Button("Share recipe", systemImage: "square.and.arrow.up") { showShare = true }
                }
                ToolbarItem { Button("Edit") { edit(recipe) } }
                ToolbarItem { Button("Delete", systemImage: "trash") { confirmDelete = true } }
            }
            .sheet(isPresented: $showShare) {
                RecipeShareView(recipe: recipe)
            }
            .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete recipe", role: .destructive) {
                    book.update { $0.recipes.removeAll { $0.id == id } }
                    if book.error == nil { dismiss() }
                }
            }
            .onChange(of: recipe.ingredients) { omitted = []; added = false }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

struct RecipeShareView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: recipe.shareText, subject: Text(recipe.title)) {
                        Label("Share as text", systemImage: "text.alignleft")
                    }
                    Text("Anyone can read the recipe in a message or email.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ShareLink(item: SharedRecipe(recipe), preview: SharePreview(recipe.title)) {
                        Label("Share recipe file", systemImage: "doc")
                    }
                    Text("Recipe app users can save the file and choose Import shared recipe from the cookbook menu.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .appSurface()
            .navigationTitle("Share recipe")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }
}

private struct StepNumber: View {
    let number: Int

    var body: some View {
        Text(number.formatted())
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .padding(6)
            .background(.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("Step \(number)")
    }
}

private struct RecipePhoto: View {
    let photo: RecipeImage

    static func embeddedImage(_ data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(macOS)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }

    var body: some View {
        if let image = Self.embeddedImage(photo.data) {
            preview(image)
        } else if let url = photo.url.flatMap({ RecipeIntake.photoURL($0) }) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): preview(image)
                case .failure: Label("Photo unavailable", systemImage: "photo").foregroundStyle(.secondary)
                default: ProgressView().accessibilityLabel("Loading recipe photo")
                }
            }
        }
    }

    private func preview(_ image: Image) -> some View {
        Color.clear.overlay { image.resizable().scaledToFill() }
            .frame(height: 160).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Recipe photo")
    }
}
