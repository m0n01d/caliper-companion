# Caliper Companion — v0 spec (mobile web PWA, Ternpike stack)

**Status:** ready for Claude Code · **Owner:** Dwight · **Target:** installable PWA, one user, two weeks
**Supersedes:** `caliper-companion-spec-v0.md` (Swift). Same product, same JSON contract, different runtime.

## 1. Why this exists

Reverse-engineering a small part today means a notepad sketch, caliper readings scribbled next to arrows, then retyping everything into Fusion 360 — and the CAD agent never creates named user parameters unless told to. The app replaces the notepad: photograph each face, tap two edges, enter the caliper reading, name the feature. It exports a dimensioned image for humans and a `features.json` for the Fusion MCP, which creates one user parameter per feature and one sketch per face.

**The photo is never measured.** It is a labeled sketch. No calibration, no scale bar, no lens correction. The caliper is the only source of numbers.

## 2. Hypothesis v0 tests

> Annotated-photo capture is at least 30% faster than notepad + calipers from part-in-hand to a parametric Fusion model, on five real parts.

Kill if not true by part five. Everything in v0 serves this test.

## 3. Goals

- G1: 3 faces, 10 dimensions, captured, named and exported in under 4 minutes hands-on.
- G2: `features.json` round-trips into Fusion via the MCP with zero manual renaming.
- G3: Zero data loss — closing the tab or killing Safari loses at most the dimension being typed.
- G4: Works in airplane mode once installed to the home screen.

## 4. Non-goals for v0 (do not build)

- Bluetooth of any kind. The caliper path is a text input; a keyboard-wedge dongle (§9) will type into it later. Nothing in the app knows a dongle exists.
- Edge snap (Canny/contours) — P1.
- Reconciliation UI — the data model supports one name on several faces; UI shows a warning row only.
- AR, 3D, WebXR, LiDAR, mesh import.
- Accounts, auth, sync to CouchDB, Stripe, analytics. (Sync is v1; the PouchDB doc shapes are designed for it now.)
- Desktop layout. Phone portrait only, 360–430 px wide.
- Fusion sketch generation — that is the MCP skill's job; the app ends at JSON.

## 5. Platform and constraints

- **Language/UI:** ReScript + React, mirroring Ternpike exactly: same ReScript major version, same bundler and config, same lint/test setup. Copy Ternpike's PouchDB bindings, PWA scaffold (manifest, service worker, install prompt), and theme tokens; do not rewrite them. Point Claude Code at the Ternpike repo and say "match this."
- **Persistence:** PouchDB (IndexedDB adapter). Images stored as PouchDB attachments (JPEG blobs). No CouchDB sync in v0, but every doc has `type`, `partId`, and `updatedAt` so v1 sync is a config change.
- **Offline:** service worker precaches the app shell; all reads/writes hit PouchDB. No network calls in v0.
- **Dependencies:** PouchDB, React, ReScript toolchain. One optional extra allowed: `fflate` for zipping the export bundle. Nothing else without asking.
- **iOS Safari rules that bite (encode as tests where possible):**
  - Camera via `<input type="file" accept="image/jpeg,image/png" capture="environment">`; Safari transcodes HEIC to JPEG for file inputs. Never use `getUserMedia` for stills.
  - Decode photos with `createImageBitmap(file, { imageOrientation: "from-image" })` so EXIF rotation is applied **before** any coordinate is computed. Every normalized point is relative to the oriented image.
  - Canvas render at source size: 4032×3024 (12.2 MP) is under Safari's ~16.7 MP canvas cap; anything larger gets downscaled to 4096 on the long edge and the scale recorded in JSON.
  - Layout with `100dvh` and `env(safe-area-inset-*)`; no `position: fixed` toolbars over the canvas (keyboard resizes break them); use `visualViewport` for the reading-input sheet.
  - Numeric entry uses `<input type="text" inputmode="decimal" enterkeyhint="next">` — `type="number"` strips leading dots and fights fractions.
  - Home-screen installed apps are exempt from Safari's 7-day storage eviction; the app still offers "Export" prominently and v1 sync is the real backstop.
  - `navigator.share({ files })` for export; test that multiple files share on iOS 17+.

## 6. Data model (`core/` — pure ReScript, no DOM, fully unit-tested)

```rescript
type units = Mm | Inch
type faceKind = Top | Side | End | Detail
type dimensionKind = Length | Diameter | Depth
type readingSource = Typed | Wedge   // Wedge = a keyboard-wedge dongle typed it; indistinguishable at runtime, set by a user toggle

type point = {x: float, y: float}   // 0.0–1.0 of oriented image width/height

type dimension = {
  id: string,            // "dim:" ++ uuid
  faceId: string,
  name: string,          // validated by FeatureName
  kind: dimensionKind,
  value: float,          // part units
  tolerance: float,      // ± part units
  p1: point,
  p2: point,
  source: readingSource,
  createdAt: string,     // ISO 8601
}

type face = {
  id: string,            // "face:" ++ uuid
  partId: string,
  kind: faceKind,
  imageAttachment: string,   // attachment name on this doc, e.g. "image.jpg"
  pixelWidth: int,
  pixelHeight: int,          // oriented dimensions
  levelDegrees: option<float>,
  outline: option<array<point>>,   // optional 4 corners, reserved for future AR review; no v0 UI
  capturedAt: string,
}

type part = {
  id: string,            // "part:" ++ uuid
  name: string,
  slug: string,
  units: units,
  notes: string,
  anchors: array<anchor>,   // reserved, always [] in v0
  createdAt: string,
  updatedAt: string,
}

type anchor = {family: string, tagId: int, sizeMm: float}   // reserved for AR review

/// Derived, never stored.
type feature = {
  name: string,
  kind: dimensionKind,
  value: float,          // reconciled
  tolerance: float,      // max of contributors
  faceIds: array<string>,
  spread: float,         // max − min
  flagged: bool,         // spread > tolerance
}
```

### 6.1 PouchDB documents

- One doc per part, face, dimension. `_id` = the typed id above. Every doc carries `type: "part" | "face" | "dimension"`, `partId`, `updatedAt`.
- Face image lives as attachment `image.jpg` on the face doc. Never inline base64 in a doc body.
- Indexes (`pouchdb-find`): `[type, partId]` and `[type, updatedAt]`.
- Deleting a part deletes its faces and dimensions in one bulk write.

### 6.2 Feature names

- Regex `^[a-z][a-z0-9_]{0,31}$`. Valid Fusion 360 user-parameter names.
- Reject reserved: `pi`, `e`, `sin`, `cos`, `tan`, `sqrt`, `abs`, `floor`, `ceil`, `round`, `min`, `max`, `log`, `ln`, `exp`.
- Suggestions, in order: names already used on other faces of this part; then `overall_l`, `overall_w`, `overall_h`, `hole_dia`, `wall`, `slot_w`, `slot_l`, `chamfer`.
- Part `slug`: lowercase, non `[a-z0-9]` runs → `_`, trimmed, ≤ 40 chars, must match `^[a-z][a-z0-9_]*$`, prefix `p_` if it would start with a digit.

### 6.3 Reconciliation (pure function)

`reconcile: array<dimension> => result<array<feature>, reconcileError>`

