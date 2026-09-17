# Architecture — TEA on SwiftUI

Caliper Companion is an Elm-architecture app written in Swift. Every screen is a `Program`:
a `Model` (one struct), a `Msg` (one enum), a pure `update`, and a `view` that is a pure function
of the model. Side effects are `Cmd` values returned from `update` and executed at the edge by a
`Store`. Nothing in `update` touches the disk, the camera, SwiftData, or the clock.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CaliperCompanion  (Xcode app target — iOS 18, SwiftUI, SwiftData, AVF)     │
│                                                                             │
│   SwiftUI View ── send(Msg) ──▶ Store<P> ── P.update(&model, msg) ──▶ [Cmd] │
│        ▲                          │                                    │    │
│        └──── reads store.model ◀──┘        EffectHandler runs each Cmd ◀┘    │
│                                            (SwiftData, ImageStore actor,    │
│                                             camera, ImageRenderer, share)   │
│                                            …and dispatches result Msgs back │
├─────────────────────────────────────────────────────────────────────────────┤
│  CaliperFlow  (pure Swift, tested on Linux) — the "Elm" layer               │
│   Program protocol · Store · AnnotateProgram · CaptureProgram · PartSummary │
│   ExportPlan · AnnotationLayout · HandsOnTimer · TelemetryCSV               │
│   KeyboardReadingInput · ImageStore (actor) · ExportBundler (actor)         │
├─────────────────────────────────────────────────────────────────────────────┤
│  CaliperCore  (pure Swift, tested on Linux) — the domain                    │
│   Units · FaceKind · DimensionKind · ReadingSource · NormalizedPoint        │
│   Dimension · Face · Part · Feature · FeatureName · Part.slug(from:)        │
│   reconcile · FeaturesDocument (features.json codec) · ReadingText          │
│   ZipArchive · Reading · ReadingInput (BLE seam)                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

Both `CaliperCore` and `CaliperFlow` are targets of the local package at `CaliperCore/`. Neither
imports UIKit, SwiftUI, SwiftData, AVFoundation, CoreMotion or Photos. That is what lets them build
and test on Linux with `swift test`.

## Why the Elm layer is separate from the domain

`CaliperCore` is what SPEC.md §5 asks for: models, codec, reconciliation. `CaliperFlow` is the
addendum in §14: the per-screen state machines. Keeping them apart means the frozen JSON contract
(`FeaturesDocument`) never depends on UI state, and the UI state machines can be tested with plain
value comparisons — no SwiftUI, no simulator.

## The runtime

```swift
public protocol Program {
    associatedtype Model: Sendable & Equatable
    associatedtype Msg: Sendable
    associatedtype Cmd: Sendable & Equatable
    /// Pure. Mutates the model in place and returns the effects to run, in order.
    static func update(_ model: inout Model, _ msg: Msg) -> [Cmd]
}

/// Runs `Cmd`s at the edge. Implemented in the app target (SwiftData, camera, files…)
/// and by test doubles in CaliperFlowTests.
public protocol EffectHandler<P>: Sendable {
    associatedtype P: Program
    func run(_ cmd: P.Cmd, dispatch: @escaping @MainActor @Sendable (P.Msg) -> Void) async
}

@MainActor @Observable
public final class Store<P: Program> {
    public private(set) var model: P.Model
    public init(model: P.Model, effects: some EffectHandler<P>)
    /// Runs `P.update`, then starts one Task per returned Cmd. Effects dispatch Msgs back via `send`.
    public func send(_ msg: P.Msg)
}
```

Elm mapping, for orientation:

| Elm                              | Here                                                 |
|----------------------------------|------------------------------------------------------|
| `Model`                          | `P.Model` struct                                     |
| `Msg`                            | `P.Msg` enum                                         |
| `update : Msg -> Model -> (Model, Cmd Msg)` | `static func update(_ model: inout Model, _ msg: Msg) -> [Cmd]` |
| `Cmd Msg`                        | `P.Cmd` enum, interpreted by an `EffectHandler`      |
| `Sub Msg`                        | SwiftData `@Query` (read-only subscription) and `ReadingInput.readings` |
| `view : Model -> Html Msg`       | SwiftUI `View` reading `store.model`, calling `store.send` |

