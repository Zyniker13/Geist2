import Foundation

/// The module manifest, decoded from the canonical JSON value tree so the
/// integer/float distinction and unknown-field tolerance are exact.
///
/// Unknown fields are ignored, never failed (compatibility rule); the
/// required fields are checked in code, not by a decoder.
public struct ModuleManifest: Equatable, Sendable {
    /// The module format version this reader implements: 1.
    public static let currentFormatVersion = 1

    /// The module's identity, reverse-domain style (`com.example.cocktails`).
    public let id: String
    /// The module's own version, semver (`1.0.0`).
    public let version: String
    /// The module format version the archive declares.
    public let formatVersion: Int
    public let title: String
    public let description: String
    /// BCP-47 language tags the module's text is written in.
    public let languages: [String]
    public let authors: [String]
    public let publisher: String?
    /// An SPDX license identifier (`MIT`), or `LicenseRef-…`.
    public let license: String?
    /// A path inside the archive to a license file, when the license has no
    /// SPDX identifier.
    public let licenseFile: String?
    /// Attribution text the app must show.
    public let attribution: String
    public let homepage: String?
    /// The lowest taxonomy version the module's ingredients work with.
    public let minTaxonomyVersion: Int
    /// The module's monotonic content revision, when it declares one — how
    /// first-party archives tell an app "the contents changed, replace what
    /// you stored". Optional; readers that don't use it ignore it.
    public let revision: Int?
    /// What the archive carries, as counts; the reader verifies them.
    public let contents: [String: Int]
    /// SHA-256 hex digests of every other file in the archive.
    public let integrity: [String: String]
    /// The signature block, present when the archive is signed.
    public let signature: Signature?

    public struct Signature: Equatable, Sendable {
        /// The signing key's identifier in a trust store.
        public let keyID: String
        /// The Ed25519 signature over the canonical form of the manifest
        /// without this field, base64.
        public let value: Data

        public init(keyID: String, value: Data) {
            self.keyID = keyID
            self.value = value
        }
    }

    /// The manifest's canonical bytes with the `signature` field removed —
    /// exactly what an Ed25519 signature is computed over.
    public func canonicalFormForSigning() throws -> Data {
        var tree = signingTree
        tree["signature"] = nil
        return Data(CanonicalJSON.emit(.object(tree)))
    }

    /// The parsed manifest tree, kept for signature verification.
    public let signingTree: [String: CanonicalJSON.Value]

    /// How the manifest failed its shape.
    public enum ManifestError: Error, Equatable, Sendable {
        case badJSON
        case notAnObject
        case badFormatVersion
        case badModuleID
        case badVersion
        case missingField(String)
        case badField(String)
        case unknownFormatVersion(Int)
    }

