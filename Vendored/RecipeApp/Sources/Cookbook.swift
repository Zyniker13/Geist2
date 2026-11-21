import CoreTransferable
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct Recipe: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title = ""
    var category: String? = ""
    var time: String? = ""
    var ingredients: [String] = []
    var directions: String? = ""
    var notes: String? = ""
    var source: String? = ""
    var image: String?
    var photoData: Data?
    var extraPhotos: [RecipeImage]?
    var categoryNames: [String]?

    var categories: [String] {
        get { categoryNames ?? [category ?? ""].filter { !$0.trimmed.isEmpty } }
        set {
            categoryNames = Self.uniqueNames(newValue)
            category = categoryNames?.first
        }
    }

    var photos: [RecipeImage] {
        get {
            let cover = RecipeImage(url: image, data: photoData)
            return (cover.url != nil || cover.data != nil ? [cover] : []) + (extraPhotos ?? [])
        }
        set {
            image = newValue.first?.url
            photoData = newValue.first?.data
            extraPhotos = Array(newValue.dropFirst())
        }
    }

    static let standardCategories = ["Breakfast", "Brunch", "Lunch", "Dinner", "Appetizers", "Sides", "Salads", "Soups", "Breads", "Desserts", "Snacks", "Drinks", "Vegetarian", "Vegan", "Gluten-free", "Meal prep", "Holiday"]

    static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map(\.trimmed).filter { !$0.isEmpty && seen.insert(nameKey($0)).inserted }
    }

    static func nameKey(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    var rating = 0
    var created = Date().timeIntervalSince1970 * 1000
}

struct RecipeImage: Codable, Hashable {
    var url: String?
    var data: Data?
}

struct SharedRecipe: Codable, Transferable {
    private let format: String
    private let recipe: Recipe

    init(_ original: Recipe) {
        format = "geist2.recipe.v1"
        var copy = original
        copy.id = UUID().uuidString
        copy.notes = nil
        copy.rating = 0
        copy.created = 0
        recipe = copy
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { shared in
            let name = shared.recipe.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: "-")
            let filename = name.isEmpty ? "recipe" : String(name.prefix(45))
            let directory = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: filename + ".json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shared).write(to: file, options: .atomic)
            return SentTransferredFile(file)
        }
    }

    static func importRecipe(from data: Data) throws -> Recipe {
        guard let shared = try? JSONDecoder().decode(Self.self, from: data),
              shared.format == "geist2.recipe.v1",
              !shared.recipe.title.trimmed.isEmpty else {
            throw RecipeError.message("Choose a recipe file shared from Recipe app.")
        }
        var recipe = shared.recipe
        recipe.id = UUID().uuidString
        recipe.created = Date().timeIntervalSince1970 * 1000
        recipe.notes = nil
        recipe.rating = 0
        return recipe
    }
}

extension Recipe {
    var directionSteps: [String] {
        (directions ?? "").recipeLines.map {
            $0.replacingOccurrences(of: #"^(?:Step\s+)?[0-9]+[.):]\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
    }

    var shareText: String {
        var sections = [title]
        if !categories.isEmpty { sections.append(categories.joined(separator: ", ")) }
        if let time, !time.isEmpty { sections.append("Total time: " + time) }
        if !ingredients.isEmpty {
            sections.append((["Ingredients"] + ingredients.map { "• " + $0 }).joined(separator: "\n"))
        }
        if !directionSteps.isEmpty {
            let numbered = directionSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }
            sections.append((["Directions"] + numbered).joined(separator: "\n"))
        }
        if let source, let url = RecipeIntake.webURL(source) { sections.append("Source: " + url.absoluteString) }
        return sections.joined(separator: "\n\n")
    }
}

struct Grocery: Codable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var done = false
}

struct Library: Codable {
    var recipes: [Recipe] = []
    var groceries: [Grocery] = []
    var customCategories: [String]?

    static func decode(_ data: Data) throws -> Library {
        let library = try JSONDecoder().decode(Self.self, from: data)
        guard Set(library.recipes.map(\.id)).count == library.recipes.count,
              Set(library.groceries.map(\.id)).count == library.groceries.count,
              library.recipes.allSatisfy({ (0...5).contains($0.rating) && !$0.title.trimmed.isEmpty }) else {
            throw RecipeError.message("This backup contains invalid or duplicate entries.")
        }
        return library
    }
}