`update` never calls `UUID()` or `Date()`. Anything that needs fresh identity or the clock is a
`Cmd` (e.g. `.persist(NewDimension)`); the effect handler mints the id/date and reports back with a
Msg (`.persistSucceeded(Dimension)`).

### Persistence compromise

SwiftData is the database at the edge. Lists (parts, faces, dimensions) are read with `@Query` in
views — that is our `Sub`. Every *mutation* goes through a `Cmd`. The annotate screen, which is the
interactive core, keeps its own copy of the face's dimensions in its `Model` so the two-tap loop is
fully testable without SwiftData.

## `CaliperCore` public API (source of truth for M1)

Enums and structs exactly as SPEC.md §6, all `Sendable`, all `Codable`, plus `CaseIterable` on
`Units`, `FaceKind`, `DimensionKind`. Every public declaration carries a one-line `///` summary.

```swift
public enum FeatureNameError: Error, Equatable, Sendable {
    case empty, tooLong(max: Int), mustStartWithLetter, invalidCharacters, reserved(String)
    /// One sentence suitable for inline display under the name field.
    public var rule: String { get }
}

public enum FeatureName {
    public static let maxLength = 32
    public static let reserved: Set<String>                 // pi, e, sin, cos, tan, sqrt, abs, floor, ceil, round, min, max, log, ln, exp
    public static let defaults: [String]                    // overall_l, overall_w, overall_h, hole_dia, wall, slot_w, slot_l, chamfer
    public static func validate(_ name: String) -> Result<String, FeatureNameError>
    public static func isValid(_ name: String) -> Bool
    /// §6.1 order: `existing` (deduplicated, first-seen order) then `defaults` not already present.
    public static func suggestions(existing: [String]) -> [String]
}

extension Part {
    /// §6.1 slug rules. "Norcold freezer hinge pin" → norcold_freezer_hinge_pin; "2018 NB bezel" → p_2018_nb_bezel. Empty/unslugable → "part".
    public static func slug(from name: String) -> String
}

public enum TolerancePolicy: Sendable { case maximum, minimum }   // default .maximum (spec: tolerance = max)
public enum ReconcileError: Error, Equatable, Sendable { case kindConflict(name: String) }
/// §6.2. Groups by name; mean value; tolerance per policy; spread = max − min; flagged = spread > tolerance; sorted by name.
public func reconcile(_ dimensions: [Dimension], tolerancePolicy: TolerancePolicy = .maximum) -> Result<[Feature], ReconcileError>

public struct FeaturesDocument: Codable, Equatable, Sendable {
    public static let currentSchema = "caliper-companion/features/1"
    public struct AppInfo: Codable, Equatable, Sendable { public var name: String; public var version: String }
    public struct PartInfo: Codable, Equatable, Sendable { public var id: UUID; public var name: String; public var slug: String; public var units: Units; public var notes: String }
    public struct FaceEntry: Codable, Equatable, Sendable { public var id: UUID; public var kind: FaceKind; public var image: String; public var annotated: String; public var pixelWidth: Int; public var pixelHeight: Int; public var levelDegrees: Double? }
    public struct Measurement: Codable, Equatable, Sendable { public var faceId: UUID; public var value: Double; public var p1: [Double]; public var p2: [Double]; public var source: ReadingSource; public var at: Date }
    public struct FeatureEntry: Codable, Equatable, Sendable { public var name: String; public var kind: DimensionKind; public var value: Double; public var tolerance: Double; public var faceIds: [UUID]; public var spread: Double; public var flagged: Bool; public var measurements: [Measurement] }
    public struct Telemetry: Codable, Equatable, Sendable { public var handsOnSeconds: Int }

    public var schema: String
    public var exportedAt: Date
    public var app: AppInfo
    public var part: PartInfo
    public var faces: [FaceEntry]
    public var features: [FeatureEntry]
    public var telemetry: Telemetry?          // M6; omitted from JSON when nil

    /// Builds the document. Faces ordered top, side, end, detail then capturedAt; features by name; measurements by createdAt then id.
    /// image = "faces/<kind>.jpg", annotated = "faces/<kind>_dimensioned.png". Throws on kindConflict.
    public static func make(part: Part, faces: [Face], dimensions: [Dimension], exportedAt: Date, appVersion: String, telemetry: Telemetry? = nil) throws(ReconcileError) -> FeaturesDocument
    /// Deterministic bytes: sortedKeys + prettyPrinted + withoutEscapingSlashes, ISO-8601 dates (no fractional seconds), UUIDs uppercase.
    public func encoded() throws -> Data
    public static func decode(_ data: Data) throws -> FeaturesDocument
}

public enum ReadingText {
    /// "42.18", ".5", "42", and (inch only) "1 3/8", "3/8". Rejects negatives, empty, zero denominators, junk. Whitespace-trimmed.
    public static func parse(_ text: String, units: Units) -> Double?
    /// mm → 2 decimals, inch → 4 decimals, trailing zeros kept ("6.50"). Used to refill the field on edit and for labels.
    public static func format(_ value: Double, units: Units) -> String
}

/// Minimal ZIP writer: STORE method only, CRC-32, one local header per file, central directory, EOCD. No ZIP64.
public struct ZipArchive: Sendable {
    public init()
    public mutating func addFile(path: String, data: Data, modified: Date)
    public func serialized() -> Data
}

/// §9 BLE seam.
public struct Reading: Sendable, Equatable { public var value: Double; public var units: Units; public var source: ReadingSource; public var hold: Bool }
public protocol ReadingInput: Sendable { var readings: AsyncStream<Reading> { get } }

extension Units {
    /// Converts a value between mm and inch (25.4 mm per inch). Same units → identity.
    public static func convert(_ value: Double, from: Units, to: Units) -> Double
    /// Initial tolerance per SPEC M4: 0.10 mm / 0.005 in.
    public var defaultTolerance: Double { get }
    /// "mm" / "in" for display.
    public var symbol: String { get }
}
```

