import Foundation

enum MenuCSVDuplicatePolicy: String, CaseIterable, Identifiable {
    case update
    case skip

    var id: String { rawValue }
    var label: String { self == .update ? "既存商品を更新" : "既存商品をスキップ" }
}

struct MenuCSVRow: Identifiable, Sendable {
    var id: Int { lineNumber }

    let lineNumber: Int
    let name: String
    let price: Int
    let taxRate: TaxRate
    let taxType: TaxType
    let menuType: MenuType
    let categoryName: String
    let isFrequent: Bool
    let isEnabled: Bool
}

struct MenuCSVRowDraft: Identifiable, Sendable {
    var id: Int { lineNumber }

    let lineNumber: Int
    var name: String
    var price: String
    var taxRate: String
    var taxType: String
    var menuType: String
    var categoryName: String
    var isFrequent: String
    var isEnabled: String
}

struct MenuCSVValidationIssue: Identifiable, Sendable {
    let id = UUID()
    let lineNumber: Int
    let message: String
}

struct MenuCSVImportResult: Sendable {
    let fileName: String
    let drafts: [MenuCSVRowDraft]
    let rows: [MenuCSVRow]
    let issues: [MenuCSVValidationIssue]
}

enum MenuCSVImportError: LocalizedError {
    case fileTooLarge
    case unsupportedEncoding
    case emptyFile
    case malformedCSV(line: Int)
    case missingRequiredHeader(String)
    case tooManyRows

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "CSVは5MB以下にしてください。"
        case .unsupportedEncoding:
            "文字コードを判定できませんでした。UTF-8またはShift_JISで保存してください。"
        case .emptyFile:
            "CSVにヘッダーと商品行がありません。"
        case let .malformedCSV(line):
            "CSVの引用符が閉じられていません（\(line)行目付近）。"
        case let .missingRequiredHeader(header):
            "必須列「\(header)」がありません。"
        case .tooManyRows:
            "一度に読み込める商品は10,000行までです。"
        }
    }
}

enum MenuCSVImportService {
    static let maximumFileSize = 5 * 1_024 * 1_024
    static let maximumDataRows = 10_000

    static func load(url: URL) throws -> MenuCSVImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let fileSize, fileSize > maximumFileSize { throw MenuCSVImportError.fileTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data: data, fileName: url.lastPathComponent)
    }

    static func parse(data: Data, fileName: String = "menu.csv") throws -> MenuCSVImportResult {
        guard data.count <= maximumFileSize else { throw MenuCSVImportError.fileTooLarge }
        let text = try decode(data)
        return try parse(text: text, fileName: fileName)
    }

    static func parse(text: String, fileName: String = "menu.csv") throws -> MenuCSVImportResult {
        let records = try parseRecords(text)
        guard let header = records.first else { throw MenuCSVImportError.emptyFile }
        guard records.count > 1 else { throw MenuCSVImportError.emptyFile }
        guard records.count - 1 <= maximumDataRows else { throw MenuCSVImportError.tooManyRows }

        let columns = columnIndexes(from: header.fields)
        guard columns[.name] != nil else { throw MenuCSVImportError.missingRequiredHeader("name / 商品名") }
        guard columns[.price] != nil else { throw MenuCSVImportError.missingRequiredHeader("price / 価格") }

        var drafts: [MenuCSVRowDraft] = []

        for record in records.dropFirst() {
            guard record.fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }

            drafts.append(MenuCSVRowDraft(
                lineNumber: record.lineNumber,
                name: value(.name, in: record, columns: columns),
                price: value(.price, in: record, columns: columns),
                taxRate: value(.taxRate, in: record, columns: columns),
                taxType: value(.taxType, in: record, columns: columns),
                menuType: value(.menuType, in: record, columns: columns),
                categoryName: value(.category, in: record, columns: columns),
                isFrequent: value(.isFrequent, in: record, columns: columns),
                isEnabled: value(.isEnabled, in: record, columns: columns)
            ))
        }

        return validate(drafts: drafts, fileName: fileName)
    }

    static func validate(drafts: [MenuCSVRowDraft], fileName: String) -> MenuCSVImportResult {
        var rows: [MenuCSVRow] = []
        var issues: [MenuCSVValidationIssue] = []
        var seenNames = Set<String>()

        for draft in drafts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = parsePrice(draft.price)
            let taxRate = parseTaxRate(draft.taxRate)
            let taxType = parseTaxType(draft.taxType)
            let menuType = parseMenuType(draft.menuType)
            let frequent = parseBoolean(draft.isFrequent, defaultValue: false)
            let enabled = parseBoolean(draft.isEnabled, defaultValue: true)
            var rowIssues: [String] = []

            if name.isEmpty { rowIssues.append("商品名が空です") }
            if price == nil { rowIssues.append("価格は0以上の整数で入力してください") }
            if taxRate == nil { rowIssues.append("税率は8または10で入力してください") }
            if taxType == nil { rowIssues.append("税区分はincluded/内税またはexcluded/外税で入力してください") }
            if menuType == nil { rowIssues.append("メニュー区分はgrand/グランドまたはlimited/期間限定で入力してください") }
            if frequent == nil { rowIssues.append("頻出はtrue/false、1/0、はい/いいえで入力してください") }
            if enabled == nil { rowIssues.append("有効はtrue/false、1/0、はい/いいえで入力してください") }

            let duplicateKey = name.precomposedStringWithCompatibilityMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !duplicateKey.isEmpty, seenNames.contains(duplicateKey) {
                rowIssues.append("同じCSV内に同名商品があります")
            }

            if !rowIssues.isEmpty {
                issues.append(contentsOf: rowIssues.map {
                    MenuCSVValidationIssue(lineNumber: draft.lineNumber, message: $0)
                })
                continue
            }

            seenNames.insert(duplicateKey)
            rows.append(MenuCSVRow(
                lineNumber: draft.lineNumber,
                name: name,
                price: price ?? 0,
                taxRate: taxRate ?? .standard,
                taxType: taxType ?? .included,
                menuType: menuType ?? .grand,
                categoryName: draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines),
                isFrequent: frequent ?? false,
                isEnabled: enabled ?? true
            ))
        }

        return MenuCSVImportResult(fileName: fileName, drafts: drafts, rows: rows, issues: issues)
    }
}

