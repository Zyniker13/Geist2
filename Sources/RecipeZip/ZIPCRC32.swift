import Foundation

/// CRC-32/ISO-HDLC (the polynomial ZIP uses), table driven.
enum ZIPCRC32 {
    static let polynomial: UInt32 = 0xEDB8_8320

    static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (value >> 1) ^ polynomial : value >> 1
            }
            table[index] = value
        }
        return table
    }()

    static func digest(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// The digest as the little-endian four bytes the ZIP headers carry.
    static func bytes(_ digest: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: digest),
            UInt8(truncatingIfNeeded: digest >> 8),
            UInt8(truncatingIfNeeded: digest >> 16),
            UInt8(truncatingIfNeeded: digest >> 24),
        ]
    }
}
