// Part — the part screen (`#/parts/:id`), SPEC M2 bullet 3 + M6 bullet 2.
// Faces row, features table (via Reconcile), a warning row, export, and the
// per-part hands-on timer.

type partStatus =
  | Pending
  | Found(Types.part)
  | Missing

type exportStatus =
  | Idle
  | Running
  | Done(string)
  | Failed(string)

type model = {
  partId: string,
  partStatus: partStatus,
  faces: array<Types.face>,
  faceImages: Dict.t<string>, // faceId -> object URL (Download.objectUrlOfImage)
  dimensions: array<Types.dimension>,
  timer: option<Store.timer>,
  now: float, // Date.now(), refreshed by Tick — drives the running-timer readout
  error: option<string>,
  exportState: exportStatus,
  // SPEC §8a A7: faces are deleted from this page (a captured custom face
  // has nowhere else to go). "Edit" swaps the slot row for a list with a
  // Remove per face; `pendingDelete` is the inline confirm's subject.
  facesEditing: bool,
  pendingDelete: option<Types.face>,
  deleting: bool,
  // DESIGN.md §9 "Live region": the current `aria-live="polite"` line
  // (`Ui.Live`, rendered unconditionally in `view`). "" is silence, not
  // absence — see `Ui.Live`'s own doc comment for why it must stay mounted.
  announcement: string,
}

type msg =
  | PartLoaded(option<Types.part>)
  | FacesLoaded(array<Types.face>)
  | DimensionsLoaded(array<Types.dimension>)
  | TimerLoaded(option<Store.timer>)
  | LoadFailed(string)
  | FaceImageLoaded(string, option<string>)
  | Tick
  | ExportClicked
  | ExportFinished(result<Export.outcome, Export.error>)
  | FacesEditToggled
  | FaceRemoveClicked(Types.face)
  | FaceDeleteConfirmed
  | FaceDeleteCancelled
  | FaceDeleted(result<unit, string>)

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let loadFacesCmd = (~partId: string): Tea.cmd<msg> =>
  Tea.fromPromise(() => Store.facesOf(store(), ~partId), fs => FacesLoaded(fs), e => LoadFailed(
    describeError(e),
  ))

let loadDimensionsCmd = (~partId: string): Tea.cmd<msg> =>
  Tea.fromPromise(() => Store.dimensionsOf(store(), ~partId), ds => DimensionsLoaded(ds), e => LoadFailed(
    describeError(e),
  ))

let init = (~partId: string): (model, Tea.cmd<msg>) => {
  let model = {
    partId,
    partStatus: Pending,
    faces: [],
    faceImages: Dict.make(),
    dimensions: [],
    timer: None,
    now: Date.now(),
    error: None,
    exportState: Idle,
    facesEditing: false,
    pendingDelete: None,
    deleting: false,
    announcement: "",
  }
  let s = store()
  let cmd = Tea.batch([
    Tea.fromPromise(() => Store.getPart(s, partId), p => PartLoaded(p), e => LoadFailed(
      describeError(e),
    )),
    loadFacesCmd(~partId),
    loadDimensionsCmd(~partId),
    Tea.fromPromise(() => Store.getTimer(s, ~partId), t => TimerLoaded(t), e => LoadFailed(
      describeError(e),
    )),
    // Runs for the lifetime of the app, not just this page — see
    // Timers.res's doc comment and LOGBOOK.md for why that's fine.
    Timers.everySecond(Tick),
  ])
  (model, cmd)
}

