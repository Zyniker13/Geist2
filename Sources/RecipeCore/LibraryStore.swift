import Foundation

/// A clock and an ID minter the library store uses, injected as values so
/// RecipeCore stays deterministic (tests pass fixed values).
public struct LibraryClock: Sendable {
    /// Milliseconds since the Unix epoch.
    public let now: @Sendable () -> Int64
    /// Mints a stable document ID (a UUID string in the app).
    public let newID: @Sendable () -> String

    public init(
        now: @escaping @Sendable () -> Int64,
        newID: @escaping @Sendable () -> String
    ) {
        self.now = now
        self.newID = newID
    }

    /// The production clock and UUID minter. RecipeCore itself never
    /// calls this; only the app wiring does.
    public static let live = LibraryClock(
        now: { Int64(Date().timeIntervalSince1970 * 1000) },
        newID: { UUID().uuidString })
}

/// The library: a file package of JSON documents plus a photo store.
///
/// One JSON file per recipe, plan, list and pantry document. Writes are
/// atomic per document (write to a temp file, rename over). Every change
/// goes through the `SyncPort` (decision 0005). The SQLite index is
/// rebuilt from these documents and is never the source of truth.
public actor LibraryStore {
    public let root: URL
    public let photos: PhotoStore
    private var syncPort: SyncPort
    private let clock: LibraryClock

    public init(
        root: URL, syncPort: SyncPort = NullSyncPort(),
        clock: LibraryClock = .live
    ) {
        self.root = root
        self.photos = PhotoStore(root: root.appendingPathComponent("Photos"))
        self.syncPort = syncPort
        self.clock = clock
    }

    /// Attaches a different sync port (the app does this once at setup).
    public func setSyncPort(_ port: SyncPort) {
        syncPort = port
    }

    // MARK: Reading

    public func listIDs(kind: DocumentKind) throws -> [String] {
        let directory = root.appendingPathComponent(kind.rawValue + "s")
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return
            files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Loads and decodes one document, migrating it forward when its
    /// schema version is older than current.
    public func loadRecipe(id: String) throws -> RecipeDocument {
        let data = try read(kind: .recipe, id: id)
        return try decode(data, kind: .recipe)
    }

    public func loadPlan(id: String) throws -> PlanDocument {
        try decode(try read(kind: .plan, id: id), kind: .plan)
    }

    public func loadList(id: String) throws -> ListDocument {
        try decode(try read(kind: .list, id: id), kind: .list)
    }

    public func loadPantry(id: String) throws -> PantryDocument {
        try decode(try read(kind: .pantry, id: id), kind: .pantry)
    }

    // MARK: Writing

    /// Writes a recipe. The document's `modifiedAt` is stamped by the
    /// store (the writer may not lie about it), and a field-level change
    /// is emitted through the sync port.
    public func write(_ recipe: RecipeDocument) async throws {
        var copy = recipe
        let now = clock.now()
        let old = (try? loadRecipe(id: recipe.id))?.syncFields()
        let changed = diff(oldNew: (old, copy.syncFields()))
        copy.modifiedAt = now
        try writeJSON(copy.encoded(), kind: .recipe, id: recipe.id)
        await emit(
            DocumentChange(
                kind: .recipe, documentID: recipe.id,
                changedFieldIDs: changed, fields: copy.syncFields(),
                modifiedAt: now))
    }

    public func write(_ plan: PlanDocument) async throws {
        var copy = plan
        let now = clock.now()
        let old = (try? loadPlan(id: plan.id))?.syncFields()
        let changed = diff(oldNew: (old, copy.syncFields()))
        copy.modifiedAt = now
        try writeJSON(copy.encoded(), kind: .plan, id: plan.id)
        await emit(
            DocumentChange(
                kind: .plan, documentID: plan.id,
                changedFieldIDs: changed, fields: copy.syncFields(),
                modifiedAt: now))
    }

    public func write(_ list: ListDocument) async throws {
        var copy = list
        let now = clock.now()
        let old = (try? loadList(id: list.id))?.syncFields()
        let changed = diff(oldNew: (old, copy.syncFields()))
        copy.modifiedAt = now
        try writeJSON(copy.encoded(), kind: .list, id: list.id)
        await emit(
            DocumentChange(
                kind: .list, documentID: list.id,
                changedFieldIDs: changed, fields: copy.syncFields(),
                modifiedAt: now))
    }

    public func write(_ pantry: PantryDocument) async throws {
        var copy = pantry
        let now = clock.now()
        let old = (try? loadPantry(id: pantry.id))?.syncFields()
        let changed = diff(oldNew: (old, copy.syncFields()))
        copy.modifiedAt = now
        try writeJSON(copy.encoded(), kind: .pantry, id: pantry.id)
        await emit(
            DocumentChange(
                kind: .pantry, documentID: pantry.id,
                changedFieldIDs: changed, fields: copy.syncFields(),
                modifiedAt: now))
    }

    // MARK: Photos

    @discardableResult
    public func storePhoto(_ data: Data) throws -> String {
        try photos.store(data)
    }

    public func photoData(for hash: String) -> Data? {
        photos.data(for: hash)
    }

    // MARK: Soft delete

    /// Soft-deletes a recipe: sets `deletedAt`, keeps the file.
    public func deleteRecipe(id: String) async throws {
        var recipe = try loadRecipe(id: id)
        recipe.deletedAt = clock.now()
        try await write(recipe)
    }

    /// Restores a soft-deleted recipe.
    public func restoreRecipe(id: String) async throws {
        var recipe = try loadRecipe(id: id)
        recipe.deletedAt = nil
        try await write(recipe)
    }

    /// Permanently removes a soft-deleted recipe and its orphaned photos.
    public func purgeRecipe(id: String) async throws {
        let recipe = try loadRecipe(id: id)
        guard recipe.deletedAt != nil else {
            throw LibraryError.notFound
        }
        for hash in recipe.photoHashes {
            photos.delete(hash)
        }
        try FileManager.default.removeItem(at: fileURL(kind: .recipe, id: id))
        await emit(
            DocumentChange(
                kind: .recipe, documentID: id,
                changedFieldIDs: ["deletedAt"], fields: ["deletedAt": .null],
                modifiedAt: clock.now()))
    }

    // MARK: Internals

    private func read(kind: DocumentKind, id: String) throws -> Data {
        let url = fileURL(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryError.notFound
        }
        return try Data(contentsOf: url)
    }

    private func fileURL(kind: DocumentKind, id: String) -> URL {
        root.appendingPathComponent(kind.rawValue + "s")
            .appendingPathComponent(id + ".json")
    }

    private func writeJSON(_ data: Data, kind: DocumentKind, id: String) throws {
        let directory = root.appendingPathComponent(kind.rawValue + "s", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(id + ".json")
        try data.write(to: url, options: .atomic)
    }

    /// Decodes a document, migrating its JSON forward when the schema
    /// version on disk is older than current.
    private func decode<T: Decodable & DocumentDecoding>(
        _ data: Data, kind: DocumentKind
    ) throws -> T {
        let version = try T.readSchemaVersion(data)
        let migrated = try Migrations.upgrade(data, kind: kind, from: version)
        guard let document = try? T.decode(from: migrated) else {
            throw LibraryError.malformed
        }
        return document
    }

    /// The field names written between the old and new states, by stable
    /// field name. A new document (no old state) writes every field.
    private func diff(
        oldNew: (old: [String: FieldValue]?, new: [String: FieldValue])
    ) -> Set<String> {
        guard let old = oldNew.old else { return Set(oldNew.new.keys) }
        var changed: Set<String> = []
        for (key, newValue) in oldNew.new where old[key] != newValue {
            changed.insert(key)
        }
        for key in old.keys where oldNew.new[key] == nil {
            changed.insert(key)
        }
        return changed
    }

    private func emit(_ change: DocumentChange) async {
        await syncPort.apply(change)
    }
}

/// Decoding helpers shared by the store's generic decode.
public protocol DocumentDecoding: Decodable, Sendable {
    static func readSchemaVersion(_ data: Data) throws -> Int
    static func decode(from data: Data) throws -> Self
}

extension RecipeDocument: DocumentDecoding {
    public static func readSchemaVersion(_ data: Data) throws -> Int {
        try Self.schemaVersion(in: data)
    }

    public static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

extension PlanDocument: DocumentDecoding {
    public static func readSchemaVersion(_ data: Data) throws -> Int {
        try Self.schemaVersion(in: data)
    }

    public static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

extension ListDocument: DocumentDecoding {
    public static func readSchemaVersion(_ data: Data) throws -> Int {
        try Self.schemaVersion(in: data)
    }

    public static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

extension PantryDocument: DocumentDecoding {
    public static func readSchemaVersion(_ data: Data) throws -> Int {
        try Self.schemaVersion(in: data)
    }

    public static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

/// Reading `schemaVersion` without decoding the whole document.
private struct SchemaEnvelope: Decodable {
    let schemaVersion: Int?
}

extension DocumentDecoding where Self: Decodable {
    static func schemaVersion(in data: Data) throws -> Int {
        let envelope = try? JSONDecoder().decode(SchemaEnvelope.self, from: data)
        guard let version = envelope?.schemaVersion else {
            throw SchemaError.missingVersion
        }
        return version
    }
}
