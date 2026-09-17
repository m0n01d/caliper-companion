// Capture — the face picker + camera/library capture flow (SPEC M3, all
// four bullets; SPEC §8a A7 custom faces). `init` takes the route's
// `partId`; the exported contract (`model`/`msg`/`init`/`update`/`title`/
// `back`/`view`) matches the M6 stub it replaces so `Main.res` needs no
// changes.
//
// TEA discipline (CLAUDE.md "Architecture"): all Store/decode work is a
// `Tea.cmd` built in `update`, never run inline in `view`; `view` stays a
// pure function of `model`. See the module-end notes for the judgment
// calls this page makes where SPEC left the exact reading open.
//
// Design wave 2 (DESIGN.md §11, §11.2 "Capture"): restyled onto the wave-1
// foundation (Ui/Icon/theme/global). A7 (SPEC §8a): the page is keyed by
// face *label*, not kind — the four default chips plus any custom ones,
// each with its own always-mounted camera + library `<input>` pair. Nothing
// about the file-input/decode/save/recapture flow itself changed — see the
// notes at the end of this file for what's new and why.
//
// Design wave P2b "layout A" (branch `agent/p2-capture`,
// docs/design/review-2026-09-17.md findings C1-C4, DESIGN.md §11.2
// "Capture"): the chip row + slot row are gone, replaced by one
// `Ui.FaceCard` grid (`faceGrid`) that is both the kind picker and the
// thumbnail gallery; the shutter/library block moves into the bottom 60% of
// the screen (`.capture-action { margin-top: auto }` inside a
// `min-height: 100%` `.capture-page`). Capture/decode/recapture/custom-face
// logic is unchanged — this wave only touches `faceGrid`, `view`'s markup,
// and `Capture.css`. See the module-end notes for what's new and the Ui
// gaps this ran into.

// -- model -------------------------------------------------------------

// One face slot the shutter/library inputs can capture into (SPEC §8a A7).
// The four defaults always exist (`label == Enums.faceKindToString(kind)`);
// custom chips come from captured custom faces (`model.faces`) and from
// `customChips` (added on this page, no face yet).
type chip = {
  label: string, // unique per part; slug-safe (FeatureName rule)
  kind: Types.faceKind, // sketch-plane hint
}

type pendingCapture = {
  chip: chip,
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

// The "+ Custom" inline card's in-progress state (SPEC §8a A7).
type customDraft = {
  draftLabel: string,
  plane: Types.faceKind,
}

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
  // UI-only: which chip/slot/shutter target is active, by label.
  selectedLabel: string,
  // True once the user taps a chip/slot — stops a (currently single, but
  // future-proofed) `GotFaces` from overriding their choice with the
  // "first default without a face" default.
  labelManuallySelected: bool,
  // Custom chips added on this page that have no face yet (SPEC §8a A7:
  // "unsaved custom chips live in the page model only"). A chip moves out
  // of here the moment its face is saved (it then comes from `faces`).
  customChips: array<chip>,
  customDraft: option<customDraft>,
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
  // One generation counter per (label, source) `<input>`, used as a React
  // `key` to force-remount the element and clear its native file value —
  // see `bumpGen` below for why this fires on every selection, not just
  // cancel.
  inputGens: Dict.t<int>,
  busy: option<string>, // the label being decoded/saved
  error: option<(string, string)>, // (label, message)
  dialog: dialog,
  // DESIGN.md §9 "Live region" — see `Ui.Live`'s doc comment for why "" is
  // silence, not absence.
  announcement: string,
}

type status = Loading | NotFound | Found

let statusOf = (model: model): status =>
  !model.partChecked ? Loading : model.partExists ? Found : NotFound

type msg =
  | GotPart(option<Types.part>)
  | GotFaces(array<Types.face>)
  | FaceImageLoaded(string, option<string>)
  | SelectChip(string)
  | CustomOpen
  | CustomLabelChanged(string)
  | CustomPlaneChanged(Types.faceKind)
  | CustomAdd
  | CustomCancel
  | CustomRemove(string)
  | CameraPermissionChecked(bool)
  | OrientationSample(option<float>, option<float>)
  | CaptureArmed
  | OrientationPermissionResult(option<Orientation.permissionState>)
  | FileChosen(string, bool, option<ImageDecode.file>)
  | Decoded(string, bool, PouchDb.blob, string, int, int, option<float>)
  | DecodeFailed(string, string)
  | Saved(Types.face)
  | SaveFailed(string, string)
  | TimerStarted(string)
  | RecaptureConfirmClicked
  | RecaptureKeepClicked
  | RecaptureCancelClicked
  | DimensionsDeletedThenSave
  | DeleteDimensionsFailed(string)

// -- pure helpers --------------------------------------------------------

let defaultChips: array<chip> =
  Enums.allFaceKinds->Array.map(kind => {label: Enums.faceKindToString(kind), kind})

