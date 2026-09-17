// Debug — stub (SPEC M6). A later agent fills in the timer CSV export (SPEC
// M6 second/third checkboxes).

type model = unit
type msg = NoOp

let init = (): (model, Tea.cmd<msg>) => ((), Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | NoOp => (model, Tea.none)
  }

let title = (_model: model): string => "Debug"
let back = (_model: model): option<Route.t> => Some(Route.Parts)

let view = (_model: model, ~dispatch as _dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("Debug")} </p>
    <h2> {React.string("Timers")} </h2>
  </div>
