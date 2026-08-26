import SwiftData
import SwiftUI

struct SaleHistoryView: View {
    @Query(sort: \Sale.completedAt, order: .reverse) private var sales: [Sale]

    var body: some View {
        List(sales) { sale in
            NavigationLink {
                SaleDetailView(sale: sale)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: sale.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(sale.status == .completed ? .green : .red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sale.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        HStack {
                            Text(sale.sourceTableName)
                            Text("・")
                            Text(sale.paymentMethod.label)
                            if sale.originalSaleID != nil { Text("・訂正版") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(sale.total.yenText).font(.headline)
                        Text(sale.status.label)
                            .font(.caption)
                            .foregroundStyle(sale.status == .completed ? .green : .red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if sales.isEmpty {
                EmptyStateView(title: "会計履歴がありません", message: "会計を完了するとここに記録されます。", systemImage: "clock")
            }
        }
        .navigationTitle("会計履歴")
    }
}

struct SaleDetailView: View {
    @Query(sort: \SaleItem.sortOrder) private var allItems: [SaleItem]
    @Query private var cancellations: [CancellationRecord]
    let sale: Sale

    @State private var showCancel = false
    @State private var showCorrection = false

    private var items: [SaleItem] { allItems.filter { $0.saleID == sale.id } }
    private var cancellation: CancellationRecord? { cancellations.first { $0.saleID == sale.id } }
    private var summary: TaxSummary {
        TaxSummary(
            subtotal: sale.subtotal,
            taxableBase8: sale.taxableBase8,
            taxableBase10: sale.taxableBase10,
            includedTax8: sale.includedTax8,
            includedTax10: sale.includedTax10,
            externalTax8: sale.externalTax8,
            externalTax10: sale.externalTax10
        )
    }

    var body: some View {
        List {
            Section("会計") {
                LabeledContent("日時", value: sale.completedAt.formatted(date: .long, time: .shortened))
                LabeledContent("テーブル", value: sale.sourceTableName)
                LabeledContent("状態", value: sale.status.label)
                LabeledContent("支払方法", value: sale.paymentMethod.label)
                if let original = sale.originalSaleID {
                    LabeledContent("訂正元ID", value: String(original.uuidString.prefix(8)))
                }
                if let replacement = sale.replacementSaleID {
                    LabeledContent("訂正版ID", value: String(replacement.uuidString.prefix(8)))
                }
            }
            Section("明細") {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name.nonEmptyOrPlaceholder)
                            Text("\(item.unitPrice.yenText) × \(item.quantity)・\(item.taxRate.label) \(item.taxType.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.lineAmount.yenText)
                    }
                }
            }
            Section("金額") {
                TotalBreakdownView(summary: summary, adjustment: sale.roundingAdjustment)
                if let received = sale.receivedAmount { LabeledContent("預かり", value: received.yenText) }
                if let change = sale.changeAmount { LabeledContent("お釣り", value: change.yenText) }
            }
            if let cancellation {
                Section("取消記録") {
                    LabeledContent("取消日時", value: cancellation.cancelledAt.formatted(date: .long, time: .shortened))
                    LabeledContent("理由", value: cancellation.reason)
                }
            }
            if sale.status == .completed {
                Section("修正・取消") {
                    Button("訂正版を作成", systemImage: "doc.badge.plus") { showCorrection = true }
                    Button("この会計を取り消す", systemImage: "xmark.circle", role: .destructive) { showCancel = true }
                }
            }
        }
        .navigationTitle("会計詳細")
        .sheet(isPresented: $showCancel) { CancelSaleSheet(sale: sale) }
        .sheet(isPresented: $showCorrection) { CorrectionSaleSheet(original: sale, sourceItems: items) }
    }
}

private struct CancelSaleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let sale: Sale
    @State private var reason = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("取消理由") {
                    TextField("例: 入力間違い", text: $reason, axis: .vertical)
                }
                Section {
                    Text("売上は削除されず、取消済みとして記録されます。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("会計を取り消す")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("取消を記録", role: .destructive) {
                        do {
                            try SaleService.cancel(sale: sale, reason: reason, in: modelContext)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("取消できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.medium])
    }
}

private struct CorrectionSaleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [StoreSettings]

    let original: Sale
    @State private var lines: [CorrectionLine]
    @State private var reason = ""
    @State private var paymentMethod: PaymentMethod
    @State private var receivedAmount: Int
    @State private var useTenYenRounding: Bool
    @State private var errorMessage: String?

    init(original: Sale, sourceItems: [SaleItem]) {
        self.original = original
        _lines = State(initialValue: sourceItems.map {
            CorrectionLine(
                id: $0.id,
                sourceProductID: $0.sourceProductID,
                name: $0.name,
                unitPrice: $0.unitPrice,
                quantity: $0.quantity,
                taxRate: $0.taxRate,
                taxType: $0.taxType,
                isCustom: $0.isCustom
            )
        })
        _paymentMethod = State(initialValue: original.paymentMethod)
        _receivedAmount = State(initialValue: original.receivedAmount ?? original.total)
        _useTenYenRounding = State(initialValue: original.roundingAdjustment != 0)
    }

    private var roundingRule: TaxRoundingRule { settings.first?.taxRoundingRule ?? .floor }
    private var summary: TaxSummary {
        TaxCalculator.calculate(lines: lines.filter { $0.quantity > 0 }.map {
            TaxLine(unitPrice: $0.unitPrice, quantity: $0.quantity, taxRate: $0.taxRate, taxType: $0.taxType)
        }, rounding: roundingRule)
    }
    private var adjustment: Int {
        useTenYenRounding ? TaxCalculator.tenYenAdjustment(for: summary.preRoundedTotal) : 0
    }
    private var total: Int { summary.preRoundedTotal + adjustment }

    var body: some View {
        NavigationStack {
            Form {
                Section("訂正理由") {
                    TextField("必須", text: $reason, axis: .vertical)
                }
                Section("明細を訂正") {
                    ForEach($lines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("商品名", text: $line.name)
                            HStack {
                                TextField("単価", value: $line.unitPrice, format: .number)
                                    .keyboardType(.numberPad)
                                TextField("数量", value: $line.quantity, format: .number)
                                    .keyboardType(.numberPad)
                            }
                            HStack {
                                Picker("税率", selection: $line.taxRate) {
                                    ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                                }
                                Picker("区分", selection: $line.taxType) {
                                    ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                Section("再会計") {
                    TotalBreakdownView(summary: summary, adjustment: adjustment)
                    Button(useTenYenRounding ? "10円丸めを解除" : "10円単位へ丸める") {
                        useTenYenRounding.toggle()
                    }
                    Picker("支払方法", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) }
                    }
                    if paymentMethod == .cash {
                        TextField("預かり金", value: $receivedAmount, format: .number)
                            .keyboardType(.numberPad)
                        LabeledContent("お釣り", value: max(receivedAmount - total, 0).yenText)
                    }
                }
            }
            .navigationTitle("訂正版を作成")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("訂正を確定") { createCorrection() }
                        .disabled(
                            reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            lines.allSatisfy { $0.quantity <= 0 } ||
                            (paymentMethod == .cash && receivedAmount < total)
                        )
                }
            }
            .alert("訂正できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func createCorrection() {
        do {
            _ = try SaleService.createCorrection(
                original: original,
                lines: lines,
                reason: reason,
                paymentMethod: paymentMethod,
                receivedAmount: paymentMethod == .cash ? receivedAmount : nil,
                applyTenYenRounding: useTenYenRounding,
                roundingRule: roundingRule,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
