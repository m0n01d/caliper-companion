# `data-testid` contract

Playwright specs written by one page's author drive other pages through these ids. Keep them
stable; add to this list before you rely on a new one.

## Parts list (`#/`)
- `new-part` — creates a part. Exactly one of these exists at a time: the empty state's body
  capsule (list empty) or the bar's trailing 44 px icon button, `aria-label="New part"` (list
  non-empty) — never both (P2a, review-2026-09-17.md P3)
- `parts-edit` — the bar's trailing "Edit" / "Done" text action; present once the list is
  non-empty. Out of edit mode a row is purely navigational (chevron only); in edit mode each row
  also shows `part-rename` (icon button, `aria-label="Rename"`) and `part-delete` (P2a,
  review-2026-09-17.md P1 — these used to be permanent per-row icon buttons)
- `part-name` — text input · `part-units` — `<select>` with `mm` / `in` · `part-create` — submit
- `part-row` — one per part in the list (contains the name and a 72 px first-face thumbnail);
  `part-rename`, `part-delete` inside a row, only in edit mode (see `parts-edit`)
- `part-rename-input`, `part-rename-save`, `part-rename-cancel` — inline rename form (shown in place
  of a row's normal contents after `part-rename`)
- `part-delete-confirm`, `part-delete-cancel` — inline confirm strip (shown after `part-delete`)
- `parts-empty` — the empty state
- `parts-live` — visually hidden `aria-live="polite"` line (design wave 3b, DESIGN.md §9): "Part
  created" / "Part deleted"; empty otherwise
- `parts-search` — the `<input type="search" inputmode="search" enterkeyhint="search">` above the
  list (SPEC §8a A10), present once the list is non-empty and the create form is closed; live,
  case-insensitive filter on name or folder path (stored or display form), sections preserved ·
  `parts-search-clear` — the page's own 44 px clear icon button (`aria-label="Clear search"`),
  present only while the query is non-empty; clearing refocuses the field ·
  `parts-search-empty` — the one Footnote line `No parts match "<q>".` when nothing matches
- `parts-section` — one `role="list"` container per folder section, root first (only while the
  root has parts), then folders sorted case-insensitively; each holds its `part-row`s ·
  `parts-section-header` — the section's `<h2>`, text `"<display path> · <count>"` (e.g.
  `Miata / Interior · 2`; rendered uppercase by `.list-group-header`, so `textContent` is the
  mixed-case spelling and `innerText` the uppercase one). **Absent for the root section**, so a
  list with no folders has zero headers
- `part-folder-row` — the **Folder row** (SPEC §8a A12a) in **both** the create form (a `list-row`
  `<button>` with a chevron: title "Folder", trailing value the chosen folder in display form —
  `Miata / Interior` — or `None` at root) and the inline rename strip (the same `<button>`, drawn
  as a field under a "Folder" label instead of a row). Tapping it opens the picker; Done and
  Cancel both return focus here. ~~`part-path`~~, ~~`part-path-chip`~~, ~~`part-path-error`~~ are
  retired — the free-text Folder field and its chips are gone
- **Folder picker** (A12a) — takes over the page while open (list, search, Edit/"+" hidden; the
  create form or the rename strip it came from is restored on return). Bar: `.shell-title` reads
  `Choose Folder` (centred Headline, no Large Title) between `folder-picker-cancel` (leading text
  action; replaces `settings-link` while open) and `folder-picker-done` (trailing) ·
  `folder-picker-list` — the one `role="listbox"` container · `folder-option` — one
  `<button type="button" role="option">` per row: root first (`data-path=""`,
  `aria-label="None, top level"`, visible "None" / "Top level"), then every folder as a flat tree
  (explicit folders ∪ the parts' paths ∪ their ancestors, depth-first, case-insensitive within a
  level) with `data-path="<stored path>"`, `aria-label="<display path>"` (`Miata / Interior`),
  visible text the leaf, `padding-left` = 16 + depth × 20 px, `aria-selected` truthful, a Check
  glyph on the selected row; a tap selects (no navigation); opening focuses the selected option ·
  `folder-new` — the secondary "New Folder" capsule under the list, `aria-disabled` (with the
  Footnote `folder-new-depth`, "Folders go six deep.") once the selection is six deep ·
  `folder-new-name` — the inline one-segment input it reveals (`autocapitalize="words"
  autocorrect="off" enterkeyhint="done"`, placeholder `Folder name`, focused on open; Enter
  creates) · `folder-new-create` (primary, `aria-disabled` while empty or invalid) ·
  `folder-new-cancel` (focus back to `folder-new`) · `folder-new-error` — the inline rule once
  the field holds something invalid (`a/b`, `?`, > 32 chars). Create = `Folder.join` under the
  selection, `Folder.snap` against the listed paths (`interior` under `Miata` selects the
  existing `Interior`, no twin), `Store.ensureFolder`; the result becomes the selection and takes
  focus. A folder created here is a real `folder:` doc even if the picker is then Cancelled

