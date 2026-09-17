// Debug — `#/debug`, SPEC M6 bullet 3. Lists the last 20 dogfood timers and
// exports them as CSV.

type timerRow = {
  timer: Store.timer,
  partLabel: string, // the part's name once resolved; the id until then or if deleted
}

type model = {
  loaded: bool,
  rows: array<timerRow>,
  error: option<string>,
}

type msg =
  | TimersLoaded(array<Store.timer>)
  | LoadFailed(string)
  | PartLabelLoaded(string, string) // partId, label
  | ExportCsvClicked

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let init = (): (model, Tea.cmd<msg>) => (
  {loaded: false, rows: [], error: None},
  Tea.fromPromise(() => Store.listTimers(store(), ~limit=20), ts => TimersLoaded(ts), e => LoadFailed(
    describeError(e),
  )),
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
      {loaded: true, rows: ts->Array.map(t => {timer: t, partLabel: t.partId}), error: None},
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
  }

let title = (_model: model): string => "Debug"
let back = (_model: model): option<Route.t> => Some(Route.Parts)

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
  </div>
