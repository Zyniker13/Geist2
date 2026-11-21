import Crypto
import Foundation

/// Why a document could not be stored or read.
public enum LibraryError: Error, Equatable, Sendable {
    /// The document's JSON is malformed.
    case malformed
    /// The document declares an unsupported schema version.
    case unsupportedVersion(Int)
    /// A write failed at the filesystem level.
    case writeFailed
    /// The document was not found.
    case notFound
}

/// Content hashing for photos and integrity checks.
public enum ContentHash {
    /// The SHA-256 hex digest of bytes.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A content-hashed photo stored once in the library, referenced by its
/// SHA-256 hex digest from every document that uses it.
public struct PhotoStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Stores photo bytes under their content hash; returns the hash.
    /// Storing the same bytes again is a no-op that returns the same
    /// hash — photos are deduplicated by construction.
    public func store(_ data: Data) throws -> String {
        let digest = ContentHash.sha256Hex(data)
        let directory = root.appendingPathComponent(Self.directory(for: digest), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(digest)
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file, options: .atomic)
        }
        return digest
    }

    /// Reads the bytes for a content hash, or nil when the photo is
    /// missing (a dangling reference, tolerated on read).
    public func data(for hash: String) -> Data? {
        let file = root.appendingPathComponent(Self.directory(for: hash))
            .appendingPathComponent(hash)
        return try? Data(contentsOf: file)
    }

    /// Deletes a stored photo; missing files are ignored.
    public func delete(_ hash: String) {
        let file = root.appendingPathComponent(Self.directory(for: hash))
            .appendingPathComponent(hash)
        try? FileManager.default.removeItem(at: file)
    }

    /// All stored hashes.
    public func allHashes() -> [String] {
        let shards =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
        var hashes: [String] = []
        for shard in shards {
            let nested =
                (try? FileManager.default.contentsOfDirectory(
                    at: shard, includingPropertiesForKeys: nil)) ?? []
            hashes.append(contentsOf: nested.map(\.lastPathComponent))
        }
        return hashes.sorted()
    }

    /// Two-character shard directories keep photo folders from growing
    /// past a few thousand entries.
    static func directory(for hash: String) -> String {
        String(hash.prefix(2))
    }
}