- Group by `name`. Kind conflict within a group → `Error(KindConflict(name))`.
- `value` = mean, `tolerance` = max, `spread` = max − min, `flagged` = `spread > tolerance`.
- Output sorted by name ascending. Deterministic.

## 7. JSON contract — `features.json` (schema `caliper-companion/features/1`)

Unchanged from the Swift spec except two optional reserved fields. Frozen once v0 ships.

```json
{
  "schema": "caliper-companion/features/1",
  "exportedAt": "2026-09-17T14:12:03Z",
  "app": { "name": "Caliper Companion", "version": "0.1.0", "runtime": "web" },
  "part": { "id": "part:…", "name": "Norcold freezer hinge pin", "slug": "norcold_freezer_hinge_pin",
            "units": "mm", "notes": "", "anchors": [] },
  "faces": [
    { "id": "face:…", "kind": "top", "image": "faces/top.jpg", "annotated": "faces/top_dimensioned.png",
      "pixelWidth": 4032, "pixelHeight": 3024, "renderScale": 1.0, "levelDegrees": 0.4, "outline": null }
  ],
  "features": [
    { "name": "overall_l", "kind": "length", "value": 42.18, "tolerance": 0.10,
      "faceIds": ["face:…"], "spread": 0.0, "flagged": false,
      "measurements": [
        { "faceId": "face:…", "value": 42.18, "p1": [0.171, 0.448], "p2": [0.811, 0.448],
          "source": "typed", "at": "2026-09-17T14:03:11Z" } ] }
  ]
}
```

Export bundle: `<slug>.ccpart.zip` (via `fflate`) containing `features.json`, `faces/<kind>.jpg`, `faces/<kind>_dimensioned.png`. If zip is skipped, share the same files as an array with `navigator.share`. Paths in JSON are bundle-relative either way. (`part.path`, added by §8a A10, is a folder path — a Fusion Data Panel location — not a file path.)

**MCP skill contract (built in parallel against the golden fixture):** one user parameter per feature (`name = value units`, comment carries tolerance and faceIds); one sketch per face on top→XY, side→XZ, end→YZ, detail→XY, with the annotated PNG attached as a canvas. Never invent geometry. In v1 the skill pulls the JSON straight from CouchDB over HTTP; in v0 it reads the exported file.

## 8. Modules, in build order, with acceptance criteria

One module → green tests → commit → next. Never start N+1 with red tests in N.

### M1 — `core/` (day 1–2)

- [ ] Types in §6 compile; JSON encode/decode round-trips a fixture part (3 faces, 9 dimensions) losslessly.
- [ ] `FeatureName.validate` accepts `overall_l`, `hole_dia2`; rejects `Overall_L`, `2nd_hole`, `pi`, `sqrt`, 33-char names, empty.
- [ ] `Slug.make("Norcold freezer hinge pin") == "norcold_freezer_hinge_pin"`; `Slug.make("2018 NB bezel") == "p_2018_nb_bezel"`.
- [ ] `reconcile` on the fixture returns 9 features sorted by name; two-face `pin_dia` 6.50/6.52 tol 0.05 → value 6.51, spread 0.02, `flagged == false`; 6.40/6.52 → `flagged == true`.
- [ ] `reconcile` returns `KindConflict("wall")` when `wall` is Length on one face and Depth on another.
- [ ] `FeaturesDocument.make` matches the checked-in golden `features.json` byte-for-byte with injected dates.
- [ ] Number parsing: `"42.18"`, `".5"`, `"42"` parse in mm; `"1 3/8"` and `"1-3/8"` parse only when units are inch; negatives and empty are errors.

### M2 — Persistence (day 3–4)

- [ ] PouchDB store with the doc shapes and indexes in §6.1; typed ReScript API (`Store.putPart`, `Store.facesOf(partId)`, …) — no raw PouchDB calls outside `store/`.
- [ ] Parts list: create (name, units), rename, delete with confirmation; empty state names the first action.
- [ ] Part screen: faces row, features table (name, value, tolerance, faces), warning row when any feature is flagged or a kind conflict exists.
- [ ] Given a dimension half-typed, when the tab is killed, then reopening shows every *saved* dimension; the half-typed one is gone. (Playwright: reload mid-entry.)
- [ ] A face doc is written only after its image attachment write resolves; failure leaves no orphan doc.

### M3 — Capture (day 5–6)

- [ ] Face picker (top/side/end/detail). Recapturing a kind replaces the image after confirmation; dimensions are discarded unless the user chooses "keep".
- [ ] `<input type="file" capture="environment">` flow; image decoded with `imageOrientation: "from-image"`; oriented `pixelWidth/Height` stored. Test: a portrait EXIF-rotated fixture JPEG yields the rotated dimensions and a tap on a known feature yields the expected normalized point.
- [ ] `DeviceOrientationEvent` permission requested once; `levelDegrees` recorded at the moment the file input is opened; `None` when denied or when importing from the library.
- [ ] Given camera permission denied at the OS level, when the user taps Capture, then the library picker still works and a one-line explanation shows.

### M4 — Annotate (day 7–10) — the core screen

- [ ] Canvas image view with pinch-zoom and pan (Pointer Events, no third-party gesture lib). Taps convert to normalized image coordinates regardless of zoom; Playwright test taps the same feature at 1× and 3× and asserts points within 0.005.
- [ ] Two-tap dimension: tap 1 places p1 (handle), tap 2 places p2 and draws the line with extension ticks; handles draggable afterwards.
- [ ] Reading field: `inputmode="decimal"`, `enterkeyhint="next"`, parses per M1; shows part units; rejects invalid with an inline message.
- [ ] Name field with suggestion chips in §6.2 order; invalid names show the rule inline and disable Save.
- [ ] Kind segmented control and tolerance field defaulting to the part's last-used tolerance (initial 0.10 mm / 0.005 in).
- [ ] **Enter in the reading field moves focus to the name field; Enter in the name field saves.** This is the keyboard-wedge seam: a dongle that types `42.18⏎` lands a reading and advances with zero app code.
- [ ] Save writes the dimension, clears reading and name, keeps kind and tolerance, returns focus to the canvas for the next tap.
- [ ] Existing dimensions on the face render dimmed; tapping one selects it for edit or delete.
- [ ] Settings toggle "Readings come from a wedge dongle" sets `source: Wedge` on saved dimensions; default `Typed`.

### M5 — Export (day 11–12)

- [ ] Dimensioned PNG per face rendered on an offscreen canvas at oriented source size (or 4096 long edge with `renderScale` recorded): lines, ticks, name + value labels on solid pills, label height ≥ 2% of image height.
- [ ] Bundle zipped with `fflate` and passed to `navigator.share({ files })`; fallback "Download" anchor for browsers without file sharing.
- [ ] Given a kind conflict, when the user taps Export, then export is blocked and the name is shown.
- [ ] Given a flagged feature, when the user exports, then JSON carries `flagged: true` — never silently averaged.
- [ ] Re-export of an unchanged part produces identical `features.json` except `exportedAt`.

### M6 — PWA shell and dogfood timer (day 12–13)

- [ ] Manifest, icons, service worker precache; "Add to Home Screen" hint shown once on iOS Safari; app launches offline from the home screen (Playwright WebKit with network blocked).
- [ ] Per-part hands-on timer: starts at first capture, stops at first export; shown on the part screen; included in JSON as `"telemetry": {"handsOnSeconds": …}`. Local only.
- [ ] Debug screen exports the last 20 timer results as CSV.

