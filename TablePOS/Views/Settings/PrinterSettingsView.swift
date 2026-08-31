import SwiftUI

struct PrinterSettingsView: View {
    @StateObject private var printerService = StarPrinterService.shared
    @State private var alertMessage: String?

    var body: some View {
        List {
            Section("使用中のプリンタ") {
                LabeledContent("プリンタ", value: printerService.selectedPrinterLabel ?? "未設定")
                Button {
                    Task { await openDrawer() }
                } label: {
                    Label("キャッシュドロアを開く", systemImage: "tray.2")
                }
                .disabled(printerService.selectedPrinterLabel == nil || printerService.isOperating)
            }

            Section {
                Button {
                    printerService.discover()
                } label: {
                    if printerService.isDiscovering {
                        Label("プリンタを検索中…", systemImage: "antenna.radiowaves.left.and.right")
                    } else {
                        Label("mPOPプリンタを検索", systemImage: "magnifyingglass")
                    }
                }
                .disabled(printerService.isDiscovering)

                ForEach(printerService.discoveredPrinters) { candidate in
                    Button {
                        printerService.select(candidate)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.modelName).font(.headline)
                            Text("\(candidate.interfaceLabel)・\(candidate.settings.identifier)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("プリンタ探索")
            } footer: {
                Text("LAN、Bluetooth、Bluetooth LE、USBをまとめて探索します。POP10／POP10CI／POP10CBIなどの型番名では絞り込まず、見つかったStarプリンタを選択します。")
            }
        }
        .navigationTitle("mPOPプリンタ")
        .onChange(of: printerService.operationMessage) { _, message in
            if let message { alertMessage = message }
        }
        .onDisappear { printerService.stopDiscovery() }
        .alert("プリンタ", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("閉じる") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func openDrawer() async {
        do {
            try await printerService.openDrawer()
            alertMessage = "キャッシュドロアを開きました。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
