# Caliper Companion — DESIGN.md (handoff for Claude Code)

Companion to `SPEC.md`. The spec says what to build; this says what it looks like and how it feels. Reference mocks: the six-screen canvas at https://claude.ai/artifact/6VxQE92DMrsGfyJSQG4eDB (Parts → Capture → Dimension → Part → Export → Calipers). Function first — where this doc and the spec's acceptance criteria conflict, the spec wins; where this doc and Ternpike's theme conflict, this doc wins for this app.

## 1. Principles

- **Shop UI.** Dark, high-contrast, glove-tolerant. The phone sits on a bench next to a caliper; the user glances, taps once, looks back at the part.
- **Two accents, two meanings.** Amber = something you can tap on the photo (handles, dimension lines, primary buttons). Teal = something live or verified (connected instrument, reconciled feature, the last saved dimension). Never mix them.
- **The photo is a sketch, not a measurement.** Overlays must look drawn-on, not "scanned": pills behind text, dashed extension lines, chunky handles. Nothing should imply precision the pixels don't have.
- **Hands stay on the part.** Every capture-loop action is reachable with a thumb in the bottom 60% of the screen; the reading and name fields sit directly under the photo, never in a modal.
- **No fake chrome.** Real buttons, real inputs, real labels. Nothing that looks tappable and isn't.

## 2. Design tokens

Add these to Ternpike's token file under a `cc-` prefix (or a separate theme scope) rather than overriding Ternpike's own values.

| Token | Value | Usage |
|---|---|---|
| `cc-ground` | `#17181A` | page background |
| `cc-surface` | `#232527` | cards, list rows, panels |
| `cc-surface-2` | `#2C2F32` | thumbnails, nested chips, table header |
| `cc-field` | `#1E2022` | input backgrounds, segmented control unselected |
| `cc-border` | `#34373B` | 1px borders, dividers, dashed placeholders |
| `cc-text` | `#F4F2EC` | primary text (warm off-white) |
| `cc-text-2` | `#B9B5AB` | secondary text, labels — 8.7:1 on ground, 7:1 on surface |
| `cc-text-3` | `#8F8B81` | tertiary/muted, ≥ 4.6:1 on surface only; never on `cc-surface-2` |
| `cc-amber` | `#F2A33A` | tappable overlays, primary buttons, links |
| `cc-amber-ink` | `#2B1A02` | text on amber |
| `cc-teal` | `#4FD1B1` | live/verified states, saved dims on canvas |
| `cc-teal-wash` | `#163B33` | teal badge/banner background |
| `cc-teal-ink` | `#CFF5EA` | text on teal wash |
| `cc-teal-border` | `#1F4A41` | border for teal wash cards |
| `cc-error` | `#F26B4E` | invalid input border and inline message; text on it `#2B0E08` |
| `cc-photo-mat` | `#2A2C2F` | canvas background behind letterboxed photos |
| `cc-scrim` | `#1A1B1DCC` | translucent pills over the photo |

Typography (Google Fonts, self-host in the PWA precache; never render text before fallback fonts are declared):

| Token | Value | Usage |
|---|---|---|
| `cc-font-display` | `"Space Grotesk", "IBM Plex Sans", system-ui, sans-serif` · 600 | screen titles (18px), Parts title (30px) |
| `cc-font-body` | `"IBM Plex Sans", "Helvetica Neue", system-ui, sans-serif` · 400/500/600 | everything else |
| `cc-font-mono` | `"IBM Plex Mono", ui-monospace, Menlo, monospace` · 400/500 | readings, feature names, values, JSON |
| `cc-size-reading` | 38px / 1.0 / mono 500 | the live reading |
| `cc-size-title` | 18px / 1.2 / display 600 | nav title |
| `cc-size-body` | 15px / 1.5 | inputs, list rows, buttons |
| `cc-size-small` | 13px / 1.45 | secondary lines, helper text |
| `cc-size-caption` | 12px / 1.4 | field labels, chips |
| `cc-size-micro` | 11px / uppercase / 0.04em | table headers only |

Spacing and shape:

| Token | Value |
|---|---|
| `cc-space-1..6` | 4 / 8 / 12 / 16 / 20 / 24 px |
| `cc-page-x` | 20px horizontal page padding |
| `cc-radius-sm` | 10px (small buttons) |
| `cc-radius` | 12px (inputs, chips, list rows) |
| `cc-radius-lg` | 14px (cards, primary buttons) |
| `cc-radius-photo` | 16px (canvas container) |
| `cc-tap-min` | 44px — every interactive element; shutter 76px; canvas handles 44px hit area on a 22px visual |

