# TablePOS プロジェクト構成

## 1. このアプリについて

TablePOSは、飲食店の1店舗・1端末運用を想定したローカル完結型のレジアプリです。主用途はiPadですが、開発・動作確認用にiPhoneにも対応しています。

- UI: SwiftUI
- 保存: SwiftData
- OCR: Vision
- 日本語検索: Sudachi.rs + SudachiDict core
- 意味検索: Natural Languageの`NLEmbedding`
- 物理レシート: StarXpand SDK (`StarIO10` 2.13.0)
- 対応OS: iOS / iPadOS 17以降
- データ同期: なし。会計データを含めて端末内へ保存

## 2. 全体構造

```text
SwiftUI画面
    │
    ├─ @QueryでSwiftDataを参照
    │
    └─ ユーザー操作
         │
         ├─ AppDataService / OrderService / SaleService
         ├─ TaxCalculator
         ├─ ProductSearch ─ SudachiAnalyzer ─ Sudachi.rs
         └─ OCRService ─ Vision
              │
              ▼
        SwiftData / 端末内ストア
```

画面はデータを表示し、注文・会計など複数データを変更する処理はServiceへ寄せています。金額や税額は`Int`の日本円で扱い、浮動小数点数は使いません。

## 3. ディレクトリ構成

```text
TablePOS/
├── App/
│   ├── TablePOSApp.swift        # アプリ起動、SwiftDataコンテナ
│   └── AppRootView.swift        # 初回設定判定、4タブの入口
│
├── Models/
│   ├── Enums.swift              # 税率、内外税、支払方法など
│   └── PersistenceModels.swift  # SwiftDataの保存モデル
│
├── Services/
│   ├── AppDataService.swift     # 初期設定、注文、移動、会計、取消・訂正
│   ├── TaxCalculator.swift      # 税額・合計・10円丸め
│   ├── ProductSearch.swift      # 商品検索インデックスと順位付け
│   ├── SudachiAnalyzer.swift    # SwiftとSudachi.rsの橋渡し
│   ├── OCRService.swift         # Vision OCRと商品・価格候補抽出
│   ├── MenuCSVImportService.swift # CSV解析、文字コード判定、行検証
│   ├── MenuCSVProductService.swift # CSV商品・カテゴリの一括保存
│   ├── BackupService.swift       # 重要データの書出し、検証、初期復元
│   ├── DigitalReceiptService.swift # 会計スナップショットのQR・PDF生成
│   ├── StarPrinterService.swift # mPOP探索、印刷、カット、ドロア開放
│   └── Formatting.swift         # 円表示、色などの共通処理
│
├── Views/
│   ├── Tables/
│   │   ├── TableHomeView.swift  # ホームのテーブルタイル
│   │   ├── OrderView.swift      # 商品選択と注文内容
│   │   └── OrderSheets.swift    # カスタム商品、卓移動、会計
│   ├── Products/
│   │   ├── ProductListView.swift # 商品一覧、追加・編集
│   │   └── CSVImportView.swift  # CSV選択、検証結果、取込実行
│   ├── OCR/
│   │   └── OCRImportView.swift  # 撮影・写真選択・OCR確認
│   ├── History/
│   │   ├── SaleHistoryView.swift # 会計履歴、取消・訂正
│   │   └── DigitalReceiptView.swift # QR表示とPDF共有
│   ├── Settings/
│   │   ├── SettingsView.swift   # 卓数、税丸め、カテゴリ設定
│   │   ├── BackupRestoreView.swift # Files/iCloud Driveへの手動バックアップ
│   │   └── PrinterSettingsView.swift # mPOPの探索・選択・ドロアテスト
│   └── Components/
│       ├── StatusViews.swift    # 空表示、金額内訳など
│       └── NumericKeypad.swift  # 価格、点数、預かり金のアプリ内テンキー
│
├── Frameworks/
│   └── TablePOSSudachi.xcframework # 実機・Simulator用のRust静的ライブラリ
│
└── Resources/
    └── SudachiResources.bundle # 設定、文字定義、日本語辞書

SudachiBridge/                    # Rust製C ABIブリッジのソース
Scripts/                          # 辞書取得、XCFramework再生成
ThirdPartyLicenses/               # Sudachi関連ライセンス
docs/                             # GitHub Pages用の静的レシートビューア
```

