import Foundation

/// Loads the versioned taxonomy reference data bundled with the package.
///
/// The document lives at `Resources/taxonomy-v1.json` in the BarCore
/// target; the file name carries the schema generation of the document
/// format, so a later format change ships as a new file alongside the code
/// that understands it.
public enum TaxonomyLoader {
    public enum LoadError: Error, Equatable, Sendable {
        /// The resource is missing from the bundle — a packaging bug, not a
        /// user-facing condition.
        case missingResource
    }

    /// Decodes the bundled taxonomy document.
    public static func bundledDocument() throws -> TaxonomyDocument {
        try document(in: .module)
    }

    /// Decodes a taxonomy document from an explicit bundle. Internal so
    /// tests can point at their own copies; `Bundle.module` is internal to
    /// the package and therefore cannot back a public default argument.
    static func document(in bundle: Bundle) throws -> TaxonomyDocument {
        guard let url = bundle.url(forResource: "taxonomy-v1", withExtension: "json") else {
            throw LoadError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TaxonomyDocument.self, from: data)
    }
}
