import Foundation

enum TaxRate: Int, CaseIterable, Identifiable, Codable, Sendable {
    case reduced = 8
    case standard = 10

    var id: Int { rawValue }
    var label: String { "\(rawValue)%" }
}

enum TaxType: String, CaseIterable, Identifiable, Codable, Sendable {
    case included
    case excluded

    var id: String { rawValue }
    var label: String { self == .included ? "内税" : "外税" }
}

enum MenuType: String, CaseIterable, Identifiable, Codable, Sendable {
    case grand
    case limited

    var id: String { rawValue }
    var label: String { self == .grand ? "グランド" : "期間限定" }
}

enum TaxRoundingRule: String, CaseIterable, Identifiable, Codable {
    case floor
    case nearest
    case ceiling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .floor: "切り捨て"
        case .nearest: "四捨五入"
        case .ceiling: "切り上げ"
        }
    }
}

enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case cash
    case card
    case qr
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "現金"
        case .card: "カード"
        case .qr: "QR"
        case .other: "その他"
        }
    }
}

enum OrderStatus: String, Codable {
    case open
}

enum SaleStatus: String, Codable {
    case completed
    case cancelled

    var label: String { self == .completed ? "完了" : "取消済み" }
}
