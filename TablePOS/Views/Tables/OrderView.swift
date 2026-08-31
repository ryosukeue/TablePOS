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
    @State private var categoryFilter: OrderCategoryFilter = .all
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
            .padding(.horizontal)
            .padding(.top)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton(title: "頻出", systemImage: "star.fill", filter: .frequent, color: .yellow)
                    categoryButton(title: "すべて", filter: .all, color: .indigo)
                    ForEach(categories) { category in
                        categoryButton(
                            title: category.name,
                            filter: .category(category.id),
                            color: Color(hex: category.colorHex)
                        )
                    }
                    categoryButton(title: "未分類", filter: .uncategorized, color: .gray)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            ScrollView {
                if !searchText.isEmpty {
                    productGrid(ProductSearch.ranked(enabledProducts, query: searchText), color: .indigo)
                        .padding()
                } else if categoryFilteredProducts.isEmpty {
                    EmptyStateView(
                        title: "商品がありません",
                        message: categoryFilter == .frequent
                            ? "商品マスタで頻出を有効にすると、ここへ表示されます。"
                            : "このカテゴリに有効な商品はありません。",
                        systemImage: categoryFilter == .frequent ? "star" : "line.3.horizontal.decrease.circle"
                    )
                    .padding(.top, 40)
                } else if categoryFilter == .all || categoryFilter == .frequent {
                    groupedProductSections(categoryFilteredProducts)
                        .padding()
                } else {
                    productGrid(categoryFilteredProducts, color: selectedCategoryColor)
                        .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var enabledProducts: [Product] { products.filter(\.isEnabled) }

    private var categoryFilteredProducts: [Product] {
        products.filter { product in
            guard product.isEnabled else { return false }
            switch categoryFilter {
            case .frequent:
                return product.isFrequent
            case .all:
                return true
            case .category(let id):
                return product.categoryID == id
            case .uncategorized:
                return product.categoryID == nil || !categories.contains { $0.id == product.categoryID }
            }
        }
    }

    private var selectedCategoryColor: Color {
        switch categoryFilter {
        case .frequent: return .yellow
        case .all: return .indigo
        case .uncategorized: return .gray
        case .category(let id):
            return Color(hex: categories.first { $0.id == id }?.colorHex ?? "64748B")
        }
    }

    private func categoryButton(
        title: String,
        systemImage: String? = nil,
        filter: OrderCategoryFilter,
        color: Color
    ) -> some View {
        Button {
            categoryFilter = filter
        } label: {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
                .font(.subheadline.weight(categoryFilter == filter ? .bold : .medium))
                .foregroundStyle(categoryFilter == filter ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(categoryFilter == filter ? color : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay { Capsule().stroke(color.opacity(0.45)) }
        }
        .buttonStyle(.plain)
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

    private func groupedProductSections(_ source: [Product]) -> some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(categories) { category in
                let categoryProducts = source.filter { $0.categoryID == category.id }
                if !categoryProducts.isEmpty {
                    productSection(
                        title: category.name,
                        products: categoryProducts,
                        color: Color(hex: category.colorHex)
                    )
                }
            }

            let uncategorizedProducts = source.filter { product in
                product.categoryID == nil || !categories.contains { $0.id == product.categoryID }
            }
            if !uncategorizedProducts.isEmpty {
                productSection(title: "未分類", products: uncategorizedProducts, color: .gray)
            }
        }
    }

    private func productSection(title: String, products: [Product], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 6, height: 24)
                Text(title)
                    .font(.title3.bold())
                Text("\(products.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            productGrid(products, color: color)
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

            Button {
                showCustomItem = true
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 31, weight: .semibold))
                    Text("カスタム商品を追加")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
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

private enum OrderCategoryFilter: Hashable {
    case frequent
    case all
    case category(UUID)
    case uncategorized
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
