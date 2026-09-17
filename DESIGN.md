# Caliper Companion — DESIGN.md (handoff for Claude Code)

Companion to `SPEC.md`. The spec says what to build; this says what it looks like and how it feels. Reference mocks: the six-screen canvas at https://claude.ai/artifact/6VxQE92DMrsGfyJSQG4eDB (Parts → Capture → Dimension → Part → Export → Calipers). Function first — where this doc and the spec's acceptance criteria conflict, the spec wins; where this doc and Ternpike's theme conflict, this doc wins for this app.

## 1. Principles

- **Shop UI.** Dark, high-contrast, glove-tolerant. The phone sits on a bench next to a caliper; the user glances, taps once, looks back at the part.
- **Two accents, two meanings.** Orange = something you can tap on the photo (handles, dimension lines, primary buttons). Blue = something live or verified (connected instrument, reconciled feature, the last saved dimension). Never mix them.
- **The photo is a sketch, not a measurement.** Overlays must look drawn-on, not "scanned": pills behind text, dashed extension lines, chunky handles. Nothing should imply precision the pixels don't have.
- **Hands stay on the part.** Every capture-loop action is reachable with a thumb in the bottom 60% of the screen; the reading and name fields sit directly under the photo, never in a modal.
- **No fake chrome.** Real buttons, real inputs, real labels. Nothing that looks tappable and isn't.

## 2. Design tokens

Add these to Ternpike's token file under a `cc-` prefix (or a separate theme scope) rather than overriding Ternpike's own values.

**Dark Sky palette** (applied 2026-09-17, design wave P1/`agent/p1-darksky`; see
`docs/design/palettes-2026-09-17.md`). v1.0 shipped a warm amber/teal pair under the token names
`cc-amber(-ink/-pressed)`/`cc-teal(-wash/-ink/-border)`; the values and names below replaced them
everywhere (`cc-accent*`/`cc-live*`) — no aliases were kept.

| Token | Value | Usage |
|---|---|---|
| `cc-ground` | `#15181D` | page background |
| `cc-surface` | `#20242A` | cards, list rows, panels |
| `cc-surface-2` | `#2A2F36` | thumbnails, nested chips, table header |
| `cc-field` | `#1B1F25` | input backgrounds, segmented control unselected |
| `cc-border` | `#343A43` | 1px borders, dividers, dashed placeholders |
| `cc-text` | `#EEF1F5` | primary text |
| `cc-text-2` | `#AFB7C1` | secondary text, labels — 8.4:1 on ground, 7.7:1 on surface |
| `cc-text-3` | `#87909B` | tertiary/muted, ≥ 4.8:1 on surface only; never on `cc-surface-2` |
| `cc-accent` | `#FF7F2A` | tappable overlays, primary buttons, links |
| `cc-accent-pressed` | `#FF6B00` | primary button pressed state (§6) |
| `cc-accent-ink` | `#2A1200` | text on accent |
| `cc-live` | `#5AC1F2` | live/verified states, saved dims on canvas |
| `cc-live-wash` | `#0E2D42` | live badge/banner background |
| `cc-live-ink` | `#CDEAF7` | text on live wash |
| `cc-live-border` | `#174A6B` | border for live wash cards |
| `cc-error` | `#F47070` | invalid input border and inline message; text on it `#2B0A0A` |
| `cc-photo-mat` | `#242930` | canvas background behind letterboxed photos |
| `cc-scrim` | `#171A1ECC` | translucent pills over the photo |

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
- Photo canvas: full content width (358 at 390 — 350 was stale from before the page margin moved to 16px, see §11.1 "Layout"), fixed aspect from the image, letterboxed on `cc-photo-mat`, 16px radius, overflow hidden. On Dimension it's capped at 290–300px tall so the reading and name fields stay visible above the keyboard.
- No `position: fixed` bars over the canvas. The Save button scrolls with content; when the software keyboard is up, use `visualViewport` to keep the focused field in view.

## 4. Components

