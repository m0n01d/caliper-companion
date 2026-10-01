// Settings — `#/settings`, SPEC M4 last bullet. The wedge-dongle toggle
// (`settings.wedge`), the edge-snap toggle (`settings.snap`, SPEC §8a A5 —
// the same field the annotate toolbar's Snap pill flips) and the current
// default tolerances, read-only.

type model = {
  loaded: bool,
  wedge: bool,
  snap: bool,
  lastToleranceMm: float,
  lastToleranceIn: float,
  error: option<string>,
}

// Which toggle an in-flight write belongs to, so a failure reverts the
// right one (both rows write the whole settings record).
type flipped = Wedge | Snap

type msg =
  | SettingsLoaded(Store.settings)
  | LoadFailed(string)
  | ToggleWedge
  | ToggleSnap
  | SaveFinished(flipped, result<unit, string>)

let store = () => Store.shared()

// See PartsList.res's `describeError` — same reasoning, duplicated rather
// than shared because there's no page-shared module in the file-ownership
// list for this track to add one to.
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let init = (): (model, Tea.cmd<msg>) => (
  {
    loaded: false,
    wedge: Store.defaultSettings.wedge,
    snap: Store.defaultSettings.snap,
    lastToleranceMm: Store.defaultSettings.lastToleranceMm,
    lastToleranceIn: Store.defaultSettings.lastToleranceIn,
    error: None,
  },
  Tea.fromPromise(() => Store.getSettings(store()), s => SettingsLoaded(s), e => LoadFailed(
    describeError(e),
  )),
)

let toSettings = (model: model): Store.settings => {
  wedge: model.wedge,
  snap: model.snap,
  lastToleranceMm: model.lastToleranceMm,
  lastToleranceIn: model.lastToleranceIn,
}

let saveCmd = (model: model, flipped: flipped): Tea.cmd<msg> =>
  Tea.fromPromise(
    () => Store.putSettings(store(), toSettings(model)),
    () => SaveFinished(flipped, Ok()),
    e => SaveFinished(flipped, Error(describeError(e))),
  )

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | SettingsLoaded(s) => (
      {
        loaded: true,
        wedge: s.wedge,
        snap: s.snap,
        lastToleranceMm: s.lastToleranceMm,
        lastToleranceIn: s.lastToleranceIn,
        error: None,
      },
      Tea.none,
    )
  | LoadFailed(msg) => ({...model, loaded: true, error: Some(msg)}, Tea.none)
  | ToggleWedge =>
    let next = {...model, wedge: !model.wedge}
    (next, saveCmd(next, Wedge))
  | ToggleSnap =>
    let next = {...model, snap: !model.snap}
    (next, saveCmd(next, Snap))
  | SaveFinished(_, Ok()) => (model, Tea.none)
  // Revert the optimistic flip and surface the failure — the checkbox is
  // the only "yes it saved" signal the user gets in v0.
  | SaveFinished(Wedge, Error(msg)) => ({...model, wedge: !model.wedge, error: Some(msg)}, Tea.none)
  | SaveFinished(Snap, Error(msg)) => ({...model, snap: !model.snap, error: Some(msg)}, Tea.none)
  }

let title = (_model: model): string => "Settings"
let back = (_model: model): option<Route.t> => Some(Route.Parts(""))

// Shell slots (DESIGN.md §11.1): an optional Footnote under the title and an
// optional trailing bar action. Default none; pages override.
let subtitle = (_model: model): option<string> => None
let actions = (_model: model, ~dispatch as _dispatch: msg => unit): option<React.element> => None

// DESIGN.md §11.2: inset grouped rows, real Ui.Toggles (wedge-toggle stays
// the checkbox's id; snap-setting-toggle is A5's), and a read-only group
// for the default tolerances (hig-brief §2 Settings: "switch style only inside a list row,
// no separate label needed — row content supplies context").
let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg">
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <Ui.ListGroup footer="A Bluetooth caliper or a dongle paired as a keyboard types each reading. Saved dimensions are tagged `wedge`.">
      <div className="list-row wedge-row">
        <span className="list-row-body">
          <span className="t-body"> {React.string("Readings come from a connected caliper")} </span>
        </span>
        <Ui.Toggle
          checked={model.wedge}
          disabled={!model.loaded}
          id="wedge-toggle-input"
          testId="wedge-toggle"
          ariaLabel="Readings come from a connected caliper"
          onChange={_ => dispatch(ToggleWedge)}
        />
      </div>
    </Ui.ListGroup>
    <Ui.ListGroup
      footer="Taps on the annotate canvas move to the nearest visible edge. The Snap pill on that screen flips the same setting.">
      <div className="list-row">
        <span className="list-row-body">
          <span className="t-body"> {React.string("Snap taps to edges")} </span>
        </span>
        <Ui.Toggle
          checked={model.snap}
          disabled={!model.loaded}
          id="snap-setting-toggle-input"
          testId="snap-setting-toggle"
          ariaLabel="Snap taps to edges"
          onChange={_ => dispatch(ToggleSnap)}
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
    <Ui.ListGroup
      header="Diagnostics" footer="Dogfood timers, CSV export and the on-device viewport readout.">
      <Ui.ListRow
        href={Route.href(Route.Debug)}
        chevron=true
        testId="debug-link"
        leading={<span className="list-row-leading"> <Icon name=Bug size=20 /> </span>}>
        <Ui.ListRow.Title> {React.string("Debug")} </Ui.ListRow.Title>
      </Ui.ListRow>
    </Ui.ListGroup>
  </div>
