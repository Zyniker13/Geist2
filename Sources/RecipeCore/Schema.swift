import Foundation

/// The schema version of the on-disk document formats. Bumping this
/// number means a migration function is required; migrations are
/// explicit, tested functions from one version to the next (M1.1).
public enum DocumentSchema {
    /// The current schema version of every document type.
    public static let current = 1
}

/// Errors raised when decoding a document of an unknown or unsupported
/// schema version.
public enum SchemaError: Error, Equatable, Sendable {
    /// The document declares a schema version newer than this build
    /// understands (written by a future version of the app).
    case unsupportedVersion(Int)
    /// The document declares no schema version and no default can apply.
    case missingVersion
}
