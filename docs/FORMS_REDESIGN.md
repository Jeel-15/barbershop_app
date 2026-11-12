# Forms redesign (2026-11-05)

Client feedback: forms should be easier to read and fill, mistakes should be easy
to find, and an invoice or booking should be checked before it is saved.

## Research used

- Mobbin: Shopee, Whatnot, Depop, PayPal, Beside (add product forms: grouped
  sections, photo tile first, red required star, `$` in price, counter, sticky
  Save); Instacart, Depop, foodpanda, IMDb (error under the field, red border,
  clear x); Rocket Money, Wabi, HBO Max, Yami (profile forms in cards).
- Web: Baymard / UXPin. Label above the field (kept), judge a field when the
  person leaves it (not while typing), an error disappears the moment it is
  fixed, the message sits under the field, and submit still checks everything.

## What is in the design system (`lib/design_system/components`)

| Piece | What it does |
|---|---|
| `AppTextField` | Red `*` when the label ends in `*` (the web's wording stays). Units drawn as `prefixText` (`$`) / `suffixText` (`min`, `%`). `clearable` x, `showCounter`, and `validator` that runs on the first blur, then on every change. A server `errorText` always wins. |
| `FieldLabel` | The label with the red star, for fields that are not text fields (chips, photo). |
| `FormSection` / `FormRow` / `SwitchTile` | A titled card of fields, two short fields side by side, a plain on/off row with a grey hint line. |
| `FormPageFrame` + `FormActionBar` | Back button and title, the form, a button bar pinned above the keyboard. `dirty: true` makes Back (button or phone) ask "Discard changes?". |
| `scrollToFirstError` | After a failed Save: scroll to the first field with an error and nudge the phone. The form list needs a large `scrollCacheExtent` so every section is built. |
| `ImagePickField(compact: true)` | A dashed 104 px tile with the words beside it. |
| `showReviewSheet` | "Check before you save": sections, warnings, total, and **Edit** / **Done**. Edit (or dragging down, or Back) answers false and leaves the form untouched. |

## Forms moved to the new frame

Service, Product, Testimonial, Staff, Role (Cancel + Submit), My Profile (edit
card), Shop Settings (General, Contact), Customer sheet, GST, Category and the
booking form's customer card got the field upgrades (icons, units, clear).
Invoice and booking forms keep their own layout and gained the review step.

## Review before save

- **Invoice**: the bottom button reads "Review invoice" / "Review & complete" /
  "Review changes". The sheet lists customer, services, products, amounts (discount,
  tax, tip), payment and the total. Warnings: total is $0, no customer (walk-in),
  discount of 25% or more, tip over 40% of the bill.
- **Appointment**: "Review appointment" / "Review changes". The sheet lists
  customer, services (qty, minutes), barber, date, time, duration, notes and the
  total. Warnings: date in the past, or a time already passed today.
- Both read the **current** state when pressed (not the state of the last build),
  and take focus off the last field when the sheet closes.

## Demo tour

Beats `c04_17` (booking) and `c06_16` (invoice) now press Review, wait, then Done;
the Staff Calendar beats were changed earlier. `coverage.json` keywords follow.
