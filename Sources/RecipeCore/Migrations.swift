import Foundation

/// Explicit, tested migrations between document schema versions.
///
/// A migration is a pure function from the JSON of one version to the
/// JSON of the next. Migrations are composed in order, so a document of
/// version N is migrated forward by applying `migrations[N]`,
/// `migrations[N+1]`, ... up to `current`. Documents of a version newer
/// than `current` are refused (a future app wrote them).
public enum Migrations {
    /// Migrate a document's JSON from `fromVersion` to the current
    /// version. Throws `SchemaError.unsupportedVersion` for versions the
    /// current build cannot read, and returns the JSON unchanged when
    /// the document is already current.
    public static func upgrade(
        _ data: Data, kind: DocumentKind, from fromVersion: Int
    ) throws -> Data {
        guard fromVersion <= DocumentSchema.current else {
            throw SchemaError.unsupportedVersion(fromVersion)
        }
        var json = try JSONSerialization.jsonObject(with: data)
        var version = fromVersion
        while version < DocumentSchema.current {
            guard let step = migrations[version] else { break }
            json = try step(json, kind)
            version += 1
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// One migration step per source version. `migrations[1]` upgrades a
    /// version-1 document to version 2, and so on. Empty until a schema
    /// change ships; the migration tests still exercise the machinery.
    static var migrations: [Int: (Any, DocumentKind) throws -> Any] {
        [:]
    }
}
