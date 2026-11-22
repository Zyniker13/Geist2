import Foundation
import GRDB

/// The SQLite index over the library (M1.3).
///
/// The documents are the source of truth; this index is rebuilt from
/// them and can be deleted and recreated at any time. It exists for
/// full-text search (FTS5) and for the filters the browser needs (tag,
/// category, cuisine, time, rating), which would otherwise require
/// loading every document.
public actor RecipeIndex {
    /// The index database, separate from the documents.
    private let dbPath: String

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbPath = directory.appendingPathComponent("index.sqlite").path
    }

    /// Rebuilds the whole index from recipes. Idempotent: clears the
    /// tables first. Returns the number of indexed recipes.
    @discardableResult
    public func rebuild(from recipes: [RecipeDocument]) throws -> Int {
        let pool = try DatabasePool(path: dbPath)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "recipe") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("tags", .text).notNull()  // JSON array
                t.column("categories", .text).notNull()
                t.column("cuisine", .text)
                t.column("totalSeconds", .integer)
                t.column("rating", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("modifiedAt", .integer).notNull()
                t.column("ingredientsText", .text).notNull()
                t.column("stepsText", .text).notNull()
                t.column("notes", .text).notNull()
            }
            try db.create(virtualTable: "recipeFTS", using: FTS5()) { t in
                t.synchronize(withTable: "recipe")
                t.column("title")
                t.column("summary")
                t.column("ingredientsText")
                t.column("stepsText")
                t.column("notes")
                t.column("tags")
            }
        }
        try migrator.migrate(pool)

        try pool.write { db in
            try db.execute(sql: "DELETE FROM recipe")
            for recipe in recipes where recipe.deletedAt == nil {
                let ingredients = recipe.ingredientSections.flatMap(\.lines)
                    .map { line in
                        [line.item, line.preparation ?? "", line.note ?? ""]
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                    .joined(separator: "\n")
                let steps = recipe.stepSections.flatMap(\.steps)
                    .map(\.text).joined(separator: "\n")
                try db.execute(
                    sql: """
                        INSERT INTO recipe
                        (id, title, summary, tags, categories, cuisine, totalSeconds,
                         rating, deletedAt, modifiedAt, ingredientsText, stepsText, notes)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        recipe.id, recipe.title, recipe.summary,
                        toJSON(recipe.tags), toJSON(recipe.categories),
                        recipe.cuisine, recipe.totalTime?.seconds,
                        recipe.rating, recipe.deletedAt, recipe.modifiedAt,
                        ingredients, steps, recipe.notes,
                    ])
            }
        }
        return recipes.filter { $0.deletedAt == nil }.count
    }

    /// Full-text search over title, ingredients, steps, tags and notes.
    /// Returns matching recipe IDs, best first.
    public func search(_ query: String) throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pool = try DatabasePool(path: dbPath)
        return try pool.read { db in
            // Every term becomes a prefix term: "tom" matches "tomato".
            let terms = trimmed.split(whereSeparator: \.isWhitespace)
                .map { term -> String in
                    let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(escaped)\"*"
                }
                .joined(separator: " ")
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT recipe.id FROM recipe
                    JOIN recipeFTS ON recipe.rowid = recipeFTS.rowid
                    WHERE recipeFTS MATCH ?
                      AND recipe.deletedAt IS NULL
                    ORDER BY rank
                    """,
                arguments: [terms])
            return rows.map { $0["id"] as String }
        }
    }

    /// Filters: tag, category, cuisine, maximum total time, minimum rating.
    public func filter(
        tag: String? = nil, category: String? = nil, cuisine: String? = nil,
        maxTotalSeconds: Int? = nil, minRating: Int? = nil
    ) throws -> [String] {
        var conditions: [String] = ["deletedAt IS NULL"]
        var arguments: [DatabaseValueConvertible] = []
        if let tag {
            conditions.append("tags LIKE ?")
            arguments.append("%\"\(tag)\"%")
        }
        if let category {
            conditions.append("categories LIKE ?")
            arguments.append("%\"\(category)\"%")
        }
        if let cuisine {
            conditions.append("cuisine = ?")
            arguments.append(cuisine)
        }
        if let maxTotalSeconds {
            conditions.append("totalSeconds <= ?")
            arguments.append(maxTotalSeconds)
        }
        if let minRating {
            conditions.append("rating >= ?")
            arguments.append(minRating)
        }
        let pool = try DatabasePool(path: dbPath)
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM recipe WHERE \(conditions.joined(separator: " AND "))",
                arguments: StatementArguments(arguments))
            return rows.map { $0["id"] as String }
        }
    }

    private func toJSON(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
