import SwiftData
import SwiftUI

struct CustomItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let tableID: UUID

    @State private var name = ""
    @State private var price = 0
    @State private var quantity = 1
    @State private var taxRate = TaxRate.standard
    @State private var taxType = TaxType.included
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("カスタム商品") {
                    TextField("名称（空欄可）", text: $name)
                    TextField("価格", value: $price, format: .number)
                        .keyboardType(.numberPad)
                    Stepper("数量: \(quantity)", value: $quantity, in: 1...999)
                }
                Section("税") {
                    Picker("税率", selection: $taxRate) {
                        ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("区分", selection: $taxType) {
                        ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("カスタム商品")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        do {
                            try OrderService.addCustom(
                                name: name,
                                price: price,
                                quantity: quantity,
                                taxRate: taxRate,
                                taxType: taxType,
                                to: tableID,
                                in: modelContext
                            )
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(price < 0)
                }
            }
            .alert("追加できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.medium])
    }
}

struct MoveTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiningTable.sortOrder) private var tables: [DiningTable]
    @Query private var orders: [Order]

    let sourceTable: DiningTable
    let onMoved: () -> Void
    @State private var mergeDestination: DiningTable?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tables.filter { $0.id != sourceTable.id }) { table in
                        Button {
                            if orders.contains(where: { $0.tableID == table.id }) {
                                mergeDestination = table
                            } else {
                                performMove(to: table, merge: false)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(table.name)
                                    Text(orders.contains { $0.tableID == table.id } ? "使用中" : "空席")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: orders.contains { $0.tableID == table.id }
                                      ? "arrow.triangle.merge" : "arrow.right")
                            }
                        }
                    }
                } footer: {
                    Text("使用中の移動先を選ぶと、注文を合算する確認が表示されます。")
                }
            }
            .navigationTitle("\(sourceTable.name)を移動")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .confirmationDialog(
                "移動先の注文と合算しますか？",
                isPresented: Binding(
                    get: { mergeDestination != nil },
                    set: { if !$0 { mergeDestination = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("合算して移動") {
                    if let destination = mergeDestination {
                        performMove(to: destination, merge: true)
                    }
                }
                Button("キャンセル", role: .cancel) { mergeDestination = nil }
            } message: {
                Text("移動元の明細は移動先の注文へまとめられます。この操作は元に戻せません。")
            }
            .alert("移動できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func performMove(to destination: DiningTable, merge: Bool) {
        do {
            try OrderService.move(
                from: sourceTable.id,
                to: destination.id,
                merge: merge,
                in: modelContext
            )
            dismiss()
            onMoved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [StoreSettings]

    let table: DiningTable
    let items: [OrderItem]
    let onCompleted: () -> Void

    @State private var paymentMethod = PaymentMethod.cash
    @State private var receivedAmount = 0
    @State private var useTenYenRounding = false
    @State private var errorMessage: String?

    private var roundingRule: TaxRoundingRule { settings.first?.taxRoundingRule ?? .floor }
    private var summary: TaxSummary {
        TaxCalculator.calculate(lines: items.map {
            TaxLine(unitPrice: $0.unitPrice, quantity: $0.quantity, taxRate: $0.taxRate, taxType: $0.taxType)
        }, rounding: roundingRule)
    }
    private var adjustment: Int {
        useTenYenRounding ? TaxCalculator.tenYenAdjustment(for: summary.preRoundedTotal) : 0
    }
    private var total: Int { summary.preRoundedTotal + adjustment }
    private var change: Int { max(receivedAmount - total, 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section("会計内容") {
                    TotalBreakdownView(summary: summary, adjustment: adjustment)
                    Button {
                        useTenYenRounding.toggle()
                    } label: {
                        Label(
                            useTenYenRounding ? "10円単位の丸めを解除" : "1円の位を四捨五入して10円単位へ",
                            systemImage: useTenYenRounding ? "arrow.uturn.backward" : "10.circle"
                        )
                    }
                }

                Section("支払い") {
                    Picker("支払方法", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if paymentMethod == .cash {
                        TextField("預かり金", value: $receivedAmount, format: .number)
                            .keyboardType(.numberPad)
                        HStack {
                            Text("お釣り")
                            Spacer()
                            Text(change.yenText).font(.headline)
                        }
                        if receivedAmount < total {
                            Text("あと \((total - receivedAmount).yenText) 必要です")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("\(table.name)の会計")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("会計を完了") { completeCheckout() }
                        .disabled(paymentMethod == .cash && receivedAmount < total)
                }
            }
            .alert("会計できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.large])
    }

    private func completeCheckout() {
        do {
            _ = try OrderService.checkout(
                table: table,
                paymentMethod: paymentMethod,
                receivedAmount: paymentMethod == .cash ? receivedAmount : nil,
                applyTenYenRounding: useTenYenRounding,
                roundingRule: roundingRule,
                in: modelContext
            )
            dismiss()
            onCompleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
