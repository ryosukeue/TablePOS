import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [StoreSettings]
    @Query(sort: \DiningTable.number) private var tables: [DiningTable]
    @Query private var products: [Product]

    @State private var requestedTableCount = 12
    @State private var notice: String?

    private var storeSettings: StoreSettings? { settings.first }

    var body: some View {
        Form {
            Section {
                Stepper("テーブル数: \(requestedTableCount)卓", value: $requestedTableCount, in: 1...100)
                Button("テーブル数を反映") { updateTableCount() }
                    .disabled(requestedTableCount == tables.count)
            } header: {
                Text("テーブル")
            } footer: {
                Text("使用中のテーブルが削除対象に含まれる場合は減らせません。")
            }

            Section {
                Picker("税の端数処理", selection: Binding(
                    get: { storeSettings?.taxRoundingRule ?? .floor },
                    set: { newValue in
                        storeSettings?.taxRoundingRule = newValue
                        try? modelContext.save()
                    }
                )) {
                    ForEach(TaxRoundingRule.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("税計算")
            } footer: {
                Text("外税は税率ごとの対象商品合計に対して計算します。会計の10円丸めとは別の設定です。")
            }

            Section("マスタ") {
                NavigationLink("カテゴリ管理") { CategoryManagementView() }
            }

            Section("データ管理") {
                NavigationLink {
                    BackupRestoreView()
                } label: {
                    Label("バックアップと復元", systemImage: "icloud.and.arrow.up")
                }
            }

            Section {
                Button("サンプル商品を追加") { addSamples() }
                    .disabled(!products.isEmpty)
            } header: {
                Text("評価用データ")
            } footer: {
                Text("商品が0件のときだけ、頻出商品4件を追加できます。")
            }

            Section("このMVPについて") {
                LabeledContent("通常データ", value: "この端末内")
                LabeledContent("バックアップ", value: "手動でファイル保存")
                LabeledContent("対象", value: "1店舗・1台")
                LabeledContent("対応", value: "iOS / iPadOS 17以降")
                Text("自動同期、プリンタ、キャッシュドロア、自動バックアップ、売切れ、割り勘はMVP対象外です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .onAppear { requestedTableCount = storeSettings?.tableCount ?? tables.count }
        .alert("お知らせ", isPresented: .constant(notice != nil)) {
            Button("閉じる") { notice = nil }
        } message: { Text(notice ?? "") }
    }

    private func updateTableCount() {
        guard let storeSettings else { return }
        do {
            try AppDataService.resizeTables(to: requestedTableCount, settings: storeSettings, in: modelContext)
            notice = "テーブル数を\(requestedTableCount)卓に更新しました。"
        } catch {
            requestedTableCount = tables.count
            notice = error.localizedDescription
        }
    }

    private func addSamples() {
        do {
            try AppDataService.insertSampleProducts(in: modelContext)
            notice = "サンプル商品を追加しました。"
        } catch {
            notice = error.localizedDescription
        }
    }
}

private struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]
    @State private var editingCategory: ProductCategory?
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(categories) { category in
                Button { editingCategory = category } label: {
                    HStack {
                        Circle().fill(Color(hex: category.colorHex)).frame(width: 18, height: 18)
                        Text(category.name)
                        Spacer()
                        Text("表示順 \(category.sortOrder + 1)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("削除", role: .destructive) {
                        modelContext.delete(category)
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("カテゴリ管理")
        .toolbar {
            Button("追加", systemImage: "plus") { showAdd = true }
        }
        .sheet(isPresented: $showAdd) {
            CategoryFormView(category: nil, suggestedSortOrder: categories.count)
        }
        .sheet(item: $editingCategory) {
            CategoryFormView(category: $0, suggestedSortOrder: categories.count)
        }
    }
}

private struct CategoryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let category: ProductCategory?
    let suggestedSortOrder: Int

    @State private var name: String
    @State private var colorHex: String
    @State private var sortOrder: Int

    private let colors: [(String, String)] = [
        ("青", "2563EB"), ("橙", "EA580C"), ("緑", "16A34A"),
        ("紫", "7C3AED"), ("赤", "DC2626"), ("グレー", "64748B")
    ]

    init(category: ProductCategory?, suggestedSortOrder: Int) {
        self.category = category
        self.suggestedSortOrder = suggestedSortOrder
        _name = State(initialValue: category?.name ?? "")
        _colorHex = State(initialValue: category?.colorHex ?? "2563EB")
        _sortOrder = State(initialValue: category?.sortOrder ?? suggestedSortOrder)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("カテゴリ名", text: $name)
                Picker("色", selection: $colorHex) {
                    ForEach(colors, id: \.1) { color in
                        Label(color.0, systemImage: "circle.fill")
                            .foregroundStyle(Color(hex: color.1))
                            .tag(color.1)
                    }
                }
                Stepper("表示順: \(sortOrder + 1)", value: $sortOrder, in: 0...99)
            }
            .navigationTitle(category == nil ? "カテゴリを追加" : "カテゴリを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let category {
            category.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            category.colorHex = colorHex
            category.sortOrder = sortOrder
        } else {
            modelContext.insert(ProductCategory(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: colorHex,
                sortOrder: sortOrder
            ))
        }
        try? modelContext.save()
        dismiss()
    }
}
