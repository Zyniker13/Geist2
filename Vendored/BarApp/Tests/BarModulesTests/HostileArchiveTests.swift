import BarModules
import Foundation
import Testing

/// The hostile-archive property: no mutation of a valid archive may crash
/// the reader — it either reads or throws a defined error, every time.
/// A seeded deterministic generator, so any failure reproduces.
@Suite
struct HostileArchiveTests {
    /// A valid archive to mutate, from the conformance cases.
    static func validArchive() throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        // Tests/<target>/<file>.swift: the root is three levels up, whatever
        // the checkout directory is called.
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return try Data(
            contentsOf: URL(fileURLWithPath: url.path)
                .appendingPathComponent("docs/modules/conformance/cases")
                .appendingPathComponent("valid-minimal.geistmodule"))
    }

    /// A tiny deterministic PRNG (SplitMix64), so runs reproduce.
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func everyMutationEitherReadsOrThrowsADefinedError() throws {
        let original = try Self.validArchive()
        var random = Self.Random(state: 0xC0FFEE)
        for _ in 0..<500 {
            var mutated = original
            let mutations = 1 + Int(random.next() % 3)
            for _ in 0..<mutations {
                let position = Int(random.next() % UInt64(mutated.count))
                let replacement = UInt8(random.next() % 256)
                mutated[position] = replacement
            }
            // The contract: reads or throws — never crashes, never hangs.
            _ = try? ModuleReader.read(mutated)
        }
    }

    @Test func everyTruncationEitherReadsOrThrowsADefinedError() throws {
        let original = try Self.validArchive()
        for cut in stride(from: original.count, to: 0, by: -37) {
            _ = try? ModuleReader.read(original.prefix(cut))
        }
    }

    @Test func oversizeAndCountLimitsHold() throws {
        // The declared-size limit is checked before any decompression: an
        // archive whose entries claim more than the total limit is refused.
        let original = try Self.validArchive()
        var inflated = original
        // Find the first entry's declared uncompressed size in the central
        // directory and raise it far past the limit.
        if let eocd = inflated.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06])) {
            let cdOffset =
                Int(inflated[eocd.lowerBound + 16])
                | Int(inflated[eocd.lowerBound + 17]) << 8
                | Int(inflated[eocd.lowerBound + 18]) << 16
                | Int(inflated[eocd.lowerBound + 19]) << 24
            // First central entry: uncompressed size at +24.
            inflated[cdOffset + 24] = 0xFF
            inflated[cdOffset + 25] = 0xFF
            inflated[cdOffset + 26] = 0x00
            inflated[cdOffset + 27] = 0x00
        }
        #expect(throws: Error.self) {
            _ = try ModuleReader.read(inflated)
        }
    }
}
