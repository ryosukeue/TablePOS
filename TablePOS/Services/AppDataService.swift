import Foundation
import SwiftData

enum AppDataError: LocalizedError {
    case occupiedTableWouldBeRemoved
    case noActiveOrder
    case invalidDestination
    case emptyOrder
    case insufficientCash
    case alreadyCancelled

    var errorDescription: String? {
        switch self {
        case .occupiedTableWouldBeRemoved: "使用中のテーブルが含まれるため、テーブル数を減らせません。"
        case .noActiveOrder: "移動する注文がありません。"
        case .invalidDestination: "移動先のテーブルを確認してください。"
        case .emptyOrder: "商品がないため会計できません。"
        case .insufficientCash: "預かり金が会計金額に足りません。"
        case .alreadyCancelled: "この会計はすでに取り消されています。"
        }
    }
}

enum AppDataService {
    static func setupStore(tableCount: Int, in context: ModelContext) throws {
        let safeCount = min(max(tableCount, 1), 100)
        let settings = try context.fetch(FetchDescriptor<StoreSettings>()).first ?? StoreSettings()
        if settings.modelContext == nil { context.insert(settings) }
        settings.tableCount = safeCount
        settings.isSetupComplete = true
        try ensureDefaultCategories(in: context)
        try resizeTables(to: safeCount, settings: settings, in: context)
    }

    static func ensureDefaultCategories(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<ProductCategory>()) == 0 else { return }
        [
            ProductCategory(name: "ドリンク", colorHex: "2563EB", sortOrder: 0),
            ProductCategory(name: "フード", colorHex: "EA580C", sortOrder: 1),
            ProductCategory(name: "突き出し", colorHex: "16A34A", sortOrder: 2),
            ProductCategory(name: "その他", colorHex: "64748B", sortOrder: 3)
        ].forEach(context.insert)
        try context.save()
    }

    static func resizeTables(
        to requestedCount: Int,
        settings: StoreSettings,
        in context: ModelContext
    ) throws {
        let requestedCount = min(max(requestedCount, 1), 100)
        let tables = try context.fetch(FetchDescriptor<DiningTable>()).sorted { $0.number < $1.number }
        let orders = try context.fetch(FetchDescriptor<Order>())

        if requestedCount < tables.count {
            let removing = tables.filter { $0.number > requestedCount }
            let occupiedIDs = Set(orders.map(\.tableID))
            guard removing.allSatisfy({ !occupiedIDs.contains($0.id) }) else {
                throw AppDataError.occupiedTableWouldBeRemoved
            }
            removing.forEach(context.delete)
        } else if requestedCount > tables.count {
            let existingNumbers = Set(tables.map(\.number))
            for number in 1...requestedCount where !existingNumbers.contains(number) {
                context.insert(DiningTable(number: number))
            }
        }

        settings.tableCount = requestedCount
        try context.save()
    }

    static func insertSampleProducts(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Product>()) == 0 else { return }
        try ensureDefaultCategories(in: context)
        let categories = try context.fetch(FetchDescriptor<ProductCategory>())
        func category(_ name: String) -> UUID? { categories.first { $0.name == name }?.id }

        let products = [
            Product(name: "生ビール", price: 600, taxRate: .standard, taxType: .included, menuType: .grand, categoryID: category("ドリンク"), isFrequent: true),
            Product(name: "ウーロン茶", price: 350, taxRate: .standard, taxType: .included, menuType: .grand, categoryID: category("ドリンク"), isFrequent: true),
            Product(name: "枝豆", price: 400, taxRate: .standard, taxType: .included, menuType: .grand, categoryID: category("フード"), isFrequent: true),
            Product(name: "唐揚げ", price: 680, taxRate: .standard, taxType: .included, menuType: .grand, categoryID: category("フード"), isFrequent: true)
        ]
        products.forEach {
            ProductSearch.updateIndex(for: $0)
            context.insert($0)
        }
        try context.save()
    }
}

enum OrderService {
    static func activeOrder(for tableID: UUID, in context: ModelContext) throws -> Order? {
        try context.fetch(FetchDescriptor<Order>()).first { $0.tableID == tableID }
    }

