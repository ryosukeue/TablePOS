# TablePOS MVP Requirements

## 1. Product goal

Provide a fast, low-maintenance iPad register for one restaurant operating one device. Core ordering, table management, checkout, and auditable sale history must work offline and on-device.

## 2. Platform and technical constraints

- The operational target is iPad. The same target also supports iPhone for testing with a compact adaptive layout. Minimum deployment target is iOS/iPadOS 17.
- SwiftUI for UI, SwiftData for persistence, Vision for OCR, Sudachi.rs/SudachiDict core for Japanese analysis, and Natural Language for final-stage semantic search.
- All MVP business data and processing remain on the device.
- Digital-receipt QR codes embed the completed sale snapshot in the URL fragment. The static viewer receives no receipt payload over HTTP and performs no analytics or API calls.
- A user-triggered portable backup may be saved through the system file picker, including to iCloud Drive. This is not live CloudKit synchronization.
- A clean build may download the pinned dictionary artifact and verify its checksum. The built/installed application must not require a network connection for search.
- One store and one active device. No user accounts or staff permissions in the MVP.
- Monetary values are stored as integer Japanese yen.

## 3. First launch and tables

- On first launch, the user sets the number of tables.
- After setup, the table tile grid is the default home screen.
- A table tile shows its name/number, vacant or occupied state, current total, item count, and elapsed time when occupied.
- The table count remains editable in Settings.
- Each table keeps one active order until checkout or cancellation.
- An active order can be moved to another table.
- If the destination already has an order, the user must explicitly merge the source order into it or cancel the move.
- Split bills and split payments are not supported.

## 4. Products and categories

- Products are either grand-menu or limited-time products.
- The Products screen provides create and edit operations, category filtering, single deletion, and multi-selection bulk deletion for the product master.
- Products created or updated by CSV/OCR become ordinary product-master records and remain editable with the same form as manually entered products.
- Each product has name, integer price, tax rate (8% or 10%), tax type (tax included or tax excluded), menu type, category, frequent flag, and enabled flag.
- Categories have name, color, and sort order.
- Frequent products appear automatically as quick tiles grouped by category and colored with the category color.
- The ordering screen provides category chips. Selecting a category shows every enabled product in that category and constrains text search to that category.
- Repeated taps on the same product tile increase the quantity of the existing matching line.
- Ordering category tabs start with a star-marked frequent tab, followed by All, every configured category, and uncategorized. All is selected by default and shows every enabled product; each category shows every enabled product in it.
- While a search query is present, search covers every enabled product regardless of the selected category tab.
- The order supports direct quantity entry and line removal.
- A custom item may have a blank name. Price, tax rate, tax type, and quantity are required.
- Custom item entry is an always-visible action in the order pane. Its large sheet uses an in-app numeric keypad, large price display, tax buttons, and plus/minus quantity controls without opening the system numeric keyboard.
- All limited-time products can be deleted from the product master in one confirmed operation without changing active-order or historical snapshots.

## 5. CSV menu import

The detailed Japanese specification and acceptance criteria are defined in [CSV_IMPORT_REQUIREMENTS.md](CSV_IMPORT_REQUIREMENTS.md).

- The Products screen can select a local CSV or text file and import product-master rows on-device.
- Required columns are `name` and `price`. Optional columns are `tax_rate`, `tax_type`, `menu_type`, `category`, `is_frequent`, and `is_enabled`.
- English canonical headers and documented Japanese header aliases are accepted. Column order is arbitrary and unknown columns are ignored.
- Missing optional values default to 10%, tax included, grand menu, uncategorized, not frequent, and enabled.
- UTF-8, UTF-8 with BOM, and Shift_JIS input are supported. Quoted commas, escaped quotes, quoted newlines, LF, and CRLF are parsed as CSV.
- Files are limited to 5MB and 10,000 data rows.
- Before saving, the UI shows valid-row counts, a product preview, validation errors, and original line numbers. Invalid rows are excluded while valid rows remain importable.
- Every parsed CSV row, including an invalid row, remains editable in the pre-import preview. Editing triggers validation again so minor errors can be corrected without changing and reselecting the source file.
- Duplicate names within one CSV are rejected after the first valid row.
- For a name matching an existing product after trimming and Unicode compatibility normalization, the user chooses either update or skip. Import never deletes products absent from the file.
- An unknown non-empty category is created automatically with an assigned color. An empty category remains uncategorized.
- Product search indexes are generated during import. Imported products and new categories are saved together; a save failure is rolled back.
- After import, every imported product can be opened and edited from the Products screen, filtered by its category, selected with other products, and deleted in bulk.

## 6. Search

- No manually maintained synonym dictionary.
- Search ranking uses, in order: exact surface match, prefix/partial match, Sudachi normalized-form match, Sudachi reading match, morpheme-token match, kana/kanji edit similarity, then `NLEmbedding` semantic similarity.
- Basic normalization applies Unicode compatibility normalization, case/width/diacritic folding, hiragana-to-katakana conversion, and whitespace/punctuation removal.
- Sudachi mode C creates the full normalized form and reading. Modes A/B/C contribute searchable token variants.
- Kanji reading is obtained from the Japanese dictionary; generic kanji-to-Latin transliteration is not used.
- Product search indexes are regenerated when a product is saved and lazily backfilled for existing records.
- If Sudachi resources or a Japanese sentence embedding are unavailable, search falls back to deterministic Unicode/kana normalization and character edit similarity.