let isDefaultLabel = (label: string): bool => defaultChips->Array.some(c => c.label == label)

let existingFaceOf = (faces: array<Types.face>, label: string): option<Types.face> =>
  Array.find(faces, f => f.label == label)

// Every chip on the page, in display order: the four defaults, then
// captured custom faces (Store order: kind, then label), then this page's
// unsaved custom chips (in the order they were added).
let chipsOf = (model: model): array<chip> => {
  let captured =
    model.faces
    ->Array.filter(f => !isDefaultLabel(f.label))
    ->Array.map(f => {label: f.label, kind: f.kind})
  let pending =
    model.customChips->Array.filter(c => existingFaceOf(model.faces, c.label)->Option.isNone)
  Array.concat(defaultChips, Array.concat(captured, pending))
}

let chipOf = (model: model, label: string): option<chip> =>
  chipsOf(model)->Array.find(c => c.label == label)

// UI-only default (DESIGN.md §11.2): the first default face without a
// capture, else Top.
let defaultLabel = (faces: array<Types.face>): string =>
  defaultChips
  ->Array.find(c => existingFaceOf(faces, c.label)->Option.isNone)
  ->Option.map(c => c.label)
  ->Option.getOr("top")

// SPEC §8a A7: the label rule is the feature-name rule, plus uniqueness
// among this part's faces (captured or still only a chip).
let labelError = (model: model, label: string): option<string> =>
  switch FeatureName.validate(label) {
  | Error(e) => Some(FeatureName.errorMessage(e))
  | Ok(_) =>
    chipsOf(model)->Array.some(c => c.label == label)
      ? Some("A face named `" ++ label ++ "` already exists on this part")
      : None
  }

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

let genKey = (label: string, ~fromLibrary: bool): string =>
  label ++ (fromLibrary ? "-lib" : "-cam")

let genFor = (gens: Dict.t<int>, label: string, ~fromLibrary: bool): int =>
  Dict.get(gens, genKey(label, ~fromLibrary))->Option.getOr(0)

let bumpGen = (gens: Dict.t<int>, label: string, ~fromLibrary: bool): Dict.t<int> => {
  let next = Dict.copy(gens)
  Dict.set(next, genKey(label, ~fromLibrary), genFor(gens, label, ~fromLibrary) + 1)
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
  ~chip: chip,
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
    kind: chip.kind,
    label: chip.label,
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
    _err => SaveFailed(chip.label, "Couldn't save the photo. Try again."),
  )
}