let loadFaceImageCmd = (face: Types.face): Tea.cmd<msg> =>
  Tea.fromPromise(
    () => Store.getFaceImage(store(), face.id),
    blobOpt => FaceImageLoaded(face.id, blobOpt->Option.map(Download.objectUrlOfImage)),
    _e => FaceImageLoaded(face.id, None),
  )

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | PartLoaded(Some(p)) => ({...model, partStatus: Found(p)}, Tea.none)
  | PartLoaded(None) => ({...model, partStatus: Missing}, Tea.none)
  | FacesLoaded(fs) => ({...model, faces: fs}, Tea.batch(fs->Array.map(loadFaceImageCmd)))
  | DimensionsLoaded(ds) => ({...model, dimensions: ds}, Tea.none)
  | TimerLoaded(t) => ({...model, timer: t}, Tea.none)
  | LoadFailed(msg) => ({...model, error: Some(msg)}, Tea.none)
  | FaceImageLoaded(faceId, Some(url)) =>
    let next = Dict.copy(model.faceImages)
    Dict.set(next, faceId, url)
    ({...model, faceImages: next}, Tea.none)
  | FaceImageLoaded(_, None) => (model, Tea.none)
  | Tick => ({...model, now: Date.now()}, Tea.none)
  | ExportClicked =>
    switch model.exportState {
    | Running => (model, Tea.none)
    | Idle | Done(_) | Failed(_) => (
        {...model, exportState: Running},
        Tea.fromPromise(
          () => Export.run(store(), ~partId=model.partId, ~appVersion="0.1.0"),
          r => ExportFinished(r),
          _e => ExportFinished(Error(Export.Failed("Export failed unexpectedly"))),
        ),
      )
    }
  | ExportFinished(result) =>
    let state = switch result {
    | Ok(Export.Shared) => Done("Shared")
    | Ok(Export.Downloaded(name)) => Done("Downloaded " ++ name)
    | Error(Export.KindConflict(name)) =>
      Failed("Export blocked: `" ++ name ++ "` is measured as different kinds")
    | Error(Export.NoFaces) => Failed("Capture a face first")
    | Error(Export.Failed(msg)) => Failed(msg)
    }
    // DESIGN.md §9: "Export ready: <file>" / export errors, live-announced.
    // Built from `result` directly (not `state`'s already-composed string)
    // so the wording stays clean instead of nesting "Export ready:" in
    // front of "Downloaded <file>". The share-sheet outcome has no filename
    // to report (the OS took the bytes, not this page) — its own phrasing.
    let announcement = switch result {
    | Ok(Export.Shared) => "Export shared"
    | Ok(Export.Downloaded(name)) => "Export ready: " ++ name
    | Error(_) =>
      switch state {
      | Failed(msg) => "Export failed: " ++ msg
      | Idle | Running | Done(_) => model.announcement // unreachable: state mirrors result above
      }
    }
    ({...model, exportState: state, announcement}, Tea.none)
  | FacesEditToggled => ({...model, facesEditing: !model.facesEditing, pendingDelete: None}, Tea.none)
  | FaceRemoveClicked(face) => ({...model, pendingDelete: Some(face)}, Tea.none)
  | FaceDeleteCancelled => ({...model, pendingDelete: None}, Tea.none)
  | FaceDeleteConfirmed =>
    switch model.pendingDelete {
    | Some(face) if !model.deleting => (
        {...model, deleting: true},
        // `Store.deleteFace` removes the face and its dimensions in one
        // bulk write (Store.resi); the features table re-reconciles from
        // the reloaded dimensions.
        Tea.fromPromise(
          () => Store.deleteFace(store(), face.id),
          () => FaceDeleted(Ok()),
          e => FaceDeleted(Error(describeError(e))),
        ),
      )
    | _ => (model, Tea.none)
    }
  | FaceDeleted(Ok()) => (
      {...model, deleting: false, pendingDelete: None},
      Tea.batch([loadFacesCmd(~partId=model.partId), loadDimensionsCmd(~partId=model.partId)]),
    )
  | FaceDeleted(Error(msg)) =>
    ({...model, deleting: false, pendingDelete: None, error: Some(msg)}, Tea.none)
  }

let title = (model: model): string =>
  switch model.partStatus {
  | Found(p) => p.name
  | Pending | Missing => "Part"
  }
let back = (_model: model): option<Route.t> => Some(Route.Parts)

// -- view helpers -----------------------------------------------------------

let pad2 = (n: int): string => Int.toString(n)->String.padStart(2, "0")

let formatHandsOn = (totalSeconds: int): string => {
  let clamped = totalSeconds < 0 ? 0 : totalSeconds
  let m = clamped / 60
  let s = Int.mod(clamped, 60)
  `Hands-on ${Int.toString(m)}m ${pad2(s)}s`
}

