import SwiftData
import SwiftUI

struct ProductListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var products: [Product]
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]

    @State private var searchText = ""
    @State private var editingProduct: Product?
    @State private var showNewProduct = false
    @State private var showOCR = false
    @State private var showCSV = false

    private var filteredProducts: [Product] {
        searchText.isEmpty ? products : ProductSearch.ranked(products, query: searchText)
    }

    var body: some View {
        List {
            ForEach(filteredProducts) { product in
                Button { editingProduct = product } label: {
                    HStack(spacing: 12) {
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
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("削除", role: .destructive) {
                        modelContext.delete(product)
                        try? modelContext.save()
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("読み込み", systemImage: "square.and.arrow.down") {
                    Button("CSVから読み込む", systemImage: "tablecells") { showCSV = true }
                    Button("OCRで読み込む", systemImage: "text.viewfinder") { showOCR = true }
                }
                Button("追加", systemImage: "plus") { showNewProduct = true }
            }
        }
        .sheet(isPresented: $showNewProduct) { ProductFormView(product: nil) }
        .sheet(item: $editingProduct) { ProductFormView(product: $0) }
        .sheet(isPresented: $showOCR) { OCRImportView() }
        .sheet(isPresented: $showCSV) { CSVImportView() }
        .task { await backfillMissingSearchIndexes() }
    }

    private func categoryName(for product: Product) -> String {
        categories.first { $0.id == product.categoryID }?.name ?? "未分類"
    }

    private func categoryColor(for product: Product) -> Color {
        Color(hex: categories.first { $0.id == product.categoryID }?.colorHex ?? "64748B")
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
