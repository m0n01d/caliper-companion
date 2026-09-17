// PartsList — stub (SPEC M6). A later agent fills in the real parts list
// (SPEC M2); keep this contract (`model`/`msg`/`init`/`update`/`view`/
// `title`/`back`) so `Main.res` never needs touching.

type model = unit
type msg = NewPartClicked

let init = (): (model, Tea.cmd<msg>) => ((), Tea.none)

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  // "does nothing yet" (SPEC M6 deliverable) — M2 wires this to Store.putPart.
  | NewPartClicked => (model, Tea.none)
  }

let title = (_model: model): string => "Parts"
let back = (_model: model): option<Route.t> => None

let view = (_model: model, ~dispatch: msg => unit): React.element =>
  <div className="page">
    <p className="page-name"> {React.string("PartsList")} </p>
    <div className="empty-state">
      <p> {React.string("No parts yet. Photograph the first face to get started.")} </p>
      <button type_="button" onClick={_ => dispatch(NewPartClicked)}>
        {React.string("New part")}
      </button>
    </div>
  </div>
