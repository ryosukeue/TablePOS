import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

struct TotalBreakdownView: View {
    let summary: TaxSummary
    var adjustment: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            row("商品計", summary.subtotal)
            if summary.externalTax8 > 0 { row("外税 8%", summary.externalTax8) }
            if summary.externalTax10 > 0 { row("外税 10%", summary.externalTax10) }
            if adjustment != 0 { row("10円丸め", adjustment) }
            Divider()
            HStack {
                Text("合計").font(.headline)
                Spacer()
                Text((summary.preRoundedTotal + adjustment).yenText)
                    .font(.title2.bold())
            }
            HStack {
                Text("内税（8% / 10%）")
                Spacer()
                Text("\(summary.includedTax8.yenText) / \(summary.includedTax10.yenText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ amount: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amount.yenText)
        }
    }
}
