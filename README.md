# TablePOS

TablePOS is an iPad-first, on-device point-of-sale MVP for a single restaurant and a single device. It is implemented with SwiftUI, SwiftData, Vision, Natural Language, and Sudachi.rs. An iPhone-compatible layout is included for testing.

## Open and build

1. Open `TablePOS.xcodeproj` in Xcode 26 or later.
2. Select an iPad simulator for the intended register experience, or an iPhone simulator for compact-layout testing. iOS/iPadOS 17 or later is required.
3. Build and run the `TablePOS` scheme.

The first clean build downloads the pinned official SudachiDict core archive, verifies its SHA-256 checksum, and places `system.dic` in the app resource bundle. This one-time build step needs an internet connection. The installed app performs product search entirely on-device and does not download anything at runtime. The core dictionary adds about 207 MB to the uncompressed app bundle.

The first launch asks for the number of tables. Sample categories and products can be added from Settings for evaluation.

## Documents

- [requirements.md](requirements.md): agreed product requirements and acceptance criteria
- [ARCHITECTURE.md](ARCHITECTURE.md): application structure and design decisions
- [DATA_MODEL.md](DATA_MODEL.md): persisted entities and calculation rules
- [UI_FLOW.md](UI_FLOW.md): screens and core flows
- [TODO.md](TODO.md): implemented scope and remaining work
- [SEARCH.md](SEARCH.md): Japanese normalization, ranking, fallback, and dictionary build details

## Current scope

The MVP supports table-based orders, moving/merging tables, product management, category-based quick tiles, normalized and semantic search, custom items, tax calculation, payment recording, cash change, optional ten-yen rounding, sale history, cancellation, and correction sales. OCR imports menu candidates from the camera or photo library and leaves tax fields for confirmation.

No network account, cloud synchronization, printer, cash drawer, backup, sold-out management, or split payment is included.