let saveFromPending = (~partId: string, pending: pendingCapture): Tea.cmd<msg> =>
  saveFaceCmd(
    ~partId,
    ~chip=pending.chip,
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

// DESIGN.md §9 "Focus management" — deferred one microtask past this msg's
// own model update, the same reasoning as `PartsList.focusTestId` (see that
// module's copy for the full comment): `Tea.res`'s `dispatch` runs a msg's
// cmd before React has re-rendered, so a target that only exists in the
// model this same msg just produced (the custom-face card's name input)
// needs the deferral; a target that was already on screen (the shutter,
// once the recapture card closes) would work either way but gets the same
// treatment for one code path to reason about.
let focusTestId = (id: string): Tea.cmd<msg> =>
  Tea.effect(_dispatch =>
    Promise.resolve()
    ->Promise.then(() => {
        switch Canvas.byTestId(id) {
        | Some(el) => el->Canvas.focus
        | None => ()
        }
        Promise.resolve()
      })
    ->ignore
  )

// -- init --------------------------------------------------------------

let init = (~partId: string): (model, Tea.cmd<msg>) => {
  let model = {
    partId,
    partChecked: false,
    partExists: false,
    faces: [],
    faceImages: Dict.make(),
    selectedLabel: "top",
    labelManuallySelected: false,
    customChips: [],
    customDraft: None,
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
    announcement: "",
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
    let selectedLabel = model.labelManuallySelected ? model.selectedLabel : defaultLabel(faces)
    ({...model, faces, selectedLabel}, Tea.batch(faces->Array.map(loadFaceImageCmd)))
  | FaceImageLoaded(faceId, Some(url)) =>
    let next = Dict.copy(model.faceImages)
    Dict.set(next, faceId, url)
    ({...model, faceImages: next}, Tea.none)
  | FaceImageLoaded(_, None) => (model, Tea.none)
  // Picking a real chip also closes the custom card (it's the one other
  // thing competing for the shutter slot).
  | SelectChip(label) =>
    ({...model, selectedLabel: label, labelManuallySelected: true, customDraft: None}, Tea.none)
  | CustomOpen => (
      {...model, customDraft: Some({draftLabel: "", plane: Types.Top})},
      focusTestId("custom-face-label"),
    )
  | CustomLabelChanged(text) =>
    switch model.customDraft {
    | Some(draft) => ({...model, customDraft: Some({...draft, draftLabel: text})}, Tea.none)
    | None => (model, Tea.none)
    }
  | CustomPlaneChanged(plane) =>
    switch model.customDraft {
    | Some(draft) => ({...model, customDraft: Some({...draft, plane})}, Tea.none)
    | None => (model, Tea.none)
    }
  | CustomAdd =>
    switch model.customDraft {
    | Some(draft) if draft.draftLabel != "" && labelError(model, draft.draftLabel)->Option.isNone =>
      let chip = {label: draft.draftLabel, kind: draft.plane}
      (
        {
          ...model,
          customChips: Array.concat(model.customChips, [chip]),
          selectedLabel: chip.label,
          labelManuallySelected: true,
          customDraft: None,
        },
        Tea.none,
      )
    | _ => (model, Tea.none)
    }
  | CustomCancel => ({...model, customDraft: None}, Tea.none)
  // Only a chip with no face (and no decode in flight) can go; a captured
  // custom face is deleted from the Part page like any face (SPEC A7).
  | CustomRemove(label) =>
    if existingFaceOf(model.faces, label)->Option.isSome || model.busy == Some(label) {
      (model, Tea.none)
    } else {
      let customChips = model.customChips->Array.filter(c => c.label != label)
      let selectedLabel = model.selectedLabel == label ? defaultLabel(model.faces) : model.selectedLabel
      ({...model, customChips, selectedLabel}, Tea.none)
    }
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
  | FileChosen(_label, _fromLibrary, None) => (model, Tea.none)
  | FileChosen(label, fromLibrary, Some(file)) =>
    let level = fromLibrary ? None : model.armedLevel
    // Reset the input's own generation immediately: the `File` object is
    // already captured in this msg, independent of the DOM node, so the
    // input can safely remount (clearing its native value) right away —
    // that's what lets the same file (or a fresh one) be re-picked after a
    // decode failure or a recapture cancel, without extra reset logic at
    // either of those sites.
    let nextGens = bumpGen(model.inputGens, label, ~fromLibrary)
    let nextModel = {...model, inputGens: nextGens, busy: Some(label), error: None}
    (
      nextModel,
      Tea.fromPromise(
        () => decodeAndCap(file),
        ((image, contentType, w, h)) => Decoded(label, fromLibrary, image, contentType, w, h, level),
        _err => DecodeFailed(label, "Couldn't read that photo. Try a different one."),
      ),
    )
  | Decoded(label, fromLibrary, image, contentType, width, height, level) =>
    switch chipOf(model, label) {
    | None => ({...model, busy: None}, Tea.none) // chip vanished mid-decode; nothing to save into
    | Some(chip) =>
      // SPEC §8a A7: recapture replaces *this face* (same id, same label),
      // never "the face of this kind" — so `side` and `left_side` coexist.
      switch existingFaceOf(model.faces, label) {
      | None =>
        let id = Ids.face()
        (
          {...model, busy: None},
          saveFaceCmd(~partId=model.partId, ~chip, ~id, ~image, ~contentType, ~width, ~height, ~level),
        )
      | Some(existing) =>
        let pending: pendingCapture = {
          chip,
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
    }
  | DecodeFailed(label, msg) => ({...model, busy: None, error: Some((label, msg))}, Tea.none)
  | Saved(face) =>
    let faces = upsertFace(model.faces, face)
    // The chip now comes from `faces`; drop the page-only copy.
    let customChips = model.customChips->Array.filter(c => c.label != face.label)
    (
      {
        ...model,
        faces,
        customChips,
        dialog: NoDialog,
        busy: None,
        error: None,
        // DESIGN.md §9: "Face captured: <label>" — like `PartCreated` in
        // PartsList.res, `TimerStarted` below navigates away almost
        // immediately, so this is mostly symbolic; kept per spec anyway.
        announcement: "Face captured: " ++ face.label,
      },
      Tea.fromPromise(
        () => Store.startTimer(Store.shared(), ~partId=model.partId),
        _timer => TimerStarted(face.id),
        _err => TimerStarted(face.id),
      ),
    )
  | SaveFailed(label, msg) =>
    ({...model, busy: None, dialog: NoDialog, error: Some((label, msg))}, Tea.none)
  | TimerStarted(faceId) => (model, Route.push(Route.Annotate(model.partId, faceId)))
  | RecaptureConfirmClicked =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) => (
        {...model, busy: Some(pending.chip.label)},
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
        {...model, busy: Some(pending.chip.label)},
        saveFromPending(~partId=model.partId, pending),
      )
    }
  | RecaptureCancelClicked =>
    // DESIGN.md §9: the recapture card closes back into the shutter block —
    // focus follows it back to the shutter label (`dataTestId="shutter"`,
    // `tabIndex={-1}`: a `<label>` isn't natively focusable, so it needs an
    // explicit, non-tab-order focus target here — see `shutterBlock`).
    ({...model, dialog: NoDialog}, focusTestId("shutter"))
  | DimensionsDeletedThenSave =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) => (model, saveFromPending(~partId=model.partId, pending))
    }
  | DeleteDimensionsFailed(msg) =>
    switch model.dialog {
    | NoDialog => (model, Tea.none)
    | RecaptureConfirm(pending) =>
      ({...model, busy: None, dialog: NoDialog, error: Some((pending.chip.label, msg))}, Tea.none)
    }
  }

