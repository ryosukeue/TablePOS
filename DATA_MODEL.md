# Data Model and Calculation Rules

## Entities

### StoreSettings

Singleton-like record identified by a stable UUID. Holds whether setup is complete, table count, and tax rounding rule.

### DiningTable

`id`, display number, display name, sort order. Tables remain stable while active orders refer to their ID.

### Category

`id`, name, color hex string, sort order. Products refer to a category ID.

### Product

`id`, name, price, tax rate, tax type, menu type, category ID, frequent flag, enabled flag, timestamps, and optional search index fields:

- `searchNormalizedKey`: Sudachi normalized form after basic normalization
- `searchReadingKey`: Sudachi katakana reading after basic normalization
- `searchTokenKeysRaw`: normalized A/B/C token variants joined with an internal separator

The fields are optional for lightweight migration from the first MVP store. Missing values are derived on demand and backfilled when the product screen opens. Product save and OCR import regenerate them.

### Order / OrderItem

An `Order` contains a table ID, open time, and status. `OrderItem` contains order ID, optional source product ID, name, unit price, quantity, tax rate/type, custom flag, and creation time. Product values are copied into the line when added so an in-progress order is not retroactively changed by master edits.

### Sale / SaleItem

A `Sale` contains completion time, status, payment method, subtotal, taxable and tax fields by rate, included tax fields by rate, rounding adjustment, total, tendered/change values, source table label, and optional original/replacement sale IDs. `SaleItem` is the checkout snapshot.

### CancellationRecord

Contains sale ID, cancellation time, reason, and optional replacement sale ID.

## Tax calculation

For every line:

```text
lineAmount = unitPrice * quantity
```

Tax-included lines contribute their line amount to subtotal. Their included tax is informational and derived per tax-rate group:

```text
includedTax = round(groupGross * rate / (100 + rate))
```

Tax-excluded lines are aggregated by rate before tax is calculated:

```text
externalTax8  = round(sum(excluded bases at 8%)  * 8  / 100)
externalTax10 = round(sum(excluded bases at 10%) * 10 / 100)
```

`round` uses the configured floor, nearest, or ceiling strategy. Negative bases are not permitted in the MVP.

```text
subtotal = sum(all line amounts)
preRoundedTotal = subtotal + externalTax8 + externalTax10
total = preRoundedTotal + roundingAdjustment
```

The explicit ten-yen rounding action uses ordinary half-up rounding for non-negative yen:

```text
roundedTotal = ((preRoundedTotal + 5) / 10) * 10
roundingAdjustment = roundedTotal - preRoundedTotal
```

The adjustment is never folded into tax.

## Deletion behavior

- Product deletion is permitted only as a master operation; copied order and sale data remain.
- Reducing the configured table count is rejected when a removed table has an active order.
- Completed sales and cancellation records are audit records and have no delete action in the MVP UI.
