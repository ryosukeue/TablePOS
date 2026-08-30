import CryptoKit
import Foundation
import SwiftData

struct TablePOSBackupSummary: Sendable {
    let createdAt: Date
    let tables: Int
    let products: Int
    let openOrders: Int
    let sales: Int
}

enum TablePOSBackupError: LocalizedError {
    case unsupportedFormat
    case damagedFile
    case inconsistentData(String)
    case existingBusinessData

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "このバックアップ形式には対応していません。アプリを最新版へ更新してください。"
        case .damagedFile:
            "バックアップの整合性を確認できません。ファイルが破損または変更されています。"
        case .inconsistentData(let reason):
            "バックアップ内のデータ関係が不正です（\(reason)）。"
        case .existingBusinessData:
            "現在の端末には設定済みデータがあります。誤上書きを防ぐため、復元は初回設定前の端末で行ってください。"
        }
    }
}

enum BackupService {
    static let formatVersion = 1

    @MainActor
    static func makeBackupData(in context: ModelContext) throws -> (Data, TablePOSBackupSummary) {
        let payload = BackupPayload(
            settings: try context.fetch(FetchDescriptor<StoreSettings>()).map(StoreSettingsSnapshot.init),
            tables: try context.fetch(FetchDescriptor<DiningTable>()).map(DiningTableSnapshot.init),
            categories: try context.fetch(FetchDescriptor<ProductCategory>()).map(ProductCategorySnapshot.init),
            products: try context.fetch(FetchDescriptor<Product>()).map(ProductSnapshot.init),
            orders: try context.fetch(FetchDescriptor<Order>()).map(OrderSnapshot.init),
            orderItems: try context.fetch(FetchDescriptor<OrderItem>()).map(OrderItemSnapshot.init),
            sales: try context.fetch(FetchDescriptor<Sale>()).map(SaleSnapshot.init),
            saleItems: try context.fetch(FetchDescriptor<SaleItem>()).map(SaleItemSnapshot.init),
            cancellations: try context.fetch(FetchDescriptor<CancellationRecord>()).map(CancellationSnapshot.init)
        )
        try validate(payload)
        let createdAt = Date.now
        let envelope = BackupEnvelope(
            formatVersion: formatVersion,
            createdAt: createdAt,
            checksum: checksum(for: payload),
            payload: payload
        )
        let data = try envelopeEncoder(prettyPrinted: true).encode(envelope)
        return (data, summary(for: envelope))
    }

    static func inspect(data: Data) throws -> (BackupEnvelope, TablePOSBackupSummary) {
        let envelope = try envelopeDecoder().decode(BackupEnvelope.self, from: data)
        guard envelope.formatVersion == formatVersion else { throw TablePOSBackupError.unsupportedFormat }
        guard checksum(for: envelope.payload) == envelope.checksum else { throw TablePOSBackupError.damagedFile }
        try validate(envelope.payload)
        return (envelope, summary(for: envelope))
    }

