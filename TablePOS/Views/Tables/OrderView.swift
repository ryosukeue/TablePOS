import SwiftData
import SwiftUI

struct OrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]
    @Query private var orders: [Order]
    @Query(sort: \OrderItem.createdAt) private var allItems: [OrderItem]
    @Query private var settings: [StoreSettings]

    let table: DiningTable
    @State private var searchText = ""
    @State private var showCustomItem = false
    @State private var showMove = false
    @State private var showCheckout = false
    @State private var errorMessage: String?
    @State private var compactSection = CompactOrderSection.products

    private enum CompactOrderSection: String, CaseIterable, Identifiable {
        case products
        case cart

        var id: String { rawValue }
    }

    private var order: Order? { orders.first { $0.tableID == table.id } }
    private var items: [OrderItem] {
        guard let id = order?.id else { return [] }
        return allItems.filter { $0.orderID == id }
    }
    private var roundingRule: TaxRoundingRule { settings.first?.taxRoundingRule ?? .floor }
    private var summary: TaxSummary {
        TaxCalculator.calculate(lines: items.map {
            TaxLine(unitPrice: $0.unitPrice, quantity: $0.quantity, taxRate: $0.taxRate, taxType: $0.taxType)
        }, rounding: roundingRule)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(spacing: 0) {
                    Picker("表示", selection: $compactSection) {
                        Text("商品").tag(CompactOrderSection.products)
                        Text("注文 \(items.reduce(0) { $0 + $1.quantity })点")
                            .tag(CompactOrderSection.cart)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    switch compactSection {
                    case .products:
                        productPane
                    case .cart:
                        cartPane
                    }
                }
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        productPane
                            .frame(width: proxy.size.width * 0.62)
                        Divider()
                        cartPane
                    }
                }
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("カスタム商品", systemImage: "plus.circle") { showCustomItem = true }
                    Button("テーブル移動", systemImage: "arrow.right.arrow.left") { showMove = true }
                        .disabled(items.isEmpty)
                } label: {
                    Label("注文操作", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCustomItem) {
            CustomItemSheet(tableID: table.id)
        }
        .sheet(isPresented: $showMove) {
            MoveTableSheet(sourceTable: table) {
                showMove = false
                dismiss()
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView(table: table, items: items) {
                showCheckout = false
                dismiss()
            }
        }
        .alert("操作できませんでした", isPresented: .constant(errorMessage != nil)) {
            Button("閉じる") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var productPane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("商品名・読み・意味で検索", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button("消去") { searchText = "" }.font(.caption)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding()

            ScrollView {
                if searchText.isEmpty {
                    frequentProducts
                } else {
                    productGrid(ProductSearch.ranked(products.filter(\.isEnabled), query: searchText))
                        .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var frequentProducts: some View {
        let frequent = products.filter { $0.isEnabled && $0.isFrequent }
        if frequent.isEmpty {
            EmptyStateView(
                title: "頻出商品がありません",
                message: "商品画面で頻出を有効にすると、ここへ自動配置されます。",
                systemImage: "square.grid.3x3"
            )
            .padding(.top, 40)
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(categories) { category in
                    let categoryProducts = frequent.filter { $0.categoryID == category.id }
                    if !categoryProducts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.name, systemImage: "circle.fill")
                                .font(.headline)
                                .foregroundStyle(Color(hex: category.colorHex))
                            productGrid(categoryProducts, color: Color(hex: category.colorHex))
                        }
                    }
                }
                let uncategorized = frequent.filter { product in
                    !categories.contains { $0.id == product.categoryID }
                }
                if !uncategorized.isEmpty {
                    VStack(alignment: .leading) {
                        Text("未分類").font(.headline)
                        productGrid(uncategorized)
                    }
                }
            }
            .padding()
        }
    }

    private func productGrid(_ source: [Product], color: Color = .indigo) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            ForEach(source) { product in
                Button {
                    do {
                        try OrderService.add(product: product, to: table.id, in: modelContext)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(product.name)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(product.price.yenText)
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .padding(8)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.35)) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cartPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("注文").font(.title2.bold())
                Spacer()
                Text("\(items.reduce(0) { $0 + $1.quantity })点").foregroundStyle(.secondary)
            }
            .padding()
            Divider()

            if items.isEmpty {
                EmptyStateView(title: "注文は空です", message: "左の商品タイルをタップしてください。", systemImage: "cart")
            } else {
                List {
                    ForEach(items) { item in
                        OrderLineRow(item: item) { quantity in
                            do {
                                try OrderService.setQuantity(quantity, for: item, in: modelContext)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .listStyle(.plain)
                VStack(spacing: 16) {
                    TotalBreakdownView(summary: summary)
                    Button("会計へ") { showCheckout = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(.bar)
            }
        }
    }
}

private struct OrderLineRow: View {
    let item: OrderItem
    let onQuantityChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name.nonEmptyOrPlaceholder).font(.headline)
                    Text("\(item.unitPrice.yenText)・\(item.taxRate.label) \(item.taxType.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.lineAmount.yenText).font(.headline)
            }
            HStack {
                Stepper("", value: Binding(
                    get: { item.quantity },
                    set: onQuantityChange
                ), in: 0...999)
                .labelsHidden()
                TextField("数量", value: Binding(
                    get: { item.quantity },
                    set: onQuantityChange
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                Text("個")
                Spacer()
                Button(role: .destructive) { onQuantityChange(0) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
