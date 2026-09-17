# Caliper Companion — v0 spec (dogfood MVP)

**Status:** ready for Claude Code · **Owner:** Dwight · **Target:** TestFlight, one user, two weeks

## 1. Why this exists

Reverse-engineering a small part today means a notepad sketch, caliper readings scribbled next to arrows, then retyping everything into Fusion 360 — and the CAD agent never creates named user parameters unless told to. The app replaces the notepad: photograph each face, tap two edges, enter the caliper reading, name the feature. It exports a dimensioned image for humans and a `features.json` for the Fusion MCP, which creates one user parameter per feature and one sketch per face.

**The photo is never measured.** It is a labeled sketch. No calibration, no scale bar, no lens correction. The caliper is the only source of numbers.

## 2. Hypothesis v0 tests

> Annotated-photo capture is at least 30% faster than notepad + calipers from part-in-hand to a parametric Fusion model, on five real parts.

Kill if not true by part five. Everything in v0 serves this test and nothing else.

## 3. Goals

- G1: A part with 3 faces and 10 dimensions is captured, named and exported in under 4 minutes of hands-on time.
- G2: `features.json` round-trips into Fusion via the MCP with zero manual renaming.
- G3: Zero data loss — force-quit at any point loses at most the dimension being typed.
- G4: Works with airplane mode on.

## 4. Non-goals for v0 (do not build)

- Bluetooth / caliper hardware — the keyboard path proves value first. Design the reading input so a BLE source can replace typing later (see §9).
- Edge snap (Vision contours) — P1. Taps land where the thumb lands.
- Multi-face reconciliation UI — the *data model* supports a name on several faces; the UI shows a plain warning only.
- LiDAR, 3D, photogrammetry, AR — separate product (Sawyer).
- Accounts, sync, cloud, analytics, subscriptions, App Store listing.
- iPad layout, landscape, Dynamic Type beyond system defaults.
- Fusion sketch generation inside the app — that is the MCP skill's job; the app ends at JSON.

## 5. Platform and constraints

- Swift 6, strict concurrency on. SwiftUI. iOS 18 minimum (iPhone only).
- SwiftData for persistence. Images stored as JPEG files in the app's Documents directory, referenced by filename.
- No third-party dependencies. No backend. No network calls.
- Apply the `swift-best-practices` skill: `@MainActor` view models, actors for file I/O, no split isolation, cancellation checks in loops.
- Project layout: an Xcode app target `CaliperCompanion` plus a local Swift package `CaliperCore` (models, codec, reconciliation, pure Swift, fully unit-tested, no UIKit/SwiftUI imports).

## 6. Data model (`CaliperCore`)

```swift
enum Units: String, Codable { case mm, inch }
enum FaceKind: String, Codable { case top, side, end, detail }
enum DimensionKind: String, Codable { case length, diameter, depth }
enum ReadingSource: String, Codable { case typed, ble }

struct NormalizedPoint: Codable, Hashable { var x: Double; var y: Double }   // 0...1 of image width/height

struct Dimension: Codable, Identifiable, Hashable {
    var id: UUID
    var faceID: UUID
    var name: String            // validated by FeatureName
    var kind: DimensionKind
    var value: Double           // in part units
    var tolerance: Double       // ± in part units
    var p1: NormalizedPoint
    var p2: NormalizedPoint
    var source: ReadingSource
    var createdAt: Date
}

struct Face: Codable, Identifiable, Hashable {
    var id: UUID
    var partID: UUID
    var kind: FaceKind
    var imageFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var levelDegrees: Double?   // nil when not captured with the in-app camera
    var capturedAt: Date
}

struct Part: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var slug: String            // derived, see FeatureName rules, used for filenames
    var units: Units
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

/// Derived, never stored. One per distinct dimension name across all faces of a part.
struct Feature: Codable, Hashable {
    var name: String
    var kind: DimensionKind
    var value: Double           // reconciled
    var tolerance: Double       // max of contributing tolerances
    var faceIDs: [UUID]
    var spread: Double          // max - min of contributing values
    var flagged: Bool           // spread > tolerance
}
```

