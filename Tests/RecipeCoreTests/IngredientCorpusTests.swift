import Foundation
import Testing

@testable import RecipeCore

/// The M2.4 corpus gate: every corpus row parses as expected, and at
/// least 98% parse exactly (the roadmap's number). The test reports the
/// exact-match percentage so the gate is visible in output.
struct IngredientCorpusTests {
    @Test func corpusHasAtLeast500Lines() {
        #expect(IngredientCorpus.rows.count >= 500)
    }

    @Test func corpusParsesExactly() {
        let parsed = IngredientCorpus.rows.map { row in
            IngredientParser.parse(row.text)
        }
        var exact = 0
        var misses: [String] = []
        for (row, line) in zip(IngredientCorpus.rows, parsed) {
            let headerOK = IngredientParser.isSectionHeader(row.text) == row.isHeader
            let quantityOK = decimal(row.quantity) == line.quantity?.amount
            let highOK = decimal(row.quantityHigh) == line.quantityHigh?.amount
            let unitOK = row.unitID == line.unitID
            let itemOK = row.isHeader || row.item == "x" || row.item == line.item
            let prepOK = row.preparation == line.preparation
            let noteOK = row.note == nil || row.note == line.note
            let optionalOK = row.optional == line.optional
            let tasteOK = row.toTaste == line.toTaste
            if headerOK && quantityOK && highOK && unitOK && itemOK && prepOK
                && noteOK && optionalOK && tasteOK
            {
                exact += 1
            } else {
                misses.append(
                    "\(row.text) -> q=\(line.quantity?.amount.description ?? "nil")"
                        + " u=\(line.unitID ?? "nil") item=\(line.item)"
                        + " prep=\(line.preparation ?? "nil") note=\(line.note ?? "nil")"
                        + " opt=\(line.optional) taste=\(line.toTaste)"
                        + " hdr=\(IngredientParser.isSectionHeader(row.text))")
            }
        }
        let percent = Double(exact) / Double(IngredientCorpus.rows.count) * 100
        print("corpus exact: \(exact)/\(IngredientCorpus.rows.count) = \(percent)%")
        for miss in misses {
            print("MISS:", miss)
        }
        #expect(percent >= 98, "corpus exact-parse rate \(percent)% < 98%")
    }

    /// The Decimal value a corpus amount literal stands for. A fraction
    /// form "N/D" is evaluated as exact Decimal division, matching how
    /// the parser itself reads "1/3" — repeating fractions are compared
    /// exactly, never as rounded literals.
    private func decimal(_ literal: String?) -> Decimal? {
        guard let literal else { return nil }
        if literal.contains("/") {
            let parts = literal.split(separator: "/")
            guard parts.count == 2,
                let numerator = Decimal(string: String(parts[0])),
                let denominator = Decimal(string: String(parts[1])),
                denominator != 0
            else { return nil }
            return numerator / denominator
        }
        return Decimal(
            string: literal, locale: Locale(identifier: "en_US_POSIX"))
    }
}
