import Foundation

/// The ZIP writer for module archives: stored entries only, in the order
/// given, with fixed metadata so the same files always produce the same
/// bytes. Writing archives keeps `barmod pack` and `barmod sign` inside
/// the package, with no external ZIP dependency.
public enum ZIPWriter {
    /// Why writing an archive fails. The name rules mirror the reader's:
    /// anything the reader would reject, the writer refuses to emit.
    public enum WriterError: Error, Equatable, Sendable {
        case unsafeEntryName(name: String)
        case duplicateEntry(name: String)
    }

    /// Build a stored-entry archive from named files, in the given order.
    public static func archive(of files: [(name: String, data: Data)]) throws -> Data {
        var local = Data()
        var central = Data()
        var seen = Set<String>()
        var offsets: [Int] = []
        for file in files {
            try checkEntryName(file.name)
            guard seen.insert(file.name).inserted else {
                throw WriterError.duplicateEntry(name: file.name)
            }
            offsets.append(local.count)
            let nameBytes = Array(file.name.utf8)
            let crc = ZIPCRC32.digest(file.data)
            // Local file header: signature, version 2.0, flags 0, method 0,
            // times zero, CRC, sizes, name.
            local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            local.append(contentsOf: ZIPCRC32.bytes(crc))
            local.append(contentsOf: le32(file.data.count))
            local.append(contentsOf: le32(file.data.count))
            local.append(contentsOf: le16(nameBytes.count))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: nameBytes)
            local.append(file.data)

            // Central directory header.
            central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            central.append(contentsOf: [20, 0])  // version made by
            central.append(contentsOf: [20, 0])  // version needed
            central.append(contentsOf: [0, 0])  // flags
            central.append(contentsOf: [0, 0])  // method: stored
            central.append(contentsOf: [0, 0, 0, 0])  // time and date
            central.append(contentsOf: ZIPCRC32.bytes(crc))
            central.append(contentsOf: le32(file.data.count))
            central.append(contentsOf: le32(file.data.count))
            central.append(contentsOf: le16(nameBytes.count))
            central.append(contentsOf: le16(0))  // extra length
            central.append(contentsOf: le16(0))  // comment length
            central.append(contentsOf: le16(0))  // disk number
            central.append(contentsOf: le16(0))  // internal attributes
            central.append(contentsOf: le32(0))  // external attributes
            central.append(contentsOf: le32(offsets.last!))
            central.append(contentsOf: nameBytes)
        }
        var eocd = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        eocd.append(contentsOf: le16(files.count))
        eocd.append(contentsOf: le16(files.count))
        eocd.append(contentsOf: le32(central.count))
        eocd.append(contentsOf: le32(local.count))
        eocd.append(contentsOf: le16(0))
        return local + central + eocd
    }

    /// The name rules a stored entry must satisfy, before any bytes are
    /// written (the reader re-checks on the way back in).
    static func checkEntryName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasSuffix("/"),
            !name.contains("\\"), !name.contains("\0")
        else { throw WriterError.unsafeEntryName(name: name) }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(".."), !parts.contains(".") else {
            throw WriterError.unsafeEntryName(name: name)
        }
    }

    static func le16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }

    static func le32(_ value: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
        ]
    }
}
