/// Digests and signatures for module archives (decision 0005): SHA-256 for
/// the integrity section, Ed25519 for pack signatures. `swift-crypto` covers
/// both on every platform the package builds for (decision 0015).
import Crypto
import Foundation

public enum Digests {
    /// The lowercase hex SHA-256 of `data`, as the integrity section stores it.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
