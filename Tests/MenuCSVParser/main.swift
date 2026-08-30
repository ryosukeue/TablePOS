import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

let canonical = """
name,price,tax_rate,tax_type,menu_type,category,is_frequent,is_enabled
生ビール,600,10,included,grand,ドリンク,true,true
"刺身盛り合わせ, 小","1,200",10,included,limited,フード,false,true
"""
let canonicalResult = try MenuCSVImportService.parse(text: canonical)
check(canonicalResult.rows.count == 2, "canonical row count")
check(canonicalResult.issues.isEmpty, "canonical issues")
check(canonicalResult.rows[1].name == "刺身盛り合わせ, 小", "quoted comma")
check(canonicalResult.rows[1].price == 1_200, "quoted thousands price")
check(canonicalResult.rows[1].menuType == .limited, "limited menu")

let sampleURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Examples/menu_import_sample.csv")
let sampleResult = try MenuCSVImportService.load(url: sampleURL)
check(sampleResult.rows.count == 4, "documented sample row count")
check(sampleResult.issues.isEmpty, "documented sample issues")

let japanese = """
商品名,価格,税率,税区分,メニュー区分,カテゴリ,頻出,有効
塩むすび,300,8%,内税,グランド,フード,はい,はい
"""
let shiftJISData = japanese.data(using: .shiftJIS)!
let japaneseResult = try MenuCSVImportService.parse(data: shiftJISData, fileName: "japanese.csv")
check(japaneseResult.rows.count == 1, "Shift_JIS row count")
check(japaneseResult.rows[0].taxRate == .reduced, "Japanese tax rate")
check(japaneseResult.rows[0].isFrequent, "Japanese boolean")

let multiline = """
name,price
"二行の
商品名",500
枝豆,400
"""
let multilineResult = try MenuCSVImportService.parse(text: multiline)
check(multilineResult.rows.count == 2, "multiline row count")
check(multilineResult.rows[0].name == "二行の\n商品名", "quoted newline")
check(multilineResult.rows[1].lineNumber == 4, "source line tracking")

let invalid = """
name,price,tax_rate,tax_type
,abc,7,unknown
枝豆,400,10,included
枝豆,450,10,included
"""
let invalidResult = try MenuCSVImportService.parse(text: invalid)
check(invalidResult.rows.count == 1, "valid rows survive invalid rows")
check(invalidResult.drafts.count == 3, "invalid rows remain editable")
check(invalidResult.issues.contains { $0.lineNumber == 2 }, "invalid line number")
check(invalidResult.issues.contains { $0.lineNumber == 4 && $0.message.contains("同名") }, "duplicate row")

var correctedDrafts = invalidResult.drafts
correctedDrafts[0].name = "生ビール"
correctedDrafts[0].price = "600"
correctedDrafts[0].taxRate = "10"
correctedDrafts[0].taxType = "内税"
correctedDrafts[2].name = "枝豆（大）"
let correctedResult = MenuCSVImportService.validate(drafts: correctedDrafts, fileName: "corrected.csv")
check(correctedResult.rows.count == 3, "edited rows become importable")
check(correctedResult.issues.isEmpty, "edited rows are revalidated")

do {
    _ = try MenuCSVImportService.parse(text: "name\n生ビール")
    check(false, "missing price header should fail")
} catch MenuCSVImportError.missingRequiredHeader {
    // Expected.
}

do {
    _ = try MenuCSVImportService.parse(text: "name,price\n\"生ビール,600")
    check(false, "unclosed quote should fail")
} catch MenuCSVImportError.malformedCSV {
    // Expected.
}

print("CSV parser smoke tests passed")
