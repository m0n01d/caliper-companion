// Annotate — stub (SPEC M6). `init` takes the route's `partId` and `faceId`.
// A later agent fills in the tap-to-dimension canvas (SPEC M4, the core
// screen).

type model = {partId: string, faceId: string}
type msg = NoOp

let init = (~partId: string, ~faceId: string): (model, Tea.cmd<msg>) =>
  ({partId: partId, faceId: faceId}, Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | NoOp => (model, Tea.none)
  }

let title = (_model: model): string => "Annotate"
let back = (model: model): option<Route.t> => Some(Route.Part(model.partId))

let view = (model: model, ~dispatch as _dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("Annotate")} </p>
    <p className="route-params">
      {React.string("partId: " ++ model.partId ++ ", faceId: " ++ model.faceId)}
    </p>
  </div>
