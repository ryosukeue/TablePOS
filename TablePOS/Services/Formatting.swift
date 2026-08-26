import SwiftUI

extension Int {
    var yenText: String {
        Self.yenFormatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }

    private static let yenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x64748B
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension String {
    var nonEmptyOrPlaceholder: String { isEmpty ? "（名称なし）" : self }
}