## 4. アプリ起動と画面構成

`TablePOSApp`がSwiftDataのSchemaと`ModelContainer`を生成し、`AppRootView`を表示します。

```text
アプリ起動
  ├─ 初期設定前 → テーブル数設定
  └─ 初期設定済み
       ├─ テーブル
       ├─ 商品
       ├─ 履歴
       └─ 設定
```

iPadとiPhoneは同じTarget・同じデータモデルを使用します。iPhoneの注文画面だけ、横幅に合わせて商品領域と注文領域を切り替えるコンパクト表示になります。

## 5. データモデル

```text
StoreSettings

DiningTable ── tableID ── Order ── orderID ── OrderItem

ProductCategory ── categoryID ── Product
                                  │
                                  └─ 注文追加時にOrderItemへ内容をコピー

Sale ── saleID ── SaleItem
  │
  ├─ originalSaleID / replacementSaleID
  └─ CancellationRecord
```

SwiftDataのオブジェクトリレーションではなくUUIDを保存し、Service側で関連付けています。これにより、商品マスタを変更・削除しても注文中の商品や過去会計が書き換わりません。

主要モデルは次の役割を持ちます。

| モデル | 役割 |
| --- | --- |
| `StoreSettings` | 初期設定状態、卓数、税端数処理 |
| `DiningTable` | 卓番号、名称、表示順 |
| `ProductCategory` | カテゴリ名、タイル色、表示順 |
| `Product` | 商品マスタと日本語検索インデックス |
| `Order` | 卓に紐づく会計前の注文 |
| `OrderItem` | 注文時点の商品名・価格・税情報 |
| `Sale` | 支払方法、税額、合計、取消・訂正関係 |
| `SaleItem` | 会計完了時点の商品スナップショット |
| `CancellationRecord` | 取消日時、理由、訂正後会計との関係 |

詳細な項目と税計算式は[DATA_MODEL.md](DATA_MODEL.md)を参照してください。

## 6. 注文から会計まで

```text
テーブルを選択
  → 商品タイル・検索・カスタム商品から追加
  → 同じ商品は数量を加算
  → 必要なら別テーブルへ移動または合算
  → 税額と合計を計算
  → 実際の商品合計点数を手入力して注文と照合
  → 任意で10円単位へ丸める
  → 現金 / カード / QR / その他で会計
  → SaleとSaleItemを保存
  → 完了サマリーからデジタルレシートまたはmPOP物理レシート
  → OrderとOrderItemを削除して空卓へ戻す
```

外税は明細単位ではなく、8%と10%それぞれの対象商品を合計してから計算します。10円丸めは税額を変えず、差額だけを`roundingAdjustment`へ記録します。

## 7. 会計取消と訂正

過去会計を直接上書きしません。

```text
元Sale
  → 取消済みに変更
  → CancellationRecordを追加
  → 訂正版を新しいSaleとして保存
  → originalSaleID / replacementSaleIDで相互参照
```

この構造により、将来CSV出力を追加したときも元会計・取消・訂正版を追跡できます。

## 8. 日本語商品検索

商品保存時に、検索用の正規形・読み・分割語を`Product`へ保存します。

```text
入力
  → Unicode互換正規化
  → 全角半角・大小文字・ひらがな/カタカナ統一
  → 空白・記号除去
  → Sudachiの正規形・読み・A/B/C分割語
  → 日本語文字単位の編集距離
  → 最後にNLEmbedding意味検索
```

完全一致や読み一致を意味検索より優先します。手動同義語辞書はありません。Sudachiが利用できない場合も、基本的な文字・かな正規化へフォールバックします。詳しくは[SEARCH.md](SEARCH.md)を参照してください。

## 9. CSVメニュー取込

UTF-8またはShift_JISのCSVを選択し、商品名・価格などをまとめて商品マスタへ保存できます。CSV解析と行検証を先に実行し、利用者がプレビューとエラー行を確認してからSwiftDataを更新します。

