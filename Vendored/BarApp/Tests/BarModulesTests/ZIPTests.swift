import Foundation
import Testing

@testable import BarModules

/// The minimal ZIP subset the module format uses (decision 0005): stored and
/// deflate entries only, no encryption, no ZIP64, no data descriptors, and a
/// hostile-input matrix the reader must reject with a defined error.
@Suite
struct ZIPTests {
    // MARK: Golden vectors

    @Test func crc32MatchesTheStandardVector() {
        // CRC-32/ISO-HDLC of "123456789" is 0xCBF43926.
        #expect(ZIPCRC32.digest(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZIPCRC32.digest(Data()) == 0)
    }

    @Test func readsAStoredArchiveBuiltByteByByte() throws {
        let archive = Self.multiEntryArchive(names: ["schema"], contents: [Data("1".utf8)])
        let entries = try ZIPReader.read(archive).entries
        #expect(entries.count == 1)
        #expect(entries[0].name == "schema")
        #expect(entries[0].data == Data("1".utf8))
    }

    @Test func readsARealDeflateArchive() throws {
        let url = Bundle.module.url(
            forResource: "deflate-sample", withExtension: "zip"
        )
        let data = try Data(contentsOf: try #require(url))
        let entries = try ZIPReader.read(data).entries
        #expect(entries.map(\.name) == ["schema", "data/recipes.jsonl"])
        #expect(entries[0].data == Data("1".utf8))
        #expect(
            String(decoding: entries[1].data, as: UTF8.self)
                .hasPrefix("hello deflate world")
        )
    }

    // MARK: Hostile inputs, each rejected with a defined error

    private let valid = Self.multiEntryArchive(names: ["schema"], contents: [Data("1".utf8)])

