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
     -> frequent tiles grouped by category
     -> search all enabled products
     -> custom item sheet
     -> line quantity edit/remove
     -> move/merge table sheet
     -> checkout sheet
        -> optional ten-yen round action
        -> payment method
        -> cash tender/change when applicable
        -> complete -> table home
```

## Product flow

```text
Products tab
  -> add/edit product
  -> swipe delete
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
  -> cancel -> reason -> status becomes cancelled
  -> correct -> editable copied lines -> create replacement sale
                and cancel/link original sale
```

Correction intentionally creates a new sale; the original detail remains visible as cancelled.

## Compact iPhone test layout

The iPhone layout keeps the same data and flows. The order screen replaces the iPad two-pane layout with a `Products / Order` segmented switch so both areas remain usable at compact width. iPad remains the intended register device.

## Settings flow

```text
Settings
  -> table count
  -> tax rounding rule
  -> category management
  -> optional sample-data insertion
```