SwiftData `@Model` classes mirror these three stored types (`PartRecord`, `FaceRecord`, `DimensionRecord`) inside the app target only; `CaliperCore` stays value types so the codec and tests never touch SwiftData.

### 6.1 Feature names

- Regex: `^[a-z][a-z0-9_]{0,31}$`. Lowercase, starts with a letter, underscore allowed. This is a valid Fusion 360 user-parameter name.
- Auto-suggest, in order: names already used on other faces of this part; then `overall_l`, `overall_w`, `overall_h`, `hole_dia`, `wall`, `slot_w`, `slot_l`, `chamfer`.
- Reserved words rejected: `pi`, `e`, and anything that is already a Fusion built-in function name (`sin`, `cos`, `tan`, `sqrt`, `abs`, `floor`, `ceil`, `round`, `min`, `max`, `log`, `ln`, `exp`).
- `slug` for a part: name lowercased, non `[a-z0-9]` runs collapsed to `_`, trimmed, max 40 chars, must match `^[a-z][a-z0-9_]*$`; prefix `p_` if it would otherwise start with a digit.

### 6.2 Reconciliation (pure function)

`func reconcile(_ dimensions: [Dimension], tolerancePolicy: ...) -> [Feature]`

- Group by `name`.
- `kind` conflicts within a group are an error surfaced to the UI (the second entry must be renamed); the function returns `.failure(.kindConflict(name:))`.
- `value` = arithmetic mean of the group; `tolerance` = max; `spread` = max − min; `flagged` = `spread > tolerance`.
- Deterministic ordering of output: by name ascending.

## 7. JSON contract — `features.json` (schema `caliper-companion/features/1`)

This is the interface with the Fusion MCP skill. Treat it as frozen once v0 ships; bump the schema string to change it.

```json
{
  "schema": "caliper-companion/features/1",
  "exportedAt": "2026-09-17T14:12:03Z",
  "app": { "name": "Caliper Companion", "version": "0.1.0" },
  "part": {
    "id": "6F0C…",
    "name": "Norcold freezer hinge pin",
    "slug": "norcold_freezer_hinge_pin",
    "units": "mm",
    "notes": ""
  },
  "faces": [
    { "id": "A1…", "kind": "top", "image": "faces/top.jpg", "annotated": "faces/top_dimensioned.png",
      "pixelWidth": 4032, "pixelHeight": 3024, "levelDegrees": 0.4 }
  ],
  "features": [
    {
      "name": "overall_l", "kind": "length", "value": 42.18, "tolerance": 0.10,
      "faceIds": ["A1…"], "spread": 0.0, "flagged": false,
      "measurements": [
        { "faceId": "A1…", "value": 42.18, "p1": [0.171, 0.448], "p2": [0.811, 0.448],
          "source": "typed", "at": "2026-09-17T14:03:11Z" }
      ]
    }
  ]
}
```

Export bundle is a directory `<slug>.ccpart/` containing `features.json`, `faces/<kind>.jpg`, `faces/<kind>_dimensioned.png`, zipped as `<slug>.ccpart.zip` for the share sheet. Paths inside JSON are relative to the bundle root.

**MCP skill contract (built against this schema, in parallel, not in this repo):** for each `feature`, create or update a user parameter `name = value units` with a comment carrying `tolerance` and `faceIds`; for each `face`, create a sketch named `<slug>_<kind>` on the matching plane (top→XY, side→XZ, end→YZ, detail→XY) with the annotated image attached as a canvas at unit scale; never invent geometry — the sketch contains only the canvas and the parameters exist for the human to constrain against.

## 8. Modules, in build order, with acceptance criteria

Build one module, run its tests, commit, then the next. Do not start module N+1 with failing tests in N.

### M1 — `CaliperCore` package (day 1–2)