    private func reject(_ data: Data, _ error: ZIPError) {
        #expect(throws: error) {
            _ = try ZIPReader.read(data)
        }
    }

    /// The offset of the central directory record for `name`.
    private func centralOffset(of name: String, in data: Data) -> Int? {
        let needle = Data([0x50, 0x4B, 0x01, 0x02])
        var from = 0
        while let at = data.range(of: needle, in: from..<data.count)?.lowerBound {
            let nameLength = Int(data[at + 28]) | Int(data[at + 29]) << 8
            let nameStart = at + 46
            let nameEnd = nameStart + nameLength
            if nameEnd <= data.count,
                String(decoding: data[nameStart..<nameEnd], as: UTF8.self) == name
            {
                return at
            }
            from = at + 1
        }
        return nil
    }

    /// The offset of the local header record for `name`.
    private func localOffset(of name: String, in data: Data) -> Int? {
        let needle = Data([0x50, 0x4B, 0x03, 0x04])
        var from = 0
        while let at = data.range(of: needle, in: from..<data.count)?.lowerBound {
            let nameLength = Int(data[at + 26]) | Int(data[at + 27]) << 8
            let nameStart = at + 30
            let nameEnd = nameStart + nameLength
            if nameEnd <= data.count,
                String(decoding: data[nameStart..<nameEnd], as: UTF8.self) == name
            {
                return at
            }
            from = at + 1
        }
        return nil
    }

    @Test func rejectsNotAZip() {
        reject(Data("not a zip".utf8), .notAZip)
    }

    @Test func rejectsTruncatedCentralDirectory() {
        // The EOCD survives but claims a central directory larger than
        // the archive holds.
        var truncated = valid
        let eocd = truncated.count - 22
        // cd size field at eocd+12: set it far beyond the archive.
        for (index, byte) in Self.le32(1 << 30).enumerated() {
            truncated[eocd + 12 + index] = byte
        }
        reject(truncated, .truncated)
    }

    @Test func rejectsCorruptedContent() {
        // Flip the stored content byte: the CRC must catch it.
        var corrupt = valid
        let local = try! #require(localOffset(of: "schema", in: corrupt))
        let nameLength = Int(corrupt[local + 26]) | Int(corrupt[local + 27]) << 8
        corrupt[local + 30 + nameLength] ^= 0xFF
        reject(corrupt, .contentMismatch)
    }

    @Test func rejectsEncryptionAndDataDescriptors() {
        // The general-purpose flags live at +6 in both header kinds.
        var encrypted = valid
        encrypted[try! #require(centralOffset(of: "schema", in: encrypted)) + 8] ^= 0x01
        reject(encrypted, .unsupportedFeature)
        var descriptor = valid
        descriptor[try! #require(centralOffset(of: "schema", in: descriptor)) + 8] ^= 0x08
        reject(descriptor, .unsupportedFeature)
    }

    @Test func rejectsUnsafePaths() {
        // Path-safety rules the generic ZIP reader enforces; the module
        // layout check on top of it lives in the module reader.
        reject(Self.multiEntryArchive(names: ["/etc/passwd"], contents: [Data()]), .unsafeEntryName)
        reject(
            Self.multiEntryArchive(names: ["data/../manifest.json"], contents: [Data()]),
            .unsafeEntryName
        )
        reject(
            Self.multiEntryArchive(names: ["data\\recipes.jsonl"], contents: [Data()]),
            .unsafeEntryName)
        reject(Self.multiEntryArchive(names: ["schema/"], contents: [Data()]), .unsafeEntryName)
        reject(Self.multiEntryArchive(names: ["."], contents: [Data()]), .unsafeEntryName)
    }

    @Test func rejectsDuplicateEntries() {
        let doubled = Self.multiEntryArchive(
            names: ["schema", "schema"],
            contents: [Data("1".utf8), Data("2".utf8)]
        )
        #expect(throws: ZIPError.duplicateEntry) {
            _ = try ZIPReader.read(doubled)
        }
    }

    @Test func rejectsDeflateRatioBombs() throws {
        // The real deflate fixture, with its declared uncompressed size
        // patched to 64 MiB against a 26-byte compressed stream: a ratio
        // the reader must refuse before inflating anything.
        let url = try #require(
            Bundle.module.url(
                forResource: "deflate-sample", withExtension: "zip"
            )
        )
        var bomb = try Data(contentsOf: url)
        let claimed = 64 << 20
        let value = Self.le32(claimed)
        let central = try #require(centralOffset(of: "data/recipes.jsonl", in: bomb))
        let local = try #require(localOffset(of: "data/recipes.jsonl", in: bomb))
        for (index, byte) in value.enumerated() {
            bomb[central + 24 + index] = byte  // central uncompressed size (+24)
            bomb[local + 22 + index] = byte  // local uncompressed size (+22)
        }
        #expect(throws: ZIPError.ratioBomb) {
            _ = try ZIPReader.read(bomb)
        }
    }

    @Test func rejectsTooManyEntries() {
        let names = (0..<4097).map { "assets/\($0)" }
        let data = Self.multiEntryArchive(
            names: names,
            contents: Array(repeating: Data(), count: names.count)
        )
        #expect(throws: ZIPError.tooManyEntries) {
            _ = try ZIPReader.read(data)
        }
    }

    // MARK: Test archive builders

    /// Stored-entry archive laid out exactly as the format specifies.
    static func multiEntryArchive(names: [String], contents: [Data]) -> Data {
        precondition(names.count == contents.count)
        var local = Data()
        var central = Data()
        var offsets: [Int] = []
        for (name, content) in zip(names, contents) {
            offsets.append(local.count)
            let nameBytes = Array(name.utf8)
            local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            local.append(contentsOf: ZIPCRC32.bytes(ZIPCRC32.digest(content)))
            local.append(contentsOf: le32(content.count))
            local.append(contentsOf: le32(content.count))
            local.append(contentsOf: le16(nameBytes.count))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: nameBytes)
            local.append(contentsOf: content)

            central.append(contentsOf: [
                0x50, 0x4B, 0x01, 0x02, 20, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            ])
            central.append(contentsOf: ZIPCRC32.bytes(ZIPCRC32.digest(content)))
            central.append(contentsOf: le32(content.count))
            central.append(contentsOf: le32(content.count))
            central.append(contentsOf: le16(nameBytes.count))
            central.append(contentsOf: le16(0))  // extra
            central.append(contentsOf: le16(0))  // comment
            central.append(contentsOf: le16(0))  // disk
            central.append(contentsOf: le16(0))  // internal attrs
            central.append(contentsOf: le32(0))  // external attrs
            central.append(contentsOf: le32(offsets.last!))
            central.append(contentsOf: nameBytes)
        }
        var eocd = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        eocd.append(contentsOf: le16(names.count))
        eocd.append(contentsOf: le16(names.count))
        eocd.append(contentsOf: le32(central.count))
        eocd.append(contentsOf: le32(local.count))
        eocd.append(contentsOf: le16(0))
        return local + central + eocd
    }

    static func le16(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    static func le32(_ value: Int) -> [UInt8] {
        [
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
        ]
    }
}
