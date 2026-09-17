// PartsList — the parts list (`#/`), SPEC M2 bullet 2. Create, rename,
// delete (with confirm), empty state naming the first action, loading/error
// states as visible text (never a blank screen).

type createForm = {
  name: string,
  units: Types.units,
  error: option<string>,
  submitting: bool,
}

type rowState =
  | Normal
  | Renaming(string) // draft name
  | ConfirmingDelete

type model = {
  loaded: bool,
  parts: array<Types.part>,
  error: option<string>,
  form: option<createForm>,
  rowStates: Dict.t<rowState>, // partId -> rowState; absent == Normal
  rowError: option<string>, // surfaces a rename/delete failure inline
}

type msg =
  | PartsLoaded(array<Types.part>)
  | LoadFailed(string)
  | NewPartClicked
  | FormNameChanged(string)
  | FormUnitsChanged(Types.units)
  | FormCancel
  | CreateSubmit
  | PartCreated(Types.part)
  | CreateFailed(string)
  | RowTapped(string)
  | RenameStart(string)
  | RenameDraftChanged(string, string)
  | RenameCancel(string)
  | RenameSubmit(string)
  | RenameSaved(Types.part)
  | RenameFailed(string)
  | DeleteStart(string)
  | DeleteCancel(string)
  | DeleteConfirm(string)
  | DeleteDone(string)
  | DeleteFailed(string)

let store = () => Store.shared()

// Errors here are PouchDB/JS exceptions the user can't act on beyond
// retrying — a generic, visible message beats trying to unwrap `JsExn`
// payloads that may not even be an `Error` instance (see PouchDb.res).
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

let init = (): (model, Tea.cmd<msg>) => (
  {loaded: false, parts: [], error: None, form: None, rowStates: Dict.make(), rowError: None},
  Tea.fromPromise(() => Store.listParts(store()), parts => PartsLoaded(parts), e => LoadFailed(
    describeError(e),
  )),
)

let rowStateOf = (model: model, id: string): rowState =>
  switch Dict.get(model.rowStates, id) {
  | Some(s) => s
  | None => Normal
  }

let setRowState = (model: model, id: string, s: rowState): Dict.t<rowState> => {
  let next = Dict.copy(model.rowStates)
  switch s {
  | Normal => Dict.delete(next, id)
  | _ => Dict.set(next, id, s)
  }
  next
}

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | PartsLoaded(parts) => ({...model, loaded: true, parts, error: None}, Tea.none)
  | LoadFailed(msg) => ({...model, loaded: true, error: Some(msg)}, Tea.none)
  | NewPartClicked => (
      {...model, form: Some({name: "", units: Types.Mm, error: None, submitting: false})},
      Tea.none,
    )
  | FormNameChanged(name) => (
      {...model, form: model.form->Option.map(f => {...f, name, error: None})},
      Tea.none,
    )
  | FormUnitsChanged(units) => ({...model, form: model.form->Option.map(f => {...f, units})}, Tea.none)
  | FormCancel => ({...model, form: None}, Tea.none)
  | CreateSubmit =>
    switch model.form {
    | None => (model, Tea.none)
    | Some(f) =>
      let trimmed = String.trim(f.name)
      if trimmed == "" {
        ({...model, form: Some({...f, error: Some("Name can't be empty")})}, Tea.none)
      } else {
        (
          {...model, form: Some({...f, submitting: true, error: None})},
          Tea.fromPromise(
            () => Store.createPart(store(), ~name=trimmed, ~slug=Slug.make(trimmed), ~units=f.units),
            part => PartCreated(part),
            e => CreateFailed(describeError(e)),
          ),
        )
      }
    }
  | PartCreated(part) => ({...model, form: None}, Route.push(Route.Part(part.id)))
  | CreateFailed(msg) => (
      {...model, form: model.form->Option.map(f => {...f, submitting: false, error: Some(msg)})},
      Tea.none,
    )
  | RowTapped(id) => (model, Route.push(Route.Part(id)))
  | RenameStart(id) =>
    let draft = model.parts->Array.find(p => p.id == id)->Option.map(p => p.name)->Option.getOr("")
    ({...model, rowStates: setRowState(model, id, Renaming(draft)), rowError: None}, Tea.none)
  | RenameDraftChanged(id, draft) => (
      {...model, rowStates: setRowState(model, id, Renaming(draft))},
      Tea.none,
    )
  | RenameCancel(id) => ({...model, rowStates: setRowState(model, id, Normal)}, Tea.none)
  | RenameSubmit(id) =>
    switch (rowStateOf(model, id), model.parts->Array.find(p => p.id == id)) {
    | (Renaming(draft), Some(part)) =>
      let trimmed = String.trim(draft)
      if trimmed == "" {
        (model, Tea.none)
      } else {
        (
          model,
          Tea.fromPromise(
            () => Store.putPart(store(), {...part, name: trimmed}),
            p => RenameSaved(p),
            e => RenameFailed(describeError(e)),
          ),
        )
      }
    | _ => (model, Tea.none)
    }
  | RenameSaved(part) => (
      {
        ...model,
        parts: model.parts->Array.map(p => p.id == part.id ? part : p),
        rowStates: setRowState(model, part.id, Normal),
        rowError: None,
      },
      Tea.none,
    )
  | RenameFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  | DeleteStart(id) => ({...model, rowStates: setRowState(model, id, ConfirmingDelete)}, Tea.none)
  | DeleteCancel(id) => ({...model, rowStates: setRowState(model, id, Normal)}, Tea.none)
  | DeleteConfirm(id) => (
      model,
      Tea.fromPromise(() => Store.deletePart(store(), id), () => DeleteDone(id), e => DeleteFailed(
        describeError(e),
      )),
    )
  | DeleteDone(id) => (
      {
        ...model,
        parts: model.parts->Array.filter(p => p.id != id),
        rowStates: setRowState(model, id, Normal),
        rowError: None,
      },
      Tea.none,
    )
  | DeleteFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  }

