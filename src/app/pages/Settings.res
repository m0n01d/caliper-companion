// Settings — `#/settings`, SPEC M4 last bullet. The wedge-dongle toggle
// (`settings.wedge`) and the current default tolerances, read-only.

type model = {
  loaded: bool,
  wedge: bool,
  lastToleranceMm: float,
  lastToleranceIn: float,
  error: option<string>,
}

type msg =
  | SettingsLoaded(Store.settings)
  | LoadFailed(string)
  | ToggleWedge
  | SaveFinished(result<unit, string>)

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let init = (): (model, Tea.cmd<msg>) => (
  {
    loaded: false,
    wedge: Store.defaultSettings.wedge,
    lastToleranceMm: Store.defaultSettings.lastToleranceMm,
    lastToleranceIn: Store.defaultSettings.lastToleranceIn,
    error: None,
  },
  Tea.fromPromise(() => Store.getSettings(store()), s => SettingsLoaded(s), e => LoadFailed(
    describeError(e),
  )),
)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | SettingsLoaded(s) => (
      {
        loaded: true,
        wedge: s.wedge,
        lastToleranceMm: s.lastToleranceMm,
        lastToleranceIn: s.lastToleranceIn,
        error: None,
      },
      Tea.none,
    )
  | LoadFailed(msg) => ({...model, loaded: true, error: Some(msg)}, Tea.none)
  | ToggleWedge =>
    let next = !model.wedge
    let settings: Store.settings = {
      wedge: next,
      lastToleranceMm: model.lastToleranceMm,
      lastToleranceIn: model.lastToleranceIn,
    }
    (
      {...model, wedge: next},
      Tea.fromPromise(() => Store.putSettings(store(), settings), () => SaveFinished(Ok()), e =>
        SaveFinished(Error(describeError(e)))
      ),
    )
  | SaveFinished(Ok()) => (model, Tea.none)
  // Revert the optimistic flip and surface the failure — the checkbox is
  // the only "yes it saved" signal the user gets in v0.
  | SaveFinished(Error(msg)) => ({...model, wedge: !model.wedge, error: Some(msg)}, Tea.none)
  }

let title = (_model: model): string => "Settings"
let back = (_model: model): option<Route.t> => Some(Route.Parts)

// DESIGN.md §11.2: inset grouped rows, a real Ui.Toggle (wedge-toggle stays
// the checkbox's id), and a second read-only group for the default
// tolerances (hig-brief §2 Settings: "switch style only inside a list row,
// no separate label needed — row content supplies context").
let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg">
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <Ui.ListGroup footer="A keyboard-wedge dongle types readings; saved dimensions are tagged `wedge`.">
      <div className="list-row wedge-row">
        <span className="list-row-body">
          <span className="t-body"> {React.string("Readings come from a wedge dongle")} </span>
        </span>
        <Ui.Toggle
          checked={model.wedge}
          disabled={!model.loaded}
          id="wedge-toggle-input"
          testId="wedge-toggle"
          ariaLabel="Readings come from a wedge dongle"
          onChange={_ => dispatch(ToggleWedge)}
        />
      </div>
    </Ui.ListGroup>
    <Ui.ListGroup header="Default tolerances">
      <div className="list-row">
        <span className="list-row-body">
          <span className="list-row-title"> {React.string("Millimetres")} </span>
        </span>
        <span className="list-row-trailing mono">
          {React.string("± " ++ NumberParse.format(model.lastToleranceMm, Types.Mm))}
        </span>
      </div>
      <div className="list-row">
        <span className="list-row-body">
          <span className="list-row-title"> {React.string("Inches")} </span>
        </span>
        <span className="list-row-trailing mono">
          {React.string("± " ++ NumberParse.format(model.lastToleranceIn, Types.Inch))}
        </span>
      </div>
    </Ui.ListGroup>
  </div>