    static func load(url: URL) throws -> (BackupEnvelope, TablePOSBackupSummary) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try inspect(data: Data(contentsOf: url))
    }

    @MainActor
    static func restore(_ envelope: BackupEnvelope, in context: ModelContext) throws {
        guard envelope.formatVersion == formatVersion else { throw TablePOSBackupError.unsupportedFormat }
        guard checksum(for: envelope.payload) == envelope.checksum else { throw TablePOSBackupError.damagedFile }
        try validate(envelope.payload)
        guard try hasBusinessData(in: context) == false else { throw TablePOSBackupError.existingBusinessData }

        let payload = envelope.payload

        payload.settings.forEach {
            context.insert(StoreSettings(
                id: $0.id,
                isSetupComplete: $0.isSetupComplete,
                tableCount: $0.tableCount,
                taxRoundingRule: $0.taxRoundingRule
            ))
        }
        payload.tables.forEach {
            context.insert(DiningTable(id: $0.id, number: $0.number, name: $0.name, sortOrder: $0.sortOrder))
        }
        payload.categories.forEach {
            context.insert(ProductCategory(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder))
        }
        payload.products.forEach {
            context.insert(Product(
                id: $0.id,
                name: $0.name,
                price: $0.price,
                taxRate: $0.taxRate,
                taxType: $0.taxType,
                menuType: $0.menuType,
                categoryID: $0.categoryID,
                isFrequent: $0.isFrequent,
                isEnabled: $0.isEnabled,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            ))
        }
        payload.orders.forEach {
            let order = Order(id: $0.id, tableID: $0.tableID, openedAt: $0.openedAt)
            order.statusRaw = $0.status.rawValue
            context.insert(order)
        }
        payload.orderItems.forEach {
            context.insert(OrderItem(
                id: $0.id,
                orderID: $0.orderID,
                productID: $0.productID,
                name: $0.name,
                unitPrice: $0.unitPrice,
                quantity: $0.quantity,
                taxRate: $0.taxRate,
                taxType: $0.taxType,
                isCustom: $0.isCustom,
                createdAt: $0.createdAt
            ))
        }
        payload.sales.forEach {
            let sale = Sale(
                id: $0.id,
                completedAt: $0.completedAt,
                status: $0.status,
                paymentMethod: $0.paymentMethod,
                sourceTableName: $0.sourceTableName,
                subtotal: $0.subtotal,
                taxableBase8: $0.taxableBase8,
                taxableBase10: $0.taxableBase10,
                includedTax8: $0.includedTax8,
                includedTax10: $0.includedTax10,
                externalTax8: $0.externalTax8,
                externalTax10: $0.externalTax10,
                roundingAdjustment: $0.roundingAdjustment,
                total: $0.total,
                receivedAmount: $0.receivedAmount,
                changeAmount: $0.changeAmount,
                originalSaleID: $0.originalSaleID
            )
            sale.replacementSaleID = $0.replacementSaleID
            sale.cancelledAt = $0.cancelledAt
            sale.cancellationReason = $0.cancellationReason
            context.insert(sale)
        }
        payload.saleItems.forEach {
            context.insert(SaleItem(
                id: $0.id,
                saleID: $0.saleID,
                sourceProductID: $0.sourceProductID,
                name: $0.name,
                unitPrice: $0.unitPrice,
                quantity: $0.quantity,
                taxRate: $0.taxRate,
                taxType: $0.taxType,
                isCustom: $0.isCustom,
                sortOrder: $0.sortOrder
            ))
        }
        payload.cancellations.forEach {
            context.insert(CancellationRecord(
                id: $0.id,
                saleID: $0.saleID,
                cancelledAt: $0.cancelledAt,
                reason: $0.reason,
                replacementSaleID: $0.replacementSaleID
            ))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func hasBusinessData(in context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<StoreSettings>()) > 0 ||
        context.fetchCount(FetchDescriptor<DiningTable>()) > 0 ||
        context.fetchCount(FetchDescriptor<ProductCategory>()) > 0 ||
        context.fetchCount(FetchDescriptor<Product>()) > 0 ||
        context.fetchCount(FetchDescriptor<Order>()) > 0 ||
        context.fetchCount(FetchDescriptor<OrderItem>()) > 0 ||
        context.fetchCount(FetchDescriptor<Sale>()) > 0 ||
        context.fetchCount(FetchDescriptor<SaleItem>()) > 0 ||
        context.fetchCount(FetchDescriptor<CancellationRecord>()) > 0
    }

    static func defaultFilename(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "TablePOS-backup-\(formatter.string(from: date)).json"
    }
}

