import Crypto
import Foundation

/// Ed25519 verification for module manifests, per decision 0005: a
/// signature in the manifest covers the canonical form of the manifest
/// with the `signature` field removed. Archives without a signature have
/// nothing to verify — callers decide whether an unsigned archive is
/// acceptable (imports are; store packs are not).
public enum ModuleSignatures {
    /// How a signature check fails.
    public enum SignatureError: Error, Equatable, Sendable {
        /// The manifest names a key the caller does not trust.
        case unknownKey(keyID: String)
        /// The signature does not match the manifest's canonical bytes.
        case invalidSignature(keyID: String)
    }

    /// Verify a manifest's signature against a trust store of raw Ed25519
    /// public keys by key id. Returns false when the manifest is unsigned;
    /// throws when it is signed and the signature does not hold.
    public static func verify(
        _ manifest: ModuleManifest,
        trustedKeys: [String: Data]
    ) throws -> Bool {
        guard let signature = manifest.signature else { return false }
        guard let keyData = trustedKeys[signature.keyID] else {
            throw SignatureError.unknownKey(keyID: signature.keyID)
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw SignatureError.unknownKey(keyID: signature.keyID)
        }
        let covered = try manifest.canonicalFormForSigning()
        guard publicKey.isValidSignature(signature.value, for: covered) else {
            throw SignatureError.invalidSignature(keyID: signature.keyID)
        }
        return true
    }

    /// Sign a manifest with a key: returns the signature bytes an author
    /// places in the manifest's `signature` block under the key's id.
    public static func sign(
        _ manifest: ModuleManifest,
        keyID: String,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> Data {
        try signingKey.signature(for: manifest.canonicalFormForSigning())
    }
}