    @discardableResult
    static func add(product: Product, to tableID: UUID, in context: ModelContext) throws -> Order {
        let order = try getOrCreateOrder(for: tableID, in: context)
        let items = try context.fetch(FetchDescriptor<OrderItem>()).filter { $0.orderID == order.id }
        if let existing = items.first(where: {
            $0.productID == product.id &&
            $0.unitPrice == product.price &&
            $0.taxRateValue == product.taxRateValue &&
            $0.taxTypeRaw == product.taxTypeRaw
        }) {
            existing.quantity += 1
        } else {
            context.insert(OrderItem(
                orderID: order.id,
                productID: product.id,
                name: product.name,
                unitPrice: product.price,
                quantity: 1,
                taxRate: product.taxRate,
                taxType: product.taxType,
                isCustom: false
            ))
        }
        try context.save()
        return order
    }

    @discardableResult
    static func addCustom(
        name: String,
        price: Int,
        quantity: Int,
        taxRate: TaxRate,
        taxType: TaxType,
        to tableID: UUID,
        in context: ModelContext
    ) throws -> Order {
        let order = try getOrCreateOrder(for: tableID, in: context)
        context.insert(OrderItem(
            orderID: order.id,
            productID: nil,
            name: name,
            unitPrice: max(price, 0),
            quantity: max(quantity, 1),
            taxRate: taxRate,
            taxType: taxType,
            isCustom: true
        ))
        try context.save()
        return order
    }

    static func setQuantity(_ quantity: Int, for item: OrderItem, in context: ModelContext) throws {
        if quantity <= 0 {
            let orderID = item.orderID
            context.delete(item)
            try removeOrderIfEmpty(orderID: orderID, in: context)
        } else {
            item.quantity = quantity
        }
        try context.save()
    }

    static func move(
        from sourceTableID: UUID,
        to destinationTableID: UUID,
        merge: Bool,
        in context: ModelContext
    ) throws {
        guard sourceTableID != destinationTableID else { throw AppDataError.invalidDestination }
        guard let source = try activeOrder(for: sourceTableID, in: context) else {
            throw AppDataError.noActiveOrder
        }

        if let destination = try activeOrder(for: destinationTableID, in: context) {
            guard merge else { throw AppDataError.invalidDestination }
            let allItems = try context.fetch(FetchDescriptor<OrderItem>())
            let sourceItems = allItems.filter { $0.orderID == source.id }
            let destinationItems = allItems.filter { $0.orderID == destination.id }
            for sourceItem in sourceItems {
                if let match = destinationItems.first(where: {
                    $0.productID == sourceItem.productID &&
                    $0.name == sourceItem.name &&
                    $0.unitPrice == sourceItem.unitPrice &&
                    $0.taxRateValue == sourceItem.taxRateValue &&
                    $0.taxTypeRaw == sourceItem.taxTypeRaw
                }) {
                    match.quantity += sourceItem.quantity
                    context.delete(sourceItem)
                } else {
                    sourceItem.orderID = destination.id
                }
            }
            context.delete(source)
        } else {
            source.tableID = destinationTableID
        }
        try context.save()
    }

    static func checkout(
        table: DiningTable,
        paymentMethod: PaymentMethod,
        receivedAmount: Int?,
        applyTenYenRounding: Bool,
        roundingRule: TaxRoundingRule,
        in context: ModelContext
    ) throws -> Sale {
        guard let order = try activeOrder(for: table.id, in: context) else { throw AppDataError.emptyOrder }
        let items = try context.fetch(FetchDescriptor<OrderItem>())
            .filter { $0.orderID == order.id }
            .sorted { $0.createdAt < $1.createdAt }
        guard !items.isEmpty else { throw AppDataError.emptyOrder }

        let summary = TaxCalculator.calculate(lines: items.map {
            TaxLine(unitPrice: $0.unitPrice, quantity: $0.quantity, taxRate: $0.taxRate, taxType: $0.taxType)
        }, rounding: roundingRule)
        let adjustment = applyTenYenRounding ? TaxCalculator.tenYenAdjustment(for: summary.preRoundedTotal) : 0
        let total = summary.preRoundedTotal + adjustment
        if paymentMethod == .cash, (receivedAmount ?? 0) < total { throw AppDataError.insufficientCash }
        let received = paymentMethod == .cash ? receivedAmount : nil

        let sale = Sale(
            paymentMethod: paymentMethod,
            sourceTableName: table.name,
            subtotal: summary.subtotal,
            taxableBase8: summary.taxableBase8,
            taxableBase10: summary.taxableBase10,
            includedTax8: summary.includedTax8,
            includedTax10: summary.includedTax10,
            externalTax8: summary.externalTax8,
            externalTax10: summary.externalTax10,
            roundingAdjustment: adjustment,
            total: total,
            receivedAmount: received,
            changeAmount: received.map { $0 - total }
        )
        context.insert(sale)
        for (index, item) in items.enumerated() {
            context.insert(SaleItem(
                saleID: sale.id,
                sourceProductID: item.productID,
                name: item.name,
                unitPrice: item.unitPrice,
                quantity: item.quantity,
                taxRate: item.taxRate,
                taxType: item.taxType,
                isCustom: item.isCustom,
                sortOrder: index
            ))
            context.delete(item)
        }
        context.delete(order)
        try context.save()
        return sale
    }

