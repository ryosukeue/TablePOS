import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

struct DigitalReceiptPayload: Codable, Sendable {
    let version: Int
    let saleID: String
    let completedAt: Int
    let status: String
    let paymentMethod: String
    let tableName: String
    let items: [DigitalReceiptItem]
    let subtotal: Int
    let includedTax8: Int
    let includedTax10: Int
    let externalTax8: Int
    let externalTax10: Int
    let roundingAdjustment: Int
    let total: Int
    let receivedAmount: Int?
    let changeAmount: Int?
    let originalSaleID: String?
    let replacementSaleID: String?

    enum CodingKeys: String, CodingKey {
        case version = "v", saleID = "id", completedAt = "at", status = "s"
        case paymentMethod = "pm", tableName = "tb", items = "i", subtotal = "sub"
        case includedTax8 = "it8", includedTax10 = "it10", externalTax8 = "et8"
        case externalTax10 = "et10", roundingAdjustment = "adj", total = "tot"
        case receivedAmount = "recv", changeAmount = "chg", originalSaleID = "orig"
        case replacementSaleID = "repl"
    }
}

struct DigitalReceiptItem: Codable, Sendable {
    let name: String
    let unitPrice: Int
    let quantity: Int
    let taxRate: Int
    let taxType: String

    enum CodingKeys: String, CodingKey {
        case name = "n", unitPrice = "p", quantity = "q", taxRate = "r", taxType = "t"
    }
}

enum DigitalReceiptError: LocalizedError {
    case tooLargeForQRCode
    case qrGenerationFailed

    var errorDescription: String? {
        switch self {
        case .tooLargeForQRCode:
            "この会計は明細が多いため、読み取りやすいQRコードへ全データを収められません。PDF共有を利用してください。"
        case .qrGenerationFailed:
            "QRコードを生成できませんでした。"
        }
    }
}

enum DigitalReceiptService {
    static let viewerBaseURL = "https://ryosukeue.github.io/TablePOS/receipt/"
    private static let practicalQRByteLimit = 1_800

    static func payload(sale: Sale, items: [SaleItem]) -> DigitalReceiptPayload {
        DigitalReceiptPayload(
            version: 1,
            saleID: sale.id.uuidString,
            completedAt: Int(sale.completedAt.timeIntervalSince1970),
            status: sale.status.rawValue,
            paymentMethod: sale.paymentMethod.rawValue,
            tableName: sale.sourceTableName,
            items: items.sorted { $0.sortOrder < $1.sortOrder }.map {
                DigitalReceiptItem(
                    name: $0.name,
                    unitPrice: $0.unitPrice,
                    quantity: $0.quantity,
                    taxRate: $0.taxRateValue,
                    taxType: $0.taxTypeRaw
                )
            },
            subtotal: sale.subtotal,
            includedTax8: sale.includedTax8,
            includedTax10: sale.includedTax10,
            externalTax8: sale.externalTax8,
            externalTax10: sale.externalTax10,
            roundingAdjustment: sale.roundingAdjustment,
            total: sale.total,
            receivedAmount: sale.receivedAmount,
            changeAmount: sale.changeAmount,
            originalSaleID: sale.originalSaleID?.uuidString,
            replacementSaleID: sale.replacementSaleID?.uuidString
        )
    }

    static func receiptJSON(sale: Sale, items: [SaleItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload(sale: sale, items: items))
    }

    static func receiptURL(sale: Sale, items: [SaleItem]) throws -> URL {
        let json = try receiptJSON(sale: sale, items: items)
        let encoded = json.base64URLEncodedString()
        guard let url = URL(string: "\(viewerBaseURL)#r1.\(encoded)") else {
            throw DigitalReceiptError.qrGenerationFailed
        }
        guard Data(url.absoluteString.utf8).count <= practicalQRByteLimit else {
            throw DigitalReceiptError.tooLargeForQRCode
        }
        return url
    }