// Kind-conflicting names are dropped wholesale before reconciling, so the
// rest of the part's features still render (SPEC: "never a blank section")
// and the conflict is still visible in the warning row.
let reconcileForDisplay = (dimensions: array<Types.dimension>): (
  array<Types.feature>,
  array<string>,
) => {
  let conflicts = Reconcile.conflicts(dimensions)
  let clean = dimensions->Array.filter(d => !Array.includes(conflicts, d.name))
  let features = switch Reconcile.reconcile(clean) {
  | Ok(fs) => fs
  | Error(_) => [] // unreachable: `clean` has no conflicting name by construction
  }
  (features, conflicts)
}

let uniqueSorted = (names: array<string>): array<string> =>
  names
  ->Array.reduce([], (acc, n) => Array.includes(acc, n) ? acc : Array.concat(acc, [n]))
  ->Array.toSorted(String.compare)

// SPEC §8a A7: a default face's label is its kind ("top"), shown
// capitalised by Part.css's `.face-slot-label`; a custom label is a slug
// and renders as-is in the mono stack (DESIGN.md §7), without that class.
let isDefaultLabel = (face: Types.face): bool =>
  face.label == Enums.faceKindToString(face.kind)

let faceLabelEl = (face: Types.face): React.element =>
  isDefaultLabel(face)
    ? <span className="face-slot-label t-caption-1"> {React.string(face.label)} </span>
    : <span className="t-caption-1 mono"> {React.string(face.label)} </span>

let sizeText = (face: Types.face): string =>
  Int.toString(face.pixelWidth) ++ " × " ++ Int.toString(face.pixelHeight)

// DESIGN.md §11.2: 56 px .slot tiles in a horizontal scroll row (reusing
// global.css's .chip-row scroller — it already hides the scrollbar and
// scrolls horizontally, so this page doesn't need its own). The size text
// stays a descendant of the face-<label> element (capture.spec.js reads it
// off the tile itself, not a Part-page-specific location). Faces come in
// Store order (kind, then label — SPEC §8a A7).
let renderFaces = (model: model): React.element =>
  <div className="chip-row faces-row">
    {model.faces
    ->Array.map(face =>
      <a
        key={face.id}
        className="face-slot"
        dataTestId={"face-" ++ face.label}
        href={Route.href(Route.Annotate(model.partId, face.id))}>
        <span className="slot slot-captured">
          {switch Dict.get(model.faceImages, face.id) {
          | Some(url) => <img src={url} alt={face.label} />
          | None => React.null
          }}
          <span className="slot-check" ariaHidden=true> <Icon name=Check size=10 /> </span>
        </span>
        {faceLabelEl(face)}
        <span className="face-slot-size t-caption-2 muted"> {React.string(sizeText(face))} </span>
      </a>
    )
    ->React.array}
    <a
      className="face-slot"
      dataTestId="capture-face"
      href={Route.href(Route.Capture(model.partId))}>
      <span className="slot slot-empty"> <Icon name=Camera size=20 /> </span>
      <span className="face-slot-label t-caption-1"> {React.string("Capture")} </span>
    </a>
  </div>