JSON notes: `.sortedKeys` means key order is alphabetical, not the illustrative order in SPEC §7.
JSON is order-insensitive and the MCP skill parses it, so this is fine; the golden file in
`Fixtures/hinge_pin/features.json` is the canonical byte layout. iOS 18 and the Linux toolchain both
use the swift-foundation `JSONEncoder`, so the golden is expected to match on device; if it ever
doesn't, that's a Foundation difference to record in LOGBOOK.md, not a reason to hand-roll JSON.

## `CaliperFlow` public API (source of truth for M2–M6 logic)

### AnnotateProgram (M4)

```swift
public enum AnnotateProgram: Program {
    public enum Pending: Sendable, Equatable { case none, one(NormalizedPoint), two(NormalizedPoint, NormalizedPoint) }
    public enum Handle: Sendable, Equatable { case p1, p2 }
    public enum Field: Sendable, Equatable { case reading, name, tolerance }
    public enum Notice: Sendable, Equatable {
        case kindConflict(name: String, existingKind: DimensionKind)   // name used elsewhere with another kind
        case persistFailed(String)
    }
    /// Everything needed to mint a Dimension except id/createdAt (the effect handler supplies those).
    public struct NewDimension: Sendable, Equatable {
        public var faceID: UUID; public var name: String; public var kind: DimensionKind; public var value: Double
        public var tolerance: Double; public var p1: NormalizedPoint; public var p2: NormalizedPoint; public var source: ReadingSource
    }
    public struct Model: Sendable, Equatable {
        public var face: Face
        public var units: Units
        public var dimensions: [Dimension]                   // saved on this face, createdAt order
        public var knownKinds: [String: DimensionKind]       // name → kind for dimensions on OTHER faces of the part
        public var pending: Pending
        public var readingText: String
        public var nameText: String
        public var kind: DimensionKind
        public var toleranceText: String
        public var readingSource: ReadingSource              // .typed unless the last fill came from ReadingInput with .ble
        public var selectedDimensionID: UUID?
        public var inFlight: NewDimension?                   // awaiting persistSucceeded
        public var notice: Notice?
        public var focus: Field?                             // nil = hands on the image

        // Derived (computed, not stored):
        public var readingValue: Double?                     // ReadingText.parse(readingText, units:)
        public var toleranceValue: Double?                   // ReadingText.parse(toleranceText, units:)
        public var nameValidation: Result<String, FeatureNameError>
        public var suggestions: [String]                     // FeatureName.suggestions(existing: knownKinds.keys sorted + own names)
        public var kindConflict: DimensionKind?              // knownKinds[nameText] when it differs from kind
        public var canSave: Bool                             // pending == .two (or a selection) && reading, tolerance, name valid && kindConflict == nil
    }
    public enum Msg: Sendable, Equatable {
        case imageTapped(NormalizedPoint)
        case handleDragged(Handle, to: NormalizedPoint)
        case readingTextChanged(String)
        case nameTextChanged(String)
        case suggestionTapped(String)
        case kindChanged(DimensionKind)
        case toleranceTextChanged(String)
        case fieldFocused(Field?)
        case saveTapped
        case dimensionTapped(UUID)
        case deselectTapped
        case deleteSelectedTapped
        case clearPendingTapped
        case readingReceived(Reading)                        // from any ReadingInput
        case persistSucceeded(Dimension)
        case persistFailed(String)
        case updateSucceeded(Dimension)
        case deleteSucceeded(UUID)
    }
    public enum Cmd: Sendable, Equatable {
        case persist(NewDimension)
        case update(Dimension)
        case delete(UUID)
    }
    public static func initial(face: Face, units: Units, dimensions: [Dimension], otherFaceDimensions: [Dimension], lastTolerance: Double?) -> Model
    public static func update(_ model: inout Model, _ msg: Msg) -> [Cmd]
}
```

