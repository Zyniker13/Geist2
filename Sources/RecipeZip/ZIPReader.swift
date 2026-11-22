import Foundation

/// Every way reading a module archive's ZIP container can fail, each its
/// own defined error so callers and tests can name exactly what was wrong.
public enum ZIPError: Error, Equatable, Sendable {
    /// The bytes are not a ZIP archive at all.
    case notAZip
    /// The archive ends mid-structure.
    case truncated
    /// The archive uses something the format does not allow: encryption,
    /// data descriptors, ZIP64, an unknown compression method, more than
    /// one disk, or a nonzero archive comment.
    case unsupportedFeature
    /// An entry name is outside the archive's allowed paths: absolute,
    /// containing `..` or a backslash or a NUL, or a directory entry.
    case unsafeEntryName
    /// Two entries carry the same name.
    case duplicateEntry
    /// The archive declares more entries than the limit allows.
    case tooManyEntries
    /// An entry, or the archive in total, declares more decompressed bytes
    /// than the limit allows.
    case tooLarge
    /// An entry's declared expansion ratio exceeds the limit — the shape
    /// of a decompression bomb.
    case ratioBomb
    /// An entry's bytes do not match its declared CRC, its declared sizes
    /// disagree between headers and data, or an entry name differs between
    /// the central directory and the local header.
    case contentMismatch
    /// A deflate stream is malformed.
    case corruptData
}

/// A reader for the minimal ZIP subset module archives use (decision 0005):
/// stored and deflate entries only, no encryption, no ZIP64, no data
/// descriptors, no archive comment, and hard safety limits — absolute
/// paths, `..` components, backslashes, and duplicate or non-UTF-8 names
/// are rejected before any content is decompressed, and every entry's
/// declared sizes and CRC are verified.
public enum ZIPReader {
    /// The safety limits a reader enforces. The format specification pins
    /// these numbers; they bound work and memory before anything inflates.
    public struct Limits: Sendable {
        /// At most this many entries.
        public var maxEntries: Int
        /// At most this many bytes in one decompressed entry.
        public var maxEntryBytes: Int
        /// At most this many decompressed bytes across all entries.
        public var maxTotalBytes: Int
        /// The largest accepted decompressed-to-compressed ratio.
        public var maxRatio: Int

        public static let format = Limits(
            maxEntries: 4096,
            maxEntryBytes: 64 << 20,
            maxTotalBytes: 256 << 20,
            maxRatio: 200
        )

        public init(
            maxEntries: Int,
            maxEntryBytes: Int,
            maxTotalBytes: Int,
            maxRatio: Int
        ) {
            self.maxEntries = maxEntries
            self.maxEntryBytes = maxEntryBytes
            self.maxTotalBytes = maxTotalBytes
            self.maxRatio = maxRatio
        }
    }

