import Foundation

/// One recipe as a document: everything the roadmap's model line lists,
/// as `Codable` value types.
///
/// Documents are shaped so each maps one to one onto a sync document:
/// maps of fields and lists of lines, no platform types, no Date —
/// times are `Int64` milliseconds since the Unix epoch.
public struct RecipeDocument: Codable, Hashable, Sendable {
    /// The document's schema version; migrations are explicit functions.
    public var schemaVersion: Int
    /// Stable identifier (a UUID string, minted by the app).
    public var id: String
    public var title: String
    public var summary: String
    /// The yield: how much the recipe makes, with its unit ("4
    /// servings", "24 cookies").
    public var yieldAmount: Decimal?
    public var yieldUnit: String
    public var prepTime: Duration?
    public var cookTime: Duration?
    public var totalTime: Duration?
    /// Ingredient sections: an ordered list; a section with an empty
    /// name is the implicit first section when the recipe has none.
    public var ingredientSections: [IngredientSection]
    /// Step sections, same shape.
    public var stepSections: [StepSection]
    public var tags: [String]
    public var categories: [String]
    public var cuisine: String?
    /// Where the recipe came from, kept for attribution and dedup.
    public var sourceURL: String?
    public var attribution: String?
    public var notes: String
    /// 0 means unrated; 1...5 otherwise.
    public var rating: Int
    /// Photos by content hash: the bytes live once in the library's
    /// photo store; the document references them by SHA-256 hex.
    public var photoHashes: [String]
    /// Nutrition as the source gave it, never computed here.
    public var nutrition: [String: String]
    /// Times in milliseconds since the Unix epoch.
    public var createdAt: Int64
    public var modifiedAt: Int64
    /// Soft delete: when set, the document is hidden but present until
    /// Recently Deleted empties it.
    public var deletedAt: Int64?

    public init(id: String, title: String = "", createdAt: Int64, modifiedAt: Int64) {
        self.schemaVersion = DocumentSchema.current
        self.id = id
        self.title = title
        self.summary = ""
        self.yieldUnit = "servings"
        self.ingredientSections = [IngredientSection(name: "", lines: [])]
        self.stepSections = [StepSection(name: "", steps: [])]
        self.tags = []
        self.categories = []
        self.notes = ""
        self.rating = 0
        self.photoHashes = []
        self.nutrition = [:]
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// One named group of ingredient lines.
public struct IngredientSection: Codable, Hashable, Sendable {
    public var name: String
    public var lines: [IngredientLine]

    public init(name: String, lines: [IngredientLine]) {
        self.name = name
        self.lines = lines
    }
}

/// One named group of steps.
public struct StepSection: Codable, Hashable, Sendable {
    public var name: String
    public var steps: [Step]

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }
}

/// A meal plan: recipes placed onto days and meals, with servings.
public struct PlanDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: String
    /// Entries keyed by day ("2026-11-24") and meal slot.
    public var entries: [PlanEntry]
    public var createdAt: Int64
    public var modifiedAt: Int64
    public var deletedAt: Int64?

    public init(id: String, createdAt: Int64, modifiedAt: Int64) {
        self.schemaVersion = DocumentSchema.current
        self.id = id
        self.entries = []
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// One recipe placed onto one day and meal.
public struct PlanEntry: Codable, Hashable, Sendable {
    public var day: String
    /// "breakfast", "lunch", "dinner", "snack" or a custom slot name.
    public var meal: String
    public var recipeID: String
    public var servings: Decimal

    public init(day: String, meal: String, recipeID: String, servings: Decimal) {
        self.day = day
        self.meal = meal
        self.recipeID = recipeID
        self.servings = servings
    }
}

/// A shopping list: lines that may carry a source recipe or pantry link.
public struct ListDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var lines: [ListLine]
    public var createdAt: Int64
    public var modifiedAt: Int64
    public var deletedAt: Int64?

    public init(id: String, name: String, createdAt: Int64, modifiedAt: Int64) {
        self.schemaVersion = DocumentSchema.current
        self.id = id
        self.name = name
        self.lines = []
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// One line of a shopping list.
public struct ListLine: Codable, Hashable, Sendable {
    /// The item text as shown ("2 cups flour" or "olive oil").
    public var text: String
    /// Structured, when the line came from a recipe ingredient.
    public var quantity: Quantity?
    public var unitID: String?
    public var item: String
    /// The aisle grouping label ("Produce", "Dairy").
    public var aisle: String?
    /// The recipe the line came from, when it did.
    public var recipeID: String?
    public var checked: Bool
    /// Set when a checked line was moved into the pantry.
    public var movedToPantry: Bool

    public init(text: String, item: String) {
        self.text = text
        self.item = item
        self.checked = false
        self.movedToPantry = false
    }
}

/// The pantry: what is in the kitchen, with optional amounts and
/// use-by dates.
public struct PantryDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var items: [PantryItem]
    public var createdAt: Int64
    public var modifiedAt: Int64
    public var deletedAt: Int64?

    public init(id: String, createdAt: Int64, modifiedAt: Int64) {
        self.schemaVersion = DocumentSchema.current
        self.id = id
        self.items = []
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct PantryItem: Codable, Hashable, Sendable {
    /// The item name, matched against recipes through the taxonomy (M7).
    public var name: String
    public var quantity: Quantity?
    public var unitID: String?
    /// Milliseconds since the Unix epoch; nil when the item has no
    /// use-by date.
    public var useBy: Int64?

    public init(name: String) {
        self.name = name
    }
}