- [ ] Models in §6 compile with `Codable` and round-trip through `JSONEncoder`/`JSONDecoder` losslessly (test with a fixture part of 3 faces, 9 dimensions).
- [ ] `FeatureName.validate(_:)` accepts `overall_l`, `hole_dia2`; rejects `Overall_L`, `2nd_hole`, `pi`, `sqrt`, 33-char names, empty.
- [ ] `Part.slug(from:)` turns `"Norcold freezer hinge pin"` into `norcold_freezer_hinge_pin` and `"2018 NB bezel"` into `p_2018_nb_bezel`.
- [ ] `reconcile` on the fixture returns 9 features sorted by name; a two-face `pin_dia` of 6.50/6.52 with tolerance 0.05 yields value 6.51, spread 0.02, `flagged == false`; the same with 6.40/6.52 yields `flagged == true`.
- [ ] `reconcile` returns `.kindConflict` when `wall` is `length` on one face and `depth` on another.
- [ ] `FeaturesDocument.make(part:faces:dimensions:)` produces JSON matching §7 byte-for-byte against a checked-in golden file (dates injected).
- [ ] 100% of `CaliperCore` public API is documented with a one-line summary.

### M2 — Persistence and navigation (day 3–4)

- [ ] SwiftData store with `PartRecord`, `FaceRecord`, `DimensionRecord`; mapping to/from `CaliperCore` value types lives in one file, tested.
- [ ] Parts list: create part (name, units), rename, delete with confirmation. Empty state names the first action.
- [ ] Part screen: faces row, features table (name, value, tolerance, faces), reconciliation warning row when any feature is `flagged` or when `kindConflict`.
- [ ] Given a part with unsaved dimension text in the field, when the app is force-quit, then reopening shows the part with every *saved* dimension intact.
- [ ] Images are written to `Documents/parts/<partID>/<faceKind>.jpg` by an actor; a face record is never saved before its file write completes.

### M3 — Capture (day 5–6)

- [ ] Face picker (top/side/end/detail); capturing the same kind again replaces the image after confirmation and keeps dimensions only if the user confirms "keep" (default: discard).
- [ ] In-app camera via `AVFoundation` with a shutter button ≥ 60 pt; photo saved at full resolution; `levelDegrees` captured from `CoreMotion` at shutter time.
- [ ] Import from Photos via `PhotosPicker` sets `levelDegrees = nil`.
- [ ] Given camera permission denied, when the user opens Capture, then the import path is offered and the denial is explained in one sentence with a Settings link.

### M4 — Annotate (day 7–10) — the core screen

- [ ] Image view with pinch-zoom and pan; taps are converted to `NormalizedPoint` in image space regardless of zoom, verified by a UI test that taps the same physical feature at 1× and 3× and gets points within 0.005.
- [ ] Two-tap dimension: first tap places p1 (handle drawn), second tap places p2 and draws the dimension line with extension ticks; either handle is draggable afterwards.
- [ ] Reading field: numeric keypad, accepts `42.18`, `.5`, `42`, `1 3/8` (fractional inches only when units are inch); rejects negatives and empty; shows the part units.
- [ ] Name field with suggestion chips (§6.1 order); invalid names show the rule inline and disable Save.
- [ ] Kind segmented control (length/diameter/depth) and tolerance field defaulting to the part's last-used tolerance (initial 0.10 mm / 0.005 in).
- [ ] Save writes the dimension, clears the reading and name, keeps kind and tolerance, and advances focus to the next tap — a "hands stay on the part" loop.
- [ ] Existing dimensions on the face render dimmed; tapping one selects it for edit or delete.
- [ ] `ReadingInput` is a protocol with one conformer `KeyboardReadingInput`; the annotate view model depends on the protocol, not the conformer (this is the BLE seam, §9).

### M5 — Export (day 11–12)

