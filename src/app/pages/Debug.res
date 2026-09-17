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

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="page debug-page">
    <h2> {React.string("Timers")} </h2>
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {if !model.loaded {
      <p> {React.string("Loading timers…")} </p>
    } else if Array.length(model.rows) == 0 {
      <p className="muted"> {React.string("No timers recorded yet.")} </p>
    } else {
      <table className="timers-table">
        <thead>
          <tr>
            <th> {React.string("Part")} </th>
            <th> {React.string("Started")} </th>
            <th> {React.string("Stopped")} </th>
            <th> {React.string("Hands-on (s)")} </th>
          </tr>
        </thead>
        <tbody>
          {model.rows
          ->Array.map(row =>
            <tr key={row.timer.partId} className="timer-row" dataTestId="timer-row">
              <td> {React.string(row.partLabel)} </td>
              <td> {React.string(row.timer.startedAt->Option.getOr("—"))} </td>
              <td> {React.string(row.timer.stoppedAt->Option.getOr("—"))} </td>
              <td>
                {React.string(
                  Store.handsOnSeconds(row.timer)->Option.map(n => Int.toString(n))->Option.getOr("—"),
                )}
              </td>
            </tr>
          )
          ->React.array}
        </tbody>
      </table>
    }}
    <button type_="button" dataTestId="export-csv" onClick={_ => dispatch(ExportCsvClicked)}>
      {React.string("Export CSV")}
    </button>
  </div>
