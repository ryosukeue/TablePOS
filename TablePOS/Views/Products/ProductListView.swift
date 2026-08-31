import SwiftData
import SwiftUI

struct ProductListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]

    @State private var searchText = ""
    @State private var categoryFilter: ProductCategoryFilter = .all
    @State private var selectedProductIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var editingProduct: Product?
    @State private var showNewProduct = false
    @State private var showOCR = false
    @State private var showCSV = false
    @State private var showBulkDeleteConfirmation = false
    @State private var showLimitedDeleteConfirmation = false
    @State private var errorMessage: String?

    private var filteredProducts: [Product] {
        let categoryFiltered = products.filter { product in
            switch categoryFilter {
            case .all:
                return true
            case .uncategorized:
                return product.categoryID == nil
            case .category(let id):
                return product.categoryID == id
            }
        }
        return searchText.isEmpty
            ? categoryFiltered
            : ProductSearch.ranked(categoryFiltered, query: searchText)
    }

    var body: some View {
        List {
            ForEach(filteredProducts) { product in
                HStack(spacing: 12) {
                    if isSelecting {
                        Image(systemName: selectedProductIDs.contains(product.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedProductIDs.contains(product.id) ? .blue : .secondary)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(categoryColor(for: product))
                        .frame(width: 8, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(product.name).font(.headline)
                            if product.menuType == .limited {
                                Text("期間限定").font(.caption2).padding(4)
                                    .background(.orange.opacity(0.16), in: Capsule())
                            }
                            if product.isFrequent {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                        Text("\(product.price.yenText)・\(product.taxRate.label) \(product.taxType.label)・\(categoryName(for: product))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !product.isEnabled {
                        Text("無効").foregroundStyle(.secondary)
                    }
                    if !isSelecting {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(product.id)
                    } else {
                        editingProduct = product
                    }
                }
                .swipeActions {
                    if !isSelecting {
                        Button("削除", role: .destructive) {
                            delete([product])
                        }
                    }
                }
            }
        }
        .overlay {
            if products.isEmpty {
                EmptyStateView(title: "商品がありません", message: "＋、CSV、またはOCRから商品を登録してください。", systemImage: "fork.knife")
            }
        }
        .searchable(text: $searchText, prompt: "商品名・読み・意味で検索")
        .navigationTitle("商品マスタ")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("カテゴリ", selection: $categoryFilter) {
                        Text("すべて（\(products.count)）").tag(ProductCategoryFilter.all)
                        ForEach(categories) { category in
                            Text("\(category.name)（\(productCount(in: category.id))）")
                                .tag(ProductCategoryFilter.category(category.id))
                        }
                        Text("未分類（\(productCount(in: nil))）")
                            .tag(ProductCategoryFilter.uncategorized)
                    }
                } label: {
                    Label(categoryFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button {
                        showBulkDeleteConfirmation = true
                    } label: {
                        Label("\(selectedProductIDs.count)件を削除", systemImage: "trash")
                    }
                    .tint(.red)
                    .disabled(selectedProductIDs.isEmpty)
                    Button("完了") { finishSelecting() }
                } else {
                    Menu("読み込み", systemImage: "square.and.arrow.down") {
                        Button("CSVから読み込む", systemImage: "tablecells") { showCSV = true }
                        Button("OCRで読み込む", systemImage: "text.viewfinder") { showOCR = true }
                    }
                    Button("追加", systemImage: "plus") { showNewProduct = true }
                    Button("選択") { isSelecting = true }
                    Menu("商品操作", systemImage: "ellipsis.circle") {
                        Button("期間限定商品を一括削除", systemImage: "calendar.badge.minus", role: .destructive) {
                            showLimitedDeleteConfirmation = true
                        }
                        .disabled(limitedProducts.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewProduct) { ProductFormView(product: nil) }
        .sheet(item: $editingProduct) { ProductFormView(product: $0) }
        .sheet(isPresented: $showOCR) { OCRImportView() }
        .sheet(isPresented: $showCSV) { CSVImportView() }
        .confirmationDialog(
            "選択した\(selectedProductIDs.count)件の商品を削除しますか？",
            isPresented: $showBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(selectedProductIDs.count)件を削除", role: .destructive) {
                delete(products.filter { selectedProductIDs.contains($0.id) })
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("進行中の注文と会計履歴に保存済みの商品情報は残ります。")
        }
        .confirmationDialog(
            "期間限定商品\(limitedProducts.count)件をすべて削除しますか？",
            isPresented: $showLimitedDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(limitedProducts.count)件を一括削除", role: .destructive) {
                delete(limitedProducts)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("商品マスタから期間限定メニューだけを削除します。進行中の注文と会計履歴のスナップショットは残ります。")
        }
        .alert("操作を完了できませんでした", isPresented: .constant(errorMessage != nil)) {
            Button("閉じる") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: categoryFilter) { _, _ in selectedProductIDs.removeAll() }
        .onChange(of: searchText) { _, _ in selectedProductIDs.removeAll() }
        .task { await backfillMissingSearchIndexes() }
    }

    private var categoryFilterLabel: String {
        switch categoryFilter {
        case .all: return "すべて"
        case .uncategorized: return "未分類"
        case .category(let id): return categories.first { $0.id == id }?.name ?? "カテゴリ"
        }
    }

    private var limitedProducts: [Product] {
        products.filter { $0.menuType == .limited }
    }

    private func productCount(in categoryID: UUID?) -> Int {
        products.count { $0.categoryID == categoryID }
    }

    private func categoryName(for product: Product) -> String {
        categories.first { $0.id == product.categoryID }?.name ?? "未分類"
    }

    private func categoryColor(for product: Product) -> Color {
        Color(hex: categories.first { $0.id == product.categoryID }?.colorHex ?? "64748B")
    }

    private func delete(_ productsToDelete: [Product]) {
        productsToDelete.forEach(modelContext.delete)
        do {
            try modelContext.save()
            selectedProductIDs.subtract(productsToDelete.map(\.id))
            if selectedProductIDs.isEmpty {
                isSelecting = false
            }
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedProductIDs.contains(id) {
            selectedProductIDs.remove(id)
        } else {
            selectedProductIDs.insert(id)
        }
    }

    private func finishSelecting() {
        selectedProductIDs.removeAll()
        isSelecting = false
    }

    @MainActor
    private func backfillMissingSearchIndexes() async {
        let missing = products
            .filter { $0.searchNormalizedKey == nil || $0.searchReadingKey == nil }
            .map { ($0.id, $0.name) }
        guard !missing.isEmpty else { return }

        let indexes = await Task.detached(priority: .utility) {
            missing.map { ($0.0, ProductSearch.makeIndex(for: $0.1)) }
        }.value
        for (id, index) in indexes {
            guard let product = products.first(where: { $0.id == id }) else { continue }
            product.searchNormalizedKey = index.normalized
            product.searchReadingKey = index.reading
            product.searchTokenKeysRaw = index.tokens.joined(separator: "\u{1F}")
        }
        try? modelContext.save()
    }
}

private enum ProductCategoryFilter: Hashable {
    case all
    case uncategorized
    case category(UUID)
}

struct ProductFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]

    private let product: Product?
    @State private var name: String
    @State private var price: Int
    @State private var taxRate: TaxRate
    @State private var taxType: TaxType
    @State private var menuType: MenuType
    @State private var categoryID: UUID?
    @State private var isFrequent: Bool
    @State private var isEnabled: Bool
    @State private var errorMessage: String?

    init(product: Product?) {
        self.product = product
        _name = State(initialValue: product?.name ?? "")
        _price = State(initialValue: product?.price ?? 0)
        _taxRate = State(initialValue: product?.taxRate ?? .standard)
        _taxType = State(initialValue: product?.taxType ?? .included)
        _menuType = State(initialValue: product?.menuType ?? .grand)
        _categoryID = State(initialValue: product?.categoryID)
        _isFrequent = State(initialValue: product?.isFrequent ?? false)
        _isEnabled = State(initialValue: product?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名", text: $name)
                    TextField("価格", value: $price, format: .number)
                        .keyboardType(.numberPad)
                    Picker("メニュー", selection: $menuType) {
                        ForEach(MenuType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("カテゴリ", selection: $categoryID) {
                        Text("未分類").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("税") {
                    Picker("税率", selection: $taxRate) {
                        ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("区分", selection: $taxType) {
                        ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("表示") {
                    Toggle("頻出タイルに表示", isOn: $isFrequent)
                    Toggle("商品を有効にする", isOn: $isEnabled)
                }
            }
            .navigationTitle(product == nil ? "商品を追加" : "商品を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || price < 0)
                }
            }
            .alert("保存できませんでした", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let savedProduct: Product
        if let product {
            product.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            product.price = price
            product.taxRate = taxRate
            product.taxType = taxType
            product.menuType = menuType
            product.categoryID = categoryID
            product.isFrequent = isFrequent
            product.isEnabled = isEnabled
            product.updatedAt = .now
            savedProduct = product
        } else {
            let product = Product(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                price: price,
                taxRate: taxRate,
                taxType: taxType,
                menuType: menuType,
                categoryID: categoryID,
                isFrequent: isFrequent,
                isEnabled: isEnabled
            )
            modelContext.insert(product)
            savedProduct = product
        }
        ProductSearch.updateIndex(for: savedProduct)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
