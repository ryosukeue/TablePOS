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
    @State private var editingDraft: MenuCSVRowDraft?
    @State private var selectedLineNumbers = Set<Int>()

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

                if let result, !result.drafts.isEmpty {
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

                    Section("選択した商品の一括変更") {
                        HStack {
                            Text("\(selectedLineNumbers.count)件を選択中")
                                .foregroundStyle(selectedLineNumbers.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button(selectedLineNumbers.count == result.drafts.count ? "選択解除" : "すべて選択") {
                                if selectedLineNumbers.count == result.drafts.count {
                                    selectedLineNumbers.removeAll()
                                } else {
                                    selectedLineNumbers = Set(result.drafts.map(\.lineNumber))
                                }
                            }
                        }

                        HStack {
                            Menu {
                                ForEach(MenuType.allCases) { menuType in
                                    Button(menuType.label) {
                                        updateSelectedDrafts(menuType: menuType)
                                    }
                                }
                            } label: {
                                Label("メニュー区分", systemImage: "fork.knife")
                            }
                            .disabled(selectedLineNumbers.isEmpty)

                            Spacer()

                            Menu {
                                ForEach(TaxType.allCases) { taxType in
                                    Button(taxType.label) {
                                        updateSelectedDrafts(taxType: taxType)
                                    }
                                }
                            } label: {
                                Label("内税・外税", systemImage: "percent")
                            }
                            .disabled(selectedLineNumbers.isEmpty)
                        }

                        Text("下の丸で商品を複数選び、グランド／期間限定または内税／外税をまとめて変更できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("取込前の確認・修正") {
                        ForEach(result.drafts) { draft in
                            HStack(spacing: 12) {
                                Button {
                                    toggleSelection(of: draft)
                                } label: {
                                    Image(systemName: selectedLineNumbers.contains(draft.lineNumber)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(selectedLineNumbers.contains(draft.lineNumber) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(selectedLineNumbers.contains(draft.lineNumber) ? "選択を解除" : "選択")

                                Button {
                                    editingDraft = draft
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: issueMessages(for: draft.lineNumber).isEmpty
                                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(issueMessages(for: draft.lineNumber).isEmpty ? .green : .red)
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrPlaceholder)
                                                    .font(.headline)
                                                Spacer()
                                                Text(draft.price.isEmpty ? "価格なし" : draft.price)
                                            }
                                            Text("\(draft.lineNumber)行目・\(draft.categoryName.isEmpty ? "未分類" : draft.categoryName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let issue = issueMessages(for: draft.lineNumber).first {
                                                Text(issue)
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("商品をタップすると、CSVを選び直さずに内容を修正できます。修正後は自動で再チェックします。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result, result.drafts.isEmpty {
                    Section("取込プレビュー") {
                        Text("商品行がありません。")
                            .foregroundStyle(.secondary)
                    }
                }

                if let result, !result.issues.isEmpty {
                    Section("修正が必要な行") {
                        ForEach(result.issues) { issue in
                            Label("\(issue.lineNumber)行目：\(issue.message)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text("赤い行をタップして修正してください。エラーが残る行だけ保存対象から除外されます。")
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
            .sheet(item: $editingDraft) { draft in
                CSVRowEditorView(draft: draft) { updated in
                    updateDraft(updated)
                }
            }
        }
    }

    private func issueMessages(for lineNumber: Int) -> [String] {
        result?.issues.filter { $0.lineNumber == lineNumber }.map(\.message) ?? []
    }

    private func updateDraft(_ updated: MenuCSVRowDraft) {
        guard let result,
              let index = result.drafts.firstIndex(where: { $0.lineNumber == updated.lineNumber }) else { return }
        var drafts = result.drafts
        drafts[index] = updated
        self.result = MenuCSVImportService.validate(drafts: drafts, fileName: result.fileName)
    }

    private func toggleSelection(of draft: MenuCSVRowDraft) {
        if selectedLineNumbers.contains(draft.lineNumber) {
            selectedLineNumbers.remove(draft.lineNumber)
        } else {
            selectedLineNumbers.insert(draft.lineNumber)
        }
    }

    private func updateSelectedDrafts(menuType: MenuType? = nil, taxType: TaxType? = nil) {
        guard let result else { return }
        let drafts = result.drafts.map { draft in
            guard selectedLineNumbers.contains(draft.lineNumber) else { return draft }
            var updated = draft
            if let menuType { updated.menuType = menuType.rawValue }
            if let taxType { updated.taxType = taxType.rawValue }
            return updated
        }
        self.result = MenuCSVImportService.validate(drafts: drafts, fileName: result.fileName)
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
                selectedLineNumbers.removeAll()
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

private struct CSVRowEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MenuCSVRowDraft
    let onSave: (MenuCSVRowDraft) -> Void

    init(draft: MenuCSVRowDraft, onSave: @escaping (MenuCSVRowDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名", text: $draft.name)
                    TextField("価格", text: $draft.price)
                        .keyboardType(.numberPad)
                    TextField("カテゴリ（空欄は未分類）", text: $draft.categoryName)
                }
                Section("税・メニュー") {
                    Picker("税率", selection: taxRateSelection) {
                        ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("税区分", selection: taxTypeSelection) {
                        ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("メニュー区分", selection: menuTypeSelection) {
                        ForEach(MenuType.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("表示") {
                    Toggle("頻出タイルに表示", isOn: frequentSelection)
                    Toggle("商品を有効にする", isOn: enabledSelection)
                }
            }
            .navigationTitle("\(draft.lineNumber)行目を修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("反映") {
                        normalizeSelections()
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private var taxRateSelection: Binding<TaxRate> {
        Binding(
            get: { draft.taxRate.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("8") ? .reduced : .standard },
            set: { draft.taxRate = String($0.rawValue) }
        )
    }

    private var taxTypeSelection: Binding<TaxType> {
        Binding(
            get: {
                let value = draft.taxType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return value == TaxType.excluded.rawValue || value == "外税" ? .excluded : .included
            },
            set: { draft.taxType = $0.rawValue }
        )
    }

    private var menuTypeSelection: Binding<MenuType> {
        Binding(
            get: {
                let value = draft.menuType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return value == MenuType.limited.rawValue || value == "期間限定" ? .limited : .grand
            },
            set: { draft.menuType = $0.rawValue }
        )
    }

    private var frequentSelection: Binding<Bool> {
        Binding(
            get: { booleanValue(draft.isFrequent, defaultValue: false) },
            set: { draft.isFrequent = $0 ? "true" : "false" }
        )
    }

    private var enabledSelection: Binding<Bool> {
        Binding(
            get: { booleanValue(draft.isEnabled, defaultValue: true) },
            set: { draft.isEnabled = $0 ? "true" : "false" }
        )
    }

    private func booleanValue(_ source: String, defaultValue: Bool) -> Bool {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "1", "yes", "はい", "有効", "on"].contains(value) { return true }
        if ["false", "0", "no", "いいえ", "無効", "off"].contains(value) { return false }
        return defaultValue
    }

    private func normalizeSelections() {
        draft.taxRate = String(taxRateSelection.wrappedValue.rawValue)
        draft.taxType = taxTypeSelection.wrappedValue.rawValue
        draft.menuType = menuTypeSelection.wrappedValue.rawValue
        draft.isFrequent = frequentSelection.wrappedValue ? "true" : "false"
        draft.isEnabled = enabledSelection.wrappedValue ? "true" : "false"
    }
}
