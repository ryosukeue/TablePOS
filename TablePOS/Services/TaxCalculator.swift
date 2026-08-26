import Foundation

struct TaxLine: Sendable {
    let unitPrice: Int
    let quantity: Int
    let taxRate: TaxRate
    let taxType: TaxType

    var amount: Int { unitPrice * quantity }
}

struct TaxSummary: Equatable, Sendable {
    let subtotal: Int
    let taxableBase8: Int
    let taxableBase10: Int
    let includedTax8: Int
    let includedTax10: Int
    let externalTax8: Int
    let externalTax10: Int

    var externalTaxTotal: Int { externalTax8 + externalTax10 }
    var preRoundedTotal: Int { subtotal + externalTaxTotal }
}

enum TaxCalculator {
    static func calculate(lines: [TaxLine], rounding: TaxRoundingRule) -> TaxSummary {
        var includedGross8 = 0
        var includedGross10 = 0
        var excludedBase8 = 0
        var excludedBase10 = 0

        for line in lines where line.unitPrice >= 0 && line.quantity > 0 {
            switch (line.taxType, line.taxRate) {
            case (.included, .reduced): includedGross8 += line.amount
            case (.included, .standard): includedGross10 += line.amount
            case (.excluded, .reduced): excludedBase8 += line.amount
            case (.excluded, .standard): excludedBase10 += line.amount
            }
        }

        return TaxSummary(
            subtotal: includedGross8 + includedGross10 + excludedBase8 + excludedBase10,
            taxableBase8: includedGross8 + excludedBase8,
            taxableBase10: includedGross10 + excludedBase10,
            includedTax8: roundedFraction(includedGross8 * 8, denominator: 108, rule: rounding),
            includedTax10: roundedFraction(includedGross10 * 10, denominator: 110, rule: rounding),
            externalTax8: roundedFraction(excludedBase8 * 8, denominator: 100, rule: rounding),
            externalTax10: roundedFraction(excludedBase10 * 10, denominator: 100, rule: rounding)
        )
    }

    static func tenYenAdjustment(for amount: Int) -> Int {
        guard amount >= 0 else { return 0 }
        let rounded = ((amount + 5) / 10) * 10
        return rounded - amount
    }

    private static func roundedFraction(
        _ numerator: Int,
        denominator: Int,
        rule: TaxRoundingRule
    ) -> Int {
        guard numerator > 0 else { return 0 }
        switch rule {
        case .floor:
            return numerator / denominator
        case .nearest:
            return (numerator + denominator / 2) / denominator
        case .ceiling:
            return (numerator + denominator - 1) / denominator
        }
    }
}