| Component | Spec | Notes |
|---|---|---|
| Primary button | 52px min height, `cc-accent` bg, `cc-accent-ink` text 15–16px/600, `cc-radius-lg`, full width or flex-grow | "Save dimension", "Export", "New part" (44px variant with icon) |
| Secondary button | same size, `cc-surface` bg, 1px `cc-border`, `cc-text` 500 | "Add dimension", "Share", "Import photo" |
| Small button | 40–44px, `cc-field` bg, 1px `cc-border`, 13–14px | "Hold", "Type", "Zero", "Disconnect" |
| Chip (selectable) | 44px pill (36px for name suggestions), `cc-surface` + border; selected = `cc-accent` bg + ink text | Face picker, name suggestions (mono 12px) |
| Segmented control | 44px, 1px border container, `cc-radius`; selected segment `cc-accent` | Kind: Length / Diameter / Depth |
| Text input | 44px, `cc-field` bg, 1px `cc-border`, `cc-radius`, 14px side padding, 15px text; mono for numeric/name fields; label above at `cc-size-caption` in `cc-text-2` | `inputmode="decimal"` for readings; never `type="number"` |
| List row (Part) | 14px padding, `cc-surface`, `cc-radius-lg`, 72px thumbnail on `cc-surface-2` (first captured face, `cover`), name 16/500, meta 13 `cc-text-2`, chevron `cc-text-3` | Meta line turns `cc-accent` for "in progress"; rename/delete live behind the bar's Edit mode, not permanent per-row icon buttons (§11.2) |
| Status bar (Calipers) | 52px, `cc-surface`, 10px status dot (`cc-live` connected / `cc-text-3` none), trailing "Change" in `cc-text-2` | v0: shows "Keyboard" and the wedge toggle state |
| Reading panel | `cc-surface` card, 14/16px padding; label 12px `cc-text-2`; value `cc-size-reading` mono + unit 14px `cc-text-2`; right column badge + two small buttons | Badge: `cc-live-wash` bg, `cc-live` text 12/500, 7px dot. v0 badge text: "KEYBOARD" or "WEDGE" per toggle |
| Face card | Square, `(content − 16) / 2` wide (171px at 390, 156 at 360; 3-up `(content − 32) / 3` = 109px at ≥ 5 faces, `.face-grid-dense`), `cc-radius-card` 16, `cc-surface-2` bg, image `cover`; bottom scrim, label Headline 17/600 `cc-text`, caption Footnote 13 `cc-text-2` ("1600 × 1200 · 2 dims"); captured = 2px `cc-live` ring + 24px `cc-live` check badge top-right; selected (Capture's kind picker) = 2px `cc-accent` ring; empty ("+ Capture"/"+ Custom") = 2px dashed `cc-border`, centred 24px Camera icon + label. `Ui.FaceCard`, grid gap 16 (12 dense) | Replaces the old Thumbnail slot everywhere (Part's gallery, Capture's kind picker, Parts' first-face thumbnail); see §11.2 |
| Feature row | 3-col grid `minmax(0,1fr) auto auto`: name mono Body (wraps, `overflow-wrap: anywhere`, never truncates) with the faces as a Footnote line under it (`cc-text-2`; `cc-live` when the feature spans > 1 face) / value mono Body right + unit Footnote `cc-text-2` / "±0.10" mono Footnote `cc-text-2`; padding 12/8, outer 16; min 44px; no column header row; flagged = 16px triangle-alert `cc-error` before the name | Replaces the old 4-column Features table (name/value/tol/face, 9px padding, `cc-size-micro` header) |
| Warning row (live) | `cc-live-wash` bg, `cc-live-border`, check icon, 13px `cc-live-ink` | reconciliation note |
| Warning row (error) | same shape, `cc-error` at 20% wash, `cc-error` border | kind conflict (blocks export) |
| Scrim pill | `cc-scrim` bg, 12–13px, 5–6px × 10–12px padding, 12–14px radius | over-photo hints, level readout (mono, `cc-live`) |
| Shutter | 76px circle, `cc-accent` fill, 4px `cc-text` ring, centered, `aria-label="Capture this face"` | In the PWA this is a styled `<label>` for the file input |

## 5. Photo overlay drawing rules (canvas)

Everything is drawn in CSS pixels on a canvas scaled to the container; recompute on zoom. Stroke widths are in screen pixels, not image pixels.

| Element | Spec |
|---|---|
| Handle (active) | 22px circle: `cc-text` fill, 3px `cc-accent` stroke, 6px `cc-accent` center dot. Hit area 44px. |
| Dimension line (active) | 2px `cc-accent`, arrowheads 10×10 triangles at both ends |
| Extension lines | 1.5px `cc-accent`, dash 4/3, from the tap point to 6px past the dimension line |
| Value pill (active) | `cc-accent` fill, 28px tall, 14px radius, mono 15/500 `cc-accent-ink`, centered on the line, 8px clearance from the line on the outside |
| Saved dimension | same geometry at 60% opacity, `cc-live` instead of accent, pill `cc-scrim` with `cc-live` mono 12px text `name value` |
| Selected saved dimension | full opacity live, handles visible and draggable |
| Diameter kind | draw a dashed 1.5px circle through p1–p2 as diameter instead of a line; pill reads `⌀ value` |
| Depth kind | line as Length, pill prefixed `↓` |
| Placement hint | scrim pill top-left: "Tap the first edge" → "Tap the second edge" → "Read the caliper" |

