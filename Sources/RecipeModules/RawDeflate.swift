import Foundation

#if canImport(Compression)
    import Compression
#elseif canImport(CZlib)
    import CZlib
#endif

/// Raw DEFLATE (RFC 1951) — the stream format ZIP entries carry — through
/// Apple's Compression framework on Apple platforms and the system zlib on
/// Linux (decision 0005). No zlib wrapper bytes either way.
enum RawDeflate {
    /// The most the decompressor will produce for one entry.
    static func decompress(_ input: Data, expectedOutputSize: Int) throws -> Data {
        guard expectedOutputSize > 0 else { return Data() }
        var output = Data(count: expectedOutputSize)
        let written = try output.withUnsafeMutableBytes {
            (out: UnsafeMutableRawBufferPointer) -> Int in
            try input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> Int in
                #if canImport(Compression)
                    let result = compression_decode_buffer(
                        out.bindMemory(to: UInt8.self).baseAddress!,
                        expectedOutputSize,
                        inputBytes.bindMemory(to: UInt8.self).baseAddress!,
                        input.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                    guard result > 0 || (expectedOutputSize == 0 && input.isEmpty) else {
                        throw ZIPError.corruptData
                    }
                    return result
                #else
                    return try ZLib.rawInflate(
                        inputBytes.bindMemory(to: UInt8.self).baseAddress!,
                        input.count,
                        out.bindMemory(to: UInt8.self).baseAddress!,
                        expectedOutputSize
                    )
                #endif
            }
        }
        guard written == expectedOutputSize else { throw ZIPError.contentMismatch }
        return output.prefix(written)
    }

    /// Compress `input` as raw DEFLATE, returning nil when the data does
    /// not shrink (the writer then stores the entry uncompressed).
    static func compress(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        #if canImport(Compression)
            let destinationCapacity = input.count
            var destination = Data(count: destinationCapacity)
            let written = destination.withUnsafeMutableBytes {
                (out: UnsafeMutableRawBufferPointer) -> Int in
                input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                    compression_encode_buffer(
                        out.bindMemory(to: UInt8.self).baseAddress!,
                        destinationCapacity,
                        source.bindMemory(to: UInt8.self).baseAddress!,
                        input.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard written > 0, written < input.count else { return nil }
            return destination.prefix(written)
        #else
            return ZLib.rawDeflate(input)
        #endif
    }
}

#if !canImport(Compression)
    /// The system zlib on Linux, reached through the CZlib system library
    /// target: raw DEFLATE streams (window bits -15), like ZIP entries use.
    enum ZLib {
        static func rawInflate(
            _ source: UnsafePointer<UInt8>, _ sourceCount: Int,
            _ destination: UnsafeMutablePointer<UInt8>, _ destinationCount: Int
        ) throws -> Int {
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source)
            stream.avail_in = UInt32(sourceCount)
            let status = inflateInit2_(
                &stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else { throw ZIPError.corruptData }
            defer { inflateEnd(&stream) }
            stream.next_out = destination
            stream.avail_out = UInt32(destinationCount)
            let result = inflate(&stream, Z_FINISH)
            guard result == Z_STREAM_END else { throw ZIPError.corruptData }
            return destinationCount - Int(stream.avail_out)
        }

        static func rawDeflate(_ input: Data) -> Data? {
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data in
                var stream = z_stream()
                let status = deflateInit2_(
                    &stream, 6, Z_DEFLATED, -15, 8,
                    Z_DEFAULT_STRATEGY, zlibVersion(),
                    Int32(MemoryLayout<z_stream>.size)
                )
                guard status == Z_OK else { return Data() }
                defer { deflateEnd(&stream) }
                var output = Data(count: input.count + 64)
                let written = output.withUnsafeMutableBytes {
                    (out: UnsafeMutableRawBufferPointer) -> Int in
                    stream.next_in = UnsafeMutablePointer<Bytef>(
                        mutating: source.bindMemory(to: UInt8.self).baseAddress!)
                    stream.avail_in = UInt32(input.count)
                    stream.next_out = out.bindMemory(to: UInt8.self).baseAddress!
                    stream.avail_out = UInt32(out.count)
                    let result = deflate(&stream, Z_FINISH)
                    guard result == Z_STREAM_END else { return 0 }
                    return out.count - Int(stream.avail_out)
                }
                guard written > 0, written < input.count else { return Data() }
                return output.prefix(written)
            }
        }
    }
#endif