let title = (_model: model): string => "Capture"
let back = (model: model): option<Route.t> => Some(Route.Part(model.partId))

// Shell slots (DESIGN.md §11.1): an optional Footnote under the title and an
// optional trailing bar action. Default none; pages override.
let subtitle = (_model: model): option<string> => None
let actions = (_model: model, ~dispatch as _dispatch: msg => unit): option<React.element> => None

// -- view --------------------------------------------------------------
// Layout A (design wave P2b, docs/design/review-2026-09-17.md §3/§4,
// DESIGN.md §11.2 "Capture"): the face-card grid (`faceGrid`, kind picker
// and thumbnail gallery in one) on top, then the shutter/library block, the
// inline custom-face card, or the inline recapture card — swapped in place
// inside `.capture-action` — then the camera note. `.capture-page` is a
// flex column with `min-height: 100%`; `.capture-action { margin-top: auto
// }` pushes whichever of the three is showing (and the note after it) to
// the bottom of the content, into the bottom 60% per DESIGN.md §1. One
// camera + one library file input per chip renders unconditionally in
// `hiddenInputs`, independent of `selectedLabel` and `model.dialog`, so
// `setInputFiles('[data-testid="capture-file-<label>"]')` keeps working no
// matter what's on screen — see the module-end notes.

let kindLabel = (kind: Types.faceKind): string =>
  switch kind {
  | Types.Top => "Top"
  | Types.Side => "Side"
  | Types.End => "End"
  | Types.Detail => "Detail"
  }

// Display name of a chip: "Top"/"Side"/"End"/"Detail" for the defaults, the
// slug itself (mono, DESIGN.md §7 "feature names: mono, never truncated")
// for a custom face.
let chipName = (chip: chip): React.element =>
  isDefaultLabel(chip.label)
    ? React.string(kindLabel(chip.kind))
    : <span className="mono"> {React.string(chip.label)} </span>

let chipAriaName = (chip: chip): string =>
  isDefaultLabel(chip.label) ? kindLabel(chip.kind) : chip.label

let planeOptions: array<(string, string)> = [
  ("top", "Top XY"),
  ("side", "Side XZ"),
  ("end", "End YZ"),
  ("detail", "Detail XY"),
]

let formatDegrees = (deg: float): string => Float.toFixed(deg, ~digits=1) ++ "°"

let isDialogOpen = (model: model): bool =>
  switch model.dialog {
  | NoDialog => false
  | RecaptureConfirm(_) => true
  }

let onEnter = (e: JsxEvent.Keyboard.t, then: unit => unit): unit =>
  if JsxEvent.Keyboard.key(e) == "Enter" {
    e->JsxEvent.Keyboard.preventDefault
    then()
  }

let inputValue = (e: JsxEvent.Form.t): string => e->Canvas.Form.target->Canvas.value

// "W × H" for a captured face's stored pixel size — same shape as Part.res's
// own `sizeText`; that module owns its copy (file ownership), this is this
// page's, one line each.
let sizeText = (face: Types.face): string =>
  Int.toString(face.pixelWidth) ++ " × " ++ Int.toString(face.pixelHeight)

// Accessible name for a face-grid card (DESIGN.md §9 "Color is never the
// only signal" — captured/selected are visual-only otherwise: a live ring,
// an accent ring, a check badge). `Ui.FaceCard` has no `aria-pressed` (see
// the module-end notes' "Ui gaps"), so the selection state the old slot's
// `aria-pressed` used to carry is folded into the name instead.
let cardAriaLabel = (chip: chip, ~hasExisting: bool, ~isSelected: bool): string =>
  chipAriaName(chip) ++
  (hasExisting ? " — captured" : " — not captured") ++
  (isSelected ? ", selected" : "")

