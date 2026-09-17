// Capture — the face picker + camera/library capture flow (SPEC M3, all
// four bullets). `init` takes the route's `partId`; the exported contract
// (`model`/`msg`/`init`/`update`/`title`/`back`/`view`) matches the M6 stub
// it replaces so `Main.res` needs no changes.
//
// TEA discipline (CLAUDE.md "Architecture"): all Store/decode work is a
// `Tea.cmd` built in `update`, never run inline in `view`; `view` stays a
// pure function of `model`. See the module-end notes for the judgment
// calls this page makes where SPEC left the exact reading open.
//
// Design wave 2 (DESIGN.md §11, §11.2 "Capture"): restyled onto the wave-1
// foundation (Ui/Icon/theme/global). Model/update below is the same M3
// state machine plus two purely UI-only additions the task brief allows:
// `selectedKind` (which chip/slot is active) and `faceImages` (object URLs
// for the slot thumbnails, mirroring Part.res's own cheap-thumbnail
// pattern). Nothing about the file-input/decode/save/recapture flow itself
// changed — see the notes at the end of this file for what's new and why.

// -- model -------------------------------------------------------------

type pendingCapture = {
  kind: Types.faceKind,
  // The bytes actually destined for `Store.putFace` — already the
  // SPEC §8a A4 resize/re-encode outcome (or the picked file verbatim,
  // unchanged, if it was already at or under the cap), decided once at
  // `Decoded` so recapture-confirm/keep just replays this, no re-decode.
  image: PouchDb.blob,
  contentType: string,
  pixelWidth: int,
  pixelHeight: int,
  levelDegrees: option<float>,
  existingFaceId: string,
  fromLibrary: bool,
}

type dialog =
  | NoDialog
  | RecaptureConfirm(pendingCapture)

type model = {
  partId: string,
  // `Store.getPart` hasn't resolved yet vs. resolved to `None` are two
  // different states the view must tell apart ("Part not found") — see
  // `status` below.
  partChecked: bool,
  partExists: bool,
  faces: array<Types.face>,
  // faceId -> object URL (Download.objectUrlOfImage), Part.res's own cheap
  // thumbnail pattern reused for the slot row (DESIGN.md §11.2).
  faceImages: Dict.t<string>,
  // UI-only (task brief: "a msg may be added for UI-only state such as
  // 'selected kind chip'"): which chip/slot/shutter target is active.
  selectedKind: Types.faceKind,
  // True once the user taps a chip/slot — stops a (currently single, but
  // future-proofed) `GotFaces` from overriding their choice with the
  // "first kind without a face" default.
  kindManuallySelected: bool,
  cameraDenied: bool,
  // "Request once per page life" (SPEC M3 bullet 2): this flag is set the
  // first time any capture label is armed, whether or not the platform
  // actually exposes `requestPermission`.
  orientationRequested: bool,
  orientationDenied: bool,
  lastBeta: option<float>,
  lastGamma: option<float>,
  // The level snapshotted at the last capture-label pointerdown — SPEC:
  // "levelDegrees is snapshotted at the moment the capture input is
  // opened … never at file-change time". Read (and reset) at `FileChosen`.
  armedLevel: option<float>,
  // One generation counter per (kind, source) `<input>`, used as a React
  // `key` to force-remount the element and clear its native file value —
  // see `bumpGen` below for why this fires on every selection, not just
  // cancel.
  inputGens: Dict.t<int>,
  busy: option<Types.faceKind>,
  error: option<(Types.faceKind, string)>,
  dialog: dialog,
}

type status = Loading | NotFound | Found

let statusOf = (model: model): status =>
  !model.partChecked ? Loading : model.partExists ? Found : NotFound

