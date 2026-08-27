# Architecture

## Overview

TablePOS is a local-first, iPad-first SwiftUI application with an adaptive iPhone test layout. Views read SwiftData with `@Query` and perform small transactional mutations through `ModelContext`. Business calculations and search are pure services so persisted totals can be generated consistently.

```text
SwiftUI views
  -> order and checkout actions
  -> TaxCalculator / ProductSearch / OCRService
  -> SudachiAnalyzer -> bundled Sudachi.rs static library + SudachiDict core
  -> SwiftData ModelContext
  -> on-device persistent store
```

## Layers

- `App`: application entry point, model container, root setup gate, and tab navigation.
- `Models`: SwiftData records and stable string-backed enums.
- `Services`: tax calculation, search normalization/ranking, CSV import, OCR parsing, seeding, and order mutations.
- `Views`: table grid/order entry, product master, history/correction, OCR confirmation, and settings.

## Important decisions

### Integer yen

All prices and totals use `Int`. This avoids floating-point drift and makes exported amounts deterministic. Only the percentage calculation temporarily uses integer multiplication and division.

### ID-based relationships

Business links use stable UUID fields (`tableID`, `orderID`, `saleID`) rather than relying on cascading SwiftData object relationships. This keeps audit records explicit, avoids accidental historical deletion, and makes future CSV export straightforward.

### Snapshot sales

`SaleItem` copies all financial product attributes at checkout. Product deletion or editing never changes history.

### Transaction boundary

A checkout creates one `Sale`, its `SaleItem` snapshots, and then deletes the active order lines/order in one `ModelContext` save. Correction creates a copied replacement sale and marks the source cancelled in the same save.

### Japanese search pipeline

`ProductSearch` does not use Foundation's generic `toLatin` transform. It first creates a deterministic Unicode/kana key, then asks the bundled Sudachi.rs analyzer for Japanese normalized forms, katakana readings, and A/B/C-mode token variants. The results are cached on each `Product` so normal ranking does not tokenize the complete catalog for each keystroke.

Lexical matches are ranked before a kana/kanji-aware character edit score. `NLEmbedding` is the last, lower-confidence semantic tier. If Sudachi cannot be initialized or the embedding is unavailable, deterministic Unicode/kana and edit-distance search remains available.

The Rust tokenizer is exposed through a small C ABI in `SudachiBridge` and linked as `TablePOSSudachi.xcframework` with device and simulator slices. A build phase fetches the pinned SudachiDict core wheel, verifies its checksum, and copies the dictionary into `SudachiResources.bundle`. There is no runtime network access. See `SEARCH.md` for exact versions and tradeoffs.

### OCR privacy

Vision text recognition receives an in-memory image and runs locally. Images are not retained in the application model after recognition.

### CSV import boundary

`MenuCSVImportService` handles file access, UTF-8/Shift_JIS decoding, RFC-style quoted fields, header aliases, defaults, and row validation without mutating SwiftData. After preview, `MenuCSVProductService` applies valid rows, resolves or creates categories, handles the selected duplicate policy, and saves once. A persistence failure rolls the model context back.

## Error handling

The MVP shows local validation and operation errors through alerts. Save failures do not silently dismiss an editing or checkout sheet. A production release should add structured logging, store migration tests, and recovery UX.
