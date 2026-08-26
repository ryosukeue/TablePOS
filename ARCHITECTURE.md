# Architecture

## Overview

TablePOS is a local-first, iPad-first SwiftUI application with an adaptive iPhone test layout. Views read SwiftData with `@Query` and perform small transactional mutations through `ModelContext`. Business calculations and search are pure services so persisted totals can be generated consistently.

```text
SwiftUI views
  -> order and checkout actions
  -> TaxCalculator / ProductSearch / OCRService
  -> SwiftData ModelContext
  -> on-device persistent store
```

## Layers

- `App`: application entry point, model container, root setup gate, and tab navigation.
- `Models`: SwiftData records and stable string-backed enums.
- `Services`: tax calculation, search normalization/ranking, OCR parsing, seeding, and order mutations.
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

### Search fallback

`ProductSearch` first runs deterministic normalization and reading conversion. It asks `NLEmbedding` for semantic distance only when a Japanese sentence embedding is available. The UI remains fully usable without embedding assets.

### OCR privacy

Vision text recognition receives an in-memory image and runs locally. Images are not retained in the application model after recognition.

## Error handling

The MVP shows local validation and operation errors through alerts. Save failures do not silently dismiss an editing or checkout sheet. A production release should add structured logging, store migration tests, and recovery UX.