@MainActor @Observable final class Cookbook {
    private(set) var library = Library()
    var error: String?
    private let file = URL.applicationSupportDirectory.appending(path: "Geist2/Cookbook.json")

    init() {
        if FileManager.default.fileExists(atPath: file.path) {
            do { library = try Library.decode(Data(contentsOf: file)) }
            catch { self.error = "Could not read the saved cookbook. Restore a backup to recover it." }
        }
    }

    @discardableResult func update(_ edit: (inout Library) -> Void) -> Bool {
        var next = library
        edit(&next)
        return replace(with: next)
    }

    @discardableResult func replace(with next: Library) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            library = next
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult func save(_ recipe: Recipe) -> Bool {
        update {
            if let index = $0.recipes.firstIndex(where: { $0.id == recipe.id }) { $0.recipes[index] = recipe }
            else { $0.recipes.append(recipe) }
        }
    }

    var categoryOptions: [String] {
        Recipe.uniqueNames(Recipe.standardCategories + (library.customCategories ?? []) +
                           library.recipes.flatMap(\.categories)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func addCategory(_ name: String) -> String? {
        if let existing = categoryOptions.first(where: { Recipe.nameKey($0) == Recipe.nameKey(name) }) { return existing }
        guard update({ $0.customCategories = ($0.customCategories ?? []) + [name] }) else { return nil }
        return name
    }

    func duplicates(of recipe: Recipe) -> [Recipe] {
        let title = Recipe.nameKey(recipe.title)
        let source = Self.sourceKey(recipe.source)
        return library.recipes.filter {
            $0.id != recipe.id && (Recipe.nameKey($0.title) == title ||
                (source != nil && Self.sourceKey($0.source) == source))
        }
    }

    private static func sourceKey(_ address: String?) -> URL? {
        guard let url = address.flatMap(RecipeIntake.webURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.path = components.path.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        let tracking = Set(["fbclid", "link_source", "taid", "gclid"])
        let items = components.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        components.queryItems = items?.isEmpty == false ? items : nil
        return components.url
    }

    func merge(_ recipe: Recipe, into targetID: String, useIncomingRecipe: Bool) -> Bool {
        guard let target = library.recipes.first(where: { $0.id == targetID }), target.id != recipe.id else { return false }
        let backup = useIncomingRecipe ? target : recipe
        var merged = useIncomingRecipe ? recipe : target
        merged.id = target.id
        merged.created = min(target.created, recipe.created)
        merged.ingredients = merged.ingredients.isEmpty ? backup.ingredients : merged.ingredients
        if (merged.directions ?? "").trimmed.isEmpty { merged.directions = backup.directions }
        if (merged.time ?? "").trimmed.isEmpty { merged.time = backup.time }
        if (merged.source ?? "").trimmed.isEmpty { merged.source = backup.source }
        merged.categories = merged.categories + backup.categories
        var images: [RecipeImage] = []
        for image in merged.photos + backup.photos {
            if let index = images.firstIndex(where: {
                (image.url != nil && $0.url == image.url) || (image.data != nil && $0.data == image.data)
            }) {
                if images[index].data == nil { images[index].data = image.data }
            } else { images.append(image) }
        }
        merged.photos = images
        var includedNotes = Set<String>()
        merged.notes = [target.notes, recipe.notes].compactMap { $0?.trimmed }
            .filter { !$0.isEmpty && includedNotes.insert($0).inserted }.joined(separator: "\n\n")
        merged.rating = target.rating == 0 ? recipe.rating : target.rating
        return update { library in
            library.recipes.removeAll { $0.id == recipe.id }
            if let index = library.recipes.firstIndex(where: { $0.id == targetID }) { library.recipes[index] = merged }
        }
    }

    func add(_ items: [String]) {
        update { library in
            var pending = Set(library.groceries.filter { !$0.done }.map { $0.text.lowercased() })
            for item in items where pending.insert(item.lowercased()).inserted {
                library.groceries.append(Grocery(text: item))
            }
        }
    }
}

struct Backup: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var library: Library
    init(library: Library) { self.library = library }
    init(configuration: ReadConfiguration) throws {
        library = try Library.decode(configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(library))
    }
}

enum RecipeError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var recipeLines: [String] { components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty } }
}
