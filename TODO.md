# MVP Status

## Implemented

- [x] iPad-first SwiftUI project using SwiftData
- [x] iPhone test target with compact adaptive order layout
- [x] First-run table count setup and table tile home
- [x] Active order per table with persisted item snapshots
- [x] Table move and explicit merge
- [x] Product and category create/edit/delete
- [x] Product category filtering and multi-selection bulk deletion
- [x] Edit CSV/OCR-imported products with the normal product form
- [x] Grand/limited menu type and frequent category tiles
- [x] Repeated tile tap quantity increment and direct quantity input
- [x] Custom blank-name item with tax metadata
- [x] Unicode/kana normalization, Sudachi normalized/readings/tokens, Japanese edit similarity, and optional `NLEmbedding` ranking
- [x] Vision OCR from camera/photo library with editable confirmation
- [x] UTF-8/Shift_JIS menu CSV import with validation, preview, duplicate policy, and category creation
- [x] Pre-import CSV row correction and automatic revalidation
- [x] Ordering-screen category filtering
- [x] 8%/10%, included/excluded tax, aggregate excluded-tax calculation
- [x] Configurable tax fraction rounding
- [x] Explicit ten-yen checkout rounding with stored adjustment
- [x] Cash tender/change and cash/card/QR/other payment recording
- [x] Sale history and immutable sale-item snapshots
- [x] Cancellation record and linked replacement correction sale
- [x] Manual checksummed backup export to Files/iCloud Drive and fresh-install restore

## Deliberately simplified for the first build

- [ ] Automated UI tests and a full tax edge-case test matrix
- [ ] Large-menu performance profiling and cached semantic vectors
- [ ] OCR row/column layout reconstruction beyond line-based name/price parsing
- [ ] Production accessibility/localization review
- [ ] Store migration and corrupt-store recovery UX
- [ ] Evaluate SudachiDict small/custom dictionary if the 207 MB core dictionary is too large for distribution

## Outside MVP

- [ ] CSV export UI
- [ ] Multi-device/cloud sync and accounts
- [ ] Printer/cash drawer integration
- [ ] Automatic/versioned CloudKit backup and existing-store merge
- [ ] Inventory and sold-out state
- [ ] Split bills/payments
- [ ] Learned ranking from selection history
