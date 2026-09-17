// Capture — the face picker + camera/library capture flow (SPEC M3, all
// four bullets). `init` takes the route's `partId`; the exported contract
// (`model`/`msg`/`init`/`update`/`title`/`back`/`view`) matches the M6 stub
// it replaces so `Main.res` needs no changes.
//
// TEA discipline (CLAUDE.md "Architecture"): all Store/decode work is a
// `Tea.cmd` built in `update`, never run inline in `view`; `view` stays a
// pure function of `model`. See the module-end notes for the judgment
// calls this page makes where SPEC left the exact reading open.

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

// -- init --------------------------------------------------------------

let init = (~partId: string): (model, Tea.cmd<msg>) => {
  let model = {
    partId,
    partChecked: false,
    partExists: false,
    faces: [],
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
  | GotFaces(faces) => ({...model, faces}, Tea.none)
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

let kindLabel = (kind: Types.faceKind): string =>
  switch kind {
  | Types.Top => "Top"
  | Types.Side => "Side"
  | Types.End => "End"
  | Types.Detail => "Detail"
  }

let sizeText = (f: Types.face): string =>
  Int.toString(f.pixelWidth) ++ "×" ++ Int.toString(f.pixelHeight) ++ " px"

let faceRow = (model: model, ~dispatch: msg => unit, ~kind: Types.faceKind): React.element => {
  let kindStr = Enums.faceKindToString(kind)
  let existing = existingFaceOf(model.faces, kind)
  let hasExisting = existing->Option.isSome
  let isBusyHere = model.busy == Some(kind)
  let dialogOpen = switch model.dialog {
  | NoDialog => false
  | RecaptureConfirm(_) => true
  }
  let disableInputs = isBusyHere || dialogOpen
  let statusText = switch existing {
  | Some(f) => "Captured — " ++ sizeText(f)
  | None => "Not captured yet"
  }
  let camLabel = hasExisting ? "Recapture" : "Capture"
  let libLabel = hasExisting ? "Recapture from library" : "From library"
  let rowError = switch model.error {
  | Some((k, msg)) if k == kind => Some(msg)
  | _ => None
  }
  let camGen = genFor(model.inputGens, kind, ~fromLibrary=false)
  let libGen = genFor(model.inputGens, kind, ~fromLibrary=true)

  <li className="face-row" key=kindStr>
    <div className="face-row-head">
      <span className="face-row-kind"> {React.string(kindLabel(kind))} </span>
      <span className="face-row-status"> {React.string(statusText)} </span>
    </div>
    <div className="face-row-actions">
      <label
        className="capture-btn"
        htmlFor={"capture-file-" ++ kindStr}
        onPointerDown={_ => dispatch(CaptureArmed)}>
        {React.string(camLabel)}
        <input
          key={"cam-" ++ Int.toString(camGen)}
          id={"capture-file-" ++ kindStr}
          type_="file"
          accept="image/jpeg,image/png"
          capture={#environment}
          className="visually-hidden-input"
          dataTestId={"capture-file-" ++ kindStr}
          disabled={disableInputs}
          onChange={evt => dispatch(FileChosen(kind, false, ImageDecode.fileFromChangeEvent(evt)))}
        />
      </label>
      <label className="capture-btn capture-btn-secondary" htmlFor={"library-file-" ++ kindStr}>
        {React.string(libLabel)}
        <input
          key={"lib-" ++ Int.toString(libGen)}
          id={"library-file-" ++ kindStr}
          type_="file"
          accept="image/jpeg,image/png"
          className="visually-hidden-input"
          dataTestId={"library-file-" ++ kindStr}
          disabled={disableInputs}
          onChange={evt => dispatch(FileChosen(kind, true, ImageDecode.fileFromChangeEvent(evt)))}
        />
      </label>
    </div>
    {isBusyHere
      ? <p className="face-row-progress"> {React.string("Saving photo…")} </p>
      : React.null}
    {switch rowError {
    | Some(msg) => <p className="face-row-error"> {React.string(msg)} </p>
    | None => React.null
    }}
  </li>
}

let recaptureDialog = (pending: pendingCapture, ~dispatch: msg => unit): React.element =>
  <div className="recapture-overlay">
    <div className="sheet recapture-dialog" role="alertdialog" ariaLabel="Replace photo?">
      <p>
        {React.string(kindLabel(pending.kind) ++ " already has a photo. Replace it?")}
      </p>
      <div className="recapture-actions">
        <button
          type_="button" dataTestId="recapture-confirm" onClick={_ => dispatch(RecaptureConfirmClicked)}>
          {React.string("Replace photo, discard its dimensions")}
        </button>
        <button
          type_="button" dataTestId="recapture-keep" onClick={_ => dispatch(RecaptureKeepClicked)}>
          {React.string("Replace photo, keep dimensions")}
        </button>
        <button
          type_="button" dataTestId="recapture-cancel" onClick={_ => dispatch(RecaptureCancelClicked)}>
          {React.string("Cancel")}
        </button>
      </div>
    </div>
  </div>

let view = (model: model, ~dispatch: msg => unit): React.element =>
  switch statusOf(model) {
  | Loading =>
    <div className="page">
      <p className="page-name"> {React.string("Capture")} </p>
    </div>
  | NotFound =>
    <div className="page">
      <p className="page-name"> {React.string("Capture")} </p>
      <p> {React.string("Part not found.")} </p>
      <a href={Route.href(Route.Parts)}> {React.string("Back to parts")} </a>
    </div>
  | Found =>
    <div className="page capture-page">
      <p className="page-name"> {React.string("Capture")} </p>
      <ul className="face-picker">
        {Enums.allFaceKinds->Array.map(kind => faceRow(model, ~dispatch, ~kind))->React.array}
      </ul>
      <p
        className={model.cameraDenied ? "capture-note capture-note-prominent" : "capture-note"}
        dataTestId="capture-note">
        {React.string(
          "Camera blocked? Use From library — Settings › Safari › Camera controls it.",
        )}
      </p>
      {switch model.dialog {
      | NoDialog => React.null
      | RecaptureConfirm(pending) => recaptureDialog(pending, ~dispatch)
      }}
    </div>
  }

// -- judgment calls (see LOGBOOK.md "M3 capture" for the full write-up) --
//
// - `levelDegrees` = sqrt(beta² + gamma²): SPEC doesn't define the exact
//   formula, only that it's "the level". This is the standard bubble-level
//   magnitude across both tilt axes; 0° is flat.
// - Orientation-permission request is armed only by the *camera*
//   (capture-file-<kind>) label's pointerdown, not the library label's —
//   the library input never uses level data, so there's no reason for it
//   to trigger the iOS permission prompt.
// - Both actions ("capture-file" and "library-file") relabel to
//   "Recapture …" once a kind has a face, per SPEC's "its actions read
//   Recapture" (plural).
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