## Part (`#/parts/:id`)
- `.shell-subtitle` (a class, not a testid — `Shell.res` owns it) — the part's folder path in
  display form (`Miata / Interior`, SPEC §8a A10); **absent** for a root part. The features group
  header (`features-list`) reads `Features · n` — a count only
- `face-<label>` — one per captured face (P2a: a 171 px `Ui.FaceCard`, 2-column grid, links to
  annotate). `<label>` is the face's label (SPEC §8a A7): `top|side|end|detail` for the four
  defaults (so `face-top` etc. are unchanged), the custom slug otherwise (`face-left_side`).
  Contains the label and the `W × H · n dim(s)` caption text
- `capture-face` — the empty "Capture" card, links to the capture page
- `faces-edit` — the bar's trailing "Edit" / "Done" text action (P2a — this used to be a lone
  in-body "Edit faces" capsule); present once the part has a face. In edit mode the grid becomes a
  list (`faces-edit-list`) whose rows keep the `face-<label>` id and each hold a `face-remove`
  button; tapping it shows the inline confirm `face-delete-confirm` / `face-delete-cancel`
  (deleting a face removes its dimensions)
- `features-list` — the `role="list"` container of `feature-row`s (P2a — this used to be a
  `role="table"`)
- `feature-row` — one per reconciled feature, `role="listitem"`, accessible name
  `"<name>, <value> <unit>, ± <tol>, faces <labels>"` (P2a — this used to be a `<tr>` with 4
  `role="columnheader"` siblings; there is no column header row any more, the features group
  header carries the unit instead)
- `warning-row` — present only when a feature is flagged or a kind conflict exists
- `export` — the export button · `export-error` — inline message when export is blocked
- `timer` — hands-on timer readout
- `part-live` — visually hidden `aria-live="polite"` line (design wave 3b, DESIGN.md §9): "Export
  ready: <file>" / "Export shared" / "Export failed: …"; empty otherwise

## Capture (`#/parts/:id/capture`)
- `capture-file-<label>` — the `<input type="file" capture="environment">` for that face, always
  in the DOM (one per chip — the four defaults `top|side|end|detail` plus every custom face, captured
  or still only a chip — regardless of which chip is selected or whether a dialog/card is open)