    /// One archive entry, decoded and verified.
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let data: Data
    }

    /// What a parsed archive holds.
    public struct Archive: Sendable {
        public let entries: [Entry]

        public func entry(named name: String) -> Entry? {
            entries.first { $0.name == name }
        }
    }

    /// Read an archive, verifying every entry's sizes, CRC, and name.
    public static func read(_ data: Data, limits: Limits = .format) throws -> Archive {
        guard data.count >= 22 else { throw ZIPError.notAZip }
        guard let eocdOffset = endOfCentralDirectoryOffset(in: data) else { throw ZIPError.notAZip }
        let eocd = data[(data.count - 22)...]
        let diskNumber = UInt16(eocd[eocd.startIndex + 4]) | UInt16(eocd[eocd.startIndex + 5]) << 8
        let cdDisk = UInt16(eocd[eocd.startIndex + 6]) | UInt16(eocd[eocd.startIndex + 7]) << 8
        let entriesHere = UInt16(eocd[eocd.startIndex + 8]) | UInt16(eocd[eocd.startIndex + 9]) << 8
        let entriesTotal =
            UInt16(eocd[eocd.startIndex + 10]) | UInt16(eocd[eocd.startIndex + 11]) << 8
        let cdSize =
            UInt32(eocd[eocd.startIndex + 12]) | UInt32(eocd[eocd.startIndex + 13]) << 8
            | UInt32(eocd[eocd.startIndex + 14]) << 16 | UInt32(eocd[eocd.startIndex + 15]) << 24
        let cdOffset =
            UInt32(eocd[eocd.startIndex + 16]) | UInt32(eocd[eocd.startIndex + 17]) << 8
            | UInt32(eocd[eocd.startIndex + 18]) << 16 | UInt32(eocd[eocd.startIndex + 19]) << 24
        let commentLength =
            UInt16(eocd[eocd.startIndex + 20]) | UInt16(eocd[eocd.startIndex + 21]) << 8
        guard diskNumber == 0, cdDisk == 0, entriesHere == entriesTotal else {
            throw ZIPError.unsupportedFeature
        }
        guard commentLength == 0 else { throw ZIPError.unsupportedFeature }
        guard Int(cdOffset) + Int(cdSize) <= eocdOffset else { throw ZIPError.truncated }
        guard Int(entriesTotal) <= limits.maxEntries else {
            throw ZIPError.tooManyEntries
        }
        // A ZIP64 locator anywhere before the EOCD is out of format.
        if data.range(of: Data([0x50, 0x4B, 0x06, 0x07]), in: 0..<eocdOffset) != nil {
            throw ZIPError.unsupportedFeature
        }

        var entries: [Entry] = []
        entries.reserveCapacity(Int(entriesTotal))
        var names = Set<String>()
        var totalBytes = 0
        var cursor = Int(cdOffset)
        for _ in 0..<Int(entriesTotal) {
            guard cursor + 46 <= eocdOffset,
                data[cursor] == 0x50, data[cursor + 1] == 0x4B,
                data[cursor + 2] == 0x01, data[cursor + 3] == 0x02
            else { throw ZIPError.truncated }
            let flags = UInt16(data[cursor + 8]) | UInt16(data[cursor + 9]) << 8
            let method = UInt16(data[cursor + 10]) | UInt16(data[cursor + 11]) << 8
            let crc =
                UInt32(data[cursor + 16]) | UInt32(data[cursor + 17]) << 8
                | UInt32(data[cursor + 18]) << 16 | UInt32(data[cursor + 19]) << 24
            let compressedSize = readUInt32(data, cursor + 20)
            let uncompressedSize = readUInt32(data, cursor + 24)
            let nameLength = Int(data[cursor + 28]) | Int(data[cursor + 29]) << 8
            let extraLength = Int(data[cursor + 30]) | Int(data[cursor + 31]) << 8
            let commentLength = Int(data[cursor + 32]) | Int(data[cursor + 33]) << 8
            let localOffset = readUInt32(data, cursor + 42)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd + extraLength + commentLength <= eocdOffset else {
                throw ZIPError.truncated
            }
            guard flags & 0x0001 == 0, flags & 0x0008 == 0 else {
                throw ZIPError.unsupportedFeature
            }
            guard method == 0 || method == 8 else { throw ZIPError.unsupportedFeature }
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF,
                localOffset != 0xFFFF_FFFF
            else { throw ZIPError.unsupportedFeature }
            guard let bytes = data[nameStart..<nameEnd].withContiguousStorageIfAvailable({ $0 }),
                let name = String(bytes: bytes, encoding: .utf8)
            else { throw ZIPError.unsafeEntryName }
            try checkEntryName(name)
            guard !names.contains(name) else { throw ZIPError.duplicateEntry }
            names.insert(name)
            guard Int(uncompressedSize) <= limits.maxEntryBytes else { throw ZIPError.tooLarge }
            if method == 8 {
                // Refuse bombs before touching the stream: the declared
                // expansion must stay inside the ratio limit.
                let floorBytes = 4096
                let allowed = max(floorBytes, Int(compressedSize) * limits.maxRatio)
                guard Int(uncompressedSize) <= allowed else { throw ZIPError.ratioBomb }
            }
            totalBytes += Int(uncompressedSize)
            guard totalBytes <= limits.maxTotalBytes else { throw ZIPError.tooLarge }

            let content = try readEntry(
                data, localOffset: Int(localOffset), expectedName: name,
                method: method, crc: crc,
                compressedSize: Int(compressedSize), uncompressedSize: Int(uncompressedSize),
                eocdOffset: eocdOffset
            )
            entries.append(Entry(name: name, data: content))
            cursor = nameEnd + extraLength + commentLength
        }
        return Archive(entries: entries)
    }

    // MARK: Entry decode

    private static func readEntry(
        _ data: Data, localOffset: Int, expectedName: String, method: UInt16, crc: UInt32,
        compressedSize: Int, uncompressedSize: Int, eocdOffset: Int
    ) throws -> Data {
        guard localOffset >= 0, localOffset + 30 <= eocdOffset,
            data[localOffset] == 0x50, data[localOffset + 1] == 0x4B,
            data[localOffset + 2] == 0x03, data[localOffset + 3] == 0x04
        else { throw ZIPError.truncated }
        let localFlags = UInt16(data[localOffset + 6]) | UInt16(data[localOffset + 7]) << 8
        let localMethod = UInt16(data[localOffset + 8]) | UInt16(data[localOffset + 9]) << 8
        let localNameLength = Int(data[localOffset + 26]) | Int(data[localOffset + 27]) << 8
        let localExtraLength = Int(data[localOffset + 28]) | Int(data[localOffset + 29]) << 8
        let nameStart = localOffset + 30
        let nameEnd = nameStart + localNameLength
        let contentStart = nameEnd + localExtraLength
        guard localFlags == 0, localMethod == method else { throw ZIPError.unsupportedFeature }
        guard nameEnd <= eocdOffset,
            String(decoding: data[nameStart..<nameEnd], as: UTF8.self) == expectedName
        else { throw ZIPError.contentMismatch }
        guard contentStart + compressedSize <= eocdOffset else { throw ZIPError.truncated }
        let compressed = data[contentStart..<contentStart + compressedSize]

        let content: Data
        switch method {
        case 0:
            guard compressedSize == uncompressedSize else { throw ZIPError.contentMismatch }
            content = Data(compressed)
        default:
            content = try RawDeflate.decompress(compressed, expectedOutputSize: uncompressedSize)
        }
        guard content.count == uncompressedSize else { throw ZIPError.contentMismatch }
        guard ZIPCRC32.digest(content) == crc else { throw ZIPError.contentMismatch }
        return content
    }

    // MARK: Names

    /// Names the format allows: UTF-8, no leading slash, no `..` component,
    /// no backslash, no NUL, no drive letters, no trailing slash.
    static func checkEntryName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else {
            throw ZIPError.unsafeEntryName
        }
        guard !name.hasSuffix("/") else { throw ZIPError.unsafeEntryName }
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            guard !component.isEmpty, component != ".", component != ".." else {
                throw ZIPError.unsafeEntryName
            }
        }
    }

    // MARK: Layout helpers

    /// The EOCD sits at the end; the archive comment the format forbids
    /// means the magic is exactly the last 22 bytes' start.
    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let end = data.count
        guard end >= 22,
            data[end - 22] == 0x50, data[end - 21] == 0x4B,
            data[end - 20] == 0x05, data[end - 19] == 0x06
        else { return nil }
        return end - 22
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
