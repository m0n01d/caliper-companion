# `data-testid` contract

Playwright specs written by one page's author drive other pages through these ids. Keep them
stable; add to this list before you rely on a new one.

## Parts list (`#/`)
- `new-part` — button that opens the create form
- `part-name` — text input · `part-units` — `<select>` with `mm` / `in` · `part-create` — submit
- `part-row` — one per part in the list (contains the name); `part-rename`, `part-delete` inside a row
- `part-rename-input`, `part-rename-save`, `part-rename-cancel` — inline rename form (shown in place
  of a row's normal contents after `part-rename`)
- `part-delete-confirm`, `part-delete-cancel` — inline confirm strip (shown after `part-delete`)
- `parts-empty` — the empty state

## Part (`#/parts/:id`)
- `face-<kind>` — one per captured face (`top|side|end|detail`), links to annotate
- `capture-face` — link/button to the capture page
- `feature-row` — one per reconciled feature (name, value, tolerance, faces)
- `warning-row` — present only when a feature is flagged or a kind conflict exists
- `export` — the export button · `export-error` — inline message when export is blocked
- `timer` — hands-on timer readout

## Capture (`#/parts/:id/capture`)
- `capture-file-<kind>` — the `<input type="file" capture="environment">` for that face kind
- `library-file-<kind>` — the library picker input (no `capture` attribute)
- `recapture-confirm` / `recapture-keep` / `recapture-cancel` — replace-image dialog
- `capture-note` — the one-line explanation shown when camera access is unavailable

## Annotate (`#/parts/:id/faces/:faceId`)
- `annotate-canvas` — the `<canvas>`
- `reading` — reading text input (`inputmode="decimal"`) · `reading-error`
- `name` — feature-name input · `name-error` · `name-chip` — suggestion chips
- `kind-<length|diameter|depth>` — segmented control buttons
- `tolerance` — tolerance input
- `save` — save button · `delete` — delete selected dimension
- `zoom` — hidden readout of the current zoom factor (text), for tests

## Settings (`#/settings`)
- `wedge-toggle` — "Readings come from a wedge dongle" checkbox

## Debug (`#/debug`)
- `timer-row` — one per recorded timer · `export-csv` — CSV download button