// The face-card grid (design wave P2b "layout A",
// docs/design/review-2026-09-17.md §3/§4, DESIGN.md §4 "Face card" / §11.2
// "Capture"): one `Ui.FaceCard` per chip from `chipsOf`, replacing the old
// chip row + slot row — the grid doubles as the kind picker (tap =
// `SelectChip`). A captured chip is `Captured` (thumbnail + the live check
// `badge`); the selected chip additionally gets the `Selected` accent ring
// — `state` and `badge` are independent props, so a captured-and-selected
// card keeps both signals. An uncaptured chip is `Empty` (camera icon +
// label) regardless of selection: `Ui.FaceCard` only ever shows a ring when
// `image` is `Some(_)` (see its own doc comment), so a selected-but-
// uncaptured kind reads as a plain empty card here — a real Ui gap, noted
// in the module-end notes, not worked around by hand-rolling the card's
// markup outside the shared component. "+ Custom" is a fixed trailing
// `Empty` card (own testid, not one of `chipsOf`'s chips) that opens the
// existing inline custom-face card; `Ui.FaceCard`'s empty look always shows
// a camera icon (no way to ask it for `Plus` without editing `Ui.res`), so
// the card's own label reads "+ Custom" to keep the affordance legible —
// another noted Ui gap. Dense (3-up, `.face-grid-dense`) at ≥ 5 *chips*,
// reading the review's "≥ 5 faces" rule against this page's chips, not the
// total cell count including "+ Custom" — counting the trailing cell would
// make a bare 4-default, zero-capture part dense on day one.
let faceGrid = (model: model, ~dispatch: msg => unit): React.element => {
  let chips = chipsOf(model)
  let dense = Array.length(chips) >= 5
  let cards = chips->Array.map(chip => {
    let existing = existingFaceOf(model.faces, chip.label)
    let hasExisting = existing->Option.isSome
    let thumbUrl = existing->Option.flatMap(f => Dict.get(model.faceImages, f.id))
    let isSelected = chip.label == model.selectedLabel && model.customDraft->Option.isNone
    <Ui.FaceCard
      key=chip.label
      label={chipAriaName(chip)}
      caption=?{existing->Option.map(sizeText)}
      image=thumbUrl
      state={hasExisting
        ? isSelected ? Ui.FaceCard.Selected : Ui.FaceCard.Captured
        : Ui.FaceCard.Empty}
      badge=?{
        hasExisting
          ? Some(<span className="face-card-check"> <Icon name=Check size=14 /> </span>)
          : None
      }
      testId={"capture-chip-" ++ chip.label}
      ariaLabel={cardAriaLabel(chip, ~hasExisting, ~isSelected)}
      onClick={_ => dispatch(SelectChip(chip.label))}
    />
  })
  let addCustomCard =
    <Ui.FaceCard
      key="custom-face"
      label="+ Custom"
      image=None
      state=Ui.FaceCard.Empty
      testId="custom-face"
      ariaLabel="Add a custom face"
      onClick={_ => dispatch(CustomOpen)}
    />
  <div className={"face-grid" ++ (dense ? " face-grid-dense" : "")} dataTestId="capture-kinds">
    {Array.concat(cards, [addCustomCard])->React.array}
  </div>
}

// The shutter block: 76 px amber shutter (label for the selected chip's
// camera input), Body caption, "From library" secondary capsule, the live
// level readout, and the busy/error lines. Swapped out for `recaptureCard`
// or `customCard` while one of those is open (DESIGN.md §11.2).
let shutterBlock = (model: model, ~chip: chip, ~dispatch: msg => unit): React.element => {
  let label = chip.label
  let hasExisting = existingFaceOf(model.faces, label)->Option.isSome
  let isBusy = model.busy == Some(label)
  let shutterDisabled = isBusy || isDialogOpen(model)
  let liveLevel = model.orientationDenied ? None : levelFromSamples(model.lastBeta, model.lastGamma)
  let rowError = switch model.error {
  | Some((l, msg)) if l == label => Some(msg)
  | _ => None
  }
  // Both phases share the one `busy` flag; which is showing is fully
  // determined by `model.dialog` — see the module-end notes.
  let progressText = switch model.dialog {
  | RecaptureConfirm(_) => "Saving…"
  | NoDialog => "Decoding…"
  }
  // A custom chip with no face yet is page-only state and can be taken
  // back (SPEC §8a A7); a captured one is a real face, deleted from Part.
  let removable = !isDefaultLabel(label) && !hasExisting
  <div className="shutter-block">
    <div className="shutter-row">
      <label
        className={"shutter" ++ (shutterDisabled ? " shutter-disabled" : "")}
        htmlFor={"capture-file-" ++ label}
        ariaLabel="Capture this face"
        dataTestId="shutter"
        tabIndex={-1}
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
      {React.string(hasExisting ? "Recapture " : "Capture ")}
      {chipName(chip)}
    </p>
    <label className="btn btn-secondary" htmlFor={"library-file-" ++ label}>
      <Icon name=Image size=20 />
      {React.string("From library")}
    </label>
    {removable
      ? <Ui.Button
          variant=Secondary
          size=Small
          testId="custom-face-remove"
          disabled=isBusy
          ariaLabel={"Remove the " ++ label ++ " chip"}
          onClick={_ => dispatch(CustomRemove(label))}>
          <>
            <Icon name=X size=16 />
            {React.string("Remove chip")}
          </>
        </Ui.Button>
      : React.null}
    {isBusy ? <Ui.Pill> {React.string(progressText)} </Ui.Pill> : React.null}
    {switch rowError {
    | Some(msg) => <p className="t-footnote text-error"> {React.string(msg)} </p>
    | None => React.null
    }}
  </div>
}