type msg =
  | GotPart(option<Types.part>)
  | GotFaces(array<Types.face>)
  | FaceImageLoaded(string, option<string>)
  | SelectKind(Types.faceKind)
  | CameraPermissionChecked(bool)
  | OrientationSample(option<float>, option<float>)
  | CaptureArmed
  | OrientationPermissionResult(option<Orientation.permissionState>)
  | FileChosen(Types.faceKind, bool, option<ImageDecode.file>)
  | Decoded(Types.faceKind, bool, PouchDb.blob, string, int, int, option<float>)
  | DecodeFailed(Types.faceKind, string)
  | Saved(Types.face)
  | SaveFailed(Types.faceKind, string)
  | TimerStarted(string)
  | RecaptureConfirmClicked
  | RecaptureKeepClicked
  | RecaptureCancelClicked
  | DimensionsDeletedThenSave
  | DeleteDimensionsFailed(string)

// -- pure helpers --------------------------------------------------------

let existingFaceOf = (faces: array<Types.face>, kind: Types.faceKind): option<Types.face> =>
  Array.find(faces, f => f.kind == kind)

// UI-only default (DESIGN.md §11.2): the first kind without a face, else Top.
let defaultKind = (faces: array<Types.face>): Types.faceKind =>
  Enums.allFaceKinds
  ->Array.find(kind => existingFaceOf(faces, kind)->Option.isNone)
  ->Option.getOr(Types.Top)

let upsertFace = (faces: array<Types.face>, face: Types.face): array<Types.face> => {
  let replaced = ref(false)
  let next = faces->Array.map(f =>
    if f.id == face.id {
      replaced := true
      face
    } else {
      f
    }
  )
  replaced.contents ? next : Array.concat(next, [face])
}

// Judgment call (SPEC doesn't define a formula): the Euclidean norm of the
// two tilt axes the DOM exposes, a common "bubble level" magnitude — 0°
// is dead flat, larger is more tilted, regardless of which axis. Falls
// back to the one available axis if the sensor only reports one.
let levelFromSamples = (beta: option<float>, gamma: option<float>): option<float> =>
  switch (beta, gamma) {
  | (Some(b), Some(g)) => Some(Math.sqrt(b *. b +. g *. g))
  | (Some(b), None) => Some(Math.abs(b))
  | (None, Some(g)) => Some(Math.abs(g))
  | (None, None) => None
  }

let genKey = (kind: Types.faceKind, ~fromLibrary: bool): string =>
  Enums.faceKindToString(kind) ++ (fromLibrary ? "-lib" : "-cam")

let genFor = (gens: Dict.t<int>, kind: Types.faceKind, ~fromLibrary: bool): int =>
  Dict.get(gens, genKey(kind, ~fromLibrary))->Option.getOr(0)

let bumpGen = (gens: Dict.t<int>, kind: Types.faceKind, ~fromLibrary: bool): Dict.t<int> => {
  let next = Dict.copy(gens)
  Dict.set(next, genKey(kind, ~fromLibrary), genFor(gens, kind, ~fromLibrary) + 1)
  next
}

let contentTypeOf = (file: ImageDecode.file): string =>
  switch ImageDecode.fileType(file) {
  | "" => "image/jpeg"
  | t => t
  }

// SPEC §8a A4: "a single constant so a later tier can raise the cap."
let maxLongEdge = 2048

// The stored size for a decoded bitmap — unchanged if already at or under
// `maxLongEdge` ("Images already at or below 2048 are stored exactly as
// picked"), else scaled so the long edge is exactly `maxLongEdge`. Mirrors
// `Render.targetSize`'s own long-edge-cap shape (src/app/export/Render.res)
// one layer down the pipeline.
let cappedSize = (~width: int, ~height: int): (int, int) => {
  let longEdge = Math.Int.max(width, height)
  if longEdge <= maxLongEdge {
    (width, height)
  } else {
    let k = Int.toFloat(maxLongEdge) /. Int.toFloat(longEdge)
    let w = Float.toInt(Math.round(Int.toFloat(width) *. k))
    let h = Float.toInt(Math.round(Int.toFloat(height) *. k))
    (w, h)
  }
}

// -- cmds ------------------------------------------------------------------

