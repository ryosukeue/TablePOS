import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct OCRImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProductCategory.sortOrder) private var categories: [ProductCategory]

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isRecognizing = false
    @State private var candidates: [OCRCandidate] = []
    @State private var taxRate = TaxRate.standard
    @State private var taxType = TaxType.included
    @State private var menuType = MenuType.grand
    @State private var categoryID: UUID?
    @State private var isFrequent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("画像") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("写真ライブラリから選ぶ", systemImage: "photo.on.rectangle")
                    }
                    Button { showCamera = true } label: {
                        Label("カメラで撮影", systemImage: "camera")
                    }
                    if isRecognizing {
                        HStack { ProgressView(); Text("文字を認識しています…") }
                    }
                }

                if !candidates.isEmpty {
                    Section("抽出候補") {
                        ForEach($candidates) { $candidate in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("保存対象", isOn: $candidate.isSelected)
                                TextField("商品名", text: $candidate.name)
                                TextField("価格", value: $candidate.price, format: .number)
                                    .keyboardType(.numberPad)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section("候補へ共通で設定") {
                        Picker("税率", selection: $taxRate) {
                            ForEach(TaxRate.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("区分", selection: $taxType) {
                            ForEach(TaxType.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("メニュー", selection: $menuType) {
                            ForEach(MenuType.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("カテゴリ", selection: $categoryID) {
                            Text("未分類").tag(UUID?.none)
                            ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Toggle("頻出タイルに表示", isOn: $isFrequent)
                    }
                } else if !isRecognizing {
                    Section {
                        Text("「商品名 600円」のように、商品名と価格が同じ行にあるメニューを読み取ります。OCR後に税率と内外税を確認して保存します。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("OCR商品登録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("候補を保存") { saveCandidates() }
                        .disabled(validCandidates.isEmpty)
                }
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task { await recognize(item: newValue) }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    recognize(image: image)
                }
                .ignoresSafeArea()
            }
            .alert("OCR処理に失敗しました", isPresented: .constant(errorMessage != nil)) {
                Button("閉じる") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var validCandidates: [OCRCandidate] {
        candidates.filter {
            $0.isSelected && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.price >= 0
        }
    }

    @MainActor
    private func recognize(item: PhotosPickerItem) async {
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            recognize(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognize(image: UIImage) {
        guard let cgImage = image.cgImage else {
            errorMessage = "画像を読み込めませんでした。"
            return
        }
        isRecognizing = true
        Task {
            do {
                let result = try await Task.detached {
                    try OCRService.recognize(cgImage: cgImage)
                }.value
                await MainActor.run {
                    candidates = result
                    isRecognizing = false
                    if result.isEmpty {
                        errorMessage = "商品名と価格の組み合わせを抽出できませんでした。別の画像を試してください。"
                    }
                }
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveCandidates() {
        validCandidates.forEach { candidate in
            modelContext.insert(Product(
                name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                price: candidate.price,
                taxRate: taxRate,
                taxType: taxType,
                menuType: menuType,
                categoryID: categoryID,
                isFrequent: isFrequent
            ))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
