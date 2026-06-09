# Meal Line-Items — Design

- **Date:** 2026-06-09
- **Status:** Design approved; pending implementation
- **Builds on:** `2026-06-09-meal-day-consolidation-design.md` (one entry per day)

## Problem

A day's meal entry currently stores a single summed amount per slot
(breakfast/lunch/dinner). Scanning a second dinner for the same day sums it into
the one dinner amount, so the individual receipt amounts are lost. The user
wants each scanned/added meal kept as its own line item — e.g. a day can show
"Dinner $20" and "Dinner $18" as two separate lines — with a day total and all
receipts still attached to the single day entry.

## Decisions (from brainstorming)

1. **Always a separate line** — a second same-type meal on the same day becomes
   its own line item. The Add/Replace conflict prompt is removed.
2. **Meal-type popup stays** — scanning still asks Breakfast / Lunch / Dinner;
   the chosen type is what the new line item gets.
3. **Form layout: 3 quick rows + extras** — keep the familiar Breakfast / Lunch
   / Dinner quick-entry rows (the first of each type); additional same-type
   meals appear as extra rows beneath, plus an "Add another meal" button.
4. **History + exports stay compact** — per-type totals per day (e.g. "Dinner
   $38"); tapping a day opens the detail with the individual line items. Exports
   keep one column per type (summed).
5. **Receipts stay collective** — all of the day's receipts in the one receipt
   section (unchanged).

## Storage approach

**Line-items field on the meal row (chosen over a separate child table).** Add a
nullable `line_items` JSON column to `meals`. Keep `breakfast`/`lunch`/`dinner`
and `day_total` as synced sums so the Dashboard, Tax Center, and CSV/PDF exports
keep working unchanged. Additive, low-risk, no data migration.

## Data model

- `MealItem { id: UUID, type: breakfast|lunch|dinner, amount: Decimal }`.
- DB: new nullable `line_items` jsonb column on `meals`, storing
  `[{ "id", "type", "amount" }]`. *(One safe additive migration.)*
- `Meal` model:
  - Decodes `line_items` (optional) plus the existing scalar columns.
  - Computed `items: [MealItem]` = `line_items` if present, otherwise
    synthesized as one item per non-zero scalar slot (back-compat for old rows).
  - `breakfast` / `lunch` / `dinner` / `calculatedTotal` become **computed
    sums** over `items`, so every existing reader (tax, dashboard, exports,
    history) keeps working untouched.
- Save writes `line_items` **and** the scalar per-type sums + `day_total`.

## Behavior

### Form (Log Meal / Edit) — quick rows + extras
- Breakfast / Lunch / Dinner quick rows bind to the **first** item of each type
  (creating one when an amount is entered, removing it when cleared).
- Additional items (2nd+ of any type) render as extra rows below, each labeled
  with its type + amount and a trash button to remove it.
- "Add another meal" button: pick a type + enter an amount → appends an item.
- "Day Total" sums all items. Receipts section unchanged.

### Scan flow
- Scan a meal → OCR date + amount → Breakfast/Lunch/Dinner popup (unchanged) →
  review screen loads the day's entry and **appends a new line item** of the
  chosen type with the receipt's amount. No conflict prompt.

### History list
- Row shows compact per-type totals (uses the computed `breakfast/lunch/dinner`
  sums). Tapping opens the detail/edit showing individual line items.

### Exports / Tax / Dashboard
- Unchanged. They read per-type sums (computed) and the day total.

## Out of scope (YAGNI)
- Per-line-item receipt linkage (receipts remain collective per day).
- Itemized history rows / itemized export rows (compact summary chosen).
- Backfilling old summed entries into multiple items (old rows already render as
  one item per non-zero slot).

## Affected files
- DB migration: add `line_items` jsonb to `meals`.
- `Models/Meal.swift` — `MealItem`, `items`, computed slot sums, decode
  `line_items`.
- `ViewModels/MealViewModel.swift` — save/update write `line_items` + sums.
- `Views/Meals/MealLogView.swift` — quick rows + extras + Add-another; scan
  appends a line item (remove the Add/Replace conflict alert).
- `Views/Meals/MealEditView.swift` — same line-item editing layout.
- `Views/Meals/MealHistoryView.swift` — unchanged display (computed sums).

## Testing
- Scan two same-day dinners → one day entry showing two "Dinner" lines with the
  individual amounts, day total = their sum, both receipts attached.
- Manual: enter Lunch in the quick row, tap "Add another meal" → add a second
  lunch → two lunch lines; save and reopen → persists.
- Old meal (pre-migration, summed) → opens showing one line per non-zero slot.
- Tax Center / Dashboard / CSV / PDF totals match the sum of all line items.