let saveFaceCmd = (
  ~partId: string,
  ~kind: Types.faceKind,
  ~id: string,
  ~image: PouchDb.blob,
  ~contentType: string,
  ~width: int,
  ~height: int,
  ~level: option<float>,
): Tea.cmd<msg> => {
  let face: Types.face = {
    id,
    partId,
    kind,
    imageAttachment: "image.jpg",
    pixelWidth: width,
    pixelHeight: height,
    levelDegrees: level,
    outline: None,
    capturedAt: Clock.nowIso(),
  }
  Tea.fromPromise(
    () => Store.putFace(Store.shared(), face, ~image, ~contentType),
    saved => Saved(saved),
    _err => SaveFailed(kind, "Couldn't save the photo. Try again."),
  )
}

let saveFromPending = (~partId: string, pending: pendingCapture): Tea.cmd<msg> =>
  saveFaceCmd(
    ~partId,
    ~kind=pending.kind,
    ~id=pending.existingFaceId,
    ~image=pending.image,
    ~contentType=pending.contentType,
    ~width=pending.pixelWidth,
    ~height=pending.pixelHeight,
    ~level=pending.levelDegrees,
  )

// SPEC §8a A4: decode oriented, then either keep the picked file verbatim
// (at or under `maxLongEdge`) or redraw+re-encode it capped. Bundles both
// outcomes into one shape so the caller (`FileChosen` below) doesn't need
// to know which branch ran. The bitmap is closed here — every caller of
// `decodeOriented` owns closing what it opens (mirrors `Decoded`'s own
// close in the pre-A4 version of this function).
let decodeAndCap = async (file: ImageDecode.file): (PouchDb.blob, string, int, int) => {
  let bitmap = await ImageDecode.decodeOriented(file)
  let w = ImageDecode.bitmapWidth(bitmap)
  let h = ImageDecode.bitmapHeight(bitmap)
  let (cw, ch) = cappedSize(~width=w, ~height=h)
  let result = if cw == w && ch == h {
    (ImageDecode.asBlob(file), contentTypeOf(file), w, h)
  } else {
    let resized = await ImageDecode.resizeToJpeg(bitmap, ~width=cw, ~height=ch)
    (resized, "image/jpeg", cw, ch)
  }
  ImageDecode.closeBitmap(bitmap)
  result
}

// Object URL for an already-captured face's image — cheap (no decode, just
// the stored attachment blob), same pattern as Part.res's own face tiles.
let loadFaceImageCmd = (face: Types.face): Tea.cmd<msg> =>
  Tea.fromPromise(
    () => Store.getFaceImage(Store.shared(), face.id),
    blobOpt => FaceImageLoaded(face.id, blobOpt->Option.map(Download.objectUrlOfImage)),
    _err => FaceImageLoaded(face.id, None),
  )

// -- init --------------------------------------------------------------

let init = (~partId: string): (model, Tea.cmd<msg>) => {
  let model = {
    partId,
    partChecked: false,
    partExists: false,
    faces: [],
    faceImages: Dict.make(),
    selectedKind: Types.Top,
    kindManuallySelected: false,
    cameraDenied: false,
    orientationRequested: false,
    orientationDenied: false,
    lastBeta: None,
    lastGamma: None,
    armedLevel: None,
    inputGens: Dict.make(),
    busy: None,
    error: None,
    dialog: NoDialog,
  }
  let loadPartCmd = Tea.fromPromise(
    () => Store.getPart(Store.shared(), partId),
    part => GotPart(part),
    _err => GotPart(None),
  )
  let loadFacesCmd = Tea.fromPromise(
    () => Store.facesOf(Store.shared(), ~partId),
    faces => GotFaces(faces),
    _err => GotFaces([]),
  )
  let cameraCmd = Tea.fromPromise(
    () => ImageDecode.CameraPermission.isDenied(),
    denied => CameraPermissionChecked(denied),
    _err => CameraPermissionChecked(false),
  )
  // Subscribing here (not gated on iOS permission) is deliberate: on every
  // platform that *doesn't* gate the event behind `requestPermission`,
  // samples start flowing immediately; on iOS the listener simply sits
  // idle until the user's first capture-label tap grants permission
  // (`CaptureArmed` below), so one subscription covers both cases.
  // Throttled here (not in `update`) to ~4/s per SPEC — a plain effect-
  // local timestamp, not model state, since it's a pacing detail of
  // running the effect, not something any view or other msg reads.
  let orientationCmd = Tea.effect(dispatch => {
    let lastDispatchMs = ref(0.0)
    let throttleMs = 250.0
    Orientation.subscribe((beta, gamma) => {
      let now = Date.now()
      if now -. lastDispatchMs.contents >= throttleMs {
        lastDispatchMs := now
        dispatch(OrientationSample(beta, gamma))
      }
    })->ignore
  })
  (model, Tea.batch([loadPartCmd, loadFacesCmd, cameraCmd, orientationCmd]))
}

