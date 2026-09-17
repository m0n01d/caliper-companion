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
- `capture-file-<kind>` — the `<input type="file" capture="environment">` for that face kind, always
  in the DOM (one per kind, regardless of which chip is selected or whether a dialog is open)
- `library-file-<kind>` — the library picker input (no `capture` attribute), same "always present" rule
- `recapture-confirm` / `recapture-keep` / `recapture-cancel` — replace-image dialog
- `capture-note` — the one-line explanation shown when camera access is unavailable
- `capture-kinds` — the Top/Side/End/Detail chip row (design wave 2, DESIGN.md §11.2)
- `capture-level` — the live level-readout pill next to the shutter, present only when the device
  orientation sensor has reported a sample and permission wasn't denied (design wave 2)

## Annotate (`#/parts/:id/faces/:faceId`)
- `annotate-canvas` — the `<canvas>`. Carries live attributes for tests: `data-transform="scale,tx,ty"`
  (oriented-image px → canvas CSS px: `screen = img * scale + t`) and `data-image-size="WxH"` (the
  oriented bitmap, e.g. `1200x1600` for the EXIF-rotated `end.jpg`). Screen point of a normalized
  `(nx, ny)` = `canvasBox.xy + (nx*W, ny*H) * scale + (tx, ty)`.
  `data-autofit` (SPEC §8a A6) is `fitting` while the view animates (the fit after p2, or the
  restore after Save/Clear/Delete), `fitted` once the pair is fitted, `touched` after the user
  zoomed/panned during the fitted state, `none` otherwise. While `fitting`, `data-transform`
  reports the animation's **end state**, and a `pointerdown` completes the animation before the
  tap is interpreted — so a tap computed from the attribute lands where it says. Wait for
  `data-autofit` to leave `fitting` before reading geometry you will compare later (`zoom` and the
  pixels lag until then). `page.emulateMedia({reducedMotion: 'reduce'})` makes the animation
  instant.
- `pending-points` — hidden readout of the pending/selected endpoints, `x1,y1;x2,y2` normalized to 4 dp
  (`x1,y1` with only p1 placed; empty when none)
- `dimension-count` — readout of the number of saved dimensions on this face
- `dimension-points` — hidden readout of every saved dimension's endpoints, `id:x1,y1;x2,y2|…`
  normalized to 4 dp (ids contain a colon — split each entry at its last one). `aria-busy="true"`
  while a drag's Store write is in flight (SPEC §8a A1: a drag on a saved handle or line body
  persists on release; wait for `aria-busy="false"` before reloading)
- `zoom` — readout of `scale / fitScale` to two decimals · `zoom-in` / `zoom-out` — ×1.5 about the
  canvas centre (Playwright can't pinch; pinch is Pointer Events on device)
- `reading` — reading text input (`inputmode="decimal" enterkeyhint="next"`) · `reading-error` ·
  `reading-units` — the part's units label next to it
- `name` — feature-name input (`enterkeyhint="done"`) · `name-error` · `name-chip` — suggestion chips
  in `FeatureName.suggestions` order (tap fills the name)
- `kind-<length|diameter|depth>` — segmented control buttons, `aria-pressed` on the active one
- `tolerance` — tolerance input (defaults to the part-units last-used tolerance) · `tolerance-error`
- `save` — save/update button (disabled until p1, p2, a valid reading, name and tolerance exist) ·
  `delete` — present only while an existing dimension is selected · `cancel` — clears the entry in
  progress (points, reading, name; keeps kind and tolerance) and deselects
- `annotate-error` — inline Store failure message · `annotate-missing` — the not-found message
- `annotate-live` — visually hidden `aria-live="polite"` line, "Dimension saved: name value unit" after a
  save (DESIGN.md §9); empty until then and cleared when a new p1 is placed
- Focus order (the keyboard-wedge seam): p2 placed → `reading` (performed by the canvas `click` that
  follows the tap, so iOS opens the keyboard — SPEC §8a A2); Enter in `reading` → `name`; Enter in
  `name` → Save → `annotate-canvas`.

## Settings (`#/settings`)
- `wedge-toggle` — "Readings come from a wedge dongle" checkbox

## Debug (`#/debug`)
- `timer-row` — one per recorded timer · `export-csv` — CSV download button