Export PNG uses the same rules at image resolution: stroke 0.15% of the long edge (min 2px), pill height 2% of image height, label font 1.4% of image height.

## 6. States and interactions

| Element | State | Behavior |
|---|---|---|
| Primary button | pressed | background `cc-accent-pressed` (`#FF6B00`, the Fusion-icon orange itself), no scale, 80ms |
| Primary button | disabled | 40% opacity, `aria-disabled`, still focusable so the reason can be read |
| Text input | focus | 2px `cc-accent` outline offset 0, border stays |
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
- Contrast: all text pairs listed in §2 meet 4.5:1; accent-on-ground is used for text only at 15px+/500 (it's 7.1:1) — never for 12px captions.

## 10. What the mocks don't settle (decide when you get there)

- Whether the Calipers screen exists in v0 at all — with the keyboard wedge it may collapse to a single toggle in Settings. Recommendation: collapse it.
- Icon set: the mocks use hand-drawn inline SVG. Use a single consistent set (Tabler or Lucide, outline, 2px) and stop.
- Light mode: not designed. Ship dark only; add `color-scheme: dark` to the root so form controls match.

## 11. v1.1 — native feel: HIG + Liquid Glass reconciliation (2026-09-17)

Owner direction after the first phone dogfood: "modern Apple, Liquid Glass, a more native feel; not
ternpike's look." Research inputs: `docs/design/hig-brief.md` and `docs/design/liquid-glass-web.md`
(read them before touching styles). Where this section and §1–§10 differ, this section wins. Where
this section and `SPEC.md` acceptance criteria differ, the spec still wins.

### 11.1 Decisions

| Area | Decision | Why |
|---|---|---|
| Typeface | **System stack.** UI: `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`. Numbers/names: `ui-monospace, "SF Mono", Menlo, monospace`. No web fonts, nothing in the precache. | SF Pro is the single strongest native cue and costs zero bytes. Departs from §2's Space Grotesk / IBM Plex; the *scale* below is what carries the rhythm. |
| Type scale | HIG Dynamic Type "Large" step, in px: Large Title 34/41 bold (Parts root only) · Title 3 20/25 semibold · Headline 17/22 semibold (nav titles) · Body 17/22 · Callout 16/21 · Subhead 15/20 · Footnote 13/18 · Caption 1 12/16 · Caption 2 11/13. Reading value stays 38/1.0 mono 500. | `hig-brief.md` §1. Inputs are **≥ 16 px** always: iOS Safari zooms the page on focusing anything smaller. |
| Colour | Keep §2's dark `cc-` palette and the two-accent rule (accent = tappable, live = verified). **Dark only** for v1.1, `color-scheme: dark` on `:root`, `theme-color` = `cc-ground`. Logged as a named HIG departure (HIG expects both appearances; bench tool = the "rare case"). | `hig-brief.md` §3, §6. Two accents with fixed meanings is HIG-consistent; sprawl is the risk, so accent is limited to: the one prominent button per screen, canvas overlays, links. |
| Materials | **Glass in exactly one place: the navigation bar**, `position: sticky` inside the page scroll container, never `fixed`. Recipe and tokens from `liquid-glass-web.md` §3 (`--glass-*`, `-webkit-backdrop-filter` first, `@supports` fallback to opaque). Everything else opaque: lists, the annotate control panel, chips, segmented control, buttons. Over-photo pills stay flat `cc-scrim`. No glass over the canvas, ever. | Apple keeps glass out of content and input layers; blur over a repainting canvas is the documented worst case; Safari cannot report `prefers-reduced-transparency`, so surfaces must clear 4.5:1 on their own. |
| Shape | iOS 26 vocabulary: **capsule** primary/secondary buttons (999 px radius, 50 px tall), capsule chips and segmented control, 44 px circular icon buttons, inset grouped list containers at 16 px radius with 12 px inner elements (concentric: child radius = parent − padding). Cards 16, inputs 12, photo 16. | `liquid-glass-web.md` §1, `hig-brief.md` §2. |
| Layout | Page margin **16 px** (HIG on 390-wide), safe-area insets on all four sides, `min-height: 100dvh`. Nav bar: 44 px row + `env(safe-area-inset-top)`; back = chevron icon only, `aria-label="Back"`; title centred (Headline). Parts root shows a **static Large Title** under the bar instead of a centred title. Lists are **inset grouped** (rounded container, inset separators, chevrons on navigable rows). | `hig-brief.md` §1, §2. |
| Icons | **Lucide** outline paths inlined as SVG (ISC), 2 px stroke, 20 px in text, 24 px in icon buttons. No SF Symbols on the web (licence). Set: chevron-left, chevron-right, camera, image, plus, trash-2, check, triangle-alert, share, settings, ruler, zoom-in, zoom-out, x, circle-check, bug. One `Icon.res` component; no icon font, no dependency. | `hig-brief.md` §4. |
| Interaction feel | `-webkit-tap-highlight-color: transparent`; pressed = opacity 0.6 (UIKit) on plain/icon buttons, `cc-accent-pressed` fill on the accent button; `touch-action: manipulation` on controls; `user-select: none` on chrome; focus-visible ring 2 px accent. Motion 150–200 ms, easing `cubic-bezier(0.2, 0.8, 0.2, 1)`, opacity/transform only, all zeroed under `prefers-reduced-motion`. | `hig-brief.md` §5, `liquid-glass-web.md` §4. |
| Sheets | The annotate control panel stays **in-flow, opaque, non-modal** (an elevated surface, not a system sheet: no grabber, no detents). Stop calling it "sheet" in copy and new code; class name `.panel`. | `hig-brief.md` §6 Q1. |
| Confirmations | Destructive actions confirm inline (a red "Delete" capsule + "Cancel"), never a modal; errors inline, one sentence. Empty states: one line + the one capsule. | §7 above, `hig-brief.md` §2. |
| Vertical rhythm | Sections **24 px apart** (`cc-space-6`, `.stack-lg`'s gap), group header → its group **8 px** (`cc-space-2`), siblings inside one section **12 px** (`cc-space-3`) — the 4/8/12/16/20/24 scale from §2, all the way to its top step. No 9, 10 or 14 px values anywhere in this rhythm; 14 px survives only as a text input's own side padding (§4), which is horizontal, not part of it. | `docs/design/review-2026-09-17.md` §2: `cc-space-6` had never been used as a spacing step before this pass, so the top of the scale was dead and sections read as one column. |

### 11.2 Per-screen notes

- **Parts**: Large Title "Parts"; trailing 44 px "+" icon button in the bar; inset grouped list rows (72 px first-face thumbnail, `cover`, `cc-surface-2` mat; name Body, meta Footnote in `cc-text-2`, chevron `cc-text-3`); rename/delete live behind the bar's trailing Edit/Done text action, not permanent per-row icon buttons; empty state = one Footnote line + accent capsule "New part". Create form: inset grouped inputs + units segmented + capsule.
- **Part**: title = part name; bar subtitle "n faces · n features · unit", trailing Edit/Done text action; faces = 2-column grid of Face cards (§4), "+ Capture" card last, 3-up (`.face-grid-dense`) at ≥ 5 faces; features = Feature rows (§4), group header only — no column header row (`cc-size-micro` no longer appears on this screen; Caption 1 is the smallest text here); warning rows per §4; one accent capsule "Export", disabled until a face exists; timer centred Footnote `cc-text-2` under Export.
- **Capture**: the Face card grid (§4) is the kind picker — tap a card to select its kind (selected = 2 px accent ring, captured = 2 px live ring + check, "+ Custom" is a card); the shutter block sits under the grid, anchored to the bottom of the content (`margin-top: auto`, never fixed, so the capture loop stays in the bottom 60% per §1); "From library" secondary capsule; the one-line camera note in Footnote; recapture confirm inline.
- **Annotate**: canvas on `cc-photo-mat`, 16 px radius, capped 300 px tall; tools (Snap, zoom −/readout/+) live in a 44 px opaque strip at the top of `.panel`, in flow, not over the photo — only the hint pill stays over the photo; `.panel` below with reading (38 mono + unit Subhead), name + capsule chips (40 px, mono Footnote), segmented control (tolerance field 104 px), tolerance, accent capsule "Save dimension" (becomes "Update"), red-tinted "Delete" only when editing.
- **Settings / Debug**: inset grouped rows with a system-style toggle (52×32 capsule, accent when on); Debug's CSV action is a secondary capsule.

### 11.3 What stays from §1–§10
Principles (§1), the `cc-` tokens (§2 colours, spacing, radii — §11.1 overrides typeface and button shape), layout rules (§3), canvas overlay rules (§5, as amended by SPEC §8a A3), states (§6), content rules (§7), edge cases (§8), accessibility (§9). §10's open items are now decided: Calipers screen collapsed into Settings; Lucide; dark only.