// -- update --------------------------------------------------------------

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | GotPart(part) => ({...model, partChecked: true, partExists: part->Option.isSome}, Tea.none)
  | GotFaces(faces) =>
    let selectedKind = model.kindManuallySelected ? model.selectedKind : defaultKind(faces)
    ({...model, faces, selectedKind}, Tea.batch(faces->Array.map(loadFaceImageCmd)))
  | FaceImageLoaded(faceId, Some(url)) =>
    let next = Dict.copy(model.faceImages)
    Dict.set(next, faceId, url)
    ({...model, faceImages: next}, Tea.none)
  | FaceImageLoaded(_, None) => (model, Tea.none)
  | SelectKind(kind) => ({...model, selectedKind: kind, kindManuallySelected: true}, Tea.none)
  | CameraPermissionChecked(denied) => ({...model, cameraDenied: denied}, Tea.none)
  | OrientationSample(beta, gamma) => ({...model, lastBeta: beta, lastGamma: gamma}, Tea.none)
  | CaptureArmed =>
    let level = model.orientationDenied ? None : levelFromSamples(model.lastBeta, model.lastGamma)
    let armed = {...model, armedLevel: level}
    if model.orientationRequested {
      (armed, Tea.none)
    } else if Orientation.isRequestPermissionAvailable() {
      (
        {...armed, orientationRequested: true},
        Tea.fromPromise(
          () => Orientation.requestPermission(),
          r => OrientationPermissionResult(r),
          _err => OrientationPermissionResult(None),
        ),
      )
    } else {
      ({...armed, orientationRequested: true}, Tea.none)
    }
  | OrientationPermissionResult(Some(Orientation.Denied)) =>
    ({...model, orientationDenied: true}, Tea.none)
  | OrientationPermissionResult(_) => (model, Tea.none)
  | FileChosen(_kind, _fromLibrary, None) => (model, Tea.none)
  | FileChosen(kind, fromLibrary, Some(file)) =>
    let level = fromLibrary ? None : model.armedLevel
    // Reset the input's own generation immediately: the `File` object is
    // already captured in this msg, independent of the DOM node, so the
    // input can safely remount (clearing its native value) right away —
    // that's what lets the same file (or a fresh one) be re-picked after a
    // decode failure or a recapture cancel, without extra reset logic at
    // either of those sites.
    let nextGens = bumpGen(model.inputGens, kind, ~fromLibrary)
    let nextModel = {...model, inputGens: nextGens, busy: Some(kind), error: None}
    (
      nextModel,
      Tea.fromPromise(
        () => decodeAndCap(file),
        ((image, contentType, w, h)) => Decoded(kind, fromLibrary, image, contentType, w, h, level),
        _err => DecodeFailed(kind, "Couldn't read that photo. Try a different one."),
      ),
    )
  | Decoded(kind, fromLibrary, image, contentType, width, height, level) =>
    switch existingFaceOf(model.faces, kind) {
    | None =>
      let id = Ids.face()
      (
        {...model, busy: None},
        saveFaceCmd(~partId=model.partId, ~kind, ~id, ~image, ~contentType, ~width, ~height, ~level),
      )
    | Some(existing) =>
      let pending: pendingCapture = {
        kind,
        image,
        contentType,
        pixelWidth: width,
        pixelHeight: height,
        levelDegrees: level,
        existingFaceId: existing.id,
        fromLibrary,
      }
      ({...model, busy: None, dialog: RecaptureConfirm(pending)}, Tea.none)
    }
  | DecodeFailed(kind, msg) => ({...model, busy: None, error: Some((kind, msg))}, Tea.none)
  | Saved(face) =>
    let faces = upsertFace(model.faces, face)
    (
      {...model, faces, dialog: NoDialog, busy: None, error: None},
      Tea.fromPromise(
        () => Store.startTimer(Store.shared(), ~partId=model.partId),
        _timer => TimerStarted(face.id),
        _err => TimerStarted(face.id),
      ),
    )
  | SaveFailed(kind, msg) => ({...model, busy: None, dialog: NoDialog, error: Some((kind, msg))}, Tea.none)
  | TimerStarted(faceId) => (model, Route.push(Route.Annotate(model.partId, faceId)))
  | RecaptureConfirmClicked =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) => (
        {...model, busy: Some(pending.kind)},
        Tea.fromPromise(
          () => Store.deleteDimensionsOfFace(Store.shared(), pending.existingFaceId),
          _ => DimensionsDeletedThenSave,
          _err => DeleteDimensionsFailed("Couldn't clear the old dimensions. Try again."),
        ),
      )
    }
  | RecaptureKeepClicked =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) => (
        {...model, busy: Some(pending.kind)},
        saveFromPending(~partId=model.partId, pending),
      )
    }
  | RecaptureCancelClicked => ({...model, dialog: NoDialog}, Tea.none)
  | DimensionsDeletedThenSave =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) => (model, saveFromPending(~partId=model.partId, pending))
    }
  | DeleteDimensionsFailed(msg) =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) =>
      ({...model, busy: None, dialog: NoDialog, error: Some((pending.kind, msg))}, Tea.none)
    }
  }

