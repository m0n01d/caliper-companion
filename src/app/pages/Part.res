// Part — the part screen (`#/parts/:id`), SPEC M2 bullet 3 + M6 bullet 2.
// P2a (docs/design/review-2026-09-17.md §3/§4 layout A "Gallery-first"): a
// 2-column Face-card grid, Feature rows (via Reconcile) in a role=list,
// warning rows, export, and the per-part hands-on timer.

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

// Shell slots (DESIGN.md §11.1). Layout A's own bar note ("subtitle 'n faces
// · n features · unit'") is superseded by docs/design/a10-folders-review.md
// §1 B2 (blocker, resolved in the spec's favour): the subtitle slot is
// reserved for A10's future folder path, so it stays unused here — the
// faces/features/unit stats line moves into the features group header
// instead (see `featuresHeader` below).
let subtitle = (_model: model): option<string> => None

// Trailing bar text action (DESIGN.md §11.2 "trailing Edit/Done text
// action"; review-2026-09-17.md F3 — this used to be a lone in-body
// "Edit faces" capsule). Only appears once there's a face to edit, same
// condition the old in-body button used.
let actions = (model: model, ~dispatch: msg => unit): option<React.element> =>
  Array.length(model.faces) > 0
    ? Some(
        <Ui.Button
          variant=Ui.Button.Plain
          className="bar-action"
          testId="faces-edit"
          onClick={_ => dispatch(FacesEditToggled)}>
          {React.string(model.facesEditing ? "Done" : "Edit")}
        </Ui.Button>,
      )
    : None

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

let sizeText = (face: Types.face): string =>
  Int.toString(face.pixelWidth) ++ " × " ++ Int.toString(face.pixelHeight)

let dimWord = (n: int): string => n == 1 ? "dim" : "dims"

// Layout A (review-2026-09-17.md §3/§4, mockups/part-a.html): a 2-column
// grid of `Ui.FaceCard` — the grid/card CSS itself is global.css §14
// (Ui.FaceCard's own doc comment), nothing page-scoped needed for it.
// 3-up (`.face-grid-dense`) at ≥ 5 faces per DESIGN.md §4's Face card row.
// `face-<label>` still names the whole card, so capture.spec.js's size-text
// read (`tileSize`'s innerText fallback) and faces.spec.js's `toContainText`
// checks keep working. Faces come in Store order (kind, then label — SPEC
// §8a A7).
let renderFaceGrid = (model: model): React.element => {
  let dimCountOfFace = (face: Types.face) =>
    model.dimensions->Array.filter(d => d.faceId == face.id)->Array.length
  let gridClass = Array.length(model.faces) >= 5 ? "face-grid face-grid-dense" : "face-grid"
  <div className=gridClass>
    {model.faces
    ->Array.map(face => {
        let n = dimCountOfFace(face)
        let caption = sizeText(face) ++ " · " ++ Int.toString(n) ++ " " ++ dimWord(n)
        <Ui.FaceCard
          key={face.id}
          label={face.label}
          caption
          image={Dict.get(model.faceImages, face.id)}
          state=Ui.FaceCard.Captured
          href={Route.href(Route.Annotate(model.partId, face.id))}
          badge={<span className="face-card-check"> <Icon name=Check /> </span>}
          testId={"face-" ++ face.label}
        />
      })
    ->React.array}
    <Ui.FaceCard
      label="Capture"
      image=None
      state=Ui.FaceCard.Empty
      href={Route.href(Route.Capture(model.partId))}
      testId="capture-face"
    />
  </div>
}

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

// The face grid, or in edit mode the removable list (`renderFacesEdit`).
// The Edit/Done toggle itself moved to the bar's trailing action (`actions`
// above, F3) — no in-body button here any more.
let renderFacesSection = (model: model, ~dispatch: msg => unit): React.element =>
  model.facesEditing ? renderFacesEdit(model, ~dispatch) : renderFaceGrid(model)

// A dimension's kind, spelled as the prefix its canvas pill already uses
// (DESIGN.md §5 "Diameter kind"/"Depth kind"): the row's only remaining cue
// to kind now that there's no FACES/kind column (F5, "no column header").
let kindGlyph = (kind: Types.dimensionKind): string =>
  switch kind {
  | Diameter => "⌀ "
  | Depth => "↓ "
  | Length => ""
  }

let countLabel = (n: int, singular: string, plural: string): string =>
  Int.toString(n) ++ " " ++ (n == 1 ? singular : plural)

// review-2026-09-17.md §3 layout A's own stats line ("n faces · n features ·
// unit") was written for the bar subtitle; a10-folders-review.md §1 B2
// (blocker) resolves that slot to A10's future folder path instead and
// tells this line to move into the features group header — so it lives
// here, not in `subtitle` above.
let featuresHeader = (~faceCount: int, ~featureCount: int, ~units: Types.units): string =>
  "Features · " ++
  countLabel(faceCount, "face", "faces") ++
  " · " ++
  countLabel(featureCount, "feature", "features") ++
  " · " ++
  NumberParse.unitsLabel(units)

// DESIGN.md §4 "Feature row" / §11.2: a role=list of role=listitem rows (no
// `<table>`, no column header — F5) live/error warning rows are split by
// cause (a kind conflict blocks export and is a different severity than a
// spread flag) rather than one merged "Check: …" line.
let renderFeatures = (model: model, ~part: Types.part): React.element => {
  let (features, conflicts) = reconcileForDisplay(model.dimensions)
  // SPEC §8a A7: the faces line shows labels ("top", "left_side").
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
      let header = featuresHeader(
        ~faceCount=Array.length(model.faces),
        ~featureCount=Array.length(features),
        ~units=part.units,
      )
      <Ui.ListGroup header asList=true testId="features-list">
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
            let valueText = NumberParse.format(feature.value, part.units)
            let unitLabel = NumberParse.unitsLabel(part.units)
            let tolText = NumberParse.format(feature.tolerance, part.units)
            // "<name>, <value> <unit>, ± <tol>, faces <labels>" — the row's
            // own accessible name (it carries an explicit `aria-label`, so
            // nothing inside it needs to spell this out again).
            let accessibleName =
              feature.name ++
              ", " ++
              valueText ++
              " " ++
              unitLabel ++
              ", ± " ++
              tolText ++
              ", faces " ++
              facesLabel
            <div
              key={feature.name}
              className="feature-row"
              role="listitem"
              dataTestId="feature-row"
              ariaLabel=accessibleName>
              <div className="feature-row-name">
                <span className="feature-row-name-text mono">
                  {feature.flagged
                    ? <span className="flag-marker">
                        <Icon name=TriangleAlert size=14 label="Flagged" />
                      </span>
                    : React.null}
                  {React.string(kindGlyph(feature.kind) ++ feature.name)}
                </span>
                <span
                  className={"feature-row-faces t-footnote " ++
                  (facesOnMultiple ? "text-live" : "muted")}>
                  {React.string(facesLabel)}
                </span>
              </div>
              <div className="feature-row-value mono">
                {React.string(valueText)}
                <span className="feature-row-unit t-subhead muted">
                  {React.string(" " ++ unitLabel)}
                </span>
              </div>
              <div className="feature-row-tol t-footnote mono muted">
                {React.string("±" ++ tolText)}
              </div>
            </div>
          })
        ->React.array}
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
