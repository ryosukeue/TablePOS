# TablePOS

TablePOS is an iPad-first, on-device point-of-sale MVP for a single restaurant and a single device. It is implemented with SwiftUI, SwiftData, Vision, Natural Language, and Sudachi.rs. An iPhone-compatible layout is included for testing.

## Open and build

1. Open `TablePOS.xcodeproj` in Xcode 26 or later.
2. Select an iPad simulator for the intended register experience, or an iPhone simulator for compact-layout testing. iOS/iPadOS 17 or later is required.
3. Build and run the `TablePOS` scheme.

The first clean build downloads the pinned official SudachiDict core archive, verifies its SHA-256 checksum, and places `system.dic` in the app resource bundle. This one-time build step needs an internet connection. The installed app performs product search entirely on-device and does not download anything at runtime. The core dictionary adds about 207 MB to the uncompressed app bundle.

The first launch asks for the number of tables. Sample categories and products can be added from Settings for evaluation.

## Documents

- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md): 日本語で読む全体構成、処理フロー、ファイル案内
- [CSV_IMPORT_GUIDE.md](CSV_IMPORT_GUIDE.md): メニューCSVの列定義、作成方法、取込ルール
- [CSV_IMPORT_REQUIREMENTS.md](CSV_IMPORT_REQUIREMENTS.md): メニューCSV取込の機能要件と受入条件
- [requirements.md](requirements.md): agreed product requirements and acceptance criteria
- [ARCHITECTURE.md](ARCHITECTURE.md): application structure and design decisions
- [DATA_MODEL.md](DATA_MODEL.md): persisted entities and calculation rules
- [UI_FLOW.md](UI_FLOW.md): screens and core flows
- [TODO.md](TODO.md): implemented scope and remaining work
- [SEARCH.md](SEARCH.md): Japanese normalization, ranking, fallback, and dictionary build details
- [BACKUP_GUIDE.md](BACKUP_GUIDE.md): important-data backup and fresh-install restore
- [DIGITAL_RECEIPT.md](DIGITAL_RECEIPT.md): QR receipt usage, privacy model, capacity, and PDF fallback
- [STAR_PRINTER_GUIDE.md](STAR_PRINTER_GUIDE.md): Star mPOP discovery, receipt printing, cutting, and drawer setup

## Current scope

The MVP supports table-based orders, moving/merging tables, product management, CSV menu import, frequent/All/category product tabs, category-independent search, large keypad custom-item entry, required item-count confirmation, staged checkout, payment recording, cash change, optional ten-yen rounding, sale history, cancellation, correction sales, self-contained QR/PDF digital receipts, and Star mPOP receipt printing/cutting/drawer control. OCR imports menu candidates from the camera or photo library and leaves tax fields for confirmation.

No network account, live cloud synchronization, automatic backup, sold-out management, or split payment is included. A manual checksummed backup can be saved to Files/iCloud Drive and restored on a fresh installation. Physical mPOP behavior still requires verification with the store's actual hardware and connection method.
