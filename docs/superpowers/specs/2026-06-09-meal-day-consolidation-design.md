# Meal Day Consolidation — Design

- **Date:** 2026-06-09
- **Status:** Design approved; pending implementation

## Problem

Scanning a meal receipt always inserts a new `meals` row, so multiple meal
receipts dated the same day (e.g. two receipts both June 22, 2025) create
**duplicate same-day entries**. The user wants **one meal entry per day**, with
the day's breakfast / lunch / dinner amounts and **all that day's receipts**
filed together under that single entry.

## Decisions (from brainstorming)

1. **One entry per day, enforced** — for both scanning and manual entry.
2. **Same-slot conflict → warn & choose** — if the targeted slot already has an
   amount, prompt the user to **Add** or **Replace** (never silently overwrite).
3. **Scan slot selection = "both"** — a quick **Breakfast / Lunch / Dinner**
   popup right after the scan, then land on the Log Meal review screen to adjust
   before saving.
4. **Approach A — "Day editor"** — the Log Meal screen represents one day. When
   the selected date already has an entry, the form **loads it** (amounts,
   receipts, company) so the user edits the single entry rather than creating a
   second one. Duplicates become impossible by construction.

## Data model

No schema change. The `meals` table already has `date`, `breakfast`, `lunch`,
`dinner`, `receipt_urls[]`, and `agency_id`. Target invariant: **one row per
(user_id, date)**.

## Behavior

### Save (upsert)
- On save, look up the day's existing meal in the already-loaded
  `MealViewModel.meals` array (no extra network call).
- **None found** → insert (current behavior).
- **Found** → update that row, merging amounts per the rules below and appending
  receipts.

### Day editor (form load)
- `MealLogView` tracks `existingMealId: UUID?`.
- On appear and whenever the **date changes**, look up `viewModel.meals` for a
  same-day entry:
  - Found → populate breakfast/lunch/dinner, company, and load its receipts; set
    `existingMealId`.
  - Not found → clear `existingMealId` (insert path).

### Scan flow ("both")
1. Scan → OCR reads **date** + **amount**.
2. Quick popup: **"Which meal? Breakfast / Lunch / Dinner."**
3. Review screen (`MealLogView`) loads the day's existing entry (if any), adds
   the scanned amount to the chosen slot, and attaches the receipt.
4. If the chosen slot already had an amount → **Add/Replace** prompt.
5. Save → update existing entry, or insert if none.

### Same-slot conflict
- Prompt: **"Lunch already has $15.00 — Add ($35.00) or Replace ($20.00)?"**
  Applies to the slot receiving the new scanned amount.

### Company rule
- Keep the existing day entry's **company**; if it has none, adopt the form's
  current selection. (Travel nurses are typically one assignment per day.)

### Reminder banner
- Info banner on the meal screen: **"MedMiles keeps one meal entry per day —
  double-check each amount is under the right meal (breakfast, lunch, dinner)."**

### Receipts
- Every added/scanned receipt re-associates to the day's single entry (reusing
  the existing `MealEditView` receipt re-association logic). History → tapping a
  day shows all of that day's receipts together.

## Out of scope (YAGNI)
- **No auto-merge of pre-existing duplicate rows.** This change prevents new
  duplicates only. A one-time "merge existing duplicates" pass can be added later
  if the user wants it.

## Affected files
- `ViewModels/MealViewModel.swift` — upsert/merge save; `meal(forDate:)` lookup.
- `Views/Meals/MealLogView.swift` — day-editor load on date change, slot popup
  integration, Add/Replace conflict prompt, reminder banner.
- `Views/Dashboard/ScannedReceiptReviewView.swift` — slot popup before the review
  screen; pass the chosen slot through.
- `Models/ScanPrefillData.swift` — already carries `mealSlot`; ensure it is set
  from the popup.

## Testing
- Scan two same-day meal receipts (lunch + dinner) → one June 22 entry, both
  receipts attached, amounts in the correct slots.
- Scan two same-day **lunch** receipts → Add/Replace prompt; Add sums to $35 and
  keeps both receipts.
- Manual: enter a meal for a date that already has one → form loads the existing
  entry; saving edits the single entry (no duplicate).
- Different days → separate entries (unchanged).
