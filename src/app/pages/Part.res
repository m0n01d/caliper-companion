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

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

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
  }
  let s = store()
  let cmd = Tea.batch([
    Tea.fromPromise(() => Store.getPart(s, partId), p => PartLoaded(p), e => LoadFailed(
      describeError(e),
    )),
    Tea.fromPromise(() => Store.facesOf(s, ~partId), fs => FacesLoaded(fs), e => LoadFailed(
      describeError(e),
    )),
    Tea.fromPromise(() => Store.dimensionsOf(s, ~partId), ds => DimensionsLoaded(ds), e => LoadFailed(
      describeError(e),
    )),
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
    ({...model, exportState: state}, Tea.none)
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

let renderFaces = (model: model): React.element =>
  <div className="faces-row">
    {Enums.allFaceKinds
    ->Array.filterMap(kind => model.faces->Array.find(f => f.kind == kind))
    ->Array.map(face => {
      let kindLabel = Enums.faceKindToString(face.kind)
      <a
        key={face.id}
        className="face-tile"
        dataTestId={"face-" ++ kindLabel}
        href={Route.href(Route.Annotate(model.partId, face.id))}>
        {switch Dict.get(model.faceImages, face.id) {
        | Some(url) => <img src={url} alt={kindLabel} className="face-thumb" />
        | None => <div className="face-thumb face-thumb-placeholder" />
        }}
        <span className="face-tile-label"> {React.string(kindLabel)} </span>
      </a>
    })
    ->React.array}
    <a
      className="face-tile capture-tile"
      dataTestId="capture-face"
      href={Route.href(Route.Capture(model.partId))}>
      <span> {React.string("+ Capture face")} </span>
    </a>
  </div>

let renderFeatures = (model: model, ~part: Types.part): React.element => {
  let (features, conflicts) = reconcileForDisplay(model.dimensions)
  let faceKindById = model.faces->Array.reduce(Dict.make(), (acc, f) => {
    Dict.set(acc, f.id, f.kind)
    acc
  })
  let flaggedNames = features->Array.filter(f => f.flagged)->Array.map(f => f.name)
  let warnNames = uniqueSorted(Array.concat(flaggedNames, conflicts))

  <div className="features-section">
    <h2> {React.string("Features")} </h2>
    {if Array.length(features) == 0 && Array.length(conflicts) == 0 {
      <p className="muted"> {React.string("No dimensions captured yet.")} </p>
    } else {
      <table className="features-table">
        <thead>
          <tr>
            <th> {React.string("Name")} </th>
            <th> {React.string("Value")} </th>
            <th> {React.string("Tolerance")} </th>
            <th> {React.string("Faces")} </th>
          </tr>
        </thead>
        <tbody>
          {features
          ->Array.map(feature => {
            let facesLabel =
              feature.faceIds
              ->Array.map(id =>
                switch Dict.get(faceKindById, id) {
                | Some(k) => Enums.faceKindToString(k)
                | None => "?"
                }
              )
              ->Array.join(", ")
            <tr
              key={feature.name}
              className={feature.flagged ? "feature-row flagged" : "feature-row"}
              dataTestId="feature-row">
              <td>
                {React.string(feature.name)}
                {feature.flagged
                  ? <span className="flag-marker" ariaLabel="flagged"> {React.string(" ⚠")} </span>
                  : React.null}
              </td>
              <td>
                {React.string(
                  NumberParse.format(feature.value, part.units) ++
                  " " ++
                  NumberParse.unitsLabel(part.units),
                )}
              </td>
              <td> {React.string("± " ++ NumberParse.format(feature.tolerance, part.units))} </td>
              <td> {React.string(facesLabel)} </td>
            </tr>
          })
          ->React.array}
        </tbody>
      </table>
    }}
    {if Array.length(warnNames) > 0 {
      <div className="warning-row" dataTestId="warning-row">
        {React.string("Check: " ++ Array.join(warnNames, ", "))}
      </div>
    } else {
      React.null
    }}
  </div>
}

let renderExport = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="export-section">
    <button
      type_="button"
      dataTestId="export"
      disabled={model.exportState == Running}
      onClick={_ => dispatch(ExportClicked)}>
      {React.string(model.exportState == Running ? "Exporting…" : "Export")}
    </button>
    {switch model.exportState {
    | Done(msg) => <p className="export-result"> {React.string(msg)} </p>
    | Failed(msg) => <p dataTestId="export-error"> {React.string(msg)} </p>
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
  <p className="timer" dataTestId="timer"> {React.string(text)} </p>
}

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="page part-page">
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch model.partStatus {
    | Pending => <p> {React.string("Loading part…")} </p>
    | Missing =>
      <div className="empty-state">
        <p> {React.string("Part not found.")} </p>
        <a href={Route.href(Route.Parts)}> {React.string("Back to parts")} </a>
      </div>
    | Found(part) =>
      <>
        {renderFaces(model)}
        {renderFeatures(model, ~part)}
        {renderExport(model, ~dispatch)}
        {renderTimer(model)}
      </>
    }}
  </div>
