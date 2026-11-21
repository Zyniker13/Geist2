import Foundation

/// The CSV dialect used for inventory import and export: RFC 4180 quoting
/// (double a quote to escape it, quote fields containing commas, quotes,
/// or line breaks), CRLF row separators on output, and a parser that
/// accepts CRLF, LF, or CR row ends. The codepoint is deliberately tiny —
/// it exists so files written by the app parse in a spreadsheet and files
/// written by a spreadsheet parse in the app, and nothing more.
public enum CSVCodec {
    public enum CSVError: Error, Equatable {
        /// A quoted field was never closed.
        case unterminatedQuote
    }

    /// Encodes rows of fields as CSV text. A trailing row separator ends
    /// the last row, per RFC 4180.
    public static func encode(rows: [[String]]) -> String {
        var lines: [String] = []
        for row in rows {
            let fields = row.map { field in
                field.contains(",") || field.contains("\"")
                    || field.contains("\n") || field.contains("\r")
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    : field
            }
            lines.append(fields.joined(separator: ","))
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses CSV text into rows. Accepts CRLF, LF, or CR between rows; a
    /// final row separator is optional. An unterminated quoted field throws.
    ///
    /// The scan runs over unicode scalars, not Characters: CRLF is a single
    /// grapheme cluster in Swift, and treating it as one Character would
    /// slip the most common row separator straight into field data.
    public static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var index = text.unicodeScalars.startIndex
        let scalars = text.unicodeScalars

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\"" {
                // A quoted field: consume until the closing quote, doubling
                // embedded quotes.
                index = scalars.index(after: index)
                var closed = false
                while index < scalars.endIndex {
                    let quoted = scalars[index]
                    if quoted == "\"" {
                        let next = scalars.index(after: index)
                        if next < scalars.endIndex, scalars[next] == "\"" {
                            field.append("\"")
                            index = next
                        } else {
                            closed = true
                            break
                        }
                    } else {
                        field.unicodeScalars.append(quoted)
                    }
                    index = scalars.index(after: index)
                }
                if !closed {
                    throw CSVError.unterminatedQuote
                }
                // After a closing quote the field may only end (comma, row
                // break, or text end); anything else is malformed, and the
                // strict reading is to refuse it rather than guess where
                // the field really ended — no file silently reshuffles its
                // columns.
                let next = scalars.index(after: index)
                if next < scalars.endIndex,
                    scalars[next] != ",", scalars[next] != "\n", scalars[next] != "\r"
                {
                    throw CSVError.unterminatedQuote
                }
            } else if scalar == "," {
                endField()
            } else if scalar == "\n" {
                endRow()
            } else if scalar == "\r" {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    index = next
                }
                endRow()
            } else {
                field.unicodeScalars.append(scalar)
            }
            index = scalars.index(after: index)
        }
        // A final row without a trailing separator still counts.
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