- `library-file-<label>` — the library picker input (no `capture` attribute), same "always present" rule
- `capture-chip-<label>` — one `Ui.FaceCard` per face, in the face-card grid (design wave P2b
  "layout A", DESIGN.md §4/§11.2, docs/design/review-2026-09-17.md §3/§4; agent/facecard-fix gave
  `Ui.FaceCard` a state-driven ring on `image=None` cards too): captured = thumbnail + live check
  badge; the selected one additionally gets the accent ring (both signals together when a captured
  face is also selected); a *selected but uncaptured* kind now also gets the accent ring on its
  plain dashed "Empty" look (the dashed border itself drops while selected — a solid ring replacing
  a dashed one would otherwise double up); uncaptured-and-unselected stays the plain dashed "Empty"
  look. Tapping a card selects it as the shutter/library target. `aria-pressed` (`true` for the
  selected chip, `false` otherwise) states the same signal `Ui.FaceCard`'s `~ariaPressed` now
  exposes; the card's accessible name (`"<label> — captured|not captured[, selected]"`) still
  carries it too, kept alongside rather than replaced (DESIGN.md §9 "color is never the only
  signal" — belt-and-suspenders for screen readers, not redundant noise)
- `custom-face` — the "+ Custom" card, last in the grid (SPEC §8a A7; `Ui.FaceCard` `Empty` look
  with `~icon=Plus`, label text "Custom" — the "+" is the icon now, not baked into the string)
  opens the inline card `custom-face-card`: `custom-face-label` (mono name input,
  `enterkeyhint="done"`, Enter adds) · `custom-face-error` (inline validation: feature-name rule +
  unique among this part's faces and chips) · `custom-face-plane-<top|side|end|detail>`
  (sketch-plane segmented control, `aria-pressed`) · `custom-face-add` (primary, `aria-disabled`
  until the name is valid) · `custom-face-cancel`
- `custom-face-remove` — small 24 px round button, present only while the selected chip is a custom
  one with no face yet; removes the chip (a captured face is deleted from the Part page instead).
  Sits on that chip's own face-card now (agent/facecard-fix: `Ui.FaceCard` grew `~badge`/`~caption`
  slots on `Empty` cards, not just captured ones), in the same top-right spot the captured check
  badge uses — a real `Ui.Button`, a DOM sibling of the card's own `<button>` rather than nested
  inside it (Capture.res's `faceGrid`, `.face-card-holder` in Capture.css positions it)
- `recapture-confirm` / `recapture-keep` / `recapture-cancel` — replace-image dialog
- `capture-note` — the one-line explanation shown when camera access is unavailable; the last
  element in `.capture-action`'s bottom-anchored group (design wave P2b), so it sits directly under
  whichever of the shutter/recapture/custom-face block is showing
- `capture-kinds` — the face-card grid container (design wave P2b; carried over from the old chip
  row's id — nothing in the e2e suite reads it, kept for continuity). `.face-grid-dense` (3-up) once
  there are ≥ 5 chips (not counting the trailing "+ Custom" cell)
- `capture-level` — the live level-readout pill next to the shutter, present only when the device
  orientation sensor has reported a sample and permission wasn't denied (design wave 2)
- `shutter` — the 76 px amber shutter `<label>` itself, inside `.capture-action` (design wave P2b:
  `.capture-page { min-height: 100% }` + `.capture-action { margin-top: auto }` anchor the whole
  shutter/recapture/custom-face block — and the camera note after it — to the bottom of the
  content, DESIGN.md §1 "hands stay on the part"); `tabIndex={-1}` (design wave 3b), a
  programmatic-only focus target — a `<label>` isn't natively focusable — used to return focus here
  after the recapture card's Cancel closes it, DESIGN.md §9
- `capture-live` — visually hidden `aria-live="polite"` line (design wave 3b, DESIGN.md §9): "Face
  captured: <label>"; empty otherwise

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
  `data-snap` (SPEC §8a A5) is `on|off` — the Snap pill's state. `data-snapped` is `"p1,p2"` as two
  booleans (`true,false` after a first tap that snapped); `false` for a point the user dragged (a
  drag pins it: no later tap re-snaps it) and always for a saved dimension's points.
  `data-selected` (SPEC §8a A9) is the id of the dimension being edited — the one a canvas tap or a
  `dimension-row` tap selected — and empty when none is.
- `snap-toggle` — the Snap pill in the toolbar (a button, `aria-pressed`), SPEC §8a A5. On by default,
  persisted as `settings.snap` — the same field as Settings' `snap-setting-toggle`. With it on, the
  first tap moves to the strongest edge within a fingertip (16 px, then 24 px) unless the tap already
  sits on an edge; the second tap snaps both ends along the p1→p2 segment. `pending-points` reports
  the snapped values. Reduced motion skips the 150 ms snap ring.
- `pending-points` — hidden readout of the pending/selected endpoints, `x1,y1;x2,y2` normalized to 4 dp
  (`x1,y1` with only p1 placed; empty when none)
- `dimension-count` — readout of the number of saved dimensions on this face
- `dimension-points` — hidden readout of every saved dimension's endpoints, `id:x1,y1;x2,y2|…`
  normalized to 4 dp (ids contain a colon — split each entry at its last one). `aria-busy="true"`
  while a drag's Store write is in flight (SPEC §8a A1: a drag on a saved handle or line body
  persists on release; wait for `aria-busy="false"` before reloading)
- `dimension-list` — the inset grouped list of this face's saved dimensions under the panel (SPEC
  §8a A9), in creation order; `role="list"` once it has rows · `dimension-row` — one `<button>` per
  dimension, `data-id="<dimension id>"`, `aria-selected="true"` on the one being edited (mirrors the
  canvas selection either way round), accessible name `<name>, <value> <unit>, <kind>`. A tap selects
  it exactly as a canvas tap does (fields fill, `save` reads "Update", `delete` appears, A6 fits the
  view to its segment); a tap on the selected row deselects as `cancel` does. Focus stays on the row
  after either tap. A canvas selection scrolls its row into view (`scrollIntoView` `nearest`, instant
  under reduced motion) · `dimension-empty` — the Footnote "No dimensions on this face yet." inside
  `dimension-list` while the face has none
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
- `settings-link` — the gear in the Parts root bar's leading slot (`aria-label="Settings"`), the only way
  in from an installed app
- `wedge-toggle` — "Readings come from a wedge dongle" checkbox
- `debug-link` — the Diagnostics row (anchor inside) that opens `#/debug`; Debug's Back returns here
- `snap-setting-toggle` — "Snap taps to edges" checkbox (SPEC §8a A5; the annotate toolbar's
  `snap-toggle` flips the same `settings.snap`)

## Debug (`#/debug`)
- `timer-row` — one per recorded timer · `export-csv` — CSV download button
