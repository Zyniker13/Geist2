import Foundation
import Testing

@testable import RecipeCore

/// Tests for the library file package: atomic writes, content-hashed
/// photos, soft delete, and the sync port recording every change.
struct LibraryStoreTests {
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixedClock() -> LibraryClock {
        LibraryClock(now: { 1_000 }, newID: { "id-\(UUID().uuidString)" })
    }

    @Test func writeThenLoadRoundTrips() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: fixedClock())
        var recipe = RecipeDocument(id: "r1", title: "Soup", createdAt: 1, modifiedAt: 1)
        recipe.tags = ["winter"]
        try await store.write(recipe)
        let loaded = try await store.loadRecipe(id: "r1")
        #expect(loaded.title == "Soup")
        #expect(loaded.tags == ["winter"])
        // modifiedAt is stamped by the store.
        #expect(loaded.modifiedAt == 1_000)
    }

    @Test func everyWriteEmitsAChangeThroughSyncPort() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let port = RecordingSyncPort()
        let store = LibraryStore(root: root, syncPort: port, clock: fixedClock())
        var recipe = RecipeDocument(id: "r1", title: "A", createdAt: 1, modifiedAt: 1)
        try await store.write(recipe)
        recipe.title = "B"
        try await store.write(recipe)

        let changes = await port.changes
        #expect(changes.count == 2)
        #expect(changes[0].changedFieldIDs.count > 1)  // new document: all fields
        #expect(changes[1].changedFieldIDs == ["title", "modifiedAt"])
        #expect(changes[1].fields["title"] == .string("B"))
    }

    @Test func killMidWriteLeavesNoTornDocument() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: fixedClock())
        var recipe = RecipeDocument(id: "r1", title: "Original", createdAt: 1, modifiedAt: 1)
        try await store.write(recipe)

        // Simulate a crash by writing directly over the temp file path the
        // atomic write uses: the real document must survive.
        let directory = root.appendingPathComponent("recipes")
        let tempURL = directory.appendingPathComponent(".tmp-r1.json")
        try Data("{\"partial\": true".utf8).write(to: tempURL)
        let loaded = try await store.loadRecipe(id: "r1")
        #expect(loaded.title == "Original")
    }

    @Test func photoStoreDeduplicatesByContent() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: fixedClock())
        let bytes = Data("fake jpeg bytes".utf8)
        let hash1 = try await store.storePhoto(bytes)
        let hash2 = try await store.storePhoto(bytes)
        #expect(hash1 == hash2)
        #expect(hash1.count == 64)
        let read = await store.photoData(for: hash1)
        #expect(read == bytes)
    }

    @Test func softDeleteAndRestore() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: fixedClock())
        let recipe = RecipeDocument(id: "r1", title: "A", createdAt: 1, modifiedAt: 1)
        try await store.write(recipe)
        try await store.deleteRecipe(id: "r1")
        var deleted = try await store.loadRecipe(id: "r1")
        #expect(deleted.deletedAt != nil)
        try await store.restoreRecipe(id: "r1")
        deleted = try await store.loadRecipe(id: "r1")
        #expect(deleted.deletedAt == nil)
    }

    @Test func purgeRemovesFileAndPhotos() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: fixedClock())
        var recipe = RecipeDocument(id: "r1", title: "A", createdAt: 1, modifiedAt: 1)
        let hash = try await store.storePhoto(Data("img".utf8))
        recipe.photoHashes = [hash]
        try await store.write(recipe)
        try await store.deleteRecipe(id: "r1")
        try await store.purgeRecipe(id: "r1")
        await #expect(throws: LibraryError.notFound.self) {
            try await store.loadRecipe(id: "r1")
        }
        let stillThere = await store.photoData(for: hash)
        #expect(stillThere == nil)
    }
}