    static func qrImage(sale: Sale, items: [SaleItem]) throws -> UIImage {
        let url = try receiptURL(sale: sale, items: items)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { throw DigitalReceiptError.qrGenerationFailed }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw DigitalReceiptError.qrGenerationFailed
        }
        return UIImage(cgImage: cgImage)
    }

    @MainActor
    static func makePDF(sale: Sale, items: [SaleItem]) throws -> URL {
        let sortedItems = items.sorted { $0.sortOrder < $1.sortOrder }
        let pageWidth: CGFloat = 595
        let pageHeight = max(CGFloat(720), CGFloat(510 + sortedItems.count * 34))
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 42
            let left: CGFloat = 48
            let right: CGFloat = pageWidth - 48

            func draw(_ text: String, font: UIFont, color: UIColor = .label, alignment: NSTextAlignment = .left, height: CGFloat = 28) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph
                ]).draw(in: CGRect(x: left, y: y, width: right - left, height: height))
                y += height
            }

            draw("TablePOS デジタルレシート", font: .boldSystemFont(ofSize: 23), alignment: .center, height: 40)
            draw(sale.completedAt.formatted(date: .long, time: .shortened), font: .systemFont(ofSize: 12), color: .secondaryLabel, alignment: .center)
            draw("会計ID  \(sale.id.uuidString)", font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: .secondaryLabel)
            draw("テーブル  \(sale.sourceTableName)　支払方法  \(sale.paymentMethod.label)", font: .systemFont(ofSize: 12), height: 34)
            if sale.status == .cancelled {
                draw("取消済み", font: .boldSystemFont(ofSize: 16), color: .systemRed, alignment: .center, height: 34)
            }

            y += 8
            for item in sortedItems {
                let name = item.name.nonEmptyOrPlaceholder
                draw("\(name)　\(item.unitPrice.yenText) × \(item.quantity)", font: .systemFont(ofSize: 13), height: 20)
                draw("\(item.taxRate.label) \(item.taxType.label)　　　　　　　　　\(item.lineAmount.yenText)", font: .systemFont(ofSize: 11), color: .secondaryLabel, alignment: .right, height: 22)
            }

            y += 10
            draw("小計　\(sale.subtotal.yenText)", font: .systemFont(ofSize: 13), alignment: .right)
            if sale.includedTax8 != 0 { draw("内税8%　\(sale.includedTax8.yenText)", font: .systemFont(ofSize: 11), alignment: .right, height: 20) }
            if sale.includedTax10 != 0 { draw("内税10%　\(sale.includedTax10.yenText)", font: .systemFont(ofSize: 11), alignment: .right, height: 20) }
            if sale.externalTax8 != 0 { draw("外税8%　\(sale.externalTax8.yenText)", font: .systemFont(ofSize: 11), alignment: .right, height: 20) }
            if sale.externalTax10 != 0 { draw("外税10%　\(sale.externalTax10.yenText)", font: .systemFont(ofSize: 11), alignment: .right, height: 20) }
            if sale.roundingAdjustment != 0 { draw("丸め調整　\(sale.roundingAdjustment.yenText)", font: .systemFont(ofSize: 11), alignment: .right, height: 20) }
            draw("合計　\(sale.total.yenText)", font: .boldSystemFont(ofSize: 20), alignment: .right, height: 38)
            if let received = sale.receivedAmount { draw("預かり　\(received.yenText)", font: .systemFont(ofSize: 12), alignment: .right, height: 22) }
            if let change = sale.changeAmount { draw("お釣り　\(change.yenText)", font: .systemFont(ofSize: 12), alignment: .right, height: 22) }
            draw("このPDFは会計時点の保存情報から生成されました。", font: .systemFont(ofSize: 9), color: .secondaryLabel, alignment: .center, height: 24)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TablePOS-receipt-\(sale.id.uuidString.prefix(8)).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