    private static func getOrCreateOrder(for tableID: UUID, in context: ModelContext) throws -> Order {
        if let existing = try activeOrder(for: tableID, in: context) { return existing }
        let order = Order(tableID: tableID)
        context.insert(order)
        return order
    }

    private static func removeOrderIfEmpty(orderID: UUID, in context: ModelContext) throws {
        let hasItems = try context.fetch(FetchDescriptor<OrderItem>()).contains { $0.orderID == orderID }
        guard !hasItems, let order = try context.fetch(FetchDescriptor<Order>()).first(where: { $0.id == orderID }) else { return }
        context.delete(order)
    }
}

struct CorrectionLine: Identifiable {
    let id: UUID
    var sourceProductID: UUID?
    var name: String
    var unitPrice: Int
    var quantity: Int
    var taxRate: TaxRate
    var taxType: TaxType
    var isCustom: Bool
}

enum SaleService {
    static func cancel(sale: Sale, reason: String, in context: ModelContext) throws {
        guard sale.status == .completed else { throw AppDataError.alreadyCancelled }
        let date = Date.now
        sale.status = .cancelled
        sale.cancelledAt = date
        sale.cancellationReason = reason
        context.insert(CancellationRecord(saleID: sale.id, cancelledAt: date, reason: reason))
        try context.save()
    }

    static func createCorrection(
        original: Sale,
        lines: [CorrectionLine],
        reason: String,
        paymentMethod: PaymentMethod,
        receivedAmount: Int?,
        applyTenYenRounding: Bool,
        roundingRule: TaxRoundingRule,
        in context: ModelContext
    ) throws -> Sale {
        guard original.status == .completed else { throw AppDataError.alreadyCancelled }
        let validLines = lines.filter { $0.quantity > 0 && $0.unitPrice >= 0 }
        guard !validLines.isEmpty else { throw AppDataError.emptyOrder }
        let summary = TaxCalculator.calculate(lines: validLines.map {
            TaxLine(unitPrice: $0.unitPrice, quantity: $0.quantity, taxRate: $0.taxRate, taxType: $0.taxType)
        }, rounding: roundingRule)
        let adjustment = applyTenYenRounding ? TaxCalculator.tenYenAdjustment(for: summary.preRoundedTotal) : 0
        let total = summary.preRoundedTotal + adjustment
        if paymentMethod == .cash, (receivedAmount ?? 0) < total { throw AppDataError.insufficientCash }

        let replacement = Sale(
            paymentMethod: paymentMethod,
            sourceTableName: original.sourceTableName,
            subtotal: summary.subtotal,
            taxableBase8: summary.taxableBase8,
            taxableBase10: summary.taxableBase10,
            includedTax8: summary.includedTax8,
            includedTax10: summary.includedTax10,
            externalTax8: summary.externalTax8,
            externalTax10: summary.externalTax10,
            roundingAdjustment: adjustment,
            total: total,
            receivedAmount: paymentMethod == .cash ? receivedAmount : nil,
            changeAmount: paymentMethod == .cash ? receivedAmount.map { $0 - total } : nil,
            originalSaleID: original.id
        )
        context.insert(replacement)
        for (index, line) in validLines.enumerated() {
            context.insert(SaleItem(
                saleID: replacement.id,
                sourceProductID: line.sourceProductID,
                name: line.name,
                unitPrice: line.unitPrice,
                quantity: line.quantity,
                taxRate: line.taxRate,
                taxType: line.taxType,
                isCustom: line.isCustom,
                sortOrder: index
            ))
        }

        let date = Date.now
        original.status = .cancelled
        original.cancelledAt = date
        original.cancellationReason = reason
        original.replacementSaleID = replacement.id
        context.insert(CancellationRecord(
            saleID: original.id,
            cancelledAt: date,
            reason: reason,
            replacementSaleID: replacement.id
        ))
        try context.save()
        return replacement
    }
}