let title = (_model: model): string => "Capture"
let back = (model: model): option<Route.t> => Some(Route.Part(model.partId))

// -- view --------------------------------------------------------------
// DESIGN.md §11.2 "Capture": chips (top) → slot row → shutter/library or
// the inline recapture card → camera note. All eight file inputs render
// unconditionally in `hiddenInputs`, independent of `selectedKind` and
// `model.dialog`, so `setInputFiles('[data-testid="capture-file-<kind>"]')`
// keeps working no matter what's on screen — see the module-end notes.

let kindLabel = (kind: Types.faceKind): string =>
  switch kind {
  | Types.Top => "Top"
  | Types.Side => "Side"
  | Types.End => "End"
  | Types.Detail => "Detail"
  }

let formatDegrees = (deg: float): string => Float.toFixed(deg, ~digits=1) ++ "°"

let isDialogOpen = (model: model): bool =>
  switch model.dialog {
  | NoDialog => false
  | RecaptureConfirm(_) => true
  }

let chipRow = (model: model, ~dispatch: msg => unit): React.element =>
  <Ui.ChipRow testId="capture-kinds">
    {Enums.allFaceKinds
    ->Array.map(kind => {
      let kindStr = Enums.faceKindToString(kind)
      let hasExisting = existingFaceOf(model.faces, kind)->Option.isSome
      <Ui.Chip
        key=kindStr
        large=true
        selected={kind == model.selectedKind}
        onClick={_ => dispatch(SelectKind(kind))}>
        <>
          {hasExisting ? <Icon name=Check size=16 /> : React.null}
          {React.string(kindLabel(kind))}
        </>
      </Ui.Chip>
    })
    ->React.array}
  </Ui.ChipRow>