- [ ] Dimensioned PNG per face rendered with SwiftUI `ImageRenderer` at the source image's pixel size: dimension lines, ticks, name and value labels with a solid pill behind text, minimum label height 2% of image height.
- [ ] Bundle assembled by an actor into a temp directory, zipped, offered via the share sheet; also "Save to Files".
- [ ] Given a part with a `kindConflict`, when the user taps Export, then export is blocked with the offending name shown.
- [ ] Given a flagged feature, when the user exports, then export proceeds and the JSON carries `flagged: true` — never silently averaged away.
- [ ] Re-export of an unchanged part produces identical `features.json` except `exportedAt`.

### M6 — Dogfood instrumentation (day 12)

- [ ] A per-part timer starts at first capture and stops at first export; elapsed hands-on time is shown on the part screen and included in JSON under `"telemetry": {"handsOnSeconds": …}` (local only, no upload).
- [ ] Debug screen: export the last 20 timer results as CSV.

## 9. BLE seam (design now, build in v1)

`protocol ReadingInput { var readings: AsyncStream<Reading> { get } }` with `struct Reading { value: Double; units: Units; source: ReadingSource; hold: Bool }`. v1 adds `BLEReadingInput` over CoreBluetooth against this GATT service (so the dongle firmware can be built in parallel):

- Service UUID `7A1C0001-3B6E-4F8D-9C2A-5E7F1D2B3C4D`
- Reading characteristic `7A1C0002-…`, notify, 6 bytes: `Int32` little-endian value in micrometers (inch readings converted by the dongle), `UInt8` units flag (0 = mm, 1 = inch source), `UInt8` flags (bit0 = hold).
- Battery: standard Battery Service `0x180F`.
- Dongle side: ESP32 reading Digimatic SPC (52-bit, 13 nibbles) or the 24-bit "cheap caliper" protocol, selected by a jumper; both are documented by hobbyists.

## 10. Testing

- `CaliperCore`: XCTest, target 100% line coverage on codec, names, slug, reconcile.
- App: one UI test for the golden path — create part, import fixture image, add 3 dimensions, export, assert bundle contents.
- Fixture: `Fixtures/hinge_pin/` with three JPEGs and a `features.json` golden file, checked in.
- No snapshot tests in v0.

## 11. Dogfood protocol and success metric

1. Baseline: time yourself on two parts with the notepad + Fusion process you use today. Record minutes and how many parameters you had to name by hand.
2. v0: five parts — the TPU battery tray mount, the washer-nozzle plug, the Norcold hinge pin, one Hehr window clip, one part of your choice. Record `handsOnSeconds` plus the minutes to a constrained Fusion sketch.
3. Pass: median v0 total ≤ 70% of baseline and every export produced correctly named parameters in Fusion. Fail: anything else → stop, write down why, decide.

## 12. Open questions

- **Blocking (Dwight):** fractional-inch input in v0, or mm-only until v1? Recommendation: mm-only; inch as a display toggle.
- **Non-blocking (engineering):** does `ImageRenderer` at 4032×3024 stay under memory pressure on an iPhone 13? If not, render at 2048 wide and record the scale in JSON.
- **Non-blocking (Dwight):** which plane mapping for `detail` faces in the MCP skill — XY is the placeholder.

## 13. Instructions for Claude Code (paste into `CLAUDE.md`)

```
Read SPEC.md fully before writing code. Build modules M1→M6 in order; tests first for M1, tests alongside for the rest.
Swift 6, strict concurrency, iOS 18, SwiftUI, SwiftData, zero third-party packages.
Apply the swift-best-practices skill on every file.
Do not build anything listed under Non-goals or the BLE section — the protocol seam only.
Do not change features.json shape; if the schema must change, stop and ask.
One commit per acceptance-criteria checkbox group; commit message names the module and the criteria met.
When a criterion is ambiguous, pick the simplest reading, note it in the commit body, keep going.
```

## 14. Architecture addendum (Dwight, 2026-09-17)

Use an Elm-style TEA architecture (Model / Msg / update / view) and Elm-style types wherever possible. It is a native Swift app, not ReScript — see `docs/ARCHITECTURE.md` for how TEA maps onto SwiftUI here.