```text
CSV選択
  → 文字コード判定
  → ヘッダー解決、全行を編集候補として保持して検証
  → 正常行・エラー行をプレビュー
  → 必要な行を画面で修正して再検証
  → 既存同名商品を更新またはスキップ
  → 未登録カテゴリを作成
  → 商品検索インデックスを生成
  → 一括保存
```

CSVにない既存商品は変更しません。正式な列構造と作成方法は[CSV_IMPORT_GUIDE.md](CSV_IMPORT_GUIDE.md)を参照してください。

## 10. OCR登録

カメラまたは写真ライブラリの画像をVisionへ渡し、同じ行にある商品名と価格を候補として抽出します。画像自体はSwiftDataへ保存しません。

OCRは税率や内税・外税を自動判断しません。保存前の確認画面で、利用者が次を設定します。

- 商品名と価格
- 税率8% / 10%
- 内税 / 外税
- グランド / 期間限定
- カテゴリ
- 頻出タイルへの表示

## 11. ビルド時のSudachi辞書

`system.dic`は約207MBあるためGitへ保存していません。クリーンビルド時にXcodeのBuild Phaseから`Scripts/fetch_sudachi_dictionary.sh`を実行します。

```text
公式SudachiDict coreを取得
  → wheelのSHA-256を検証
  → system.dicを展開
  → 展開後のSHA-256を再検証
  → アプリのResource Bundleへ同梱
```

初回のクリーンビルドだけネット接続が必要です。インストール後のアプリはオフラインで検索できます。

## 12. 変更したい機能ごとの入口

| やりたいこと | 最初に見るファイル |
| --- | --- |
| 起動・タブを変える | `App/AppRootView.swift` |
| 保存モデルを変える | `Models/PersistenceModels.swift` |
| 卓数や初期データを変える | `Services/AppDataService.swift` |
| 注文・卓移動・会計を変える | `Services/AppDataService.swift` |
| 税計算を変える | `Services/TaxCalculator.swift` |
| 商品検索を変える | `Services/ProductSearch.swift` |
| Sudachi連携を変える | `Services/SudachiAnalyzer.swift`と`SudachiBridge/` |
| OCR抽出を変える | `Services/OCRService.swift` |
| CSV取込を変える | `Services/MenuCSVImportService.swift`と`Views/Products/CSVImportView.swift` |
| テーブル画面を変える | `Views/Tables/` |
| 商品管理を変える | `Views/Products/` |
| 会計履歴を変える | `Views/History/` |
| デジタルレシートを変える | `Services/DigitalReceiptService.swift`、`Views/History/DigitalReceiptView.swift`、`docs/receipt/` |
| mPOP印刷を変える | `Services/StarPrinterService.swift`と`Views/Settings/PrinterSettingsView.swift` |
| 設定画面を変える | `Views/Settings/` |

## 13. 関連文書

- [requirements.md](requirements.md): 合意済み要件と受入条件
- [ARCHITECTURE.md](ARCHITECTURE.md): 設計判断
- [DATA_MODEL.md](DATA_MODEL.md): 保存モデルと税計算式
- [UI_FLOW.md](UI_FLOW.md): 画面遷移
- [SEARCH.md](SEARCH.md): 日本語検索の詳細
- [CSV_IMPORT_GUIDE.md](CSV_IMPORT_GUIDE.md): メニューCSVの正式仕様と利用方法
- [CSV_IMPORT_REQUIREMENTS.md](CSV_IMPORT_REQUIREMENTS.md): CSV取込の機能要件と受入条件
- [BACKUP_GUIDE.md](BACKUP_GUIDE.md): 手動バックアップと初期復元の操作・対象・制約
- [DIGITAL_RECEIPT.md](DIGITAL_RECEIPT.md): QRレシートの利用方法、データ、プライバシー、容量制約
- [STAR_PRINTER_GUIDE.md](STAR_PRINTER_GUIDE.md): mPOPの設定、印刷・カット・ドロア動作、実機確認事項
- [TODO.md](TODO.md): 実装済み・未実装一覧