    /// Decode a manifest from raw JSON bytes, checking the required fields.
    public init(rawJSON: Data) throws {
        let value: CanonicalJSON.Value
        do {
            value = try CanonicalJSON.parse(rawJSON)
        } catch {
            throw ManifestError.badJSON
        }
        guard case .object(let tree) = value else { throw ManifestError.notAnObject }
        self.signingTree = tree

        func string(_ key: String) throws -> String {
            guard case .string(let text) = tree[key] else {
                throw tree[key] == nil
                    ? ManifestError.missingField(key) : ManifestError.badField(key)
            }
            return text
        }
        func optionalString(_ key: String) throws -> String? {
            guard let raw = tree[key] else { return nil }
            guard case .string(let text) = raw else { throw ManifestError.badField(key) }
            return text
        }

        // The format version must be the exact integer the reader knows.
        guard case .int(let formatVersion) = tree["formatVersion"] ?? .int(-1) else {
            throw ManifestError.badFormatVersion
        }
        self.formatVersion = Int(formatVersion)

        let id = try string("id")
        try ModuleManifest.checkModuleID(id)
        self.id = id

        let version = try string("version")
        try ModuleManifest.checkSemver(version)
        self.version = version

        self.title = try string("title")
        self.description = try string("description")

        guard case .array(let languageValues) = tree["languages"] else {
            throw tree["languages"] == nil
                ? ManifestError.missingField("languages") : ManifestError.badField("languages")
        }
        var languages: [String] = []
        for languageValue in languageValues {
            guard case .string(let language) = languageValue, !language.isEmpty else {
                throw ManifestError.badField("languages")
            }
            languages.append(language)
        }
        guard !languages.isEmpty else { throw ManifestError.badField("languages") }
        self.languages = languages

        guard case .array(let authorValues) = tree["authors"] else {
            throw tree["authors"] == nil
                ? ManifestError.missingField("authors") : ManifestError.badField("authors")
        }
        var authors: [String] = []
        for authorValue in authorValues {
            guard case .string(let author) = authorValue, !author.isEmpty else {
                throw ManifestError.badField("authors")
            }
            authors.append(author)
        }
        guard !authors.isEmpty else { throw ManifestError.badField("authors") }
        self.authors = authors

        self.publisher = try optionalString("publisher")
        self.license = try optionalString("license")
        self.licenseFile = try optionalString("licenseFile")
        guard license != nil || licenseFile != nil else {
            throw ManifestError.missingField("license")
        }

        self.attribution = try string("attribution")
        self.homepage = try optionalString("homepage")

        guard case .int(let minTaxonomy) = tree["minTaxonomyVersion"] ?? .int(-1) else {
            throw tree["minTaxonomyVersion"] == nil
                ? ManifestError.missingField("minTaxonomyVersion")
                : ManifestError.badField("minTaxonomyVersion")
        }
        self.minTaxonomyVersion = Int(minTaxonomy)

        if case .int(let revision) = tree["revision"] {
            self.revision = Int(revision)
        } else if tree["revision"] != nil {
            throw ManifestError.badField("revision")
        } else {
            self.revision = nil
        }

        guard case .object(let contentsTree) = tree["contents"] ?? .object([:]) else {
            throw ManifestError.badField("contents")
        }
        var contents: [String: Int] = [:]
        for (key, value) in contentsTree {
            guard case .int(let count) = value, count >= 0 else {
                throw ManifestError.badField("contents")
            }
            contents[key] = Int(count)
        }
        self.contents = contents

        guard case .object(let integrityTree) = tree["integrity"] ?? .object([:]) else {
            throw ManifestError.badField("integrity")
        }
        var integrity: [String: String] = [:]
        for (key, value) in integrityTree {
            guard case .string(let digest) = value else {
                throw ManifestError.badField("integrity")
            }
            integrity[key] = digest
        }
        self.integrity = integrity

        if case .object(let signatureTree) = tree["signature"] {
            guard case .string(let keyID) = signatureTree["keyId"] ?? .null else {
                throw ManifestError.badField("signature")
            }
            guard case .string(let base64) = signatureTree["signature"] ?? .null,
                let value = Data(base64Encoded: base64), value.count == 64
            else { throw ManifestError.badField("signature") }
            self.signature = Signature(keyID: keyID, value: value)
        } else if tree["signature"] != nil {
            throw ManifestError.badField("signature")
        } else {
            self.signature = nil
        }
    }

    /// A module id is a reverse-domain name: at least two dot-separated
    /// labels of letters, digits, and hyphens, no label empty or numeric-only.
    static func checkModuleID(_ id: String) throws {
        let labels = id.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { throw ManifestError.badModuleID }
        for label in labels {
            guard !label.isEmpty, label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else {
                throw ManifestError.badModuleID
            }
            guard !(label.allSatisfy(\.isNumber)) else { throw ManifestError.badModuleID }
        }
    }

    /// A module version is a semver core: three dot-separated numeric parts.
    static func checkSemver(_ version: String) throws {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            throw ManifestError.badVersion
        }
    }
}