## 3. Layout

- Single column, portrait. Design width 390; must hold from 360 to 430 without horizontal scroll.
- Page: `min-height: 100dvh`, `padding: env(safe-area-inset-top) cc-page-x calc(cc-space-5 + env(safe-area-inset-bottom))`.
- Nav row: 44px back button (icon only, `aria-label`), title + one-line subtitle, optional trailing text action ("Done"). No fake status bar, no system-style large titles.
- Photo canvas: full content width (350 at 390), fixed aspect from the image, letterboxed on `cc-photo-mat`, 16px radius, overflow hidden. On Dimension it's capped at 290–300px tall so the reading and name fields stay visible above the keyboard.
- No `position: fixed` bars over the canvas. The Save button scrolls with content; when the software keyboard is up, use `visualViewport` to keep the focused field in view.

## 4. Components

| Component | Spec | Notes |
|---|---|---|
| Primary button | 52px min height, `cc-amber` bg, `cc-amber-ink` text 15–16px/600, `cc-radius-lg`, full width or flex-grow | "Save dimension", "Export", "New part" (44px variant with icon) |
| Secondary button | same size, `cc-surface` bg, 1px `cc-border`, `cc-text` 500 | "Add dimension", "Share", "Import photo" |
| Small button | 40–44px, `cc-field` bg, 1px `cc-border`, 13–14px | "Hold", "Type", "Zero", "Disconnect" |
| Chip (selectable) | 44px pill (36px for name suggestions), `cc-surface` + border; selected = `cc-amber` bg + ink text | Face picker, name suggestions (mono 12px) |
| Segmented control | 44px, 1px border container, `cc-radius`; selected segment `cc-amber` | Kind: Length / Diameter / Depth |
| Text input | 44px, `cc-field` bg, 1px `cc-border`, `cc-radius`, 14px side padding, 15px text; mono for numeric/name fields; label above at `cc-size-caption` in `cc-text-2` | `inputmode="decimal"` for readings; never `type="number"` |
| List row (Part) | 14px padding, `cc-surface`, `cc-radius-lg`, 52px thumbnail on `cc-surface-2`, name 16/500, meta 13 `cc-text-2`, chevron `cc-text-3` | Meta line turns `cc-amber` for "in progress" |
| Status bar (Calipers) | 52px, `cc-surface`, 10px status dot (`cc-teal` connected / `cc-text-3` none), trailing "Change" in `cc-text-2` | v0: shows "Keyboard" and the wedge toggle state |
| Reading panel | `cc-surface` card, 14/16px padding; label 12px `cc-text-2`; value `cc-size-reading` mono + unit 14px `cc-text-2`; right column badge + two small buttons | Badge: `cc-teal-wash` bg, `cc-teal` text 12/500, 7px dot. v0 badge text: "KEYBOARD" or "WEDGE" per toggle |
| Features table | `cc-surface` card; 4-col grid (name mono / value mono right / tol `cc-text-2` right / face `cc-text-2` right); 9px row padding; header `cc-size-micro` | Face cell `cc-teal` when the feature spans faces |
| Warning row (teal) | `cc-teal-wash` bg, `cc-teal-border`, check icon, 13px `cc-teal-ink` | reconciliation note |
| Warning row (error) | same shape, `cc-error` at 20% wash, `cc-error` border | kind conflict (blocks export) |
| Thumbnail slot | 56px, `cc-radius-sm`; captured = `cc-surface-2` + 2px `cc-teal` border; empty = 2px dashed `cc-border` | Capture screen faces row |
| Scrim pill | `cc-scrim` bg, 12–13px, 5–6px × 10–12px padding, 12–14px radius | over-photo hints, level readout (mono, `cc-teal`) |
| Shutter | 76px circle, `cc-amber` fill, 4px `cc-text` ring, centered, `aria-label="Capture this face"` | In the PWA this is a styled `<label>` for the file input |

## 5. Photo overlay drawing rules (canvas)

Everything is drawn in CSS pixels on a canvas scaled to the container; recompute on zoom. Stroke widths are in screen pixels, not image pixels.