// SPEC §8a A7 "a captured custom face is deleted from the Part page like any
// face (delete confirms inline, removes its dimensions)". Edit mode swaps
// the slot row for an inset grouped list — one row per face with a Remove —
// and the confirm is an in-flow error row + two buttons (DESIGN.md §11.1
// "Confirmations": no modal). `face-<label>` stays on each row so the label
// and size text keep the same home as in the slot row.
let renderFacesEdit = (model: model, ~dispatch: msg => unit): React.element => {
  let dimCount = (face: Types.face) =>
    model.dimensions->Array.filter(d => d.faceId == face.id)->Array.length
  <div className="stack">
    <Ui.ListGroup header="Faces" asList=true testId="faces-edit-list">
      {model.faces
      ->Array.map(face =>
        <Ui.ListRow
          key={face.id}
          testId={"face-" ++ face.label}
          leading={<Ui.ListThumb src={Dict.get(model.faceImages, face.id)} alt={face.label} />}
          trailing={<Ui.Button
            variant=Danger
            size=Small
            testId="face-remove"
            disabled={model.deleting}
            ariaLabel={"Remove " ++ face.label}
            onClick={_ => dispatch(FaceRemoveClicked(face))}>
            {React.string("Remove")}
          </Ui.Button>}>
          <Ui.ListRow.Title>
            {isDefaultLabel(face)
              ? <span className="face-slot-label"> {React.string(face.label)} </span>
              : <span className="mono"> {React.string(face.label)} </span>}
          </Ui.ListRow.Title>
          <Ui.ListRow.Meta>
            {React.string(
              sizeText(face) ++
              " · " ++
              Int.toString(dimCount(face)) ++ (dimCount(face) == 1 ? " dimension" : " dimensions"),
            )}
          </Ui.ListRow.Meta>
        </Ui.ListRow>
      )
      ->React.array}
    </Ui.ListGroup>
    {switch model.pendingDelete {
    | Some(face) =>
      <div className="stack" role="alertdialog" ariaLabel="Delete face?">
        <Ui.WarningRow tone=Ui.WarningRow.Error>
          {React.string(
            "Delete " ++
            face.label ++
            " and its " ++
            Int.toString(dimCount(face)) ++
            (dimCount(face) == 1 ? " dimension?" : " dimensions?"),
          )}
        </Ui.WarningRow>
        <Ui.Button
          variant=Danger
          block=true
          testId="face-delete-confirm"
          disabled={model.deleting}
          onClick={_ => dispatch(FaceDeleteConfirmed)}>
          {React.string(model.deleting ? "Deleting…" : "Delete face")}
        </Ui.Button>
        <Ui.Button block=true testId="face-delete-cancel" onClick={_ => dispatch(FaceDeleteCancelled)}>
          {React.string("Cancel")}
        </Ui.Button>
      </div>
    | None => React.null
    }}
  </div>
}

// The slot row (or, in edit mode, the list) plus the small Edit/Done toggle,
// which only appears once there is a face to remove.
let renderFacesSection = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack">
    {model.facesEditing ? renderFacesEdit(model, ~dispatch) : renderFaces(model)}
    {Array.length(model.faces) > 0
      ? <div>
          <Ui.Button
            variant=Secondary size=Small testId="faces-edit" onClick={_ => dispatch(FacesEditToggled)}>
            {React.string(model.facesEditing ? "Done" : "Edit faces")}
          </Ui.Button>
        </div>
      : React.null}
  </div>

