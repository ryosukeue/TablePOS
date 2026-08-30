import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [StoreSettings]
    @Query private var products: [Product]
    @Query private var orders: [Order]
    @Query private var sales: [Sale]

    let allowsExport: Bool
    let onRestored: (() -> Void)?

    @State private var exportDocument: BackupFileDocument?
    @State private var exportFilename = "TablePOS-backup.json"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingRestore: BackupEnvelope?
    @State private var pendingSummary: TablePOSBackupSummary?
    @State private var showRestoreConfirmation = false
    @State private var notice: String?
    @State private var errorMessage: String?

    init(allowsExport: Bool = true, onRestored: (() -> Void)? = nil) {
        self.allowsExport = allowsExport
        self.onRestored = onRestored
    }

    private var containsBusinessData: Bool {
        !settings.isEmpty || !products.isEmpty || !orders.isEmpty || !sales.isEmpty
    }

    var body: some View {
        Form {
            if allowsExport {
                Section {
                    Button {
                        prepareExport()
                    } label: {
                        Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("手動バックアップ")
                } footer: {
                    Text("保存画面でiCloud Driveを選ぶと、同じApple Accountから利用できます。バックアップには検索辞書やOCR画像を含めません。")
                }
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("バックアップから復元", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(containsBusinessData)
            } header: {
                Text("復元")
            } footer: {
                if containsBusinessData {
                    Text("この端末は設定済みのため、ここでは復元できません。誤上書きを防ぐため、復元はアプリの初回設定画面から行います。")
                } else {
                    Text("ファイルの形式、改ざん・破損、IDと明細の関係を確認してから復元します。")
                }
            }

            Section("バックアップ対象") {
                Label("店舗・税・テーブル設定", systemImage: "storefront")
                Label("カテゴリ・商品マスタ", systemImage: "fork.knife")
                Label("未会計の注文・注文明細", systemImage: "cart")
                Label("会計履歴・会計時の商品明細", systemImage: "receipt")
                Label("取消記録・訂正関係", systemImage: "arrow.uturn.backward.circle")
            }
        }
        .navigationTitle("バックアップと復元")
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                notice = "バックアップファイルを保存しました。"
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                inspectRestoreFile(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "このバックアップを復元しますか？",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("復元する") { restorePendingBackup() }
            Button("キャンセル", role: .cancel) {
                pendingRestore = nil
                pendingSummary = nil
            }
        } message: {
            Text(restoreConfirmationMessage)
        }
        .alert("完了", isPresented: noticeBinding) {
            Button("閉じる") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .alert("処理できませんでした", isPresented: errorBinding) {
            Button("閉じる") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var restoreConfirmationMessage: String {
        guard let summary = pendingSummary else { return "" }
        return "作成日時：\(summary.createdAt.formatted(date: .numeric, time: .shortened))\nテーブル\(summary.tables)卓、商品\(summary.products)件、未会計注文\(summary.openOrders)件、会計\(summary.sales)件"
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func prepareExport() {
        do {
            let (data, _) = try BackupService.makeBackupData(in: modelContext)
            exportDocument = BackupFileDocument(data: data)
            exportFilename = BackupService.defaultFilename()
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inspectRestoreFile(_ url: URL) {
        do {
            let (envelope, summary) = try BackupService.load(url: url)
            pendingRestore = envelope
            pendingSummary = summary
            showRestoreConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePendingBackup() {
        guard let pendingRestore else { return }
        do {
            try BackupService.restore(pendingRestore, in: modelContext)
            self.pendingRestore = nil
            pendingSummary = nil
            notice = "バックアップを復元しました。"
            onRestored?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