private extension MenuCSVImportService {
    struct CSVRecord {
        let lineNumber: Int
        let fields: [String]
    }

    enum Column: CaseIterable, Hashable {
        case name
        case price
        case taxRate
        case taxType
        case menuType
        case category
        case isFrequent
        case isEnabled

        var aliases: Set<String> {
            switch self {
            case .name: ["name", "商品名", "メニュー名"]
            case .price: ["price", "価格", "単価"]
            case .taxRate: ["taxrate", "税率"]
            case .taxType: ["taxtype", "税区分", "内外税"]
            case .menuType: ["menutype", "メニュー区分", "商品区分"]
            case .category: ["category", "カテゴリ", "カテゴリー"]
            case .isFrequent: ["isfrequent", "frequent", "頻出", "頻出商品"]
            case .isEnabled: ["isenabled", "enabled", "有効", "有効状態"]
            }
        }
    }

    static func decode(_ data: Data) throws -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = Data(bytes.dropFirst(3))
        }
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        if let shiftJIS = String(data: bytes, encoding: .shiftJIS) { return shiftJIS }
        throw MenuCSVImportError.unsupportedEncoding
    }

    static func parseRecords(_ text: String) throws -> [CSVRecord] {
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var lineNumber = 1
        var recordLineNumber = 1
        var index = text.startIndex

        func finishRecord() {
            fields.append(field)
            records.append(CSVRecord(lineNumber: recordLineNumber, fields: fields))
            fields.removeAll(keepingCapacity: true)
            field = ""
        }

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)

            if inQuotes {
                if character == "\"" {
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        index = text.index(after: nextIndex)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                    if character == "\n" { lineNumber += 1 }
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    fields.append(field)
                    field = ""
                case "\r":
                    finishRecord()
                    if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                        index = text.index(after: nextIndex)
                    } else {
                        index = nextIndex
                    }
                    lineNumber += 1
                    recordLineNumber = lineNumber
                    continue
                case "\n":
                    finishRecord()
                    lineNumber += 1
                    recordLineNumber = lineNumber
                default:
                    field.append(character)
                }
            }

            index = nextIndex
        }

        guard !inQuotes else { throw MenuCSVImportError.malformedCSV(line: recordLineNumber) }
        if !field.isEmpty || !fields.isEmpty {
            finishRecord()
        }
        return records.filter {
            $0.fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    static func columnIndexes(from headers: [String]) -> [Column: Int] {
        var result: [Column: Int] = [:]
        for (index, header) in headers.enumerated() {
            let key = normalize(header)
            for column in Column.allCases where result[column] == nil && column.aliases.contains(key) {
                result[column] = index
            }
        }
        return result
    }

    static func value(_ column: Column, in record: CSVRecord, columns: [Column: Int]) -> String {
        guard let index = columns[column], record.fields.indices.contains(index) else { return "" }
        return record.fields[index]
    }

    static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !" _-\t\r\n".contains($0) }
    }

    static func parsePrice(_ value: String) -> Int? {
        let normalized = value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .filter { !$0.isWhitespace }
        guard let price = Int(normalized), price >= 0 else { return nil }
        return price
    }

    static func parseTaxRate(_ value: String) -> TaxRate? {
        let normalized = normalize(value).replacingOccurrences(of: "%", with: "")
        if normalized.isEmpty { return .standard }
        return Int(normalized).flatMap(TaxRate.init(rawValue:))
    }

    static func parseTaxType(_ value: String) -> TaxType? {
        switch normalize(value) {
        case "", "included", "内税": .included
        case "excluded", "外税": .excluded
        default: nil
        }
    }

    static func parseMenuType(_ value: String) -> MenuType? {
        switch normalize(value) {
        case "", "grand", "グランド", "通常": .grand
        case "limited", "期間限定", "限定": .limited
        default: nil
        }
    }

    static func parseBoolean(_ value: String, defaultValue: Bool) -> Bool? {
        switch normalize(value) {
        case "": defaultValue
        case "1", "true", "yes", "on", "はい", "有効", "表示": true
        case "0", "false", "no", "off", "いいえ", "無効", "非表示": false
        default: nil
        }
    }
}
