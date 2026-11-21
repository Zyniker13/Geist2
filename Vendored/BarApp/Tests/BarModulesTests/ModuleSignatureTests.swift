import BarCore
import BarModules
import BarRecipes
import Crypto
import Foundation
import Testing

/// Ed25519 signatures over the manifest's canonical form: sign with a test
/// key, verify against the trusted key id, reject tampering and wrong keys.
@Suite
struct ModuleSignatureTests {
    // MARK: Keys and helpers

    /// A signing identity for tests: a real Curve25519 key pair.
    struct TestKey {
        let id: String
        let signingKey: Curve25519.Signing.PrivateKey
        let publicKeyRaw: Data
    }

    static func makeKey(id: String) throws -> TestKey {
        let key = Curve25519.Signing.PrivateKey()
        return TestKey(
            id: id,
            signingKey: key,
            publicKeyRaw: key.publicKey.rawRepresentation)
    }

    // MARK: The manifest builder

    /// A manifest tree with real content fields, built the way the reader
    /// builds them, so the signature has something realistic to cover.
    static func manifestTree(
        id: String = "com.example.cocktails",
        recipes: Int = 1,
        ingredients: Int = 0
    ) -> [String: CanonicalJSON.Value] {
        var tree: [String: CanonicalJSON.Value] = [
            "formatVersion": .int(1),
            "id": .string(id),
            "version": .string("1.0.0"),
            "title": .string("Example module"),
            "description": .string("A tiny module for tests."),
            "languages": .array([.string("en")]),
            "authors": .array([.string("alice")]),
            "license": .string("MIT"),
            "attribution": .string("© example"),
            "minTaxonomyVersion": .int(9),
            "contents": .object([
                "recipes": .int(Int64(recipes)),
                "ingredients": .int(Int64(ingredients)),
            ]),
            "integrity": .object([
                "schema": .string(
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
            ]),
        ]
        if ingredients > 0 {
            if case .object(var contents) = tree["contents"] {
                contents["ingredients"] = .int(Int64(ingredients))
                tree["contents"] = .object(contents)
            }
        }
        return tree
    }

    /// Decode a manifest from raw JSON through the reader's real entry.
    static func manifest(fromJSON json: String) throws -> ModuleManifest {
        try ModuleManifest(rawJSON: Data(json.utf8))
    }

    /// A manifest with real content fields, decoded from raw JSON.
    static func manifest(
        id: String = "com.example.cocktails",
        recipes: Int = 1,
        ingredients: Int = 0
    ) throws -> ModuleManifest {
        try ModuleManifest(
            rawJSON: Data(
                signedManifestJSON(
                    manifestTree(id: id, recipes: recipes, ingredients: ingredients),
                    keyID: nil, signature: nil
                ).utf8))
    }

    @Test func signedManifestVerifiesAgainstTheKey() throws {
        let key = try Self.makeKey(id: "test-key-1")
        let tree = Self.manifestTree()
        let signature = try key.signingKey.signature(
            for: Self.canonicalForm(of: tree, removingSignature: true))
        let manifestJSON = Self.signedManifestJSON(tree, keyID: key.id, signature: signature)
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        let verified = try ModuleSignatures.verify(
            manifest, trustedKeys: [key.id: key.publicKeyRaw])
        #expect(verified == true)
    }

    @Test func unsignedManifestSucceedsOnNothingToVerify() throws {
        let tree = Self.manifestTree()
        let manifestJSON = Self.signedManifestJSON(tree, keyID: nil, signature: nil)
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        #expect(try ModuleSignatures.verify(manifest, trustedKeys: [:]) == false)
    }

    @Test func tamperedManifestFails() throws {
        let key = try Self.makeKey(id: "test-key-1")
        var tree = Self.manifestTree()
        let signature = try key.signingKey.signature(
            for: Self.canonicalForm(of: tree, removingSignature: true))
        // Tamper AFTER signing: bump the version string the signature covers.
        tree["version"] = .string("2.0.0")
        let manifestJSON = Self.signedManifestJSON(tree, keyID: key.id, signature: signature)
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        #expect(throws: ModuleSignatures.SignatureError.invalidSignature(keyID: "test-key-1")) {
            _ = try ModuleSignatures.verify(manifest, trustedKeys: [key.id: key.publicKeyRaw])
        }
    }

