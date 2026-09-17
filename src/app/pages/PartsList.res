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
let unitsSegOptions: array<(string, string)> =
  unitsOptions->Array.map(((u, label)) => (Enums.unitsToString(u), label))

// DESIGN.md §11.2: inset grouped Field + Segmented, a visually-hidden real
// <select> kept in sync so parts.spec.js's `selectOption('mm')` still works
// (Ui.Segmented has no <select> semantics of its own — see the report).
let renderForm = (form: createForm, ~dispatch: msg => unit): React.element =>
  <div className="stack">
    <Ui.ListGroup>
      <div className="list-row parts-form-row">
        <Ui.Field label="Name" htmlFor="part-name-input" error=?form.error>
          <input
            id="part-name-input"
            type_="text"
            dataTestId="part-name"
            autoCapitalize="words"
            maxLength=60
            value={form.name}
            onChange={evt => dispatch(FormNameChanged(ReactEvent.Form.target(evt)["value"]))}
          />
        </Ui.Field>
      </div>
      <div className="list-row parts-form-row">
        <div className="field">
          <span className="field-label"> {React.string("Units")} </span>
          <Ui.Segmented
            options=unitsSegOptions
            selected={Enums.unitsToString(form.units)}
            onSelect={raw =>
              dispatch(FormUnitsChanged(Enums.unitsFromString(raw)->Option.getOr(Types.Mm)))}
            ariaLabel="Units"
          />
          <select
            className="visually-hidden"
            id="part-units-input"
            dataTestId="part-units"
            ariaLabel="Units"
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
        </div>
      </div>
    </Ui.ListGroup>
    <div className="btn-row">
      <Ui.Button
        variant=Ui.Button.Primary
        testId="part-create"
        disabled={form.submitting}
        onClick={_ => dispatch(CreateSubmit)}>
        {React.string(form.submitting ? "Creating…" : "Create")}
      </Ui.Button>
      <Ui.Button variant=Ui.Button.Secondary onClick={_ => dispatch(FormCancel)}>
        {React.string("Cancel")}
      </Ui.Button>
    </div>
  </div>

// A row's normal content is a real <a> (navigates to the part) plus two
// sibling <button>s (Rename, Delete) — never a <button> wrapping other
// buttons, which is invalid HTML and why this hand-rolls the shared
// list-row/-body/-trailing/-chevron classes instead of Ui.ListRow (see the
// report's Ui.res gap). Renaming/ConfirmingDelete replace this in place.
let renderRow = (model: model, part: Types.part, ~dispatch: msg => unit): React.element => {
  let state = rowStateOf(model, part.id)

  <div key={part.id} className="list-row part-row" dataTestId="part-row">
    {switch state {
    | Renaming(draft) =>
      <div className="part-row-edit">
        <input
          type_="text"
          className="field-input"
          dataTestId="part-rename-input"
          autoCapitalize="words"
          maxLength=60
          value={draft}
          onChange={evt =>
            dispatch(RenameDraftChanged(part.id, ReactEvent.Form.target(evt)["value"]))}
        />
        <div className="btn-row">
          <Ui.Button
            variant=Ui.Button.Primary
            testId="part-rename-save"
            onClick={_ => dispatch(RenameSubmit(part.id))}>
            {React.string("Save")}
          </Ui.Button>
          <Ui.Button
            variant=Ui.Button.Secondary
            testId="part-rename-cancel"
            onClick={_ => dispatch(RenameCancel(part.id))}>
            {React.string("Cancel")}
          </Ui.Button>
        </div>
      </div>
    | ConfirmingDelete =>
      <div className="part-row-edit">
        <p className="t-footnote">
          {React.string("Delete \"" ++ part.name ++ "\"? This removes its faces and dimensions.")}
        </p>
        <div className="btn-row">
          <Ui.Button
            variant=Ui.Button.Danger
            testId="part-delete-confirm"
            onClick={_ => dispatch(DeleteConfirm(part.id))}>
            {React.string("Delete")}
          </Ui.Button>
          <Ui.Button
            variant=Ui.Button.Secondary
            testId="part-delete-cancel"
            onClick={_ => dispatch(DeleteCancel(part.id))}>
            {React.string("Cancel")}
          </Ui.Button>
        </div>
      </div>
    | Normal =>
      <>
        <div className="part-row-top">
          <Ui.ListThumb src=None />
          <a className="list-row-body list-row-link" href={Route.href(Route.Part(part.id))}>
            <span className="list-row-title"> {React.string(part.name)} </span>
          </a>
          <span className="list-row-chevron"> <Icon name=ChevronRight size=20 /> </span>
        </div>
        <div className="part-row-bottom">
          <span className="list-row-meta">
            {React.string(
              Enums.unitsToString(part.units) ++ " · updated " ++ relativeDate(part.updatedAt),
            )}
          </span>
          <span className="part-row-actions">
            <button
              type_="button"
              className="btn btn-small"
              dataTestId="part-rename"
              onClick={_ => dispatch(RenameStart(part.id))}>
              {React.string("Rename")}
            </button>
            <button
              type_="button"
              className="btn btn-icon"
              ariaLabel={"Delete " ++ part.name}
              dataTestId="part-delete"
              onClick={_ => dispatch(DeleteStart(part.id))}>
              <Icon name=Trash size=20 />
            </button>
          </span>
        </div>
      </>
    }}
  </div>
}

// DESIGN.md §7: "one line of copy … and the primary button; no
// illustration" — the button sits below the line/list either way, styled
// Primary+block when it's the only affordance on the screen or Secondary
// once a list exists to sit under (§11.2).
let renderNewPartButton = (model: model, ~dispatch: msg => unit): React.element =>
  if !model.loaded {
    React.null
  } else {
    let isEmpty = Array.length(model.parts) == 0
    <Ui.Button
      variant={isEmpty ? Ui.Button.Primary : Ui.Button.Secondary}
      block=isEmpty
      testId="new-part"
      onClick={_ => dispatch(NewPartClicked)}>
      {React.string("New part")}
    </Ui.Button>
  }

let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg">
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
      <div className="stack">
        {if !model.loaded {
          <p className="t-footnote muted"> {React.string("Loading parts…")} </p>
        } else if Array.length(model.parts) == 0 {
          <div className="parts-empty" dataTestId="parts-empty">
            <p className="t-footnote muted">
              {React.string("No parts yet. A part is a set of photographed faces.")}
            </p>
          </div>
        } else {
          <Ui.ListGroup>
            {model.parts->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
          </Ui.ListGroup>
        }}
        {renderNewPartButton(model, ~dispatch)}
      </div>
    }}
  </div>
