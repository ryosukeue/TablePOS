import SwiftData
import SwiftUI

struct CustomItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let tableID: UUID

    @State private var name = ""
    @State private var priceDigits = ""
    @State private var quantity = 1
    @State private var taxRate = TaxRate.standard
    @State private var taxType = TaxType.included
    @State private var errorMessage: String?

    private var price: Int { Int(priceDigits) ?? 0 }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let wide = proxy.size.width >= 700
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 32) {
                            customItemSummary
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            Divider()
                            customItemInput
                                .frame(width: min(430, proxy.size.width * 0.46))
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                customItemInput
                                customItemSummary
                            }
                        }
                    }
                }
                .padding(28)
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
                    .disabled(priceDigits.isEmpty)
                }
            }
            .alert("追加できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.large])
    }

    private var customItemInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("商品名（空欄可）")
                .font(.headline)
            TextField("例：本日のおすすめ", text: $name)
                .font(.title2)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .trailing, spacing: 4) {
                Text("価格")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(price.yenText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .minimumScaleFactor(0.65)
            }

            HStack(spacing: 12) {
                Picker("税率", selection: $taxRate) {
                    ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("税区分", selection: $taxType) {
                    ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            NumericKeypad(digits: $priceDigits)
        }
    }

    private var customItemSummary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("注文へ追加する内容")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrPlaceholder)
                    .font(.title.bold())
                Text("\(taxRate.label)・\(taxType.label)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text((price * quantity).yenText)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 12) {
                Text("数量")
                    .font(.headline)
                HStack(spacing: 24) {
                    Button { quantity = max(1, quantity - 1) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 46))
                    }
                    Text("\(quantity)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .frame(minWidth: 80)
                    Button { quantity = min(999, quantity + 1) } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 46))
                    }
                }
                .buttonStyle(.plain)
            }
        }
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

    @StateObject private var printerService = StarPrinterService.shared
    @State private var step = CheckoutStep.confirmCount
    @State private var confirmedCountDigits = ""
    @State private var paymentMethod = PaymentMethod.cash
    @State private var receivedDigits = ""
    @State private var useTenYenRounding = false
    @State private var completedSale: Sale?
    @State private var completedItems: [SaleItem] = []
    @State private var showDigitalReceipt = false
    @State private var printerMessage: String?
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
    private var expectedCount: Int { items.reduce(0) { $0 + $1.quantity } }
    private var confirmedCount: Int? { Int(confirmedCountDigits) }
    private var countMatches: Bool { confirmedCount == expectedCount }
    private var receivedAmount: Int { Int(receivedDigits) ?? 0 }
    private var change: Int { max(receivedAmount - total, 0) }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .confirmCount:
                    countConfirmation
                case .payment:
                    paymentEntry
                case .completed:
                    completionSummary
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { leadingToolbarButton }
                ToolbarItem(placement: .confirmationAction) {
                    trailingToolbarButton
                }
            }
            .alert("会計できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showDigitalReceipt) {
                if let completedSale {
                    DigitalReceiptView(sale: completedSale, items: completedItems)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(step == .completed)
    }

    private var navigationTitle: String {
        switch step {
        case .confirmCount: "1/3 注文数の確認"
        case .payment: "2/3 お支払い"
        case .completed: "3/3 会計完了"
        }
    }

    @ViewBuilder
    private var leadingToolbarButton: some View {
        switch step {
        case .confirmCount:
            Button("キャンセル") { dismiss() }
        case .payment:
            Button("注文数へ戻る") { step = .confirmCount }
        case .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingToolbarButton: some View {
        switch step {
        case .confirmCount:
            Button("支払いへ") { step = .payment }
                .disabled(!countMatches)
        case .payment:
            Button("会計を完了") { completeCheckout() }
                .disabled(paymentMethod == .cash && receivedAmount < total)
                .fontWeight(.bold)
        case .completed:
            Button("閉じる") { finish() }
                .fontWeight(.bold)
        }
    }

    private var countConfirmation: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            Group {
                if wide {
                    HStack(spacing: 28) {
                        checkoutOverview
                        Divider()
                        countInput
                            .frame(width: min(390, proxy.size.width * 0.42))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) { checkoutOverview; countInput }
                    }
                }
            }
            .padding(28)
        }
    }

    private var checkoutOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(table.name)
                .font(.title2.bold())
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name.nonEmptyOrPlaceholder)
                            Spacer()
                            Text("× \(item.quantity)").fontWeight(.bold)
                            Text(item.lineAmount.yenText).frame(width: 100, alignment: .trailing)
                        }
                        Divider()
                    }
                }
            }
            Text(total.yenText)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var countInput: some View {
        VStack(spacing: 18) {
            Text("実際の注文数を入力")
                .font(.title2.bold())
            Text("明細を見ながら、商品の合計個数を数えて入力してください。一致するまで支払いへ進めません。")
                .foregroundStyle(.secondary)
            Text(confirmedCountDigits.isEmpty ? "—" : "\(confirmedCountDigits)点")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
            if !confirmedCountDigits.isEmpty {
                Label(
                    countMatches ? "注文数が一致しました" : "注文数が一致しません",
                    systemImage: countMatches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(countMatches ? .green : .red)
            }
            NumericKeypad(digits: $confirmedCountDigits, maximumDigits: 3, showsDoubleZero: false)
        }
    }

    private var paymentEntry: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            Group {
                if wide {
                    HStack(spacing: 28) {
                        paymentSummary
                        Divider()
                        paymentControls
                            .frame(width: min(430, proxy.size.width * 0.45))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) { paymentSummary; paymentControls }
                    }
                }
            }
            .padding(28)
        }
    }

    private var paymentSummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("お支払い金額")
                .font(.title2.bold())
            Text(total.yenText)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .minimumScaleFactor(0.6)
            TotalBreakdownView(summary: summary, adjustment: adjustment)
            Button {
                useTenYenRounding.toggle()
            } label: {
                Label(
                    useTenYenRounding ? "10円丸めを解除" : "1円の位を四捨五入して10円単位へ",
                    systemImage: useTenYenRounding ? "arrow.uturn.backward" : "10.circle"
                )
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var paymentControls: some View {
        VStack(spacing: 18) {
            Picker("支払方法", selection: $paymentMethod) {
                ForEach(PaymentMethod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if paymentMethod == .cash {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("お預かり")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(receivedAmount.yenText)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.65)
                }
                HStack {
                    Text(receivedAmount < total ? "不足" : "お釣り")
                    Spacer()
                    Text(receivedAmount < total ? (total - receivedAmount).yenText : change.yenText)
                        .font(.title2.bold())
                        .foregroundStyle(receivedAmount < total ? .red : .primary)
                }
                NumericKeypad(digits: $receivedDigits)
            } else {
                ContentUnavailableView(
                    "\(paymentMethod.label)でお支払い",
                    systemImage: paymentMethod == .card ? "creditcard" : "qrcode",
                    description: Text("決済端末での処理を確認してから、右上の「会計を完了」を押してください。")
                )
            }
        }
    }

    private var completionSummary: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("会計が完了しました")
                    .font(.largeTitle.bold())
                Text(completedSale?.total.yenText ?? total.yenText)
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                if paymentMethod == .cash {
                    LabeledContent("お預かり", value: receivedAmount.yenText)
                        .font(.title3)
                    LabeledContent("お釣り", value: change.yenText)
                        .font(.title2.bold())
                }
                Divider()
                Button {
                    showDigitalReceipt = true
                } label: {
                    Label("デジタルレシートを表示", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(completedSale == nil)

                Button {
                    printPhysicalReceipt()
                } label: {
                    Label(
                        printerService.isOperating ? "印刷中…" : "物理レシートを印刷",
                        systemImage: "printer.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(completedSale == nil || printerService.isOperating)

                if paymentMethod == .cash {
                    Button("キャッシュドロアを開く", systemImage: "tray.2") {
                        openCashDrawer()
                    }
                    .disabled(printerService.isOperating)
                }

                Text(printerService.selectedPrinterLabel.map { "使用プリンタ：\($0)" }
                     ?? "プリンタ未設定：設定タブからmPOPを検索してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let printerMessage {
                    Text(printerMessage)
                        .font(.callout)
                        .foregroundStyle(printerMessage.contains("完了") || printerMessage.contains("開きました") ? .green : .red)
                }
            }
            .frame(maxWidth: 620)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private func completeCheckout() {
        do {
            let sale = try OrderService.checkout(
                table: table,
                paymentMethod: paymentMethod,
                receivedAmount: paymentMethod == .cash ? receivedAmount : nil,
                applyTenYenRounding: useTenYenRounding,
                roundingRule: roundingRule,
                in: modelContext
            )
            completedSale = sale
            completedItems = try modelContext.fetch(FetchDescriptor<SaleItem>())
                .filter { $0.saleID == sale.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            step = .completed
            if paymentMethod == .cash, printerService.selectedPrinterLabel != nil {
                openCashDrawer()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func printPhysicalReceipt() {
        guard let completedSale else { return }
        Task {
            do {
                try await printerService.printReceipt(sale: completedSale, items: completedItems, openDrawer: false)
                printerMessage = "レシートの印刷とカットが完了しました。"
            } catch {
                printerMessage = error.localizedDescription
            }
        }
    }

    private func openCashDrawer() {
        Task {
            do {
                try await printerService.openDrawer()
                printerMessage = "キャッシュドロアを開きました。"
            } catch {
                printerMessage = error.localizedDescription
            }
        }
    }

    private func finish() {
        dismiss()
        onCompleted()
    }
}

private enum CheckoutStep {
    case confirmCount
    case payment
    case completed
}
