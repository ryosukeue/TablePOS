import Foundation
import SwiftData

@Model
final class StoreSettings {
    @Attribute(.unique) var id: UUID
    var isSetupComplete: Bool
    var tableCount: Int
    var taxRoundingRuleRaw: String

    init(
        id: UUID = UUID(),
        isSetupComplete: Bool = false,
        tableCount: Int = 12,
        taxRoundingRule: TaxRoundingRule = .floor
    ) {
        self.id = id
        self.isSetupComplete = isSetupComplete
        self.tableCount = tableCount
        self.taxRoundingRuleRaw = taxRoundingRule.rawValue
    }

    var taxRoundingRule: TaxRoundingRule {
        get { TaxRoundingRule(rawValue: taxRoundingRuleRaw) ?? .floor }
        set { taxRoundingRuleRaw = newValue.rawValue }
    }
}

@Model
final class DiningTable {
    @Attribute(.unique) var id: UUID
    var number: Int
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), number: Int, name: String? = nil, sortOrder: Int? = nil) {
        self.id = id
        self.number = number
        self.name = name ?? "\(number)番卓"
        self.sortOrder = sortOrder ?? number
    }
}

@Model
final class ProductCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}

@Model
final class Product {
    @Attribute(.unique) var id: UUID
    var name: String
    var price: Int
    var taxRateValue: Int
    var taxTypeRaw: String
    var menuTypeRaw: String
    var categoryID: UUID?
    var isFrequent: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        price: Int,
        taxRate: TaxRate,
        taxType: TaxType,
        menuType: MenuType,
        categoryID: UUID?,
        isFrequent: Bool,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.taxRateValue = taxRate.rawValue
        self.taxTypeRaw = taxType.rawValue
        self.menuTypeRaw = menuType.rawValue
        self.categoryID = categoryID
        self.isFrequent = isFrequent
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var taxRate: TaxRate {
        get { TaxRate(rawValue: taxRateValue) ?? .standard }
        set { taxRateValue = newValue.rawValue }
    }

    var taxType: TaxType {
        get { TaxType(rawValue: taxTypeRaw) ?? .included }
        set { taxTypeRaw = newValue.rawValue }
    }

    var menuType: MenuType {
        get { MenuType(rawValue: menuTypeRaw) ?? .grand }
        set { menuTypeRaw = newValue.rawValue }
    }
}

@Model
final class Order {
    @Attribute(.unique) var id: UUID
    var tableID: UUID
    var openedAt: Date
    var statusRaw: String

    init(id: UUID = UUID(), tableID: UUID, openedAt: Date = .now) {
        self.id = id
        self.tableID = tableID
        self.openedAt = openedAt
        self.statusRaw = OrderStatus.open.rawValue
    }
}

@Model
final class OrderItem {
    @Attribute(.unique) var id: UUID
    var orderID: UUID
    var productID: UUID?
    var name: String
    var unitPrice: Int
    var quantity: Int
    var taxRateValue: Int
    var taxTypeRaw: String
    var isCustom: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        orderID: UUID,
        productID: UUID?,
        name: String,
        unitPrice: Int,
        quantity: Int,
        taxRate: TaxRate,
        taxType: TaxType,
        isCustom: Bool,
        createdAt: Date = .now
    ) {
        self.id = id
        self.orderID = orderID
        self.productID = productID
        self.name = name
        self.unitPrice = unitPrice
        self.quantity = quantity
        self.taxRateValue = taxRate.rawValue
        self.taxTypeRaw = taxType.rawValue
        self.isCustom = isCustom
        self.createdAt = createdAt
    }

    var taxRate: TaxRate {
        TaxRate(rawValue: taxRateValue) ?? .standard
    }

    var taxType: TaxType {
        TaxType(rawValue: taxTypeRaw) ?? .included
    }

    var lineAmount: Int { unitPrice * quantity }
}

@Model
final class Sale {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var statusRaw: String
    var paymentMethodRaw: String
    var sourceTableName: String
    var subtotal: Int
    var taxableBase8: Int
    var taxableBase10: Int
    var includedTax8: Int
    var includedTax10: Int
    var externalTax8: Int
    var externalTax10: Int
    var roundingAdjustment: Int
    var total: Int
    var receivedAmount: Int?
    var changeAmount: Int?
    var originalSaleID: UUID?
    var replacementSaleID: UUID?
    var cancelledAt: Date?
    var cancellationReason: String?

    init(
        id: UUID = UUID(),
        completedAt: Date = .now,
        status: SaleStatus = .completed,
        paymentMethod: PaymentMethod,
        sourceTableName: String,
        subtotal: Int,
        taxableBase8: Int,
        taxableBase10: Int,
        includedTax8: Int,
        includedTax10: Int,
        externalTax8: Int,
        externalTax10: Int,
        roundingAdjustment: Int,
        total: Int,
        receivedAmount: Int?,
        changeAmount: Int?,
        originalSaleID: UUID? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
        self.paymentMethodRaw = paymentMethod.rawValue
        self.sourceTableName = sourceTableName
        self.subtotal = subtotal
        self.taxableBase8 = taxableBase8
        self.taxableBase10 = taxableBase10
        self.includedTax8 = includedTax8
        self.includedTax10 = includedTax10
        self.externalTax8 = externalTax8
        self.externalTax10 = externalTax10
        self.roundingAdjustment = roundingAdjustment
        self.total = total
        self.receivedAmount = receivedAmount
        self.changeAmount = changeAmount
        self.originalSaleID = originalSaleID
    }

    var status: SaleStatus {
        get { SaleStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        PaymentMethod(rawValue: paymentMethodRaw) ?? .other
    }
}

@Model
final class SaleItem {
    @Attribute(.unique) var id: UUID
    var saleID: UUID
    var sourceProductID: UUID?
    var name: String
    var unitPrice: Int
    var quantity: Int
    var taxRateValue: Int
    var taxTypeRaw: String
    var isCustom: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        saleID: UUID,
        sourceProductID: UUID?,
        name: String,
        unitPrice: Int,
        quantity: Int,
        taxRate: TaxRate,
        taxType: TaxType,
        isCustom: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.saleID = saleID
        self.sourceProductID = sourceProductID
        self.name = name
        self.unitPrice = unitPrice
        self.quantity = quantity
        self.taxRateValue = taxRate.rawValue
        self.taxTypeRaw = taxType.rawValue
        self.isCustom = isCustom
        self.sortOrder = sortOrder
    }

    var taxRate: TaxRate { TaxRate(rawValue: taxRateValue) ?? .standard }
    var taxType: TaxType { TaxType(rawValue: taxTypeRaw) ?? .included }
    var lineAmount: Int { unitPrice * quantity }
}

@Model
final class CancellationRecord {
    @Attribute(.unique) var id: UUID
    var saleID: UUID
    var cancelledAt: Date
    var reason: String
    var replacementSaleID: UUID?

    init(
        id: UUID = UUID(),
        saleID: UUID,
        cancelledAt: Date = .now,
        reason: String,
        replacementSaleID: UUID? = nil
    ) {
        self.id = id
        self.saleID = saleID
        self.cancelledAt = cancelledAt
        self.reason = reason
        self.replacementSaleID = replacementSaleID
    }
}
