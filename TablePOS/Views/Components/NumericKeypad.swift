import SwiftUI

struct NumericKeypad: View {
    @Binding var digits: String
    var maximumDigits = 9
    var showsDoubleZero = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(["7", "8", "9", "4", "5", "6", "1", "2", "3"], id: \.self) { value in
                    key(value) { append(value) }
                }
                if showsDoubleZero {
                    key("00") { append("00") }
                } else {
                    key("クリア", role: .destructive) { digits = "" }
                        .font(.subheadline.bold())
                }
                key("0") { append("0") }
                key("⌫") { if !digits.isEmpty { digits.removeLast() } }
                    .accessibilityLabel("一文字削除")
            }
            if showsDoubleZero {
                Button("入力をクリア", role: .destructive) { digits = "" }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func key(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private func append(_ value: String) {
        let candidate = digits + value
        guard candidate.count <= maximumDigits else { return }
        digits = candidate.drop(while: { $0 == "0" }).isEmpty ? "0" : String(candidate.drop(while: { $0 == "0" }))
    }
}