| Element | Spec |
|---|---|
| Handle (active) | 22px circle: `cc-text` fill, 3px `cc-amber` stroke, 6px `cc-amber` center dot. Hit area 44px. |
| Dimension line (active) | 2px `cc-amber`, arrowheads 10×10 triangles at both ends |
| Extension lines | 1.5px `cc-amber`, dash 4/3, from the tap point to 6px past the dimension line |
| Value pill (active) | `cc-amber` fill, 28px tall, 14px radius, mono 15/500 `cc-amber-ink`, centered on the line, 8px clearance from the line on the outside |
| Saved dimension | same geometry at 60% opacity, `cc-teal` instead of amber, pill `cc-scrim` with `cc-teal` mono 12px text `name value` |
| Selected saved dimension | full opacity teal, handles visible and draggable |
| Diameter kind | draw a dashed 1.5px circle through p1–p2 as diameter instead of a line; pill reads `⌀ value` |
| Depth kind | line as Length, pill prefixed `↓` |
| Placement hint | scrim pill top-left: "Tap the first edge" → "Tap the second edge" → "Read the caliper" |

Export PNG uses the same rules at image resolution: stroke 0.15% of the long edge (min 2px), pill height 2% of image height, label font 1.4% of image height.

## 6. States and interactions

| Element | State | Behavior |
|---|---|---|
| Primary button | pressed | background `#DB8F2A` (amber −10% L), no scale, 80ms |
| Primary button | disabled | 40% opacity, `aria-disabled`, still focusable so the reason can be read |
| Text input | focus | 2px `cc-amber` outline offset 0, border stays |
| Text input | invalid | border `cc-error`, 12px message below in `cc-error`; Save disabled until fixed |
| Reading field | Enter | focus → name field |
| Name field | Enter | Save (if valid) |
| Name chip | tap | fills the name field, does not save |
| Face chip | tap | switches face; if the face has no image, opens capture |
| Canvas | tap (no active dim) | places p1; second tap places p2; a third tap starts a new dimension only after Save or Cancel |
| Canvas | drag on handle | moves that point; 44px hit area wins over pinch |
| Canvas | pinch / two-finger pan | zoom 1×–5×, centered on the pinch; single-finger pan only when zoomed |
| Canvas | tap on saved dimension | selects it; Save button becomes "Update", a "Delete" small button appears |
| Save | tap | writes, clears reading and name, keeps kind and tolerance, focus returns to canvas, hint resets |
| Export | tap with kind conflict | blocked; error row scrolls into view |
| Warning row | tap | scrolls the features table to the flagged rows |

Motion: keep it to opacity and position, 120–160ms, `cubic-bezier(0.2, 0, 0, 1)`. Handles appear with a 120ms scale-from-0.6. Nothing bounces. Respect `prefers-reduced-motion` by dropping transitions to 0ms.

## 7. Content rules

- Feature names: mono, never truncated; the field wraps if needed.
- Part names: single line, ellipsis at the end, 60-char limit in the input.
- Numbers: always show two decimals in mm, three in inches; units after the value in `cc-text-2`.
- Empty Parts list: one line of copy ("A part is a set of photographed faces.") and the primary button; no illustration.
- Empty face on Dimension: don't show the screen — route to Capture.
- Loading: the only real load is image decode; show the photo mat with a centered 13px "Decoding…" pill, no spinner.
- Errors: inline, one sentence, no toasts, no modals. Permission denial gets a one-sentence explanation and the alternative action right there.

## 8. Edge cases

- Landscape: lock to portrait via manifest `orientation: "portrait"`; if the browser ignores it, the layout still works, just tall.
- Very long parts lists: virtualize after 100; v0 can ignore.
- Photo aspect extremes (panorama, square): letterbox on the mat; never crop.
- 360px-wide phones: face chips shrink to 40px height; the reading value drops to 32px.
- Keyboard up on Dimension: the photo canvas may scroll out of view; the reading and name fields must stay visible. Don't try to keep both.
- Dynamic Type / browser zoom at 120%: everything must still fit without horizontal scroll; the features table may wrap the face column.

## 9. Accessibility

- Focus order on Dimension: back → face title → canvas (as a group with `role="img"` and `aria-label` describing dims count) → reading → Hold/Type → name → chips → kind → tolerance → Save → saved dims list.
- Every icon-only control has an `aria-label`. The shutter announces "Capture this face".
- Live region (`aria-live="polite"`) announces "Dimension saved: overall_l 42.18" after Save.
- Color is never the only signal: flagged features also carry a check/warning icon; invalid inputs also carry text.
- Contrast: all text pairs listed in §2 meet 4.5:1; amber-on-ground is used for text only at 15px+/500 (it's 8.6:1) — never for 12px captions.

## 10. What the mocks don't settle (decide when you get there)

- Whether the Calipers screen exists in v0 at all — with the keyboard wedge it may collapse to a single toggle in Settings. Recommendation: collapse it.
- Icon set: the mocks use hand-drawn inline SVG. Use a single consistent set (Tabler or Lucide, outline, 2px) and stop.
- Light mode: not designed. Ship dark only; add `color-scheme: dark` to the root so form controls match.
