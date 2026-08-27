import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showFileImporter = false
    @State private var duplicatePolicy = MenuCSVDuplicatePolicy.update
    @State private var result: MenuCSVImportResult?
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("CSVファイル") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("ファイルを選択", systemImage: "doc.badge.plus")
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("CSVを確認しています…")
                        }
                    }

                    if let result {
                        LabeledContent("ファイル", value: result.fileName)
                        LabeledContent("取込可能", value: "\(result.rows.count)件")
                        LabeledContent("エラー", value: "\(result.issues.count)件")
                    }
                }

                if let result, !result.rows.isEmpty {
                    Section("同名商品") {
                        Picker("既存の商品名と一致した場合", selection: $duplicatePolicy) {
                            ForEach(MenuCSVDuplicatePolicy.allCases) { policy in
                                Text(policy.label).tag(policy)
                            }
                        }
                        Text("商品名は前後の空白と全角・半角の互換文字をそろえて比較します。CSVにない既存商品は削除しません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("取込プレビュー") {
                        ForEach(Array(result.rows.prefix(100))) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).font(.headline)
                                    Spacer()
                                    Text(row.price.yenText)
                                }
                                Text("\(row.lineNumber)行目・\(row.taxRate.label) \(row.taxType.label)・\(row.menuType.label)・\(row.categoryName.isEmpty ? "未分類" : row.categoryName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if result.rows.count > 100 {
                            Text("ほか\(result.rows.count - 100)件")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let result, !result.issues.isEmpty {
                    Section("読み込めない行") {
                        ForEach(Array(result.issues.prefix(100))) { issue in
                            Label("\(issue.lineNumber)行目：\(issue.message)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        if result.issues.count > 100 {
                            Text("ほか\(result.issues.count - 100)件のエラー")
                                .foregroundStyle(.secondary)
                        }
                        Text("エラー行は保存対象から除外されます。CSVを修正して選び直すこともできます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("最小フォーマット") {
                    Text("name,price")
                        .font(.system(.body, design: .monospaced))
                    Text("生ビール,600")
                        .font(.system(.body, design: .monospaced))
                    Text("省略時は10%・内税・グランド・未分類・頻出OFF・有効になります。UTF-8とShift_JISに対応します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("メニューCSV取込")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("取り込む") { importProducts() }
                        .disabled(result?.rows.isEmpty != false || isLoading || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("商品と検索インデックスを保存しています…")
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { selection in
                switch selection {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    load(url: url)
                case let .failure(error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("CSVを読み込めませんでした", isPresented: errorBinding) {
                Button("閉じる") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("取込完了", isPresented: successBinding) {
                Button("閉じる") {
                    successMessage = nil
                    dismiss()
                }
            } message: {
                Text(successMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var successBinding: Binding<Bool> {
        Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )
    }

    private func load(url: URL) {
        isLoading = true
        errorMessage = nil
        result = nil
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try MenuCSVImportService.load(url: url)
                }.value
                result = parsed
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func importProducts() {
        guard let result, !result.rows.isEmpty else { return }
        isImporting = true
        errorMessage = nil

        Task {
            let rows = result.rows
            let searchIndexes = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: rows.map {
                    ($0.lineNumber, ProductSearch.makeIndex(for: $0.name))
                })
            }.value

            do {
                let summary = try MenuCSVProductService.apply(
                    rows: rows,
                    duplicatePolicy: duplicatePolicy,
                    searchIndexes: searchIndexes,
                    in: modelContext
                )
                var parts = ["新規\(summary.created)件", "更新\(summary.updated)件"]
                if summary.skipped > 0 { parts.append("スキップ\(summary.skipped)件") }
                if summary.categoriesCreated > 0 { parts.append("カテゴリ追加\(summary.categoriesCreated)件") }
                successMessage = parts.joined(separator: "、") + "を保存しました。"
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
