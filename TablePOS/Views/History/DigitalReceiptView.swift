import SwiftUI
import UIKit

struct DigitalReceiptView: View {
    @Environment(\.dismiss) private var dismiss

    let sale: Sale
    let items: [SaleItem]

    @State private var qrImage: UIImage?
    @State private var qrError: String?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("デジタルレシート")
                            .font(.title2.bold())
                        Text(sale.completedAt.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text(sale.total.yenText)
                            .font(.largeTitle.bold())
                    }

                    if sale.status == .cancelled {
                        Label("この会計は取消済みです", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.headline)
                    }

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 360)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("デジタルレシートのQRコード")
                        Text("お客様のスマートフォンで読み取ると、明細を表示してPDFまたはJSONとして保存できます。レシート内容はQRコード内に入っています。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if let qrError {
                        ContentUnavailableView(
                            "QRコードを表示できません",
                            systemImage: "qrcode",
                            description: Text(qrError)
                        )
                    } else {
                        ProgressView("QRコードを生成中…")
                    }

                    Button {
                        sharePDF()
                    } label: {
                        Label("PDFを共有・保存", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: 620)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("レシート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { generateQRCode() }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ActivityShareSheet(items: [shareURL])
                }
            }
            .alert("処理できませんでした", isPresented: errorBinding) {
                Button("閉じる") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func generateQRCode() {
        do {
            qrImage = try DigitalReceiptService.qrImage(sale: sale, items: items)
        } catch {
            qrError = error.localizedDescription
        }
    }

    private func sharePDF() {
        do {
            shareURL = try DigitalReceiptService.makePDF(sale: sale, items: items)
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