## 7. OCR product import

- Images may be supplied by the camera or photo library.
- Vision extracts text and proposes product-name/price candidates.
- OCR does not decide tax rate or tax-included/excluded status.
- A confirmation screen lets the user edit the proposed name and price, select category/menu type/frequent status, and manually set tax rate and tax type before saving.
- OCR is an assisted import. The user confirms all saved candidates.

## 8. Tax and totals

- Both 8% and 10% tax rates are supported.
- Both tax-included and tax-excluded prices are supported.
- For tax-excluded items, tax is calculated once on the aggregate taxable base for each tax rate, not independently per line.
- Tax rounding is configurable: floor, nearest, or ceiling.
- The normal payable amount retains one-yen precision.
- Checkout has an explicit action to round the one-yen digit to the nearest ten yen.
- That action changes the payable amount only and records the delta as `roundingAdjustment`; it does not alter item prices or tax.

## 9. Checkout

- Payment methods are cash, card, QR, and other.
- Cash checkout accepts tendered amount and calculates change. Underpayment cannot complete.
- Non-cash checkout records the payment method and total.
- Checkout saves an immutable item snapshot and calculated tax/total fields before clearing the table.
- Checkout is split into count confirmation, payment entry, and completion summary. The user must manually enter the actual total item quantity and it must match the order before payment entry is enabled.
- The payment step presents a large total, payment method, and an in-app cash keypad. Completion is a separate top-right action.
- The completion summary provides digital-receipt and physical-receipt actions.

## 10. History, cancellation, and correction

- A history screen lists completed and cancelled sales and opens sale details.
- Historical items retain the name, unit price, tax rate, tax type, and quantity as they were at checkout, independent of later product edits.
- A completed sale may be cancelled with a reason. Cancellation time and reason are retained.
- Correcting a historical sale must not overwrite it. The original is marked cancelled and a replacement sale is created with a new identity.
- The original and replacement reference each other; a cancellation record retains the reason and relationship.
- The data model must remain suitable for later CSV sales export.

## 11. Digital receipts

- Sale detail can generate a QR code containing that sale's item snapshots, tax totals, payment method, tender/change, status, and audit-link IDs.
- The QR contains only the selected sale, not the product master or other business records. Product-master size therefore does not affect QR capacity.
- A customer can scan the QR to open a static mobile viewer and print/save it as PDF or save the embedded JSON data.
- Receipt data is placed after `#` in the URL so it is not sent to the static host. The viewer has no server-side receipt storage, account, tracking, or analytics.
- A practical encoded-URL limit is enforced for reliable scanning. When a sale is too large, the register explains this and retains PDF share/save as a lossless fallback.
- The register can generate and share the PDF directly without relying on the viewer.
- A receipt is an immutable checkout snapshot. Cancelling or correcting a sale does not remotely rewrite an already issued QR; its sale ID and recorded status remain auditable against the register history.

## 12. Explicitly out of MVP scope

- Multi-device sync, cloud sync, accounts, roles, and multi-store support
- Automated/scheduled backup and multi-device synchronization
- Inventory and sold-out management
- Split bills and split payments
- Production CSV export UI (the stored schema must permit it later)
- Automated semantic-learning from historical selection behavior

## 13. MVP acceptance criteria

1. A clean clone opens as an Xcode project and, with network access for the pinned dictionary build artifact, builds for iPad and iPhone simulators.
2. First-run setup creates the configured number of table tiles.
3. A user can add products, custom items, adjust quantities, move an order, and complete a payment.
4. Totals distinguish tax rates and included/excluded tax and apply the configured rounding rule.
5. Completed sales survive relaunch and contain item snapshots.
6. Cancelling and correcting a sale preserves an audit trail.
7. OCR can extract editable candidates from a selected or captured image.
8. A documented sample CSV produces a validation preview and imports products; invalid rows show their source line numbers.
9. Core operations remain usable without a network connection.
10. Product master records can be filtered by category, edited after CSV import, and deleted using multi-selection.
11. Settings can export a checksummed backup of all business records, and a fresh installation can validate and restore it before initial setup.
12. A sale detail can show a self-contained digital-receipt QR when it fits the practical capacity and can always export the receipt as PDF.
13. Checkout cannot proceed to payment until the manually entered item count matches the stored order quantity.
14. A selected Star mPOP printer can print and partially cut a snapshot receipt, and cash checkout can open the drawer.

## 14. Star mPOP printer

- Integrate the official StarXpand SDK for iOS through Swift Package Manager with an exact version.
- Discover supported Star printers over LAN, Bluetooth, Bluetooth Low Energy, and USB without filtering for one mPOP model identifier.
- Persist the selected connection locally on the device.
- Support Japanese receipt text, print, paper feed, partial cut, and cash-drawer open commands.
- POP10, POP10CI, and POP10CBI must use the same discovery/selection path rather than model-specific branches.
- Printer failure must not roll back or delete a completed sale. The completion summary remains available and shows the error.