// DESIGN.md §11.2: inset grouped table; live/error warning rows are split by
// cause (a kind conflict blocks export and is a different severity than a
// spread flag) rather than one merged "Check: …" line.
let renderFeatures = (model: model, ~part: Types.part): React.element => {
  let (features, conflicts) = reconcileForDisplay(model.dimensions)
  // SPEC §8a A7: the faces column shows labels ("top", "left_side").
  let faceLabelById = model.faces->Array.reduce(Dict.make(), (acc, f) => {
    Dict.set(acc, f.id, f.label)
    acc
  })
  let flaggedNames = uniqueSorted(features->Array.filter(f => f.flagged)->Array.map(f => f.name))
  let conflictNames = uniqueSorted(conflicts)

  <div className="stack">
    {if Array.length(features) == 0 && Array.length(conflicts) == 0 {
      <p className="t-footnote muted"> {React.string("No dimensions captured yet.")} </p>
    } else {
      <Ui.ListGroup header="Features">
        // The `display: grid` + `display: contents` layout (Part.css —
        // needed so the NAME column can shrink+ellipsis below its content
        // width, see that file's comment) makes Chromium/Firefox compute
        // this table's accessibility-tree roles from CSS `display` instead
        // of its HTML tag: a `<table>` whose own `display` isn't
        // `table`/`table-row`/etc. loses its implicit `table` role, and a
        // `<tr>`/`<thead>`/`<tbody>` styled `display: contents` loses
        // `row`/`rowgroup` the same way (a documented interaction between
        // the CSS Display and Core-AAM specs — DESIGN.md §9's own
        // parenthetical "role=table grid with proper roles if it stays a
        // CSS grid" anticipates exactly this). Explicit `role`s restore the
        // real table semantics regardless of the CSS `display` value.
        <table className="features-table" role="table">
          <thead role="rowgroup">
            <tr role="row">
              <th role="columnheader" scope="col"> {React.string("Name")} </th>
              <th role="columnheader" scope="col" className="num"> {React.string("Value")} </th>
              <th role="columnheader" scope="col" className="num"> {React.string("Tol")} </th>
              <th role="columnheader" scope="col" className="num"> {React.string("Faces")} </th>
            </tr>
          </thead>
          <tbody role="rowgroup">
            {features
            ->Array.map(feature => {
              let facesLabel =
                feature.faceIds
                ->Array.map(id =>
                  switch Dict.get(faceLabelById, id) {
                  | Some(label) => label
                  | None => "?"
                  }
                )
                ->Array.join(", ")
              let facesOnMultiple = Array.length(feature.faceIds) > 1
              <tr key={feature.name} role="row" dataTestId="feature-row">
                <td role="cell" className="mono">
                  {React.string(feature.name)}
                  {feature.flagged
                    ? <span className="flag-marker" ariaLabel="flagged">
                        <Icon name=TriangleAlert size=14 />
                        {React.string(" flagged")}
                      </span>
                    : React.null}
                </td>
                <td role="cell" className="num mono">
                  {React.string(NumberParse.format(feature.value, part.units))}
                  <span className="unit t-subhead muted">
                    {React.string(" " ++ NumberParse.unitsLabel(part.units))}
                  </span>
                </td>
                <td role="cell" className="num mono muted">
                  {React.string("± " ++ NumberParse.format(feature.tolerance, part.units))}
                </td>
                <td role="cell" className={facesOnMultiple ? "num mono text-live" : "num mono muted"}>
                  {React.string(facesLabel)}
                </td>
              </tr>
            })
            ->React.array}
          </tbody>
        </table>
      </Ui.ListGroup>
    }}
    {if Array.length(conflictNames) > 0 {
      <Ui.WarningRow tone=Ui.WarningRow.Error testId="warning-row">
        {React.string(
          "Kind conflict: " ++ Array.join(conflictNames, ", ") ++ " — measured as different kinds; blocks export.",
        )}
      </Ui.WarningRow>
    } else {
      React.null
    }}
    {if Array.length(flaggedNames) > 0 {
      <Ui.WarningRow tone=Ui.WarningRow.Live testId="warning-row">
        {React.string("Flagged: " ++ Array.join(flaggedNames, ", ") ++ " — spread exceeds tolerance.")}
      </Ui.WarningRow>
    } else {
      React.null
    }}
  </div>
}

let renderExport = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack">
    <Ui.Button
      variant=Ui.Button.Primary
      block=true
      testId="export"
      disabled={model.exportState == Running}
      onClick={_ => dispatch(ExportClicked)}>
      {React.string(model.exportState == Running ? "Exporting…" : "Export")}
    </Ui.Button>
    {switch model.exportState {
    | Done(msg) => <p className="t-footnote text-live"> {React.string(msg)} </p>
    | Failed(msg) => <p className="t-footnote text-error" dataTestId="export-error"> {React.string(msg)} </p>
    | Idle | Running => React.null
    }}
  </div>

let renderTimer = (model: model): React.element => {
  let text = switch model.timer {
  | Some({startedAt: Some(startIso), stoppedAt: None}) =>
    let startMs = Date.fromString(startIso)->Date.getTime
    formatHandsOn(Float.toInt((model.now -. startMs) /. 1000.0))
  | Some({startedAt: Some(_), stoppedAt: Some(_)} as t) =>
    switch Store.handsOnSeconds(t) {
    | Some(sec) => formatHandsOn(sec)
    | None => "Timer starts at first capture"
    }
  | Some(_) | None => "Timer starts at first capture"
  }
  <p className="t-footnote mono muted" dataTestId="timer"> {React.string(text)} </p>
}

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg">
    <Ui.Live text=model.announcement testId="part-live" />
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch model.partStatus {
    | Pending => <p className="t-footnote muted"> {React.string("Loading part…")} </p>
    | Missing =>
      <div className="stack">
        <p className="t-footnote muted"> {React.string("Part not found.")} </p>
        <a className="btn btn-secondary" href={Route.href(Route.Parts)}>
          {React.string("Back to parts")}
        </a>
      </div>
    | Found(part) =>
      <>
        {renderFacesSection(model, ~dispatch)}
        {renderFeatures(model, ~part)}
        {renderExport(model, ~dispatch)}
        {renderTimer(model)}
      </>
    }}
  </div>