    @Test func unknownKeyIDFails() throws {
        let key = try Self.makeKey(id: "test-key-1")
        let other = try Self.makeKey(id: "other-key")
        let tree = Self.manifestTree()
        let signature = try key.signingKey.signature(
            for: Self.canonicalForm(of: tree, removingSignature: true))
        let manifestJSON = Self.signedManifestJSON(tree, keyID: other.id, signature: signature)
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        #expect(throws: ModuleSignatures.SignatureError.unknownKey(keyID: "other-key")) {
            _ = try ModuleSignatures.verify(manifest, trustedKeys: [key.id: key.publicKeyRaw])
        }
    }

    @Test func signatureWithWrongKeyFails() throws {
        let key = try Self.makeKey(id: "test-key-1")
        let other = try Self.makeKey(id: "test-key-2")
        let tree = Self.manifestTree()
        let signature = try other.signingKey.signature(
            for: Self.canonicalForm(of: tree, removingSignature: true))
        let manifestJSON = Self.signedManifestJSON(tree, keyID: key.id, signature: signature)
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        #expect(throws: ModuleSignatures.SignatureError.invalidSignature(keyID: "test-key-1")) {
            _ = try ModuleSignatures.verify(manifest, trustedKeys: [key.id: key.publicKeyRaw])
        }
    }

    @Test func signedManifestVerifiesWhenItIsTheArchiveCopy() throws {
        // End-to-end: build a signed archive, read it back, and verify.
        let key = try Self.makeKey(id: "test-key-1")
        let tree = Self.manifestTree()
        let manifestJSON = Self.signedManifestJSON(
            tree, keyID: key.id,
            signature: try key.signingKey.signature(
                for: Self.canonicalForm(of: tree, removingSignature: true)))
        let manifest = try Self.manifest(fromJSON: manifestJSON)
        let archiveBytes = try manifest.canonicalFormForSigning()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key.publicKeyRaw)
        #expect(publicKey.isValidSignature(manifest.signature!.value, for: archiveBytes))
    }

    // MARK: Building canonical bytes and JSON literals

    static func canonicalForm(of tree: [String: CanonicalJSON.Value], removingSignature: Bool)
        -> Data
    {
        var copy = tree
        if removingSignature { copy["signature"] = nil }
        return Data(CanonicalJSON.emit(.object(copy)))
    }

    static func signedManifestJSON(
        _ tree: [String: CanonicalJSON.Value],
        keyID: String?,
        signature: Data?
    ) -> String {
        var object = tree.map { "\"\($0.key)\": \(render($0.value))" }
            .sorted()
            .joined(separator: ", ")
        if let keyID, let signature {
            object +=
                ", \"signature\": {\"keyId\": \"\(keyID)\", \"signature\": \"\(signature.base64EncodedString())\"}"
        }
        return "{\(object)}"
    }

    static func render(_ value: CanonicalJSON.Value) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): "\"" + value + "\""
        case .array(let items): "[" + items.map(render).joined(separator: ", ") + "]"
        case .object(let fields):
            "{" + fields.map { "\"\($0.key)\": \(render($0.value))" }.joined(separator: ", ") + "}"
        }
    }

    static func tree(from json: String) throws -> [String: CanonicalJSON.Value] {
        guard case .object(let tree) = try CanonicalJSON.parse(Data(json.utf8)) else {
            throw TestFailure.expectedObject
        }
        return tree
    }

    enum TestFailure: Error {
        case expectedObject
    }
}