let title = (_model: model): string => "Parts"
let back = (_model: model): option<Route.t> => None

// "today" for same-calendar-day, else the platform's short date string —
// good enough for a glance; SPEC only asks for "relative-ish".
let relativeDate = (iso: string): string => {
  let then_ = Date.fromString(iso)
  let now = Date.make()
  let sameDay =
    Date.getFullYear(then_) == Date.getFullYear(now) &&
    Date.getMonth(then_) == Date.getMonth(now) &&
    Date.getDate(then_) == Date.getDate(now)
  sameDay ? "today" : Date.toDateString(then_)
}

let unitsOptions: array<(Types.units, string)> = [(Types.Mm, "mm"), (Types.Inch, "in")]

let renderForm = (form: createForm, ~dispatch: msg => unit): React.element =>
  <div className="create-form">
    <label className="field-label" htmlFor="part-name-input"> {React.string("Name")} </label>
    <input
      id="part-name-input"
      type_="text"
      dataTestId="part-name"
      value={form.name}
      onChange={evt => dispatch(FormNameChanged(ReactEvent.Form.target(evt)["value"]))}
    />
    <label className="field-label" htmlFor="part-units-input"> {React.string("Units")} </label>
    <select
      id="part-units-input"
      dataTestId="part-units"
      value={Enums.unitsToString(form.units)}
      onChange={evt => {
        let raw = ReactEvent.Form.target(evt)["value"]
        dispatch(FormUnitsChanged(Enums.unitsFromString(raw)->Option.getOr(Types.Mm)))
      }}>
      {unitsOptions
      ->Array.map(((u, label)) =>
        <option key={label} value={Enums.unitsToString(u)}> {React.string(label)} </option>
      )
      ->React.array}
    </select>
    {switch form.error {
    | Some(msg) => <p className="field-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <div className="create-form-actions">
      <button
        type_="button"
        dataTestId="part-create"
        disabled={form.submitting}
        onClick={_ => dispatch(CreateSubmit)}>
        {React.string(form.submitting ? "Creating…" : "Create")}
      </button>
      <button type_="button" onClick={_ => dispatch(FormCancel)}> {React.string("Cancel")} </button>
    </div>
  </div>

let renderRow = (model: model, part: Types.part, ~dispatch: msg => unit): React.element => {
  let state = rowStateOf(model, part.id)
  let onRowClick = _evt =>
    switch state {
    | Normal => dispatch(RowTapped(part.id))
    | _ => ()
    }
  let stop = evt => ReactEvent.Mouse.stopPropagation(evt)

  <li key={part.id} className="part-row" dataTestId="part-row" onClick={onRowClick}>
    {switch state {
    | Renaming(draft) =>
      <div className="row-edit" onClick={stop}>
        <input
          type_="text"
          dataTestId="part-rename-input"
          value={draft}
          onChange={evt =>
            dispatch(RenameDraftChanged(part.id, ReactEvent.Form.target(evt)["value"]))}
        />
        <button
          type_="button" dataTestId="part-rename-save" onClick={_ => dispatch(RenameSubmit(part.id))}>
          {React.string("Save")}
        </button>
        <button
          type_="button"
          dataTestId="part-rename-cancel"
          onClick={_ => dispatch(RenameCancel(part.id))}>
          {React.string("Cancel")}
        </button>
      </div>
    | ConfirmingDelete =>
      <div className="row-edit" onClick={stop}>
        <p>
          {React.string("Delete \"" ++ part.name ++ "\"? This removes its faces and dimensions.")}
        </p>
        <button
          type_="button"
          dataTestId="part-delete-confirm"
          onClick={_ => dispatch(DeleteConfirm(part.id))}>
          {React.string("Delete")}
        </button>
        <button
          type_="button"
          dataTestId="part-delete-cancel"
          onClick={_ => dispatch(DeleteCancel(part.id))}>
          {React.string("Cancel")}
        </button>
      </div>
    | Normal =>
      <>
        <div className="part-row-main">
          <span className="part-row-name"> {React.string(part.name)} </span>
          <span className="units-badge"> {React.string(Enums.unitsToString(part.units))} </span>
          <span className="part-row-updated"> {React.string(relativeDate(part.updatedAt))} </span>
        </div>
        <div className="part-row-actions">
          <button
            type_="button"
            dataTestId="part-rename"
            onClick={evt => {
              stop(evt)
              dispatch(RenameStart(part.id))
            }}>
            {React.string("Rename")}
          </button>
          <button
            type_="button"
            dataTestId="part-delete"
            onClick={evt => {
              stop(evt)
              dispatch(DeleteStart(part.id))
            }}>
            {React.string("Delete")}
          </button>
        </div>
      </>
    }}
  </li>
}

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="page parts-list-page">
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch model.rowError {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch model.form {
    | Some(f) => renderForm(f, ~dispatch)
    | None =>
      <button type_="button" dataTestId="new-part" onClick={_ => dispatch(NewPartClicked)}>
        {React.string("New part")}
      </button>
    }}
    {if !model.loaded {
      <p> {React.string("Loading parts…")} </p>
    } else if Array.length(model.parts) == 0 {
      <div className="empty-state" dataTestId="parts-empty">
        <p> {React.string("No parts yet. Tap New part, then photograph its first face.")} </p>
      </div>
    } else {
      <ul className="list part-list">
        {model.parts->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
      </ul>
    }}
  </div>
