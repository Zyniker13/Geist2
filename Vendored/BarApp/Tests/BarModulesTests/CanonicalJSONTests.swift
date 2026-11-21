import Foundation
import Testing

@testable import BarModules

/// The canonical JSON form that signatures are computed over (decision 0005):
/// UTF-8, object keys sorted by code point, no insignificant whitespace,
/// integers unadorned, floats in shortest round-trip form.
///
/// The golden vectors here are hand-worked so the canonical form is pinned
/// by test, not by whatever one language's JSON library happens to emit.
@Suite
struct CanonicalJSONTests {
    // MARK: Parsing rejects what canonicalization must not paper over

    @Test func rejectsTrailingGarbageAndEmptyInput() {
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("{}".utf8) + Data(" x".utf8))
        }
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data())
        }
    }

    @Test func rejectsMalformedNumbersAndStrings() {
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[1. ]".utf8))
        }
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[-]".utf8))
        }
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[\"\\u12\"]".utf8))
        }
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[\"unclosed".utf8))
        }
        // A bare surrogate escape is not a character.
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[\"\\uD800\"]".utf8))
        }
        // NaN and Infinity are not JSON.
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[NaN]".utf8))
        }
    }

    // MARK: Whitespace and key order

    @Test func stripsInsignificantWhitespace() {
        let input = Data("{ \"b\" : 1 ,\n\t\"a\" : 2 }".utf8)
        let canonical = try! CanonicalJSON.canonicalize(input)
        #expect(canonical == Data(#"{"a":2,"b":1}"#.utf8))
    }

    @Test func sortsObjectKeysByCodePoint() {
        // Code point order puts "Z" (0x5A) before "a" (0x61), and the
        // multibyte "é" (U+00E9) after ASCII.
        let input = Data(#"{"a":1,"Z":2,"é":3,"B":4}"#.utf8)
        let canonical = try! CanonicalJSON.canonicalize(input)
        #expect(canonical == Data(#"{"B":4,"Z":2,"a":1,"é":3}"#.utf8))
    }

    @Test func sortsNestedObjectsAndArrayOrderStays() {
        let input = Data(#"{"x":[{"b":1,"a":2},3]}"#.utf8)
        let canonical = try! CanonicalJSON.canonicalize(input)
        #expect(canonical == Data(#"{"x":[{"a":2,"b":1},3]}"#.utf8))
        // Arrays keep their order.
        let array = try! CanonicalJSON.canonicalize(Data("[3,1,2]".utf8))
        #expect(array == Data("[3,1,2]".utf8))
    }

    // MARK: Strings

    @Test func escapesOnlyWhatJSONRequires() {
        // The two required escapes, the short control escapes, and raw
        // non-ASCII stays raw UTF-8. Both backspace spellings normalize
        // to the same short escape.
        let input = Data("[\"quote\\\"back\\\\slash\\u0008\\b\\t\\n\\f\\r\\u0001\"]".utf8)
        let canonical = try! CanonicalJSON.canonicalize(input)
        #expect(canonical == Data("[\"quote\\\"back\\\\slash\\b\\b\\t\\n\\f\\r\\u0001\"]".utf8))
        let unicode = try! CanonicalJSON.canonicalize(Data("[\"héllo 🍸\"]".utf8))
        #expect(unicode == Data("[\"héllo 🍸\"]".utf8))
        // A lone \\uXXXX for a BMP char normalizes to the raw character.
        let escapedBMP = try! CanonicalJSON.canonicalize(Data("[\"\\u00e9\"]".utf8))
        #expect(escapedBMP == Data("[\"é\"]".utf8))
    }

    // MARK: Numbers

    @Test func integersAreUnadorned() {
        let canonical = try! CanonicalJSON.canonicalize(Data("[0,-17,9007199254740993]".utf8))
        #expect(canonical == Data("[0,-17,9007199254740993]".utf8))
        // Leading zeros and plus signs are rejected on parse.
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[01]".utf8))
        }
        #expect(throws: CanonicalJSON.CanonicalJSONError.self) {
            _ = try CanonicalJSON.parse(Data("[+1]".utf8))
        }
    }

    @Test func floatsUseShortestRoundTripWithNormalizedExponent() {
        // Swift prints 1e-05; the canonical exponent has no zero padding.
        let canonical = try! CanonicalJSON.canonicalize(Data("[1.5,-0.25,1e2,2.5e-7]".utf8))
        #expect(canonical == Data("[1.5,-0.25,100.0,2.5e-7]".utf8))
        let integral = try! CanonicalJSON.canonicalize(Data("[1.0]".utf8))
        #expect(integral == Data("[1.0]".utf8))
    }

    // MARK: Stability

    @Test func canonicalizingCanonicalOutputIsFixedPoint() {
        let input = Data(#"{"z":[1,2.5,{"k":null}],"a":true,"b":"é"}"#.utf8)
        let once = try! CanonicalJSON.canonicalize(input)
        let twice = try! CanonicalJSON.canonicalize(once)
        #expect(once == twice)
    }

    @Test func canonicalFormIsDeterministicAcrossEquivalentInputs() {
        // Same value, different spellings (whitespace, key order, escape
        // forms, exponent notation for the same double): one output.
        let a = try! CanonicalJSON.canonicalize(Data(#"{"a": 1.0, "b": "é"}"#.utf8))
        let b = try! CanonicalJSON.canonicalize(Data(#"{"b":"é","a":1.0}"#.utf8))
        #expect(a == b)
        // Integers and floats are distinct values in the canonical form:
        // 2 is not 2.0, so these do not canonicalize alike.
        let int = try! CanonicalJSON.canonicalize(Data("[2]".utf8))
        let float = try! CanonicalJSON.canonicalize(Data("[2.0]".utf8))
        #expect(int != float)
    }
}