private extension BackupService {
    static func envelopeEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    static func envelopeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func checksum(for payload: BackupPayload) -> String {
        let data = (try? envelopeEncoder(prettyPrinted: false).encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func summary(for envelope: BackupEnvelope) -> TablePOSBackupSummary {
        TablePOSBackupSummary(
            createdAt: envelope.createdAt,
            tables: envelope.payload.tables.count,
            products: envelope.payload.products.count,
            openOrders: envelope.payload.orders.count,
            sales: envelope.payload.sales.count
        )
    }

    static func validate(_ payload: BackupPayload) throws {
        try requireUnique(payload.settings.map(\.id), name: "店舗設定")
        try requireUnique(payload.tables.map(\.id), name: "テーブル")
        try requireUnique(payload.categories.map(\.id), name: "カテゴリ")
        try requireUnique(payload.products.map(\.id), name: "商品")
        try requireUnique(payload.orders.map(\.id), name: "注文")
        try requireUnique(payload.orderItems.map(\.id), name: "注文明細")
        try requireUnique(payload.sales.map(\.id), name: "会計")
        try requireUnique(payload.saleItems.map(\.id), name: "会計明細")
        try requireUnique(payload.cancellations.map(\.id), name: "取消記録")
        guard payload.settings.count == 1 else { throw TablePOSBackupError.inconsistentData("店舗設定の件数") }

        let tableIDs = Set(payload.tables.map(\.id))
        let orderIDs = Set(payload.orders.map(\.id))
        let saleIDs = Set(payload.sales.map(\.id))
        guard payload.orders.allSatisfy({ tableIDs.contains($0.tableID) }) else {
            throw TablePOSBackupError.inconsistentData("注文のテーブル参照")
        }
        guard payload.orderItems.allSatisfy({ orderIDs.contains($0.orderID) }) else {
            throw TablePOSBackupError.inconsistentData("注文明細の注文参照")
        }
        guard payload.saleItems.allSatisfy({ saleIDs.contains($0.saleID) }) else {
            throw TablePOSBackupError.inconsistentData("会計明細の会計参照")
        }
        guard payload.cancellations.allSatisfy({ saleIDs.contains($0.saleID) }) else {
            throw TablePOSBackupError.inconsistentData("取消記録の会計参照")
        }
        guard payload.products.allSatisfy({ $0.price >= 0 }),
              payload.orderItems.allSatisfy({ $0.unitPrice >= 0 && $0.quantity > 0 }),
              payload.saleItems.allSatisfy({ $0.unitPrice >= 0 && $0.quantity > 0 }) else {
            throw TablePOSBackupError.inconsistentData("金額または数量")
        }
    }

    static func requireUnique(_ ids: [UUID], name: String) throws {
        guard Set(ids).count == ids.count else { throw TablePOSBackupError.inconsistentData("\(name)IDの重複") }
    }

}

struct BackupEnvelope: Codable, Sendable {
    let formatVersion: Int
    let createdAt: Date
    let checksum: String
    let payload: BackupPayload
}

struct BackupPayload: Codable, Sendable {
    let settings: [StoreSettingsSnapshot]
    let tables: [DiningTableSnapshot]
    let categories: [ProductCategorySnapshot]
    let products: [ProductSnapshot]
    let orders: [OrderSnapshot]
    let orderItems: [OrderItemSnapshot]
    let sales: [SaleSnapshot]
    let saleItems: [SaleItemSnapshot]
    let cancellations: [CancellationSnapshot]
}

struct StoreSettingsSnapshot: Codable, Sendable {
    let id: UUID
    let isSetupComplete: Bool
    let tableCount: Int
    let taxRoundingRule: TaxRoundingRule
    init(_ value: StoreSettings) {
        id = value.id; isSetupComplete = value.isSetupComplete; tableCount = value.tableCount
        taxRoundingRule = value.taxRoundingRule
    }
}

struct DiningTableSnapshot: Codable, Sendable {
    let id: UUID; let number: Int; let name: String; let sortOrder: Int
    init(_ value: DiningTable) { id = value.id; number = value.number; name = value.name; sortOrder = value.sortOrder }
}

struct ProductCategorySnapshot: Codable, Sendable {
    let id: UUID; let name: String; let colorHex: String; let sortOrder: Int
    init(_ value: ProductCategory) { id = value.id; name = value.name; colorHex = value.colorHex; sortOrder = value.sortOrder }
}

struct ProductSnapshot: Codable, Sendable {
    let id: UUID; let name: String; let price: Int; let taxRate: TaxRate; let taxType: TaxType
    let menuType: MenuType; let categoryID: UUID?; let isFrequent: Bool; let isEnabled: Bool
    let createdAt: Date; let updatedAt: Date
    init(_ value: Product) {
        id = value.id; name = value.name; price = value.price; taxRate = value.taxRate; taxType = value.taxType
        menuType = value.menuType; categoryID = value.categoryID; isFrequent = value.isFrequent
        isEnabled = value.isEnabled; createdAt = value.createdAt; updatedAt = value.updatedAt
    }
}

struct OrderSnapshot: Codable, Sendable {
    let id: UUID; let tableID: UUID; let openedAt: Date; let status: OrderStatus
    init(_ value: Order) {
        id = value.id; tableID = value.tableID; openedAt = value.openedAt
        status = OrderStatus(rawValue: value.statusRaw) ?? .open
    }
}

struct OrderItemSnapshot: Codable, Sendable {
    let id: UUID; let orderID: UUID; let productID: UUID?; let name: String; let unitPrice: Int
    let quantity: Int; let taxRate: TaxRate; let taxType: TaxType; let isCustom: Bool; let createdAt: Date
    init(_ value: OrderItem) {
        id = value.id; orderID = value.orderID; productID = value.productID; name = value.name
        unitPrice = value.unitPrice; quantity = value.quantity; taxRate = value.taxRate
        taxType = value.taxType; isCustom = value.isCustom; createdAt = value.createdAt
    }
}

struct SaleSnapshot: Codable, Sendable {
    let id: UUID; let completedAt: Date; let status: SaleStatus; let paymentMethod: PaymentMethod
    let sourceTableName: String; let subtotal: Int; let taxableBase8: Int; let taxableBase10: Int
    let includedTax8: Int; let includedTax10: Int; let externalTax8: Int; let externalTax10: Int
    let roundingAdjustment: Int; let total: Int; let receivedAmount: Int?; let changeAmount: Int?
    let originalSaleID: UUID?; let replacementSaleID: UUID?; let cancelledAt: Date?; let cancellationReason: String?
    init(_ value: Sale) {
        id = value.id; completedAt = value.completedAt; status = value.status; paymentMethod = value.paymentMethod
        sourceTableName = value.sourceTableName; subtotal = value.subtotal
        taxableBase8 = value.taxableBase8; taxableBase10 = value.taxableBase10
        includedTax8 = value.includedTax8; includedTax10 = value.includedTax10
        externalTax8 = value.externalTax8; externalTax10 = value.externalTax10
        roundingAdjustment = value.roundingAdjustment; total = value.total
        receivedAmount = value.receivedAmount; changeAmount = value.changeAmount
        originalSaleID = value.originalSaleID; replacementSaleID = value.replacementSaleID
        cancelledAt = value.cancelledAt; cancellationReason = value.cancellationReason
    }
}

struct SaleItemSnapshot: Codable, Sendable {
    let id: UUID; let saleID: UUID; let sourceProductID: UUID?; let name: String; let unitPrice: Int
    let quantity: Int; let taxRate: TaxRate; let taxType: TaxType; let isCustom: Bool; let sortOrder: Int
    init(_ value: SaleItem) {
        id = value.id; saleID = value.saleID; sourceProductID = value.sourceProductID; name = value.name
        unitPrice = value.unitPrice; quantity = value.quantity; taxRate = value.taxRate
        taxType = value.taxType; isCustom = value.isCustom; sortOrder = value.sortOrder
    }
}

struct CancellationSnapshot: Codable, Sendable {
    let id: UUID; let saleID: UUID; let cancelledAt: Date; let reason: String; let replacementSaleID: UUID?
    init(_ value: CancellationRecord) {
        id = value.id; saleID = value.saleID; cancelledAt = value.cancelledAt
        reason = value.reason; replacementSaleID = value.replacementSaleID
    }
}
