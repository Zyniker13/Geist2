import Testing

@testable import BarCore

struct CSVCodecTests {
    @Test func roundTripsTrickyFields() throws {
        let rows = [
            ["id", "name", "note"],
            ["p1", "Rye, 750ml", "said \"shake well\"\nthen stir"],
            ["p2", "Crème de Violette", ""],
            ["p3", "", "empty name is legal CSV"],
        ]
        let text = CSVCodec.encode(rows: rows)
        #expect(try CSVCodec.parse(text) == rows)
    }

    @Test func acceptsLFAndCRRowEnds() throws {
        #expect(try CSVCodec.parse("a,b\nc,d") == [["a", "b"], ["c", "d"]])
        #expect(try CSVCodec.parse("a,b\rc,d") == [["a", "b"], ["c", "d"]])
        #expect(try CSVCodec.parse("a,b\r\nc,d\r\n") == [["a", "b"], ["c", "d"]])
    }

    @Test func emptyInputGivesNoRows() throws {
        #expect(try CSVCodec.parse("") == [])
        #expect(CSVCodec.encode(rows: []) == "")
    }

    @Test func refusesUnterminatedQuote() {
        #expect(throws: CSVCodec.CSVError.unterminatedQuote) {
            try CSVCodec.parse("a,\"open")
        }
        #expect(throws: CSVCodec.CSVError.unterminatedQuote) {
            // Data after a closing quote is malformed, not silently merged.
            try CSVCodec.parse("a,\"closed\"tail,b")
        }
    }

    @Test func quotesOnlyWhenNeeded() {
        let text = CSVCodec.encode(rows: [["plain", "needs, comma", "has \"quote\""]])
        #expect(text == "plain,\"needs, comma\",\"has \"\"quote\"\"\"\r\n")
    }
}