Rules `update` must implement (each is a test):

1. `imageTapped` with `.none` → `.one(p)`. With `.one(p1)` → `.two(p1, p)` and `focus = .reading`. With `.two` and nothing selected → start over: `.one(p)`. With a selection → deselect, clear fields to defaults (keep kind and tolerance), then `.one(p)`.
2. `handleDragged` moves the named point of the pending pair; when a dimension is selected it moves that dimension's point in `dimensions` and returns `[.update(dim)]`.
3. `saveTapped` when `!canSave` → no change, no cmds. When `canSave` and no selection → `inFlight = NewDimension(...)`, `readingText = ""`, `nameText = ""`, `pending = .none`, `focus = nil`, `notice = nil`, `readingSource = .typed`; returns `[.persist(new)]`. Kind and tolerance are kept. When a dimension is selected → the selection is edited in place with the field values and `[.update(dim)]` is returned; selection cleared; fields cleared the same way.
4. `persistSucceeded(d)` → append `d` to `dimensions`, `inFlight = nil`. `persistFailed(msg)` → restore the fields from `inFlight` (reading via `ReadingText.format`, name, kind, tolerance, pending `.two`), `inFlight = nil`, `notice = .persistFailed(msg)`.
5. `dimensionTapped(id)` → `selectedDimensionID = id`, fields filled from it, `pending = .none`. `deselectTapped` → clear selection and fields (keep kind/tolerance). `deleteSelectedTapped` → remove from `dimensions`, clear selection and fields, `[.delete(id)]`. `deleteSucceeded` → no-op if already removed.
6. `suggestionTapped(name)` → `nameText = name`; if `knownKinds[name]` exists, also `kind = knownKinds[name]` (a suggestion from another face carries its kind so reconcile can't conflict).
7. `readingReceived(r)` → `readingText = ReadingText.format(Units.convert(r.value, from: r.units, to: model.units), units: model.units)`, `readingSource = r.source`. Ignored when `r.hold == false`.
8. `nameTextChanged` → set text; `notice = .kindConflict(...)` when `kindConflict != nil`, else clear a kindConflict notice. `kindChanged` re-evaluates the same.
9. `initial(...)`: `toleranceText = ReadingText.format(lastTolerance ?? units.defaultTolerance, units:)`, `kind = .length`, everything else empty/none.

### CaptureProgram (M3)

```swift
public enum CaptureProgram: Program {
    public struct Captured: Sendable, Equatable { public var imageData: Data; public var pixelWidth: Int; public var pixelHeight: Int; public var levelDegrees: Double? }
    public enum CameraAuthorization: Sendable, Equatable { case unknown, authorized, denied }
    public enum Stage: Sendable, Equatable {
        case pickingKind
        case capturing(FaceKind)
        case confirmingReplace(FaceKind, Captured, existing: Face, dimensionCount: Int)
        case saving(FaceKind)
        case saved(Face)
        case failed(String)
    }
    public struct Model: Sendable, Equatable {
        public var part: Part
        public var faces: [Face]
        public var dimensionCounts: [UUID: Int]     // faceID → number of dimensions on it
        public var camera: CameraAuthorization
        public var stage: Stage
        public var keepDimensions: Bool             // toggle in the confirm sheet; default false (spec: default discard)
        public var canUseCamera: Bool { camera == .authorized }   // derived
    }
    public enum Msg: Sendable, Equatable {
        case kindPicked(FaceKind)
        case cameraAuthorizationChanged(CameraAuthorization)
        case photoCaptured(Captured)                // in-app camera; levelDegrees set
        case photoImported(Captured)                // PhotosPicker; levelDegrees forced nil in update
        case keepDimensionsToggled(Bool)
        case replaceConfirmed
        case replaceCancelled
        case saveSucceeded(Face)
        case saveFailed(String)
        case backTapped
    }
    public enum Cmd: Sendable, Equatable {
        case requestCameraAuthorization
        case saveFace(kind: FaceKind, captured: Captured, replacing: Face?, keepDimensions: Bool)
    }
    public static func initial(part: Part, faces: [Face], dimensions: [Dimension]) -> Model     // stage .pickingKind, camera .unknown, returns no cmd; the view sends nothing until it appears
    public static func update(_ model: inout Model, _ msg: Msg) -> [Cmd]
}
```

Rules: `kindPicked(k)` → `.capturing(k)` and `[.requestCameraAuthorization]` if `camera == .unknown`. A captured/imported photo for a kind that already has a face → `.confirmingReplace(...)` with `keepDimensions = false`; otherwise → `.saving(k)` and `[.saveFace(replacing: nil, keepDimensions: false)]`. `replaceConfirmed` → `.saving` + `[.saveFace(replacing: existing, keepDimensions: model.keepDimensions)]`. `replaceCancelled` → back to `.capturing(k)`. `photoImported` always ends with `levelDegrees == nil` even if the caller set it. `saveSucceeded(face)` → `.saved(face)` and `faces` updated (replace same-kind). `backTapped` from `.capturing` → `.pickingKind`.

### PartSummary (M2 part screen)

```swift
public struct PartSummary: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable { public var id: String { name }; public var name: String; public var kind: DimensionKind; public var value: Double; public var tolerance: Double; public var faceKinds: [FaceKind]; public var flagged: Bool }
    public enum Warning: Sendable, Equatable { case flagged(names: [String]); case kindConflict(name: String) }
    public var rows: [Row]
    public var warning: Warning?
    /// Pure. rows from reconcile (empty on kindConflict), faceKinds in top/side/end/detail order.
    public static func make(faces: [Face], dimensions: [Dimension]) -> PartSummary
}
```

### ExportPlan (M5)

```swift
public enum ExportPlan {
    public struct FaceFiles: Sendable, Equatable { public var face: Face; public var imagePath: String; public var annotatedPath: String }
    public struct Plan: Sendable, Equatable { public var bundleDirectoryName: String /* <slug>.ccpart */; public var zipFilename: String /* <slug>.ccpart.zip */; public var document: FeaturesDocument; public var faceFiles: [FaceFiles] }
    public enum Block: Error, Sendable, Equatable { case kindConflict(name: String), noFaces }
    public static func make(part: Part, faces: [Face], dimensions: [Dimension], exportedAt: Date, appVersion: String, handsOnSeconds: Int?) -> Result<Plan, Block>
}
```

### AnnotationLayout (M4 on-screen drawing and M5 PNG)

Pure geometry in pixel space so the SwiftUI renderer only draws primitives:

```swift
public struct AnnotationLayout: Sendable, Equatable {
    public struct Point: Sendable, Equatable { public var x: Double; public var y: Double }
    public struct Line: Sendable, Equatable { public var from: Point; public var to: Point; public var width: Double }
    public struct Label: Sendable, Equatable { public var text: String; public var center: Point; public var height: Double; public var dimensionID: UUID }
    public struct DimensionDrawing: Sendable, Equatable, Identifiable { public var id: UUID; public var line: Line; public var ticks: [Line]; public var handles: [Point]; public var label: Label }
    public var drawings: [DimensionDrawing]
    public var width: Double
    public var height: Double
    /// lineWidth = max(2, 0.3% of height); tick length = 1.5% of height, perpendicular at each end; label height = max(2% of height, 12);
    /// label text = "<name> <ReadingText.format(value)> <units.symbol>" (diameter prefixed "⌀"); label centered on the line midpoint, offset one label-height toward the image top.
    public static func make(pixelWidth: Int, pixelHeight: Int, dimensions: [Dimension], units: Units) -> AnnotationLayout
    /// Same primitives for an in-progress pair (no label text yet beyond the reading text if non-empty).
    public static func pending(p1: NormalizedPoint, p2: NormalizedPoint?, pixelWidth: Int, pixelHeight: Int) -> DimensionDrawing?
}
```

### Telemetry (M6)

```swift
public struct HandsOnTimer: Codable, Sendable, Equatable {
    public var startedAt: Date?; public var stoppedAt: Date?
    public init(startedAt: Date? = nil, stoppedAt: Date? = nil)
    public mutating func recordCapture(at now: Date)   // starts if not started
    public mutating func recordExport(at now: Date)    // stops if started and not stopped
    public func elapsedSeconds(now: Date) -> Int?      // nil until started; running value until stopped
}
public struct TimerResult: Sendable, Equatable { public var partName: String; public var slug: String; public var handsOnSeconds: Int; public var exportedAt: Date }
public enum TelemetryCSV {
    /// Header `part,slug,hands_on_seconds,exported_at`; most recent first; at most 20 rows; RFC 4180 quoting; ISO-8601 dates.
    public static func make(_ results: [TimerResult]) -> String
}
```

### KeyboardReadingInput (M4, the one `ReadingInput` conformer in v0)

```swift
public final class KeyboardReadingInput: ReadingInput, Sendable {
    public let readings: AsyncStream<Reading>
    public init()
    /// Parses with ReadingText; on success yields Reading(source: .typed, hold: true) and returns true.
    public func submit(_ text: String, units: Units) -> Bool
}
```

### ImageStore (M2) and ExportBundler (M5) — actors, Foundation only

```swift
public actor ImageStore {
    public init(baseURL: URL)                                        // app passes Documents/
    /// Writes to <base>/parts/<partID>/<kind>.jpg atomically; returns the filename "<kind>.jpg". Overwrites.
    public func write(jpeg data: Data, partID: UUID, kind: FaceKind) throws -> String
    public func url(partID: UUID, filename: String) -> URL
    public func read(partID: UUID, filename: String) throws -> Data
    public func delete(partID: UUID, filename: String) throws
    public func deletePart(_ partID: UUID) throws
}

public actor ExportBundler {
    public init(temporaryDirectory: URL)
    /// Creates <tmp>/<bundleDirectoryName>/ with features.json, faces/<kind>.jpg (from `jpegs`), faces/<kind>_dimensioned.png (from `pngs`),
    /// then zips it to <tmp>/<zipFilename> with ZipArchive. Returns (bundleURL, zipURL). Checks Task cancellation between files.
    public func assemble(_ plan: ExportPlan.Plan, jpegs: [UUID: Data], pngs: [UUID: Data]) async throws -> (bundle: URL, zip: URL)
}
```

## App target conventions (Mac-only, SwiftUI)

- Every view is `@MainActor` and reads `store.model`; it never mutates state directly.
- Effect handlers are small `struct`s conforming to `EffectHandler`, one per program, living next to
  the program's view: `AnnotateEffects`, `CaptureEffects`, `ExportEffects`.
- SwiftData `@Model` classes (`PartRecord`, `FaceRecord`, `DimensionRecord`) and their value
  mapping live in `CaliperCompanion/Persistence/Records.swift` — one file, as the spec requires.
- `ImageStore` is the only writer of JPEGs. A `FaceRecord` is inserted only after
  `ImageStore.write` returns (M2 last criterion).
- `PartRecord` carries `handsOnStartedAt`/`handsOnStoppedAt` for `HandsOnTimer` and
  `lastTolerance` for the annotate default.

## What is verified where

| Layer            | Built and tested on Linux (this repo's CI/sandbox) | Needs a Mac |
|------------------|----------------------------------------------------|-------------|
| CaliperCore      | ✅ `swift test`                                    |             |
| CaliperFlow      | ✅ `swift test`                                    |             |
| CaliperCompanion | ❌ (SwiftUI/SwiftData/AVFoundation)                | ✅ `xcodegen generate` → Xcode build → UI test |