## 9. The keyboard-wedge dongle (v1, hardware, separate repo)

> **v1, deferred:** `docs/linked-mode/SPEC.md` — Linked Mode (phone owns geometry, desktop owns
> readings, CouchDB live sync, QR handoff). Depends on accounts + hosted CouchDB; not before then.
> Its migration moves `value/name/kind/tolerance` off `dimension` into `reading` docs — keep that in
> mind when touching the dimension type.

ESP32 reading Digimatic SPC (52-bit, 13 nibbles) or the 24-bit cheap-caliper protocol (jumper-selected), advertising as a **BLE HID keyboard**. Data button → types the reading in the phone's current units followed by Enter. Pairs in iOS Settings like any keyboard. Works in this PWA, in Fusion's parameter dialog, in a spreadsheet. The app never talks to it directly; M4's focus order is the entire integration.

## 10. Testing

- `core/`: unit tests on the compiled JS (vitest), 100% line coverage on codec, names, slug, reconcile, number parsing.
- App: Playwright with the WebKit engine and a 390×844 viewport for the golden path — create part, import fixture image, add 3 dimensions, export, assert zip contents against the golden file.
- Fixtures: `fixtures/hinge_pin/` with three JPEGs (one EXIF-rotated), `features.json` golden.
- No visual snapshot tests in v0.

## 11. Dogfood protocol

1. Baseline two parts with today's notepad + Fusion process; record minutes and parameters named by hand.
2. v0 on five parts: TPU battery tray mount, washer-nozzle plug, Norcold hinge pin, a Hehr window clip, one of your choice. Record `handsOnSeconds` plus minutes to a constrained Fusion sketch.
3. Pass: median v0 total ≤ 70% of baseline and every export yields correctly named parameters in Fusion. Fail: stop, write down why.

## 12. Borrow list from Ternpike (copy, don't rewrite)

- ReScript project config, bundler config, lint and test setup.
- PouchDB bindings and the `Store` pattern; index setup helpers.
- PWA scaffold: manifest generation, service worker, install prompt, iOS safe-area layout shell.
- Theme tokens; keep Ternpike's look for v0 — polish is post-hypothesis.
- v1 only: Cloudflare Workers auth, CouchDB per-user database provisioning, Stripe checkout.

## 13. Open questions

- **Blocking (Dwight):** mm-only in v0, inch as display toggle? Recommendation: yes.
- **Non-blocking (engineering):** does `createImageBitmap` at 12 MP hold on an iPhone 13 while the annotate canvas is live? If not, decode a 2048-wide working copy for the canvas and keep the original attachment for export.
- **Non-blocking (Dwight):** `fflate` zip vs. multi-file share — pick after seeing what iOS Files does with a `.ccpart.zip`.

## 14. Instructions for Claude Code (paste into `CLAUDE.md`)

```
Read SPEC.md fully before writing code. Build modules M1→M6 in order; tests first for M1, alongside for the rest.
ReScript + React + PouchDB, matching the Ternpike repo's versions and config exactly. Copy Ternpike's PouchDB bindings and PWA scaffold; do not reinvent them.
No dependencies beyond React, PouchDB (+ pouchdb-find), ReScript toolchain, and fflate. Ask before adding anything.
Apply EXIF orientation at decode; every stored coordinate is relative to the oriented image. This is the most common bug in this class of app — test it.
Do not build anything under Non-goals. No Bluetooth code. No AR code. Reserved fields stay reserved.
Do not change the features.json shape; if the schema must change, stop and ask.
One commit per acceptance-criteria group; the message names the module and criteria met.
Ambiguous criterion → simplest reading, note it in the commit body, keep going.
```

## 8a. v0.1 amendments (phone dogfood, 2026-09-17)

Findings from the first real capture → dimension → export → open-on-Mac loop. Same rules as §8:
one amendment → green tests → commit.

### A1 — Move dimensions directly on the photo (extends M4)

- [ ] A **saved** dimension's endpoint handles drag without selecting it first: `pointerdown` within 22 CSS px (a 44 px target, DESIGN.md §2) of a handle starts a handle drag; releasing writes the new point to the store (same id) immediately and redraws. No Save tap.
- [ ] Dragging a saved dimension's **line body** (within 16 px of the segment, not on a handle) translates both points together; releasing persists the same way.
- [ ] The pending (unsaved) dimension behaves identically for its handles and body, without persisting.
- [ ] Hit priority: handle > line body > pan. A second finger during a drag cancels the drag (points revert) and becomes a pinch.
- [ ] A tap (no movement) on a saved dimension still selects it for edit/delete, as before.
- [ ] Playwright: drag a saved handle by a known screen delta → after `page.reload()` the stored point moved by the matching normalized delta within 0.005; a body drag moves both points by the same delta.

### A2 — The keyboard must come up on the second tap (M4 bullet 6, iOS Safari)

- [ ] Given iOS Safari, when the second tap lands, then the reading field has focus and the keyboard is open, with no extra tap. `focus()` called from a `pointerup` handler does not open the iOS keyboard; the call has to run inside the `click` (or `touchend`) handler of the same tap. Implement as: `update` records the focus intent in the model on p2; the canvas `click` handler, which fires after a tap and never after a drag or pinch, performs the pending intent. Chromium e2e keeps asserting focus; Dwight verifies on the phone.

### A3 — Overlays legible on any photo (M5 PNG and the live canvas)

- [ ] Every stroke in the exported PNG (dimension line, arrowheads, extension ticks, handles) is drawn twice: a **halo** in near-black `#17181A` at 85 % alpha and 2.5× the line width underneath, then the line in amber `#F2A33A` on top (DESIGN.md §5 colours). Labels sit on solid amber pills with `#2B1A02` text and a 1 px near-black border.
- [ ] Sizes per DESIGN.md §5: stroke 0.15 % of the long edge (min 2 px), pill height 2 % of image height, label font 1.4 % of image height, 10×10-equivalent arrowheads scaled the same way.
- [ ] Test: render the same dimension onto an all-white and an all-black image; the line's amber core and its halo are both present in each (sample pixels across the line), and the pill text contrast against the pill is ≥ 4.5:1.
- [ ] The live annotate canvas uses the same halo treatment so what you see is what exports.

### A4 — Cap stored photo size (resolves the §13 "12 MP" question)

- [ ] At capture, after the oriented decode, an image whose long edge exceeds **2048 px** is redrawn to 2048 on the long edge and re-encoded as JPEG quality 0.85 before storage. `pixelWidth`/`pixelHeight` are the stored size; `features.json` reports the stored size; `renderScale` is therefore always `1.0`.
- [ ] Images already at or below 2048 are stored exactly as picked (the EXIF fixture test still yields 1200×1600).
- [ ] The cap is a single constant (`Capture.maxLongEdge`) so a later tier can raise it.
- [ ] Re-encoded images carry no EXIF: orientation is baked in, so downstream decodes are unaffected.
- [ ] Playwright: a synthetic 4000×3000 JPEG (generated in-page via canvas, passed to `setInputFiles` as a buffer) stores as 2048×1536; the stored attachment is smaller than the input.

### A5 — Edge snap (was P1 in §4; now v0.1, toggleable)

