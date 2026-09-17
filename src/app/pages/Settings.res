// Settings — stub (SPEC M6). A later agent wires the wedge-dongle toggle to
// the part's `readingSource` default (SPEC M4).

type model = unit
type msg = ToggleWedgeSource

let init = (): (model, Tea.cmd<msg>) => ((), Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  // Disabled in the view below; wired up once a part/Store exists (SPEC M4).
  | ToggleWedgeSource => (model, Tea.none)
  }

let title = (_model: model): string => "Settings"
let back = (_model: model): option<Route.t> => Some(Route.Parts)

let view = (_model: model, ~dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("Settings")} </p>
    <label className="toggle-row">
      <span> {React.string("Readings come from a wedge dongle")} </span>
      <input
        type_="checkbox" checked=false disabled=true onChange={_ => dispatch(ToggleWedgeSource)}
      />
    </label>
  </div>
