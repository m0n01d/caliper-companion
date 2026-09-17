// Part — stub (SPEC M6). `init` takes the route's `partId`, which the model
// carries so `view` (which only sees `model` and `dispatch`) can render it.
// A later agent fills in the faces row / features table (SPEC M2).

type model = {partId: string}
type msg = NoOp

let init = (~partId: string): (model, Tea.cmd<msg>) => ({partId: partId}, Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | NoOp => (model, Tea.none)
  }

let title = (_model: model): string => "Part"
let back = (_model: model): option<Route.t> => Some(Route.Parts)

let view = (model: model, ~dispatch as _dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("Part")} </p>
    <p className="route-params"> {React.string("partId: " ++ model.partId)} </p>
  </div>
