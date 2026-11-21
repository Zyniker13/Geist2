import BarModules
import Foundation
import Testing

/// The ZIP writer: deterministic stored-entry archives that our own
/// reader — and any other ZIP reader — accepts.
@Suite
struct ZIPWriterTests {
    @Test func writesAnArchiveOurReaderAccepts() throws {
        let files: [(String, Data)] = [
            ("manifest.json", Data("{\"formatVersion\":1}".utf8)),
            ("data/recipes.jsonl", Data("hello deflate world, hello deflate world, hello\n".utf8)),
        ]
        let archive = try ZIPWriter.archive(of: files)
        let read = try ZIPReader.read(archive)
        #expect(read.entries.count == 2)
        #expect(read.entries[0].data == files[0].1)
        #expect(read.entries[1].data == files[1].1)
    }

    @Test func writingIsDeterministic() throws {
        let files: [(String, Data)] = [
            ("a.txt", Data("first".utf8)),
            ("b.txt", Data("second with more bytes".utf8)),
        ]
        #expect(try ZIPWriter.archive(of: files) == ZIPWriter.archive(of: files))
    }

    @Test func emptyContentIsRepresentable() throws {
        let archive = try ZIPWriter.archive(of: [("data/tags.json", Data())])
        let read = try ZIPReader.read(archive)
        #expect(read.entries[0].data.isEmpty)
    }

    @Test func contentIsStoredNotDeflated() throws {
        // The writer emits stored entries; method field in the local header
        // must read 0. Compressibility is not the writer's concern.
        let veryCompressible = Data(String(repeating: "A", count: 5000).utf8)
        let archive = try ZIPWriter.archive(of: [("big.txt", veryCompressible)])
        let bytes = [UInt8](archive)
        // Local header: signature 0..4, version 4..6, flags 6..8, method 8..10.
        let method = Int(bytes[8]) | (Int(bytes[9]) << 8)
        #expect(method == 0)
    }

    @Test func rejectsNamesTheReaderWouldReject() {
        #expect(throws: ZIPWriter.WriterError.unsafeEntryName(name: "/etc/passwd")) {
            _ = try ZIPWriter.archive(of: [("/etc/passwd", Data("x".utf8))])
        }
        #expect(throws: ZIPWriter.WriterError.unsafeEntryName(name: "../escape")) {
            _ = try ZIPWriter.archive(of: [("../escape", Data("x".utf8))])
        }
        #expect(throws: ZIPWriter.WriterError.duplicateEntry(name: "a.txt")) {
            _ = try ZIPWriter.archive(of: [
                ("a.txt", Data("x".utf8)), ("a.txt", Data("y".utf8)),
            ])
        }
    }
}