// Inline "+ Custom" card (SPEC §8a A7, DESIGN.md §4 Text input / Segmented,
// §11.1 "Confirmations": in-flow `.list-group`, no overlay): the mono name
// field (feature-name rule + unique on this part, validated live), the
// sketch-plane picker, "Add face" and "Cancel". Enter in the field adds.
let customCard = (model: model, draft: customDraft, ~dispatch: msg => unit): React.element => {
  let error = draft.draftLabel == "" ? None : labelError(model, draft.draftLabel)
  let canAdd = draft.draftLabel != "" && error->Option.isNone
  <div className="list-group custom-card" dataTestId="custom-face-card">
    <Ui.Field
      label="Face name"
      htmlFor="custom-face-label"
      mono=true
      error=?error
      errorTestId="custom-face-error"
      help="a–z, 0–9 and _ ; names the exported files (faces/<name>.jpg)">
      {Canvas.Input.make({
        dataTestId: "custom-face-label",
        id: "custom-face-label",
        type_: "text",
        autoCapitalize: "none",
        autoCorrect: "off",
        autoComplete: "off",
        spellCheck: false,
        enterKeyHint: "done",
        placeholder: "left_side",
        ariaInvalid: error->Option.isSome,
        value: draft.draftLabel,
        onChange: e => dispatch(CustomLabelChanged(inputValue(e))),
        onKeyDown: e => onEnter(e, () => dispatch(CustomAdd)),
      })}
    </Ui.Field>
    <div className="field">
      <span className="field-label" ariaHidden=true> {React.string("Sketch plane")} </span>
      <Ui.Segmented
        options=planeOptions
        selected={Enums.faceKindToString(draft.plane)}
        onSelect={key =>
          switch Enums.faceKindFromString(key) {
          | Some(plane) => dispatch(CustomPlaneChanged(plane))
          | None => ()
          }}
        testIdPrefix="custom-face-plane-"
        ariaLabel="Sketch plane"
      />
    </div>
    <div className="custom-card-buttons">
      <Ui.Button
        variant=Primary block=true testId="custom-face-add" disabled={!canAdd} onClick={_ => dispatch(CustomAdd)}>
        {React.string("Add face")}
      </Ui.Button>
      <Ui.Button variant=Plain block=true testId="custom-face-cancel" onClick={_ => dispatch(CustomCancel)}>
        {React.string("Cancel")}
      </Ui.Button>
    </div>
  </div>
}

// Inline recapture card (DESIGN.md §11.2, §11.1 "Confirmations"): no
// overlay/modal, just a `.list-group` card in place of the shutter block.
let recaptureCard = (pending: pendingCapture, ~dispatch: msg => unit): React.element =>
  <div className="list-group recapture-card" role="alertdialog" ariaLabel="Replace photo?">
    <p className="t-body">
      {React.string("Replace the ")}
      {chipName(pending.chip)}
      {React.string(" photo?")}
    </p>
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
      <Ui.Button
        variant=Plain block=true testId="recapture-cancel" onClick={_ => dispatch(RecaptureCancelClicked)}>
        {React.string("Cancel")}
      </Ui.Button>
    </div>
  </div>

