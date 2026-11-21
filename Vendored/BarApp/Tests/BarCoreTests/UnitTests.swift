import Foundation
import Testing

@testable import BarCore

/// Conversion tests for the unit catalog. Every factor tested here is the
/// one documented in `docs/units.md`; if a factor changes, both the docs
/// and these tests change together.
@Suite struct UnitTests {
    private let catalog = UnitCatalog()

    /// Parses a decimal literal with a fixed locale, matching how the
    /// catalog itself parses factors.
    private func decimal(_ literal: String) -> Decimal {
        Decimal(
            string: literal,
            locale: Locale(identifier: "en_US_POSIX")
        )!
    }

    private func absDifference(_ a: Decimal, _ b: Decimal) -> Decimal {
        a > b ? a - b : b - a
    }

    @Test func ounceToMillilitersIsExact() {
        #expect(
            catalog.convert(2, from: "oz", to: "ml")
                == decimal("59.147059125")
        )
    }

    @Test func teaspoonToDashesIsExact() {
        #expect(catalog.convert(1, from: "tsp", to: "dash") == 8)
    }


    @Test func gramsToAvoirdupoisOuncesIsExact() {
        #expect(
            catalog.convert(decimal("453.59237"), from: "g", to: "ozm") == 16
        )
    }

    @Test func dimensionMismatchReturnsNil() {
        #expect(catalog.convert(1, from: "oz", to: "g") == nil)
        #expect(catalog.convert(1, from: "piece", to: "ml") == nil)
    }

    @Test func unknownUnitReturnsNil() {
        #expect(catalog.definition(matching: "furlong") == nil)
        #expect(catalog.convert(1, from: "furlong", to: "ml") == nil)
    }

    @Test func aliasLookupResolvesDocumentedSpellings() {
        #expect(catalog.definition(matching: "fl oz")?.id == "oz")
        #expect(catalog.definition(matching: "Tablespoons")?.id == "tbsp")
        #expect(catalog.definition(matching: " dashes ")?.id == "dash")
        #expect(catalog.definition(matching: "wine glass")?.id == "wineglass")
        #expect(
            catalog.definition(matching: "avoirdupois ounce")?.id == "ozm"
        )
    }

    @Test func everyUnitIsWellFormed() {
        let definitions = catalog.definitionsById
        #expect(definitions.count >= 23)

        var seenIds = Set<String>()
        for definition in definitions.values {
            #expect(!seenIds.contains(definition.id))
            seenIds.insert(definition.id)
            #expect(definition.perCanonical > 0)
            #expect(!definition.summary.isEmpty)
            for alias in definition.aliases {
                // The lookup normalizes to lowercase; an alias that is not
                // lowercase would be unreachable.
                #expect(alias == alias.lowercased())
                #expect(alias.trimmingCharacters(in: .whitespaces) == alias)
            }
            // Every dimension's canonical unit is defined.
            #expect(
                definitions[definition.dimension.canonicalUnitId] != nil
            )
        }
    }

    @Test func conversionsRoundTripAcrossEveryUnitInADimension() {
        let catalog = UnitCatalog()
        let byDimension = Dictionary(
            grouping: catalog.definitionsById.values,
            by: { $0.dimension }
        )
        let value = decimal("7.5")
        let tolerance = decimal("0.00000000000000000001")
        for (dimension, units) in byDimension {
            for source in units {
                for target in units {
                    let there = catalog.convert(
                        value,
                        from: source.id,
                        to: target.id
                    )
                    #expect(there != nil)
                    guard let there else { continue }
                    let back = catalog.convert(
                        there,
                        from: target.id,
                        to: source.id
                    )
                    #expect(back != nil)
                    guard let back else { continue }
                    #expect(
                        absDifference(back, value) < tolerance,
                        "round trip \(source.id) -> \(target.id) drifted in dimension \(dimension)"
                    )
                }
            }
        }
    }
}
