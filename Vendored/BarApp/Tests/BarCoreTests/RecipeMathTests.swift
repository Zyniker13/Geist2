import Foundation
import Testing

@testable import BarCore

@Suite
struct RecipeMathTests {
    private func ingredient(_ label: String, amount: String, unit: String) -> RecipeMath.Ingredient {
        RecipeMath.Ingredient(
            label: label,
            amount: Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))!,
            unit: unit)
    }

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test func scaleMultipliesAndRoundsPerUnit() throws {
        let scaled = try RecipeMath.scale(
            [
                ingredient("a", amount: "2", unit: "oz"),
                ingredient("b", amount: "0.75", unit: "oz"),
                ingredient("c", amount: "2", unit: "dash"),
                ingredient("d", amount: "0.5", unit: "tsp"),
                ingredient("e", amount: "1", unit: "whole"),
                ingredient("f", amount: "2", unit: "piece"),
            ], by: 3)
        #expect("\(scaled[0].amount)" == "6")
        #expect("\(scaled[1].amount)" == "2.25")
        #expect("\(scaled[2].amount)" == "6")
        #expect("\(scaled[3].amount)" == "1.5")
        #expect("\(scaled[4].amount)" == "3")
        #expect("\(scaled[5].amount)" == "6")
    }

    @Test func scaleRoundsToTheUnitsSensibleStep() throws {
        let scaled = try RecipeMath.scale(
            [
                ingredient("a", amount: "0.75", unit: "oz"),
                ingredient("b", amount: "0.5", unit: "dash"),
                ingredient("c", amount: "0.2", unit: "leaves"),
            ], by: decimal("2.5"))
        // 1.875 oz rounds to the nearest quarter ounce.
        #expect("\(scaled[0].amount)" == "2")
        // 1.25 dashes rounds to the nearest whole dash.
        #expect("\(scaled[1].amount)" == "1")
        // Half a leaf rounds to zero but still means at least one leaf.
        #expect("\(scaled[2].amount)" == "1")
    }

    @Test func scaleKeepsANonzeroMinimum() throws {
        let scaled = try RecipeMath.scale(
            [ingredient("a", amount: "0.2", unit: "oz")], by: decimal("0.2"))
        // 0.04 oz would vanish; the smallest amount is a quarter ounce.
        #expect("\(scaled[0].amount)" == "0.25")
    }

    @Test func scaleRejectsNonpositiveFactors() throws {
        #expect(throws: RecipeMath.MathError.badFactor) {
            try RecipeMath.scale([], by: 0)
        }
        #expect(throws: RecipeMath.MathError.badFactor) {
            try RecipeMath.scale([], by: -2)
        }
    }
}