// One real `<input type=file>`, visually hidden but always in the DOM
// (SPEC §8a A4 / docs/testids.md contract) — see `hiddenInputs` below. The
// currently-*selected* chip's pair also carries a static
// `input-selected-camera`/`input-selected-library` class, purely so
// `Capture.css` can give the visible shutter/library label a focus ring
// when its own hidden input is Tab-focused (DESIGN.md §9 "Focus-visible
// rings on every interactive element"): the input isn't a DOM descendant of
// its label (see the module-end notes on why), so a plain `:focus-within`
// on the label can't see it, and there's no way to key a rule to an
// arbitrary custom face's *id* in static CSS — but exactly one chip is ever
// selected, so a shared, non-dynamic class plus `:has()` at the
// `.capture-view` root (already used by `.shutter`'s old, dead
// `:focus-within:has(input:focus-visible)` attempt — this replaces it)
// works for every label, default or custom, with one static rule.
let renderCaptureInput = (
  model: model,
  ~dispatch: msg => unit,
  ~chip: chip,
  ~fromLibrary: bool,
): React.element => {
  let label = chip.label
  let disabled = model.busy == Some(label) || isDialogOpen(model)
  let gen = genFor(model.inputGens, label, ~fromLibrary)
  let testId = (fromLibrary ? "library-file-" : "capture-file-") ++ label
  let ariaLabel =
    (fromLibrary ? "Choose " : "Capture ") ++
    chipAriaName(chip) ++
    (fromLibrary ? " photo from library" : " photo with camera")
  let isSelected = chip.label == model.selectedLabel
  let selectedClass = switch (isSelected, fromLibrary) {
  | (true, false) => " input-selected-camera"
  | (true, true) => " input-selected-library"
  | (false, _) => ""
  }
  <input
    key={testId ++ "-" ++ Int.toString(gen)}
    id=testId
    type_="file"
    accept="image/jpeg,image/png"
    capture=?{fromLibrary ? None : Some(#environment)}
    className={"visually-hidden" ++ selectedClass}
    dataTestId=testId
    ariaLabel
    disabled
    onChange={evt => dispatch(FileChosen(label, fromLibrary, ImageDecode.fileFromChangeEvent(evt)))}
  />
}

// Every chip's inputs (one camera + one library each), always mounted —
// deliberately not nested inside the shutter/library labels above (which
// only ever reference the *selected* chip's `id` via `htmlFor`), so their
// presence never depends on `selectedLabel` or `model.dialog`.
let hiddenInputs = (model: model, ~dispatch: msg => unit): React.element =>
  chipsOf(model)
  ->Array.flatMap(chip => [
    renderCaptureInput(model, ~dispatch, ~chip, ~fromLibrary=false),
    renderCaptureInput(model, ~dispatch, ~chip, ~fromLibrary=true),
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
    // The selected label always resolves (defaults are always present);
    // the fallback only guards a removed chip between two renders.
    let selectedChip =
      chipOf(model, model.selectedLabel)->Option.getOr(
        chipOf(model, "top")->Option.getOr({label: "top", kind: Types.Top}),
      )
    <div className="capture-page">
      <Ui.Live text=model.announcement testId="capture-live" />
      {faceGrid(model, ~dispatch)}
      <div className="capture-action">
        {switch (model.dialog, model.customDraft) {
        | (RecaptureConfirm(pending), _) => recaptureCard(pending, ~dispatch)
        | (NoDialog, Some(draft)) => customCard(model, draft, ~dispatch)
        | (NoDialog, None) => shutterBlock(model, ~chip=selectedChip, ~dispatch)
        }}
      </div>
      {hiddenInputs(model, ~dispatch)}
      <p
        className={model.cameraDenied ? "camera-note camera-note-prominent" : "camera-note"}
        dataTestId="capture-note">
        {React.string("Camera blocked? Use From library — Settings › Safari › Camera controls it.")}
      </p>
    </div>
  }

// -- judgment calls (see LOGBOOK.md "A7 custom faces" and "Design wave 2 —
// capture" for the full write-ups; "M3 capture" below is the original M3
// agent's own notes) --
//
// A7 custom faces:
// - The page is keyed by *label* end to end (`selectedLabel`, `busy`,
//   `error`, `inputGens`, every msg that used to carry a kind). A chip's
//   kind is only ever read at the moment a face record is built, so the
//   four defaults behave exactly as before (`label == kind`) and the
//   `capture-file-<kind>` / `library-file-<kind>` testids are unchanged.
// - Chips are *derived* (`chipsOf`): defaults, then captured custom faces
//   from `model.faces`, then the page-only `customChips`. A custom chip
//   that gets captured therefore switches source without any bookkeeping
//   beyond dropping the page-only copy at `Saved`.
// - Uniqueness is checked against every chip, not just captured faces —
//   so "top" (an uncaptured default) and an unsaved custom chip are both
//   rejected. Same `FeatureName` rule + messages as the annotate name field.
// - The custom card replaces the shutter block while open (like the
//   recapture card) rather than stacking under it: one thing asks for input
//   at a time, and the face grid above it stays visible. Tapping any
//   card closes it.
// - No auto-focus on the name field: `Canvas.Input` has no `autoFocus`
//   prop and bindings are outside this track's file ownership. One extra
//   tap; flagged as a rough edge.
//
// Design wave 2 additions (still true, now by label):
// - `selectedLabel`/`labelManuallySelected` and `faceImages`/`FaceImageLoaded`
//   are UI-only. `GotFaces` fires exactly once (from `init`'s cmd; nothing
//   else re-fetches the face list), so "default to the first default face
//   without a capture, else Top" only ever needs to run that once —
//   `labelManuallySelected` exists mainly so a hypothetical future re-fetch
//   can't clobber a deliberate chip tap.
// - The 76 px shutter and the "From library" capsule reference the
//   selected chip's input by `htmlFor` (id), not by wrapping it — unlike
//   `Ui.Toggle`'s wrap-the-checkbox pattern, this keeps every `<input>` in
//   one fixed place, present regardless of `selectedLabel` or
//   `model.dialog`. Trade-off: keyboard Tab reaches all of them (each
//   carries its own descriptive `aria-label`, e.g. "Capture Side photo
//   with camera") rather than just the two matching the visible controls,
//   and a hidden input's own `:focus-visible` ring — being on a 1x1px
//   clipped element — isn't a useful visual cue. Untested by any spec;
//   flagged here as a minor, deliberate rough edge.
// - "From library" always reads "From library", not "Recapture from
//   library": DESIGN.md §11.2 names the capsule's copy once, and the Body
//   caption above it ("Capture Top" / "Recapture Top") already carries the
//   recapture state.
// - The progress pill's text ("Decoding…" vs "Saving…") is derived from
//   existing state, not a new msg: while `model.busy` matches the selected
//   chip, `model.dialog` is still `NoDialog` during the initial decode and
//   still `RecaptureConfirm(_)` for the whole confirm/keep-through-save
//   window, so the two phases are already distinguishable from state alone.
// - `Ui.res` gap: no "plain"/borderless button variant, so the cards'
//   Cancel uses the default (Secondary).
// - Level readout: DESIGN.md's "mono teal Ui.Pill next to the shutter when
//   available" reuses the existing `levelFromSamples` helper live off
//   `lastBeta`/`lastGamma` — display-only, no new state.
//
// Design wave P2b "layout A" (docs/design/review-2026-09-17.md C1-C4,
// DESIGN.md §11.2 "Capture" — see LOGBOOK.md "P2b — layout A: Capture" for
// the full write-up):
// - Chip row + slot row → one `faceGrid` of `Ui.FaceCard`s. No model
//   changes: the grid is a pure function of the same `chipsOf`/
//   `existingFaceOf`/`faceImages`/`selectedLabel` the two old rows already
//   read; `onClick` still dispatches the same `SelectChip`.
// - Shutter anchored low (C1): `.capture-page` (renamed from
//   `.capture-view`) is `min-height: 100%`; a new `.capture-action` wrapper
//   around the shutter/recapture/custom-card switch is `margin-top: auto`,
//   pushing it (and the camera note after it) to the bottom of the content.
//   Same technique the review doc itself proposed for the do-now fix,
//   generalized to the one wrapper so all three interchangeable blocks
//   inherit it without three separate CSS rules.
// - Ui gaps run into, not worked around by hand-rolling markup outside
//   `Ui.FaceCard` (out of this track's file ownership — `Ui.res` isn't
//   editable here): (1) no `ariaPressed` prop — the old slot's
//   `aria-pressed` is gone; selection is now stated in the card's
//   `ariaLabel` instead (`cardAriaLabel`), and `faces.spec.js`'s two
//   `capture-chip-*` `aria-pressed` assertions were updated to check
//   `face-card-selected`/`face-card-captured` instead (a legitimate
//   interaction change, not a weakening of the check — see that spec's own
//   comment at the edit). (2) `~image=None` always renders the `Empty`
//   look regardless of `~state` (per `Ui.FaceCard`'s own doc comment), so a
//   *selected but uncaptured* kind shows no accent ring — the shutter
//   block's "Capture <Label>" caption is the only cue which kind is
//   targeted in that case. (3) The `Empty` branch hardcodes a Camera icon
//   with no way to ask for `Plus`, so the "+ Custom" card's own *label*
//   text is "+ Custom" (the "+" lives in the string, not an icon swap).
//   (4) `badge`/`caption` only render in the `Some(image)` branch — a real
//   `Empty` card (no image at all, e.g. an uncaptured default or an unsaved
//   custom chip) has no slot for either, which is also why
//   `custom-face-remove` couldn't move onto the card itself (see below).
//   One knock-on effect: a just-captured face briefly shows as a plain
//   `Empty` card until its object URL loads (`FaceImageLoaded`) — the old
//   slot row showed the check badge immediately off `hasExisting`,
//   independent of the thumbnail; this is a minor, transient regression
//   (local-blob object URLs resolve in well under a frame in practice).
// - Dense grid (`.face-grid-dense`, 3-up) triggers at ≥ 5 *chips*
//   (`chipsOf`'s length), not ≥ 5 total grid cells: counting the always-
//   present "+ Custom" cell would make every bare, zero-capture part
//   (4 defaults + 1 "+ Custom" = 5 cells) dense from the first render,
//   which the review's "≥ 5 faces" rule was never meant to trigger.
// - `capture-kinds` testid moved from the old chip row onto the face-grid
//   container (docs/testids.md updated) — nothing in the e2e suite reads
//   it, kept for discoverability/continuity of the id.
// - `custom-face-remove` stays exactly where it was (a button in the
//   shutter block, shown once a custom chip with no face yet is selected)
//   rather than moving into the card's own caption/badge slot — the
//   `Empty` branch has neither slot to put it in (Ui gap #4 above), and
//   "existing" affordance in the task brief read as "keep it where it
//   already works," which is also what `faces.spec.js` already exercises.
//
// M3 capture (original, still true):
// - `levelDegrees` = sqrt(beta² + gamma²): SPEC doesn't define the exact
//   formula, only that it's "the level". This is the standard bubble-level
//   magnitude across both tilt axes; 0° is flat.
// - Orientation-permission request is armed only by the *camera*
//   (capture-file-<label>) label's pointerdown, not the library label's —
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
