// Debug — `#/debug`, SPEC M6 bullet 3. Lists the last 20 dogfood timers and
// exports them as CSV. Also a viewport readout for chasing iOS standalone
// layout bugs from the phone, where there is no console (LOGBOOK
// 2026-09-17 "iOS 26/27 standalone").

type timerRow = {
  timer: Store.timer,
  partLabel: string, // the part's name once resolved; the id until then or if deleted
}

// Every height iOS can disagree with itself about, in CSS px. The unit rows
// come from the hidden `vp-probe-*` divs in `view`; -1 means a probe wasn't
// found.
type viewportReport = {
  standalone: bool,
  userAgent: string,
  screenW: float,
  screenH: float,
  innerW: float,
  innerH: float,
  visualH: option<float>,
  vh: float,
  lvh: float,
  svh: float,
  dvh: float,
  fixedInset: float, // `position: fixed; top: 0; bottom: 0` — the ICB
  safeTop: float,
  safeBottom: float,
  frameH: float, // `.app-frame` as laid out
  docClientH: float,
  docScrollH: float, // > docClientH means the document itself scrolls
}

type model = {
  loaded: bool,
  rows: array<timerRow>,
  error: option<string>,
  viewport: option<viewportReport>,
}

type msg =
  | TimersLoaded(array<Store.timer>)
  | LoadFailed(string)
  | PartLabelLoaded(string, string) // partId, label
  | ExportCsvClicked
  | ViewportMeasured(viewportReport)
  | RemeasureClicked

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let probeHeight = (id: string): float =>
  Canvas.byTestId(id)->Option.map(Canvas.offsetHeight)->Option.getOr(-1.0)

let measureViewport = (): viewportReport => {
  let root = WebApi.Style.document->WebApi.Style.documentElement
  {
    standalone: WebApi.Platform.isStandalone(),
    userAgent: WebApi.Platform.userAgent,
    screenW: Canvas.screenWidth,
    screenH: Canvas.screenHeight,
    innerW: Canvas.innerWidth,
    innerH: Canvas.innerHeight,
    visualH: WebApi.VisualViewport.instance
    ->Nullable.toOption
    ->Option.map(WebApi.VisualViewport.height),
    vh: probeHeight("vp-probe-vh"),
    lvh: probeHeight("vp-probe-lvh"),
    svh: probeHeight("vp-probe-svh"),
    dvh: probeHeight("vp-probe-dvh"),
    fixedInset: probeHeight("vp-probe-fixed"),
    safeTop: probeHeight("vp-probe-safe-top"),
    safeBottom: probeHeight("vp-probe-safe-bottom"),
    frameH: Canvas.querySelector(".app-frame")->Option.map(Canvas.offsetHeight)->Option.getOr(-1.0),
    docClientH: Canvas.clientHeight(root),
    docScrollH: Canvas.scrollHeight(root),
  }
}

// One frame later, so the probes have laid out.
let measureCmd = (): Tea.cmd<msg> =>
  Tea.effect(dispatch =>
    Canvas.requestAnimationFrame(_ => dispatch(ViewportMeasured(measureViewport())))->ignore
  )

let init = (): (model, Tea.cmd<msg>) => (
  {loaded: false, rows: [], error: None, viewport: None},
  Tea.batch([
    Tea.fromPromise(() => Store.listTimers(store(), ~limit=20), ts => TimersLoaded(ts), e => LoadFailed(
      describeError(e),
    )),
    measureCmd(),
  ]),
)

let resolvePartLabelCmd = (t: Store.timer): Tea.cmd<msg> =>
  Tea.fromPromise(
    () => Store.getPart(store(), t.partId),
    partOpt => PartLabelLoaded(t.partId, partOpt->Option.map(p => p.name)->Option.getOr(t.partId)),
    _e => PartLabelLoaded(t.partId, t.partId),
  )

// RFC-4180 quoting: wrap in quotes and double any embedded quote whenever a
// field contains a comma, a quote, or a newline (a part name might contain
// a comma).
let csvQuote = (field: string): string =>
  if String.includes(field, ",") || String.includes(field, "\"") || String.includes(field, "\n") {
    "\"" ++ String.replaceAll(field, "\"", "\"\"") ++ "\""
  } else {
    field
  }

let csvOf = (rows: array<timerRow>): string => {
  let header = "partId,partName,startedAt,stoppedAt,handsOnSeconds"
  let lines = rows->Array.map(row => {
    let t = row.timer
    let started = t.startedAt->Option.getOr("")
    let stopped = t.stoppedAt->Option.getOr("")
    let seconds = Store.handsOnSeconds(t)->Option.map(n => Int.toString(n))->Option.getOr("")
    [t.partId, row.partLabel, started, stopped, seconds]->Array.map(csvQuote)->Array.join(",")
  })
  Array.concat([header], lines)->Array.join("\n") ++ "\n"
}

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | TimersLoaded(ts) => (
      {...model, loaded: true, rows: ts->Array.map(t => {timer: t, partLabel: t.partId}), error: None},
      Tea.batch(ts->Array.map(resolvePartLabelCmd)),
    )
  | LoadFailed(msg) => ({...model, loaded: true, error: Some(msg)}, Tea.none)
  | PartLabelLoaded(partId, label) => (
      {
        ...model,
        rows: model.rows->Array.map(row =>
          row.timer.partId == partId ? {...row, partLabel: label} : row
        ),
      },
      Tea.none,
    )
  | ExportCsvClicked => (
      model,
      Tea.effect(_dispatch =>
        Download.save(~name="caliper-timers.csv", ~mime="text/csv", ~text=csvOf(model.rows))
      ),
    )
  | ViewportMeasured(report) => ({...model, viewport: Some(report)}, Tea.none)
  | RemeasureClicked => (model, measureCmd())
  }