The tap is still a sketch mark, never a measurement; snapping only makes the drawn arrow land on
the visible edge. It must be cheap, contrast-agnostic, and easy to turn off per part.

- [ ] Pure module `EdgeSnap` (no DOM): input a grayscale patch (`width`, `height`, `Uint8Array` luma), output snapped positions in patch pixels. `snapPoint(patch, ~at, ~radius)` moves `at` to the strongest gradient-magnitude pixel within `radius`; `snapPair(patch, ~p1, ~p2, ~radius)` searches **along the p1→p2 segment** and moves each end to the strongest brightness crossing within `radius` of it, so two rough taps either side of a part land on its two edges. Returns `None` for an end when the best gradient is below a threshold (≥ 3× the patch's median gradient magnitude, and an absolute floor), leaving that tap where it was.
- [ ] Bounded cost: at decode the annotate page keeps a downscaled grayscale copy of the oriented image (long edge 1024 px, built once from the bitmap via a canvas `getImageData`); snapping runs in that space and converts back to normalized coordinates. Never touches the full-resolution bitmap.
- [ ] Toggle: a "Snap" pill in the annotate toolbar (`data-testid="snap-toggle"`, `aria-pressed`), one thumb-tap, persisted in Settings (`settings.snap: bool`, default **on**).
- [ ] Feedback and override: a snapped point draws a 150 ms ring (respecting reduced motion); `pending-points` reflects the snapped values; dragging a handle disables snap for that point (a drag never re-snaps). Applies to p1 on the first tap and to both ends on the second tap (via `snapPair`).
- [ ] Unit tests on synthetic patches: a vertical step edge snaps within 1 px from up to `radius` away on either side; a flat or noise-only patch leaves the point alone; a bar (two edges) with taps just inside and just outside each edge → `snapPair` lands on both edges; an oblique segment snaps along its own direction, not the image axes.
- [ ] Playwright on `top.jpg` (bar spans x 0.17–0.81, y 0.35–0.55): p1 tapped 12 px inside the left edge → stored x within 0.004 of 0.17; taps at (0.15, 0.45) and (0.83, 0.45) → (0.17, 0.45) and (0.81, 0.45) within 0.004; with the toggle off the stored points equal the taps; the toggle state survives reload.

### A6 — Fit the view to the dimension when the second point lands

With the keyboard up, the visible stage is roughly half its normal height (it tracks
`visualViewport`), so a freshly placed dimension can sit under the keyboard. After p2, bring it
into view.

- [ ] When p2 lands (tap, snap, or the second end of `snapPair`), the viewport animates to **fit the p1–p2 segment** into the current stage with ~15 % padding on each side, centred on the segment midpoint, scale clamped to the existing [fit, 8×fit] range (a long dimension across the whole part therefore just re-centres at the fit scale). 160 ms, `--cc-ease`; instant under `prefers-reduced-motion`. Pure math lives in `Viewport.fitToSegment` with unit tests.
- [ ] While a pending pair exists and the stage resizes (keyboard opening/closing changes `--vv-height` and therefore the canvas size), re-fit so both points stay visible.
- [ ] Any pinch or pan by the user during the fitted state cancels auto-fit for that pair: later stage resizes do not re-fit, and the view is left where the user put it.
- [ ] On Save or Clear, animate back to the view the user had **before** the fit (remembered when the fit was applied), unless the user pinched or panned in between, in which case stay.
- [ ] Playwright (Chromium, 390×844): after two taps 60 px apart at the fit scale, `data-transform` shows a larger scale and both points map to inside the canvas box with ≥ 10 % margin; the `zoom` readout reflects it; after Save the transform returns to the pre-fit value within 0.01; a `zoom-in` click between p2 and Save prevents the restore.

### A7 — Custom faces (not limited to top / side / end / detail) — **schema delta, needs owner OK**

Real parts have undersides, chamfered ends, section views. The four kinds stay as the **sketch-plane
hint** Fusion needs; a face additionally gets a **label**, and a part may have any number of faces.

**JSON delta (`features.json`, additive; `schema` stays `caliper-companion/features/1`):**
```json
{ "id": "face:…", "kind": "side", "label": "left_side",
  "image": "faces/left_side.jpg", "annotated": "faces/left_side_dimensioned.png", … }
```
- `kind` keeps its four values and its meaning (top→XY, side→XZ, end→YZ, detail→XY).
- `label` is new: `^[a-z][a-z0-9_]{0,31}$` (same rule as feature names), unique per part. Default
  faces have `label == kind` (`"top"`, `"side"`, …), so their file paths are **unchanged**.
- `image`/`annotated` paths use the label. The MCP skill names each sketch after `label` and picks
  the plane from `kind`; a consumer that ignores `label` still works for the four default faces.

**Acceptance criteria**
- [ ] `Types.face` gains `label: string`; `Codec`, `Store` (face docs; docs without `label` read back as `label = kind`), `FeaturesDocument` (paths from `label`, faces sorted by kind order then label) and the golden fixture are updated; M1 tests pass with the added field; the golden changes only by the added `"label"` lines.
- [ ] Capture page: the four default chips plus a "+ Custom" chip. Custom opens an inline card: a mono name field (validated live with `FeatureName.validate`, must be unique among this part's faces, error inline) and a plane picker (segmented: Top XY / Side XZ / End YZ / Detail XY, default Top). Confirming creates the chip and selects it; the shutter and library inputs work for it exactly as for default kinds (`capture-file-<label>` / `library-file-<label>` — labels are already slug-safe).
- [ ] Recapture replaces **by face** (same id, same label), not by kind; a part may therefore hold several faces of the same kind with different labels.
- [ ] Part page face slots and the features table's faces column show labels; the annotate title shows the label ("left_side · Hinge pin").
- [ ] Name suggestions and reconciliation are unchanged (they key on face ids).
- [ ] Custom chips can be removed only when their face has no image and no dimensions; a captured custom face is deleted from the Part page like any face (delete confirms inline, removes its dimensions).
- [ ] Playwright: add a custom face `left_side` on plane Side, capture `side.jpg` into it, dimension it, export → the zip holds `faces/left_side.jpg` and `faces/left_side_dimensioned.png`, `features.json` has that face with `kind: "side"`, `label: "left_side"`; a second custom face with the same label is rejected inline; default faces' paths are unchanged.

### A8 — Snap telemetry: drag-after-snap (**deferred — specified, not yet built**)

Decides whether edge snap earns more investment (Canny / Hough) or is left alone. Local only, like
the hands-on timer.

- [ ] Per part, count `snapAccepted` (a snapped point that was saved without being dragged) and
  `snapCorrected` (a snapped point the user dragged before saving, or a saved dimension whose
  snapped endpoint was later dragged). Points that did not snap count in neither.
- [ ] Stored on the timer doc (`timer:<partId>`) so it rides the existing per-part telemetry; shown
  on the Part page next to the hands-on time as "snap 14 / 2 corrected"; in `features.json`
  under `telemetry` as `"snap": {"accepted": 14, "corrected": 2}` (additive; schema string
  unchanged); the Debug CSV gains both columns.
- [ ] Decision rule (written here so the dogfood applies it): corrected / (accepted + corrected)
  > 20 % over five parts → do the next snap upgrade (Canny edge map, then Hough lines);
  < 5 % → leave snap alone.
- [ ] No UI beyond the two readouts. Not implemented yet; try after the five-part dogfood starts.

### A9 — Dimension list on the annotate screen (select from the list, not only the photo)

Two dimensions drawn on top of each other are hard to pick out by tapping the photo. Every saved
dimension of the face is also listed under the control panel; the list and the canvas select the
same thing.

- [ ] Below the panel, an inset grouped list (`data-testid="dimension-list"`) of this face's saved dimensions in creation order: one row per dimension (`dimension-row`, `data-id="<dim id>"`) showing the kind glyph (⌀ / ↓ / none), the name in mono, the value with unit, and ± tolerance in `cc-text-2`. Empty state: one Footnote line "No dimensions on this face yet." The list is part of the page scroll, never fixed.
- [ ] Tapping a row selects that dimension for edit exactly as tapping it on the canvas does (panel fills with its values, Save reads "Update", Delete appears, the canvas highlights it, A6's fit applies to its segment). Tapping the selected row again deselects (same as Clear). The selected row is marked (`aria-selected="true"`, `cc-teal-wash` background, teal left rule).
- [ ] Selection made on the canvas highlights the matching row and scrolls it into view (`scrollIntoView({block: "nearest"})`, instant under reduced motion). Saving, deleting and Clear update the list immediately.
- [ ] Focus order per DESIGN.md §9: … → Save → the list. Rows are real `<button>`s with an accessible name "<name>, <value> <unit>, <kind>".
- [ ] Playwright: save two dimensions with identical endpoints; tapping the second row makes `delete` visible and the panel's reading equal the second value; Delete removes only that one (`dimension-count` 1, the remaining row is the first); tapping the canvas on the shared line selects one and its row gets `aria-selected`; the list is empty-state on a fresh face.

### A10 — Folders (a Fusion-style path on every part) — **schema delta, additive**

Parts are organised the way Fusion's Data Panel is: a `/`-separated folder path plus the part name
as the leaf. A path, not tags, because the import skill can save the Fusion design into that same
project folder.

**JSON delta (`features.json`, additive; `schema` stays `caliper-companion/features/1`):**
```json
"part": { "id": "part:…", "name": "window_switch_bezel", "slug": "window_switch_bezel",
          "path": "Miata/Interior/Dashboard", "units": "mm", "notes": "", "anchors": [] }
```

- [ ] `Types.part` gains `path: string` (`""` = root; a folder path, not a file path — carve-out in
  §7). `core/Folder.res` (pure, tabled tests): `normalize` splits on `/`, trims each segment,
  collapses internal whitespace, drops empty segments and rejoins (`" /Miata//Interior /"` →
  `"Miata/Interior"`, `"a//b"` → `"a/b"` — double slashes **normalise**, they are not an error);
  `validate` normalises, then requires each segment to match
  `^[\p{L}\p{N}][\p{L}\p{N} _.()&'+-]{0,31}$` (`u` flag: any Unicode letter/digit, 1–32 chars) and
  not be all dots (`^\.+$` — keeps v1's on-disk staging safe), at most 6 segments, and the whole
  path ≤ 120 chars (`error = BadSegment(segment) | TooDeep | TooLong`; `errorMessage` renders the
  rule); `snap(~existing)` replaces a path that equals an existing folder case-insensitively with
  that spelling; `display` joins with `" / "` (`"Miata / Interior / Dashboard"`; `""` stays `""`).
  Pages call `normalize → validate → snap` before `Store.createPart(~path)` / `putPart`; `Store`
  never normalises. `Codec.decodePart` and `Store.PartDoc.fromDoc` read a missing `path` as `""`
  (the A7 `label` precedent). `FeaturesDocument` emits `"path"` after `"slug"`; the golden gains
  that one line; `Fixture.part` gains the field. `parameters.csv` (A11) is unchanged — it carries no
  path. No path index: `listParts` stays an `allDocs` range + in-memory sort, grouping is in-memory.
- [ ] Parts list: derived in `view` from `model.parts` — root section first (**never** a header on
  the root section, so a list with no folders renders exactly as before A10), then one `Ui.ListGroup`
  per distinct path, sorted case-insensitively, header `"<display path> · <count>"`
  (`parts-section`, `parts-section-header`; headers render uppercase per `.list-group-header`, the
  underlying spelling is kept unique by `snap`); rows inside keep `listParts` order (updatedAt desc;
  `RenameSaved` re-sorts). Above the list, hidden in the empty state: `<input type="search"
  inputmode="search" enterkeyhint="search" autocapitalize="none" autocorrect="off"
  placeholder="Search" aria-label="Search parts">` (`parts-search`, 17 px; `global.css` strips the
  native cancel button with `-webkit-appearance: none`, so the page supplies its own clear button,
  `parts-search-clear`, while the query is non-empty) filtering by name **or** path,
  case-insensitive substring, live, sections preserved; no match → one Footnote line `No parts
  match "<q>".` (`parts-search-empty`). Query is page-local and resets on navigation (v0.1 —
  `Route.Parts` may gain a `q` later if it bites).
- [ ] Create and rename share one `PartForm`: Name, then **Folder** (`part-path`, `type="text"
  autocapitalize="words" autocorrect="off" spellcheck="false" enterkeyhint="done"`, placeholder
  `Miata/Interior`), under it a `Ui.ChipRow` of existing folders (`part-path-chip`, at most 8,
  ordered by the newest `updatedAt` of any part in that folder — `putPart` bumps it; tapping a chip
  fills the field and returns focus there, never submits, so `/Sub` can be appended). Invalid → the
  rule inline (`part-path-error`) and the primary button disabled. Rename stays an inline strip in
  the list and lets a part be moved by editing its folder. No uniqueness: two parts may share a
  name in one folder; the slug is still `Slug.make(name)` and ignores the folder, so
  `<slug>.ccpart.zip` names can collide across folders (one user, accepted).
- [ ] Part page: the folder is the Shell subtitle (`Folder.display`, "Miata / Interior / Dashboard";
  none at root; one ellipsised Footnote line — four segments truncate on a 390 px screen). Layout
  A's "n faces · n features · unit" line lives in the features group header, not the subtitle
  (resolves review B2; `DESIGN.md` §11.2 updated to match).
- [ ] Folders are implicit: none to create or delete; one disappears when its last part leaves.
  Renaming a folder = editing each part (v1).
- [ ] Existing parts migrate as root; nothing else changes for them.
- [ ] Import skill (v1 line in `docs/fusion/IMPORT-SKILL-SPEC.md`): save the new design into the
  folder named by `path`, **relative to the active project's root folder**
  (`app.data.activeProject.rootFolder`), creating folders as needed; the first segment is a folder,
  never a project. The planner already reads `part.path` with a `""` default (`plan["part_path"]`)
  — no planner change.
- [ ] Playwright (`parts.spec.js`): create `Window switch bezel` and `Door card clip` in
  `Miata/Interior`, then `Hinge pin` at root → `parts-section` count 2, root section first and
  headerless (`parts-section-header` count 1, text `Miata / Interior · 2`); search `bezel` → one
  `part-row`; rename `Hinge pin`'s folder to `Miata/Interior` → header reads `· 3`, root section
  gone; `a//b` saves and the header reads `a / b · 1` (rendered
  uppercase as `A / B · 1` — the header is `text-transform: uppercase`); `?` → `part-path-error` visible,
  `part-create` disabled; `miata/interior` on a new part snaps into the existing section; the Part
  page's `.shell-subtitle` reads `Miata / Interior`. `export.spec.js`: `doc.part.path === ''` on the
  golden test; one part with a folder exports it verbatim.

### A11 — `parameters.csv` in the export bundle (Fusion ParameterIO format, no Claude needed)

Autodesk's free ParameterIO add-in imports user parameters from a CSV. Shipping that file in the
zip gives a standard, Claude-free import path: export → AirDrop → ParameterIO → Import.

- [ ] The bundle gains `parameters.csv` next to `features.json`: one line per feature, no header,
  exactly four comma-separated fields `name,unit,expression,comment`, LF line endings, UTF-8, e.g.
  `overall_l,mm,42.18 mm,±0.10 mm · faces top end · ccpart:norcold_freezer_hinge_pin`.
  **No commas inside any field** (the add-in splits naively): faces are joined with a space,
  separators are middle dots. A flagged feature's comment starts with
  `FLAGGED spread 0.12 > ±0.05 · `. `unit` is `mm` or `in`; `expression` carries the unit.
- [ ] The format is verified against the add-in's own source (`AutodeskFusion360/ParameterIO_Python`
  on GitHub: the reader splits each line on commas into name, unit, expression, comment and creates
  or updates the parameter by name). The verification URL and the observed parsing rules go in the
  commit body and in a comment at the top of the writer.
- [ ] Pure writer `ParametersCsv.make(~part, ~faces, ~dimensions) => result<string, Reconcile.error>`
  in `core/`, same feature order as `features.json`, unit-tested: golden `fixtures/hinge_pin/parameters.csv`
  byte-for-byte; inch part → `in` and `1.375 in`; flagged prefix; a `KindConflict` propagates.
- [ ] `Bundle.res` adds the entry; `features.json` is unchanged (no schema change). The export e2e
  asserts the zip holds `parameters.csv` with N lines of four fields matching the features.
- [ ] README ("Import into Fusion without Claude"): install ParameterIO from the Fusion App Store,
  Utilities → ParameterIO → Import → pick `parameters.csv`; canvases stay a manual Insert → Canvas.

### A12 — Folder management: explicit folders, a picker, move, rename, delete — **no JSON delta**

A10 made folders implicit (a part's `path`), so there is no way to make one before it has a part, no
way to pick one without typing it, and no way to move several parts at once (a10-folders-review.md
N7). A12 makes folders first-class in the store and gives them a picker. `features.json` is
unchanged: `part.path` stays the only thing exported, and the import skill needs no change.
Reviewed before build in `docs/design/a12-folders-review.md` (B1–B5 and S1–S10 are applied in the
text below). Two checklists under this one heading: **A12a** (store, helpers, picker) ships first;
**A12b** (selection toolbar, folder rename / delete) builds on the landed A12a. Serial, never
parallel — both edit `PartsList.res`.

#### A12a — folder docs, helpers, the picker

**Store (`Store.res` / `.resi`; PouchDB docs, app-internal):**
- [ ] `folder` docs: `_id = "folder:" ++ path`, body `{type: "folder", path, createdAt, updatedAt}`
  (`updatedAt` = `createdAt`, bumped on rename — §5's every-doc rule). `path` is always normalised,
  validated and snapped by the page before it reaches the store (`Store` never normalises — A10's
  rule; checking *existence* is not normalising). Root (`""`) is never a doc.
  `ensureFolders(t, ~paths: array<string>): promise<array<string>>` — one `allDocs` range on
  `folder:`, then one `bulkDocs` of every path in `paths` and every `Folder.ancestors` of them that
  has no doc; a per-doc 409 in the `bulkDocs` result (the binding returns `array<doc>`, nothing
  throws) counts as already existing; returns the paths it created. `ensureFolder(t, ~path)` is
  `ensureFolders([path])`. `listFolders: t => promise<array<string>>` — every folder doc's path,
  sorted case-insensitively. `createPart` and `putPart` call `ensureFolder` for a non-empty path
  before writing the part, so every path a part carries always has a doc. Store tests (vitest,
  LevelDB, the existing `StoreTest` pattern): `ensureFolders(["a/b/c", "a/x"])` creates `a`, `a/b`,
  `a/b/c`, `a/x` and a second call creates nothing; `createPart(~path="Miata/Interior")` leaves
  `folder:Miata` and `folder:Miata/Interior` behind.
- [ ] `core/Folder.res` gains pure helpers, tabled tests: `parent("a/b/c") = "a/b"`, `parent("a") =
  ""`; `leaf("a/b/c") = "c"`, `leaf("") = ""`; `ancestors("a/b/c") = ["a", "a/b"]`, `ancestors("a")
  = []`; `isUnder("a/b/c", ~folder="a") = true`, `isUnder("ab", ~folder="a") = false`, `isUnder(x,
  ~folder="") = true` for every x; `rebase("a/b/c", ~from="a", ~to="z") = "z/b/c"`, identity when
  not under; `depth("") = 0`, `depth("a/b") = 2`; `join(~parent, ~name)` (`join(~parent="",
  ~name="a") = "a"`); `validateSegment(name): result<string, error>` — `normalizeSegment`, then
  `Error(BadSegment(name))` when the result is empty or contains `/`, else the A10 segment rule
  (`"Interior"` Ok, `" interior "` → `Ok("interior")`, `"a/b"`, `"?"`, `""` and a 33-char name →
  Error; `validate` stays for whole paths). `snap` becomes **prefix-wise**: each ancestor prefix is
  snapped against `~existing` in turn, so `snap("miata/exterior", ~existing=["Miata/Interior"]) =
  "Miata/exterior"` and `snap("miata/interior", ~existing=["Miata/Interior"]) = "Miata/Interior"`;
  the A10 whole-path cases still hold.
- [ ] Migration for A10 data lives in `PartsList` (not Store) and runs **once**, after
  `PartsLoaded`: take the distinct non-root part paths in `updatedAt` order, prefix-snap each
  against the running set of paths seen so far, `putPart` any part whose spelling changed (rare:
  A10's whole-path snap let `Miata/Interior` and `miata/Exterior` coexist), then one
  `ensureFolders` over the result ∪ `listFolders` → `FoldersLoaded(array<string>)`, which fills the
  model's `folders` (every explicit folder path). Never re-run on re-render. A failure lands in the
  existing page error line.

**Folder picker (`FolderPicker`, a PartsList sub-view, not a route).** Replaces A10's free-text
Folder field in **both** the create form and the inline rename strip (`part-path`, `part-path-chip`
and `part-path-error` are retired).
- [ ] The create form shows a **Folder row** (`part-folder-row`: a `list-row` with a chevron,
  `role="button"`) — title "Folder", trailing value the current choice in display form (`Miata /
  Interior`) or "None" at root. In the inline rename strip the same control renders as a
  `.parts-form-field` button (same testid and role), not a `.list-row` — no row inside a row.
  Tapping it opens the picker, which **takes over the page** the way the create form already does
  (list, search and bar actions hidden). The picker remembers where it came from — the create form
  or one row's rename strip (A12b adds a move) — and returns there. Bar: `PartsList.title` returns
  "Choose Folder" while the picker is open and a new `PartsList.largeTitle: model => bool` returns
  false (true otherwise); `Main.view` reads `largeTitle` from the page instead of its hard-coded
  switch, so the title sits in the bar as a centred Headline. Leading: a **Cancel** text action in
  the Shell's leading slot (`folder-picker-cancel`; `Shell.back` can only push a route, and
  cancelling is a page message); trailing **Done** (`folder-picker-done`). `PartsList` therefore
  exports `leading` (normally the gear, `settings-link` — `shell.spec.js` depends on it; Cancel
  while the picker is open) and `Main.res` threads it like `actions`.
- [ ] Picker body: one `Ui.ListGroup` (`folder-picker-list`, `role="listbox"`) with a row per
  folder: `<button type="button" role="option" data-testid="folder-option" data-path aria-selected
  aria-label="<Folder.display path>">` (root: `data-path=""`, `aria-label="None, top level"`), a
  **flat tree**: root first (title "None", subtitle "Top level"), then every path in
  `model.folders` ∪ the paths of loaded parts ∪ their ancestors, ordered depth-first so children
  follow their parent (case-insensitive within a level); each row indented `depth × 20 px`, visible
  title = leaf name, a leading `Icon.Folder` glyph (`Icon.res` gains Lucide `folder`; `FolderPlus`
  already exists), a `Check` glyph in `accent` on the selected row. Tapping a row selects it (single
  tap, no navigation). Opening the picker focuses the selected row. Under the list a secondary
  capsule **New Folder** (`folder-new`, `FolderPlus` glyph) reveals an inline field
  (`folder-new-name`: `autocapitalize="words" autocorrect="off" spellcheck="false"
  enterkeyhint="done"`, placeholder "Folder name", focused on open) with Create
  (`folder-new-create`, disabled while `Folder.validateSegment` is `Error` — so also while empty)
  and Cancel (`folder-new-cancel`, focus back to `folder-new`); the rule shows inline as
  `folder-new-error` (`Folder.errorMessage`; a `/` reads `Folder name "a/b" can use …`). Create =
  `Folder.join(~parent=selected, ~name)` → `Folder.snap` against the picker's known paths (so
  `interior` under `Miata` selects the existing `Interior` instead of making a twin) →
  `ensureFolder` → the created (or snapped) path becomes the selection, `folders` gains what
  `ensureFolders` returned, the field closes and focus moves to that option. When the selection is
  already 6 deep (`Folder.depth`) the capsule is disabled with a Footnote "Folders go six deep."
- [ ] Done applies the selection to the form's draft and returns to it; Create / Save then proceed
  exactly as A10 (`Store.createPart(~path)` / `putPart`, each calling `ensureFolder`). Done with an
  unchanged selection is the same return and nothing else happens. Cancel discards the picker's
  selection, never the form's other fields (Name, units, a rename draft). A folder created in the
  picker persists even if the picker is then Cancelled — it is a real folder (A12b shows it as an
  empty section). Cancel and Done both return focus to `part-folder-row`. Picker state is page-local
  (`Main.pageForRoute` re-inits the page per route, as A10's search does).
- [ ] A12a leaves rows, Edit mode, per-row delete and the section headers exactly as A10 built
  them; a single part still moves through its rename strip.

#### A12b — selection toolbar, folder rename / delete (builds after A12a lands)

**Store:**
- [ ] `type folderError = NotEmpty | Exists | Nested`. `moveParts(t, ~partIds, ~path):
  promise<array<Types.part>>` — `ensureFolder` first, then one `bulkDocs` rewriting each part whose
  `path` differs (`updatedAt` bumped, same as `putPart`); parts already there are skipped; returns
  the moved records. `deleteFolder(t, ~path): promise<result<unit, folderError>>` removes the doc
  and **refuses** with `NotEmpty` if any part sits in it or under it (`Folder.isUnder`) or any
  folder doc is under it. `renameFolder(t, ~from, ~to): promise<result<unit, folderError>>` (`to`
  already validated by the page) refuses `Exists` when a folder doc **other than `from`** equals
  `to` case-insensitively (a case-only rename `Miata` → `miata` is allowed), `Nested` when `to` is
  under `from`; otherwise one `bulkDocs` deletes the old folder doc, creates the new one
  (`updatedAt` bumped) and rewrites every descendant folder doc (`Folder.rebase`) and every part
  whose `path == from` or is under it (`updatedAt` bumped, same as `putPart`), so the subtree
  follows. `deleteParts(t, ~partIds): promise<unit>` — `deletePart` for each id in sequence inside
  one promise. Store tests: rename `Miata` → `MX-5` moves `Miata/Interior/Dashboard`'s folder doc
  and part; `Miata` → `miata` is `Ok`; rename onto an existing sibling is `Error(Exists)`; delete of
  a folder with a part under it is `Error(NotEmpty)`; `moveParts` bumps only the moved parts.
  `NotEmpty` and `Nested` are unreachable from the UI below (delete only shows on empty leaves;
  rename keeps the parent) — store guards with store tests only, no inline copy.

**Moving parts (Edit mode):**
- [ ] "Edit" now makes every row selectable. An editing row is a plain `<div class="list-row"
  role="listitem" data-testid="part-row">` — no `href`, no chevron: leading `<input type="checkbox"
  id="part-select-<id>" data-testid="part-select" aria-label="Select <name>">` restyled as a
  selection circle (a real checkbox; never `Ui.ListRow ~onClick`, which renders a `<button>` around
  the checkbox and the pencil — nested interactive content); the body (thumbnail, title, meta) is a
  `<label for="part-select-<id>">`, so tapping the body toggles; the per-row `part-rename` (pencil)
  stays trailing as a sibling **outside** the label and never toggles. The per-row `part-delete`
  and its inline confirm strip go away in favour of the toolbar below (`part-delete-confirm` /
  `part-delete-cancel` are retired). Tab order while editing: gear (`settings-link`), Edit/Done
  (`parts-edit`), "+" (`new-part`), search (`parts-search`), then the first `part-select`.
- [ ] A **selection toolbar** (`edit-toolbar`) renders in a new `Shell ~footer:
  option<React.element>=?` slot — a sibling **after** `<main class="shell-content">` directly inside
  `.shell` (a flex column; `main` is `flex: 1 1 auto`, so a short list still pushes the footer to
  the bottom edge and a long one lets `position: sticky; bottom: 0` catch it — inside the page body
  it would sit mid-screen under a three-part list); the nav bar's glass recipe on a pseudo-child,
  hairline on top, `padding-bottom: env(safe-area-inset-bottom)`; never `fixed` (§5). `PartsList`
  exports `footer` (`Some` while editing and no form or picker is open) and `Main.res` threads it
  like `actions`. Contents: "Move" (`parts-move`) and "Delete" (`parts-delete`), both disabled until
  ≥ 1 row is selected, with the count in the label ("Move 2", "Delete 2"; bare "Move" / "Delete" at
  zero). Move opens the A12a picker titled "Move 2 Parts" ("Move 1 Part"), preselecting the root;
  Done = `moveParts` → sections re-derive, live region "Moved 2 parts to Miata / Interior" ("Moved 1
  part to …", "… to the top level"; counts only the parts actually moved — if none moved, nothing
  is announced), selection cleared, Edit mode stays on, focus returns to `parts-move`; Cancel
  returns to the list with the selection intact, focus on `parts-move`. Delete → an inline confirm
  strip in the toolbar ("Delete 2 parts? This removes their faces and dimensions." / "Delete 1
  part? …", `parts-delete-confirm` / `parts-delete-cancel`) → `Store.deleteParts` → rows removed,
  selection and strip cleared, live region "Deleted 2 parts" ("Deleted 1 part"), focus to
  `parts-edit`; if no parts remain, `editing` resets to false (Edit leaves the bar) and focus goes
  to `new-part`. "Done" clears the selection and any open strip (P1's no-leftover-state rule); a
  search query change clears the selection too. Store errors from move / delete / rename surface
  in the existing `rowError` line, one sentence.
- [ ] `DESIGN.md` §11.1 Materials: "Glass in exactly one place: the navigation bar" becomes "the
  nav bar and, while editing, the Parts bottom toolbar" — same recipe, both `sticky`, never `fixed`.

**Folder rename / delete (Edit mode, on the section header):**
- [ ] `Ui.ListGroup` gains `~headerTrailing: option<React.element>=?` (rendered as a sibling of the
  `<h2>` inside a `.list-group-header-row` flex wrapper — never inside the heading, which would
  leak the button names into the heading's accessible name) and `~headerEl:
  option<React.element>=?` (replaces the `<h2>` outright, for the rename form).
- [ ] While editing, each folder section header gains trailing icon buttons: `folder-rename`
  (pencil, `aria-label="Rename folder"`) and `folder-delete` (trash, `aria-label="Delete folder"`),
  the latter present **only** when the folder has no parts and no subfolders. Rename = the header
  becomes an inline form (`folder-rename-input`, prefilled with the leaf name, focused on open,
  `autocapitalize="words" autocorrect="off" spellcheck="false" enterkeyhint="done"`,
  `Folder.validateSegment` inline as `folder-rename-error`) with Save (`folder-rename-save`,
  disabled while invalid or unchanged) / Cancel (`folder-rename-cancel`, focus back to
  `folder-rename`); Save = `renameFolder(~from, ~to=Folder.join(~parent=Folder.parent(from),
  ~name))`; the subtree follows (`Miata` → `MX-5` also moves the parts in
  `Miata/Interior/Dashboard`); the page rebases its `parts` and `folders` from the result and
  re-sorts; focus goes to the renamed section's `folder-rename`. `Exists` → inline `A folder named
  "X" already exists here.` as `folder-rename-error`. One inline editor at a time: starting a folder
  rename resets `rowStates`; `RenameStart` on a row cancels a folder rename. Delete =
  `deleteFolder`, no confirm (it is empty by construction); the section disappears; live region
  "Deleted folder Archive"; focus to `parts-edit`.
- [ ] Empty folders: a **leaf** explicit folder (no parts, no subfolders) renders as a section too:
  header "`<display> · 0`" and one muted Footnote row "Empty folder" (`parts-section-empty`) so it
  is visible, pickable, renamable and deletable. A folder with subfolders but no direct parts
  renders **no** section outside Edit mode and a header-only row (the `<h2>` + pencil, no
  `.list-group` container) while editing, so it can be renamed. Sections stay one folder each (A10)
  — counts never include descendants. Section order is unchanged (root first, then paths
  case-insensitively). Search hides an empty folder unless its path matches the query.

**Not in A12 (v1):** drag-and-drop; moving a folder under a different parent (inline rename is one
segment — rename keeps the parent); nested counts; a folder-scoped "+"; a Folders screen of its
own; "Rename" in the toolbar (the per-row pencil stays).

- [ ] Docs, per half: `DESIGN.md` §11.2 Parts entry updated (A12a: the picker as a take-over screen
  replacing the Folder field + chips; A12b: Edit mode = selection + bottom toolbar, plus the §11.1
  Materials line above); `docs/testids.md` updated (retired ids struck, new ids listed); a LOGBOOK
  section per half.
- [ ] Playwright, A12a (`parts.spec.js`, new describe "folders — picker (SPEC §8a A12a)"): New
  Folder "Miata", then with it selected "Interior" → `folder-option` rows `None`, `Miata`,
  `Interior` (indented, `data-path="Miata/Interior"`, `aria-label="Miata / Interior"`); Done →
  `part-folder-row` reads `Miata / Interior`; create → header `Miata / Interior · 1` and the Part
  page's `.shell-subtitle` reads `Miata / Interior`. Edit → `part-rename` on a root part →
  `part-folder-row` → pick `Miata/Interior` → Done → `part-rename-save` → header `· 2`, root
  section gone. The new-folder field rejects `a/b` and `?` inline (`folder-new-error` visible,
  `folder-new-create` disabled) and snaps `interior` to the existing `Interior` (no second
  `Interior` option). Cancel from the picker leaves the form's Name intact and focuses
  `part-folder-row`. `a11y.spec.js`: the picker's options are `role="option"` buttons reachable by
  Tab, `aria-selected` truthful, the selected one focused on open. **Existing specs that change in
  A12a:** `parts.spec.js` "sections with counts, root first and headerless; search filters; rename
  moves and re-sorts" and "folder field: a//b normalises, ? is rejected inline, a different case
  snaps to the existing spelling" (both drive `part-path` / `part-path-chip`; `a//b` is no longer
  typeable — retire that case, move `?` and the snap to the picker) and the `createPartIn` helper
  (walks the segments: select the `folder-option` when it exists, else New Folder). Unchanged:
  "rename persists after reload", "delete with confirm returns to the empty state" (until A12b),
  `shell.spec.js`, `export.spec.js` (no JSON delta).
- [ ] Playwright, A12b (`parts.spec.js`, new describe "folders — management (SPEC §8a A12b)"): an
  explicit empty `Archive` (created in the picker, then Cancel) shows as a section with
  `parts-section-empty` and header `Archive · 0`. Edit → `parts-section` contains no link → select
  two rows → `parts-move` reads "Move 2" → pick `Archive` → Done → header `Archive · 2`,
  `parts-live` "Moved 2 parts to Archive", `parts-move` focused. `folder-rename` on `Miata` (a
  header-only row while editing) → `MX-5` → header `MX-5 / Interior · 1` and that part's page
  subtitle `MX-5 / Interior`; `Miata` → `miata` saves; renaming onto a sibling shows
  `folder-rename-error`. `folder-delete` absent on a non-empty section, present on an empty one,
  removes it (`parts-live` "Deleted folder Archive"). Select one → `parts-delete` reads "Delete 1"
  → confirm → row gone, `parts-live` "Deleted 1 part", `parts-edit` focused; deleting the last part
  exits Edit mode and focuses `new-part`. `a11y.spec.js`: in Edit mode, Tab reaches
  `settings-link`, `parts-edit`, `new-part`, `parts-search`, then the first `part-select`, and
  `Space` checks it. **Existing specs that change in A12b:** `parts.spec.js` "delete with confirm
  returns to the empty state" (`part-delete` → select + `parts-delete` + `parts-delete-confirm`);
  `a11y.spec.js` "parts list — rename autofocuses its draft input; deleting a part sends focus to
  New part" (toolbar delete; focus target per above).