// 56 px slot row (DESIGN.md §4 "Thumbnail slot", mirrors Part.res's own
// face tiles): captured = a thumbnail once the object URL has loaded, else
// the plain `slot-captured` surface+ring; empty = dashed. Tapping a slot
// selects that kind, same as its chip.
let slotRow = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="slot-row">
    {Enums.allFaceKinds
    ->Array.map(kind => {
      let kindStr = Enums.faceKindToString(kind)
      let existing = existingFaceOf(model.faces, kind)
      let hasExisting = existing->Option.isSome
      let thumbUrl = existing->Option.flatMap(f => Dict.get(model.faceImages, f.id))
      let stateClass = hasExisting ? " slot-captured" : " slot-empty"
      let selectedClass = kind == model.selectedKind ? " slot-selected" : ""
      let label = kindLabel(kind) ++ (hasExisting ? " — captured" : " — not captured")
      <button
        type_="button"
        key=kindStr
        className={"slot" ++ stateClass ++ selectedClass}
        ariaLabel=label
        ariaPressed={kind == model.selectedKind ? #"true" : #"false"}
        onClick={_ => dispatch(SelectKind(kind))}>
        {switch thumbUrl {
        | Some(url) => <img src=url alt={kindLabel(kind)} />
        | None => React.null
        }}
      </button>
    })
    ->React.array}
  </div>

// The shutter block: 76 px amber shutter (label for the selected kind's
// camera input), Body caption, "From library" secondary capsule, the live
// level readout, and the busy/error lines. Swapped out for `recaptureCard`
// while a dialog is open (DESIGN.md §11.2).
let shutterBlock = (model: model, ~dispatch: msg => unit): React.element => {
  let kind = model.selectedKind
  let kindStr = Enums.faceKindToString(kind)
  let hasExisting = existingFaceOf(model.faces, kind)->Option.isSome
  let isBusy = model.busy == Some(kind)
  let shutterDisabled = isBusy || isDialogOpen(model)
  let liveLevel = model.orientationDenied ? None : levelFromSamples(model.lastBeta, model.lastGamma)
  let rowError = switch model.error {
  | Some((k, msg)) if k == kind => Some(msg)
  | _ => None
  }
  // Both phases share the one `busy` flag; which is showing is fully
  // determined by `model.dialog` — see the module-end notes.
  let progressText = switch model.dialog {
  | RecaptureConfirm(_) => "Saving…"
  | NoDialog => "Decoding…"
  }
  <div className="shutter-block">
    <div className="shutter-row">
      <label
        className={"shutter" ++ (shutterDisabled ? " shutter-disabled" : "")}
        htmlFor={"capture-file-" ++ kindStr}
        ariaLabel="Capture this face"
        onPointerDown={_ => dispatch(CaptureArmed)}>
        <Icon name=Camera size=32 />
      </label>
      {switch liveLevel {
      | Some(deg) =>
        <Ui.Pill mono=true testId="capture-level"> {React.string(formatDegrees(deg))} </Ui.Pill>
      | None => React.null
      }}
    </div>
    <p className="t-body shutter-caption">
      {React.string((hasExisting ? "Recapture " : "Capture ") ++ kindLabel(kind))}
    </p>
    <label className="btn btn-secondary" htmlFor={"library-file-" ++ kindStr}>
      <Icon name=Image size=20 />
      {React.string("From library")}
    </label>
    {isBusy ? <Ui.Pill> {React.string(progressText)} </Ui.Pill> : React.null}
    {switch rowError {
    | Some(msg) => <p className="t-footnote text-error"> {React.string(msg)} </p>
    | None => React.null
    }}
  </div>
}

// Inline recapture card (DESIGN.md §11.2, §11.1 "Confirmations"): no
// overlay/modal, just a `.list-group` card in place of the shutter block.
let recaptureCard = (pending: pendingCapture, ~dispatch: msg => unit): React.element =>
  <div className="list-group recapture-card" role="alertdialog" ariaLabel="Replace photo?">
    <p className="t-body"> {React.string("Replace the " ++ kindLabel(pending.kind) ++ " photo?")} </p>
    <div className="recapture-buttons">
      <Ui.Button
        variant=Danger
        block=true
        testId="recapture-confirm"
        onClick={_ => dispatch(RecaptureConfirmClicked)}>
        {React.string("Replace, discard its dimensions")}
      </Ui.Button>
      <Ui.Button
        variant=Secondary
        block=true
        testId="recapture-keep"
        onClick={_ => dispatch(RecaptureKeepClicked)}>
        {React.string("Replace, keep dimensions")}
      </Ui.Button>
      <Ui.Button block=true testId="recapture-cancel" onClick={_ => dispatch(RecaptureCancelClicked)}>
        {React.string("Cancel")}
      </Ui.Button>
    </div>
  </div>

// One real `<input type=file>`, visually hidden but always in the DOM
// (SPEC §8a A4 / docs/testids.md contract) — see `hiddenInputs` below.
let renderCaptureInput = (
  model: model,
  ~dispatch: msg => unit,
  ~kind: Types.faceKind,
  ~fromLibrary: bool,
): React.element => {
  let kindStr = Enums.faceKindToString(kind)
  let disabled = model.busy == Some(kind) || isDialogOpen(model)
  let gen = genFor(model.inputGens, kind, ~fromLibrary)
  let testId = (fromLibrary ? "library-file-" : "capture-file-") ++ kindStr
  let label =
    (fromLibrary ? "Choose " : "Capture ") ++
    kindLabel(kind) ++
    (fromLibrary ? " photo from library" : " photo with camera")
  <input
    key={(fromLibrary ? "lib-" : "cam-") ++ Int.toString(gen)}
    id=testId
    type_="file"
    accept="image/jpeg,image/png"
    capture=?{fromLibrary ? None : Some(#environment)}
    className="visually-hidden"
    dataTestId=testId
    ariaLabel=label
    disabled
    onChange={evt => dispatch(FileChosen(kind, fromLibrary, ImageDecode.fileFromChangeEvent(evt)))}
  />
}

// All eight inputs (one camera + one library per kind), always mounted —
// deliberately not nested inside the shutter/library labels above (which
// only ever reference the *selected* kind's `id` via `htmlFor`), so their
// presence never depends on `selectedKind` or `model.dialog`.
let hiddenInputs = (model: model, ~dispatch: msg => unit): React.element =>
  Enums.allFaceKinds
  ->Array.flatMap(kind => [
    renderCaptureInput(model, ~dispatch, ~kind, ~fromLibrary=false),
    renderCaptureInput(model, ~dispatch, ~kind, ~fromLibrary=true),
  ])
  ->React.array

let view = (model: model, ~dispatch: msg => unit): React.element =>
  switch statusOf(model) {
  | Loading => <p className="t-body muted"> {React.string("Loading…")} </p>
  | NotFound =>
    <div className="stack">
      <p className="t-body"> {React.string("Part not found.")} </p>
      <a className="btn btn-secondary" href={Route.href(Route.Parts)}> {React.string("Back to parts")} </a>
    </div>
  | Found =>
    <div className="capture-view">
      {chipRow(model, ~dispatch)}
      {slotRow(model, ~dispatch)}
      {switch model.dialog {
      | RecaptureConfirm(pending) => recaptureCard(pending, ~dispatch)
      | NoDialog => shutterBlock(model, ~dispatch)
      }}
      {hiddenInputs(model, ~dispatch)}
      <p
        className={model.cameraDenied ? "camera-note camera-note-prominent" : "camera-note"}
        dataTestId="capture-note">
        {React.string("Camera blocked? Use From library — Settings › Safari › Camera controls it.")}
      </p>
    </div>
  }

// -- judgment calls (see LOGBOOK.md "Design wave 2 — capture" for the full
// write-up; "M3 capture" below is the original M3 agent's own notes) --
//
// Design wave 2 additions:
// - `selectedKind`/`kindManuallySelected` and `faceImages`/`FaceImageLoaded`
//   are the two UI-only additions the task brief allows. `GotFaces` fires
//   exactly once (from `init`'s cmd; nothing else re-fetches the face
//   list), so "default to the first kind without a face, else Top" only
//   ever needs to run that once — `kindManuallySelected` exists mainly so
//   a hypothetical future re-fetch can't clobber a deliberate chip tap.
// - The 76 px shutter and the "From library" capsule reference the
//   selected kind's input by `htmlFor` (id), not by wrapping it — unlike
//   `Ui.Toggle`'s wrap-the-checkbox pattern, this keeps all eight
//   `<input>`s in one fixed place, present regardless of `selectedKind` or
//   `model.dialog`, satisfying "all eight inputs stay in the DOM ...
//   regardless of which chip is selected" literally and unconditionally.
//   Trade-off: keyboard Tab reaches all eight (each carries its own
//   descriptive `aria-label`, e.g. "Capture Side photo with camera")
//   rather than just the two matching the visible shutter/library
//   controls, and a hidden input's own `:focus-visible` ring — being on a
//   1x1px clipped element — isn't a useful visual cue the way
//   `.btn:focus-within:has(input:focus-visible)` is for a wrapped one.
//   Untested by any spec; flagged here as a minor, deliberate rough edge.
// - "From library" always reads "From library", not "Recapture from
//   library": DESIGN.md §11.2 names the capsule's copy once, and the Body
//   caption above it ("Capture Top" / "Recapture Top") already carries the
//   recapture state — the original M3 pass had both actions relabel to
//   "Recapture …", which this page no longer does. Purely a copy change;
//   the underlying msg/testid/behaviour are identical.
// - The progress pill's text ("Decoding…" vs "Saving…") is derived from
//   existing state, not a new msg: while `model.busy` matches the selected
//   kind, `model.dialog` is still `NoDialog` during the initial decode
//   (recapture's dialog msgs never touch it) and is still
//   `RecaptureConfirm(_)` for the whole confirm/keep-through-save window
//   (only `Saved`/`SaveFailed`/`DeleteDimensionsFailed` clear it), so the
//   two phases are already distinguishable from state alone.
// - `Ui.res` gap: no "plain"/borderless button variant. DESIGN.md's
//   recapture card asks for a Danger, a Secondary, and a "plain" Cancel;
//   `Ui.Button`'s variants are Primary/Secondary/Danger/Small/Icon, so
//   Cancel uses the default (Secondary) — visually identical to "Replace,
//   keep dimensions" next to it. Worth a `Ui.Button` `Plain` variant
//   (borderless, `cc-text` on transparent) if this pattern recurs.
// - Level readout: DESIGN.md's "mono teal Ui.Pill next to the shutter when
//   available" reuses the existing `levelFromSamples` helper live off
//   `lastBeta`/`lastGamma` (gated on `orientationDenied` the same way the
//   save-time `armedLevel` snapshot is) — display-only, no new state.
//
// M3 capture (original, still true):
// - `levelDegrees` = sqrt(beta² + gamma²): SPEC doesn't define the exact
//   formula, only that it's "the level". This is the standard bubble-level
//   magnitude across both tilt axes; 0° is flat.
// - Orientation-permission request is armed only by the *camera*
//   (capture-file-<kind>) label's pointerdown, not the library label's —
//   the library input never uses level data, so there's no reason for it
//   to trigger the iOS permission prompt.
// - `Store.startTimer` is sequenced strictly before `Route.push` (via the
//   `TimerStarted` msg) rather than fired concurrently with navigation —
//   deterministic ordering was simpler to reason about than a fire-and-
//   forget effect racing the route change, and `startTimer` is cheap.
// - The `<input>`'s React `key` is bumped the moment a file is read out of
//   it (`FileChosen`), not only on recapture-cancel — the `File` object is
//   already captured independently of the DOM node by then, so remounting
//   immediately is safe and means recapture-cancel needs no separate
//   input-reset path.
// - The `deviceorientation` listener this page's `init` registers is never
//   torn down on navigating away — `Tea.res`'s `use` runs `init`'s cmd
//   once with no unsubscribe hook (out of this page's file-ownership
//   scope to change). Harmless for correctness (a stray listener updating
//   a discarded model), a known minor cost noted for whoever next touches
//   `Tea.res`.