let title = (_model: model): string => "Debug"
// Reached from Settings' Diagnostics row, so Back returns there.
let back = (_model: model): option<Route.t> => Some(Route.Settings)

// Shell slots (DESIGN.md §11.1): an optional Footnote under the title and an
// optional trailing bar action. Default none; pages override.
let subtitle = (_model: model): option<string> => None
let actions = (_model: model, ~dispatch as _dispatch: msg => unit): option<React.element> => None

// DESIGN.md §11.2: an inset grouped list of timers — part name Body,
// start/stop Footnote, hands-on mono trailing — plus a secondary capsule
// for the CSV export. `timer-row` stays on each row for parts.spec.js.
let renderRow = (row: timerRow): React.element => {
  let hands =
    Store.handsOnSeconds(row.timer)->Option.map(n => Int.toString(n) ++ "s")->Option.getOr("—")
  <div key={row.timer.partId} className="list-row" role="listitem" dataTestId="timer-row">
    <span className="list-row-body">
      <span className="list-row-title"> {React.string(row.partLabel)} </span>
      <span className="list-row-meta">
        {React.string(
          "Started " ++
          row.timer.startedAt->Option.getOr("—") ++
          " · stopped " ++
          row.timer.stoppedAt->Option.getOr("—"),
        )}
      </span>
    </span>
    <span className="list-row-trailing mono"> {React.string(hands)} </span>
  </div>
}

let px = (x: float): string => Float.toFixed(x, ~digits=1)

let vpRow = (label: string, value: string): React.element =>
  <div key=label className="list-row" role="listitem" dataTestId="viewport-row">
    <span className="list-row-body">
      <span className="list-row-title"> {React.string(label)} </span>
    </span>
    <span className="list-row-trailing mono"> {React.string(value)} </span>
  </div>

let renderViewport = (r: viewportReport): React.element =>
  React.array([
    vpRow("Mode", r.standalone ? "standalone" : "browser tab"),
    vpRow("screen", px(r.screenW) ++ " × " ++ px(r.screenH)),
    vpRow("inner", px(r.innerW) ++ " × " ++ px(r.innerH)),
    vpRow("visualViewport.height", r.visualH->Option.map(px)->Option.getOr("n/a")),
    vpRow("100vh", px(r.vh)),
    vpRow("100lvh", px(r.lvh)),
    vpRow("100svh", px(r.svh)),
    vpRow("100dvh", px(r.dvh)),
    vpRow("fixed inset 0", px(r.fixedInset)),
    vpRow("safe-area top / bottom", px(r.safeTop) ++ " / " ++ px(r.safeBottom)),
    vpRow(".app-frame height", px(r.frameH)),
    vpRow("document client / scroll", px(r.docClientH) ++ " / " ++ px(r.docScrollH)),
    vpRow("document excess scroll", px(r.docScrollH -. r.docClientH)),
  ])

let probeIds = [
  "vp-probe-vh",
  "vp-probe-lvh",
  "vp-probe-svh",
  "vp-probe-dvh",
  "vp-probe-fixed",
  "vp-probe-safe-top",
  "vp-probe-safe-bottom",
]

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg">
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <Ui.ListGroup header="Timers" asList=true>
      {if !model.loaded {
        <div className="list-row"> <p className="t-footnote muted"> {React.string("Loading timers…")} </p> </div>
      } else if Array.length(model.rows) == 0 {
        <div className="list-row">
          <p className="t-footnote muted"> {React.string("No timers recorded yet.")} </p>
        </div>
      } else {
        model.rows->Array.map(renderRow)->React.array
      }}
    </Ui.ListGroup>
    <Ui.Button variant=Ui.Button.Secondary testId="export-csv" onClick={_ => dispatch(ExportCsvClicked)}>
      {React.string("Export CSV")}
    </Ui.Button>
    <Ui.ListGroup header="Viewport" asList=true>
      {switch model.viewport {
      | None => <div className="list-row"> <p className="t-footnote muted"> {React.string("Measuring…")} </p> </div>
      | Some(r) => renderViewport(r)
      }}
    </Ui.ListGroup>
    {switch model.viewport {
    | Some(r) => <p className="t-footnote muted mono vp-ua"> {React.string(r.userAgent)} </p>
    | None => React.null
    }}
    <Ui.Button variant=Ui.Button.Secondary testId="remeasure" onClick={_ => dispatch(RemeasureClicked)}>
      {React.string("Re-measure viewport")}
    </Ui.Button>
    {probeIds
    ->Array.map(id => <div key=id className={"vp-probe " ++ id} dataTestId=id />)
    ->React.array}
  </div>
