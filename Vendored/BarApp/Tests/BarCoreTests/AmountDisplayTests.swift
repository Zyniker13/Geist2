import BarCore
import Foundation
import Testing

/// AmountDisplay turns the stored amount strings (decimals, fractions, and
/// mixed numbers) plus unit ids into metric display text. The expected
/// values come from the catalog's exact factors: one US fluid ounce is
/// exactly 29.5735295625 ml and one teaspoon is exactly 1/6 of that.
struct AmountDisplayTests {
    @Test func parsesEveryAmountShape() {
        #expect(
            AmountDisplay.parseAmount("0.5")
                == Decimal(string: "0.5", locale: Locale(identifier: "en_US_POSIX")))
        #expect(AmountDisplay.parseAmount("2") == 2)
        #expect(
            AmountDisplay.parseAmount("1/2")
                == Decimal(string: "0.5", locale: Locale(identifier: "en_US_POSIX")))
        #expect(
            AmountDisplay.parseAmount("1 1/2")
                == Decimal(string: "1.5", locale: Locale(identifier: "en_US_POSIX")))
        #expect(
            AmountDisplay.parseAmount(" 3/4 ")
                == Decimal(string: "0.75", locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test func rejectsMalformedAmounts() {
        #expect(AmountDisplay.parseAmount("") == nil)
        #expect(AmountDisplay.parseAmount("1/0") == nil)
        #expect(AmountDisplay.parseAmount("1 /2") == nil)
        #expect(AmountDisplay.parseAmount("cup") == nil)
        #expect(AmountDisplay.parseAmount("1 1/2 1/2") == nil)
    }

    @Test func convertsVolumeToMilliliters() {
        let catalog = UnitCatalog()
        // 1/2 oz = 14.78676478125 ml -> shown as 14.79 ml.
        #expect(AmountDisplay.metricText(amount: "1/2", unit: "oz", in: catalog) == "14.79 ml")
        // 1 1/2 oz = 44.36029434375 ml -> 44.36 ml.
        #expect(AmountDisplay.metricText(amount: "1 1/2", unit: "oz", in: catalog) == "44.36 ml")
        // 1 tsp = 4.928921595 ml -> 4.93 ml.
        #expect(AmountDisplay.metricText(amount: "1", unit: "tsp", in: catalog) == "4.93 ml")
    }

    @Test func countAndUnknownUnitsStayAsWritten() {
        let catalog = UnitCatalog()
        #expect(AmountDisplay.metricText(amount: "1", unit: "piece", in: catalog) == nil)
        #expect(AmountDisplay.metricText(amount: "1", unit: "handful", in: catalog) == nil)
    }
}
