# TablePOS MVP Requirements

## 1. Product goal

Provide a fast, low-maintenance iPad register for one restaurant operating one device. Core ordering, table management, checkout, and auditable sale history must work offline and on-device.

## 2. Platform and technical constraints

- The operational target is iPad. The same target also supports iPhone for testing with a compact adaptive layout. Minimum deployment target is iOS/iPadOS 17.
- SwiftUI for UI, SwiftData for persistence, Vision for OCR, Sudachi.rs/SudachiDict core for Japanese analysis, and Natural Language for final-stage semantic search.
- All MVP business data and processing remain on the device.
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
- Settings provides create, edit, and delete operations for the product master.
- Each product has name, integer price, tax rate (8% or 10%), tax type (tax included or tax excluded), menu type, category, frequent flag, and enabled flag.
- Categories have name, color, and sort order.
- Frequent products appear automatically as quick tiles grouped by category and colored with the category color.
- Repeated taps on the same product tile increase the quantity of the existing matching line.
- The order supports direct quantity entry and line removal.
- A custom item may have a blank name. Price, tax rate, tax type, and quantity are required.

## 5. Search

- No manually maintained synonym dictionary.
- Search ranking uses, in order: exact surface match, prefix/partial match, Sudachi normalized-form match, Sudachi reading match, morpheme-token match, kana/kanji edit similarity, then `NLEmbedding` semantic similarity.
- Basic normalization applies Unicode compatibility normalization, case/width/diacritic folding, hiragana-to-katakana conversion, and whitespace/punctuation removal.
- Sudachi mode C creates the full normalized form and reading. Modes A/B/C contribute searchable token variants.
- Kanji reading is obtained from the Japanese dictionary; generic kanji-to-Latin transliteration is not used.
- Product search indexes are regenerated when a product is saved and lazily backfilled for existing records.
- If Sudachi resources or a Japanese sentence embedding are unavailable, search falls back to deterministic Unicode/kana normalization and character edit similarity.

## 6. OCR product import

- Images may be supplied by the camera or photo library.
- Vision extracts text and proposes product-name/price candidates.
- OCR does not decide tax rate or tax-included/excluded status.
- A confirmation screen lets the user edit the proposed name and price, select category/menu type/frequent status, and manually set tax rate and tax type before saving.
- OCR is an assisted import. The user confirms all saved candidates.

## 7. Tax and totals

- Both 8% and 10% tax rates are supported.
- Both tax-included and tax-excluded prices are supported.
- For tax-excluded items, tax is calculated once on the aggregate taxable base for each tax rate, not independently per line.
- Tax rounding is configurable: floor, nearest, or ceiling.
- The normal payable amount retains one-yen precision.
- Checkout has an explicit action to round the one-yen digit to the nearest ten yen.
- That action changes the payable amount only and records the delta as `roundingAdjustment`; it does not alter item prices or tax.

## 8. Checkout

- Payment methods are cash, card, QR, and other.
- Cash checkout accepts tendered amount and calculates change. Underpayment cannot complete.
- Non-cash checkout records the payment method and total.
- Checkout saves an immutable item snapshot and calculated tax/total fields before clearing the table.

## 9. History, cancellation, and correction

- A history screen lists completed and cancelled sales and opens sale details.
- Historical items retain the name, unit price, tax rate, tax type, and quantity as they were at checkout, independent of later product edits.
- A completed sale may be cancelled with a reason. Cancellation time and reason are retained.
- Correcting a historical sale must not overwrite it. The original is marked cancelled and a replacement sale is created with a new identity.
- The original and replacement reference each other; a cancellation record retains the reason and relationship.
- The data model must remain suitable for later CSV sales export.

## 10. Explicitly out of MVP scope

- Multi-device sync, cloud sync, accounts, roles, and multi-store support
- Receipt printers and cash drawers
- Automated backup and restore
- Inventory and sold-out management
- Split bills and split payments
- Production CSV export UI (the stored schema must permit it later)
- Automated semantic-learning from historical selection behavior

## 11. MVP acceptance criteria

1. A clean clone opens as an Xcode project and, with network access for the pinned dictionary build artifact, builds for iPad and iPhone simulators.
2. First-run setup creates the configured number of table tiles.
3. A user can add products, custom items, adjust quantities, move an order, and complete a payment.
4. Totals distinguish tax rates and included/excluded tax and apply the configured rounding rule.
5. Completed sales survive relaunch and contain item snapshots.
6. Cancelling and correcting a sale preserves an audit trail.
7. OCR can extract editable candidates from a selected or captured image.
8. Core operations remain usable without a network connection.
