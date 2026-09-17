// Capture — stub (SPEC M6). `init` takes the route's `partId`. A later agent
// fills in the camera-file-input flow (SPEC M3).

type model = {partId: string}
type msg = NoOp

let init = (~partId: string): (model, Tea.cmd<msg>) => ({partId: partId}, Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | NoOp => (model, Tea.none)
  }

let title = (_model: model): string => "Capture"
let back = (model: model): option<Route.t> => Some(Route.Part(model.partId))

let view = (model: model, ~dispatch as _dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("Capture")} </p>
    <p className="route-params"> {React.string("partId: " ++ model.partId)} </p>
  </div>
