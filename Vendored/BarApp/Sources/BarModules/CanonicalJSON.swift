import Foundation

/// The canonical JSON form that module signatures are computed over
/// (decision 0005): UTF-8, object keys sorted by code point, no insignificant
/// whitespace, integers unadorned, floats in shortest round-trip form.
///
/// Canonicalization parses the JSON into its own value tree rather than
/// trusting `JSONSerialization`, so the integer/float distinction survives
/// on every platform the package builds for.
public enum CanonicalJSON {
    /// Why a document could not be parsed or canonicalized.
    public enum CanonicalJSONError: Error, Equatable, Sendable {
        /// The input is empty or has trailing bytes after the value.
        case truncated
        /// The byte is not valid where it appears.
        case badByte(UInt8)
        /// A number literal is malformed.
        case badNumber
        /// A string literal is malformed (bad escape, lone surrogate).
        case badString
        /// A number or string is longer than the canonical limits.
        case tooLong
    }

    /// A parsed JSON value, keeping integers and floats apart.
    public enum Value: Equatable, Sendable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([Value])
        case object([String: Value])

        /// Object member access, `nil` unless the value is an object holding
        /// that key. Lets payload consumers walk parsed JSON directly.
        public subscript(key: String) -> Value? {
            guard case .object(let tree) = self else { return nil }
            return tree[key]
        }
    }

    // MARK: API

    /// Parse a JSON document into a value tree. Strict: no trailing bytes,
    /// no comments, no NaN, no lone surrogates.
    public static func parse(_ data: Data) throws -> Value {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.atEnd else { throw CanonicalJSONError.truncated }
        return value
    }

    /// Parse, then re-emit in canonical form.
    public static func canonicalize(_ data: Data) throws -> Data {
        Data(emit(try parse(data)))
    }

    /// The canonical encoding of a value tree.
    public static func emit(_ value: Value) -> [UInt8] {
        var out: [UInt8] = []
        write(value, into: &out)
        return out
    }

    // MARK: Emission

    private static func write(_ value: Value, into out: inout [UInt8]) {
        switch value {
        case .null:
            out.append(contentsOf: Array("null".utf8))
        case .bool(true):
            out.append(contentsOf: Array("true".utf8))
        case .bool(false):
            out.append(contentsOf: Array("false".utf8))
        case .int(let int):
            out.append(contentsOf: Array(String(int).utf8))
        case .double(let double):
            out.append(contentsOf: Array(format(double).utf8))
        case .string(let string):
            write(string, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (index, item) in items.enumerated() {
                if index > 0 { out.append(UInt8(ascii: ",")) }
                write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let pairs):
            // Keys sorted by code point: UTF-8 byte order preserves it.
            out.append(UInt8(ascii: "{"))
            for (index, key) in pairs.keys.sorted().enumerated() {
                if index > 0 { out.append(UInt8(ascii: ",")) }
                write(key, into: &out)
                out.append(UInt8(ascii: ":"))
                write(pairs[key]!, into: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func write(_ string: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out.append(contentsOf: Array("\\\"".utf8))
            case "\\": out.append(contentsOf: Array("\\\\".utf8))
            case "\n": out.append(contentsOf: Array("\\n".utf8))
            case "\r": out.append(contentsOf: Array("\\r".utf8))
            case "\t": out.append(contentsOf: Array("\\t".utf8))
            case "\u{08}": out.append(contentsOf: Array("\\b".utf8))
            case "\u{0C}": out.append(contentsOf: Array("\\f".utf8))
            default:
                if scalar.value < 0x20 {
                    out.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
                } else {
                    out.append(contentsOf: Array(String(scalar).utf8))
                }
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    /// Shortest round-trip decimal form: Swift's `description` gives the
    /// shortest representation that reads back exactly; the exponent is
    /// normalized to a sign and no zero padding (`1e-05` becomes `1e-5`).
    static func format(_ double: Double) -> String {
        var text = double.description
        if let eIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissa = String(text[..<eIndex])
            var exponent = String(text[text.index(after: eIndex)...])
            var sign = ""
            if exponent.hasPrefix("-") || exponent.hasPrefix("+") {
                sign = String(exponent.removeFirst())
            }
            while exponent.count > 1 && exponent.hasPrefix("0") { exponent.removeFirst() }
            text = mantissa + "e" + (sign == "-" ? "-" : "+") + exponent
        }
        return text
    }

    // MARK: Parsing

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        static let maxDepth = 64
        static let maxTokenLength = 1 << 20

        init(bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }

        mutating func skipWhitespace() {
            while index < bytes.count,
                bytes[index] == 0x20 || bytes[index] == 0x09
                    || bytes[index] == 0x0A || bytes[index] == 0x0D
            {
                index += 1
            }
        }

        mutating func parseValue(depth: Int) throws -> Value {
            guard depth < Parser.maxDepth else { throw CanonicalJSONError.badByte(bytes[index]) }
            skipWhitespace()
            guard index < bytes.count else { throw CanonicalJSONError.truncated }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): return try parseLiteral("true", .bool(true))
            case UInt8(ascii: "f"): return try parseLiteral("false", .bool(false))
            case UInt8(ascii: "n"): return try parseLiteral("null", .null)
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                return try parseNumber()
            default:
                throw CanonicalJSONError.badByte(bytes[index])
            }
        }

        mutating func parseLiteral(_ word: String, _ value: Value) throws -> Value {
            for char in word.utf8 {
                guard index < bytes.count, bytes[index] == char else {
                    throw CanonicalJSONError.badByte(index < bytes.count ? bytes[index] : 0)
                }
                index += 1
            }
            return value
        }

        mutating func parseObject(depth: Int) throws -> Value {
            index += 1  // the opening brace
            var pairs: [String: Value] = [:]
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(pairs)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw CanonicalJSONError.badByte(index < bytes.count ? bytes[index] : 0)
                }
                let key = try parseString()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw CanonicalJSONError.badByte(index < bytes.count ? bytes[index] : 0)
                }
                index += 1
                pairs[key] = try parseValue(depth: depth + 1)
                skipWhitespace()
                guard index < bytes.count else { throw CanonicalJSONError.truncated }
                switch bytes[index] {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"):
                    index += 1
                    return .object(pairs)
                default: throw CanonicalJSONError.badByte(bytes[index])
                }
            }
        }

        mutating func parseArray(depth: Int) throws -> Value {
            index += 1  // the opening bracket
            var items: [Value] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw CanonicalJSONError.truncated }
                switch bytes[index] {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "]"):
                    index += 1
                    return .array(items)
                default: throw CanonicalJSONError.badByte(bytes[index])
                }
            }
        }

        mutating func parseString() throws -> String {
            index += 1  // the opening quote
            var scalars: [UInt8] = []
            while true {
                guard index < bytes.count else { throw CanonicalJSONError.truncated }
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: "\""):
                    index += 1
                    guard let string = String(bytes: scalars, encoding: .utf8) else {
                        throw CanonicalJSONError.badString
                    }
                    return string
                case UInt8(ascii: "\\"):
                    index += 1
                    guard index < bytes.count else { throw CanonicalJSONError.truncated }
                    switch bytes[index] {
                    case UInt8(ascii: "\""):
                        scalars.append(UInt8(ascii: "\""))
                        index += 1
                    case UInt8(ascii: "\\"):
                        scalars.append(UInt8(ascii: "\\"))
                        index += 1
                    case UInt8(ascii: "/"):
                        scalars.append(UInt8(ascii: "/"))
                        index += 1
                    case UInt8(ascii: "b"):
                        scalars.append(0x08)
                        index += 1
                    case UInt8(ascii: "f"):
                        scalars.append(0x0C)
                        index += 1
                    case UInt8(ascii: "n"):
                        scalars.append(0x0A)
                        index += 1
                    case UInt8(ascii: "r"):
                        scalars.append(0x0D)
                        index += 1
                    case UInt8(ascii: "t"):
                        scalars.append(0x09)
                        index += 1
                    case UInt8(ascii: "u"):
                        let unit = try parseHex4()
                        var scalarValue = UInt32(unit)
                        if 0xD800...0xDBFF ~= unit {
                            // High surrogate: a low surrogate must follow.
                            guard index + 2 < bytes.count,
                                bytes[index + 1] == UInt8(ascii: "\\"),
                                bytes[index + 2] == UInt8(ascii: "u")
                            else { throw CanonicalJSONError.badString }
                            index += 2
                            let low = try parseHex4()
                            guard 0xDC00...0xDFFF ~= low else { throw CanonicalJSONError.badString }
                            scalarValue =
                                0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
                        } else if 0xDC00...0xDFFF ~= unit {
                            throw CanonicalJSONError.badString
                        }
                        guard let scalar = Unicode.Scalar(scalarValue) else {
                            throw CanonicalJSONError.badString
                        }
                        scalars.append(contentsOf: Array(String(scalar).utf8))
                    default: throw CanonicalJSONError.badString
                    }
                case 0x00...0x1F: throw CanonicalJSONError.badByte(byte)
                default:
                    scalars.append(byte)
                    index += 1
                }
            }
        }

        /// Read the four hex digits of a `\u` escape.
        mutating func parseHex4() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                index += 1
                guard index < bytes.count else { throw CanonicalJSONError.truncated }
                let digit: Int
                switch bytes[index] {
                case UInt8(ascii: "0")...UInt8(ascii: "9"):
                    digit = Int(bytes[index] - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"):
                    digit = Int(bytes[index] - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"):
                    digit = Int(bytes[index] - UInt8(ascii: "A")) + 10
                default: throw CanonicalJSONError.badString
                }
                value = value << 4 | digit
            }
            index += 1
            return value
        }

        mutating func parseNumber() throws -> Value {
            let start = index
            var isDouble = false
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            // The integer part: a single zero, or digits with no leading zero.
            guard index < bytes.count else { throw CanonicalJSONError.truncated }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else if case UInt8(ascii: "1")...UInt8(ascii: "9") = bytes[index] {
                while index < bytes.count, case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index]
                {
                    index += 1
                }
            } else {
                throw CanonicalJSONError.badNumber
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                isDouble = true
                index += 1
                guard index < bytes.count,
                    case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index]
                else { throw CanonicalJSONError.badNumber }
                while index < bytes.count, case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index]
                {
                    index += 1
                }
            }
            if index < bytes.count,
                bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E")
            {
                isDouble = true
                index += 1
                if index < bytes.count,
                    bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-")
                {
                    index += 1
                }
                guard index < bytes.count,
                    case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index]
                else { throw CanonicalJSONError.badNumber }
                while index < bytes.count, case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index]
                {
                    index += 1
                }
            }
            guard index - start <= Parser.maxTokenLength else { throw CanonicalJSONError.tooLong }
            let literal = String(bytes: bytes[start..<index], encoding: .utf8)!
            guard isDouble == false else {
                guard let double = Double(literal), double.isFinite else {
                    throw CanonicalJSONError.badNumber
                }
                return .double(double)
            }
            guard let int = Int64(literal) else { throw CanonicalJSONError.badNumber }
            return .int(int)
        }
    }
}
