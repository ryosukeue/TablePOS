# UI Flow

## First launch

```text
Launch -> Table-count setup -> Table home
```

Setup creates table records and default categories. Optional sample products are available from Settings.

## Primary navigation

The root uses four tabs on iPad and iPhone:

```text
Tables (home) | Products | History | Settings
```

## Order flow

```text
Table tile
  -> order screen
     -> ★ frequent / All / category / uncategorized tabs (default: All)
     -> search all enabled products regardless of selected tab
     -> always-visible custom-item action -> large keypad sheet
     -> line quantity edit/remove
     -> move/merge table sheet
     -> checkout sheet: manually confirm total item count
        -> payment entry
        -> optional ten-yen round action
        -> payment method
        -> in-app cash tender keypad/change when applicable
        -> complete -> summary
           -> digital receipt
           -> physical receipt print/cut
           -> cash drawer open
           -> close -> table home
```

## Product flow

```text
Products tab
  -> filter by all/category/uncategorized
  -> tap a product -> edit product (including CSV/OCR imports)
  -> add product
  -> select -> select multiple products -> confirm bulk delete
  -> swipe delete
  -> CSV import
     -> choose CSV/text file
     -> validation preview and line errors
     -> tap any row -> correct values -> automatic revalidation
     -> choose update/skip for existing names
     -> import valid products and create missing categories
  -> OCR import
     -> camera or photo library
     -> recognition
     -> editable candidate list
     -> set category/tax/menu metadata
     -> save selected candidates
```

## History flow

```text
History list -> sale detail
  -> digital receipt -> show QR -> customer mobile viewer -> print/save PDF or JSON
                     -> oversized payload -> share/save native PDF
  -> cancel -> reason -> status becomes cancelled
  -> correct -> editable copied lines -> create replacement sale
                and cancel/link original sale
```

Correction intentionally creates a new sale; the original detail remains visible as cancelled.

## Backup flow

```text
Settings -> Backup and restore -> export backup
  -> system save panel -> choose iCloud Drive or local Files

Fresh-install setup -> restore from backup
  -> choose JSON backup
  -> verify checksum, format and references
  -> show date and record counts
  -> confirm -> restore -> table home
```

## Compact iPhone test layout

The iPhone layout keeps the same data and flows. The order screen replaces the iPad two-pane layout with a `Products / Order` segmented switch so both areas remain usable at compact width. iPad remains the intended register device.

## Settings flow

```text
Settings
  -> table count
  -> tax rounding rule
  -> category management
  -> mPOP discovery/selection and drawer test
  -> optional sample-data insertion
```
