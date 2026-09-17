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
  // DESIGN.md §9 "Live region" — see `Ui.Live`'s doc comment for why "" is
  // silence, not absence.
  announcement: string,
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

// DESIGN.md §9 "Focus management": focus a target by testid one microtask
// after this msg's own model update. `Tea.res`'s `dispatch` runs a msg's
// cmd synchronously, right after handing the new model to React's
// `setState` — before React has actually re-rendered/committed the DOM
// (see Tea.res's doc comment on `use`) — so looking a target up
// immediately would miss one that only exists in the model this same msg
// just produced (a newly-opened form's input, in particular). A `Promise`
// microtask reliably runs after React's synchronous-event commit without
// needing a new binding: `Canvas.res` (src/bindings, read-only from here)
// already exports `byTestId`/`focus`, the same pair Annotate.res's own
// `focusTestId` uses — Annotate's targets are already-mounted, so it
// doesn't need this deferral; a freshly-opened form's input does.
let focusTestId = (id: string): Tea.cmd<msg> =>
  Tea.effect(_dispatch =>
    Promise.resolve()
    ->Promise.then(() => {
        switch Canvas.byTestId(id) {
        | Some(el) => el->Canvas.focus
        | None => ()
        }
        Promise.resolve()
      })
    ->ignore
  )

let init = (): (model, Tea.cmd<msg>) => (
  {
    loaded: false,
    parts: [],
    error: None,
    form: None,
    rowStates: Dict.make(),
    rowError: None,
    announcement: "",
  },
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
      focusTestId("part-name"),
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
  | PartCreated(part) => (
      // The route change below unmounts this page almost immediately, so
      // this announcement is mostly symbolic (DESIGN.md §9 asks for it
      // regardless) — an AT may not get to speak it before the live region
      // itself is torn down. Noted in LOGBOOK.md rather than skipped.
      {...model, form: None, announcement: "Part created"},
      Route.push(Route.Part(part.id)),
    )
  | CreateFailed(msg) => (
      {...model, form: model.form->Option.map(f => {...f, submitting: false, error: Some(msg)})},
      Tea.none,
    )
  | RowTapped(id) => (model, Route.push(Route.Part(id)))
  | RenameStart(id) =>
    let draft = model.parts->Array.find(p => p.id == id)->Option.map(p => p.name)->Option.getOr("")
    (
      {...model, rowStates: setRowState(model, id, Renaming(draft)), rowError: None},
      focusTestId("part-rename-input"),
    )
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
        announcement: "Part deleted",
      },
      // DESIGN.md §9 "Focus management": the deleted row is gone, so send
      // focus to the one control guaranteed to still be there afterward —
      // "New part" (present whether the list is now empty or not; see
      // `renderNewPartButton`) doubles as "the list" since it's the first
      // thing after it in DOM order.
      focusTestId("new-part"),
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

// A row's Normal content is a single Ui.ListRow: thumbnail leading, name +
// meta body wrapped in a real <a> (`~href`, chevron included), Rename/
// Delete as `~trailing` siblings outside that <a> — never a <button>
// wrapping other buttons, which is invalid HTML (design wave 3a's fix for
// the Ui.res gap wave 2 reported; see LOGBOOK.md). Renaming/ConfirmingDelete
// replace a row's content in place with their own plain container (not
// Ui.ListRow — they're a form/confirm strip, not a navigable row), still
// under the same `part-row` testid.
let renderRow = (model: model, part: Types.part, ~dispatch: msg => unit): React.element => {
  let state = rowStateOf(model, part.id)

  switch state {
  | Renaming(draft) =>
    <div key={part.id} className="list-row" role="listitem" dataTestId="part-row">
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
    </div>
  | ConfirmingDelete =>
    <div key={part.id} className="list-row" role="listitem" dataTestId="part-row">
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
    </div>
  | Normal =>
    <Ui.ListRow
      key={part.id}
      testId="part-row"
      href={Route.href(Route.Part(part.id))}
      chevron=true
      leading={<Ui.ListThumb src=None />}
      trailing={
        <>
          <Ui.Button
            variant=Ui.Button.Icon
            testId="part-rename"
            ariaLabel="Rename"
            onClick={_ => dispatch(RenameStart(part.id))}>
            <Icon name=Pencil size=20 />
          </Ui.Button>
          <Ui.Button
            variant=Ui.Button.Icon
            testId="part-delete"
            ariaLabel={"Delete " ++ part.name}
            onClick={_ => dispatch(DeleteStart(part.id))}>
            <Icon name=Trash size=20 />
          </Ui.Button>
        </>
      }>
      <Ui.ListRow.Title> {React.string(part.name)} </Ui.ListRow.Title>
      <Ui.ListRow.Meta>
        {React.string(Enums.unitsToString(part.units) ++ " · updated " ++ relativeDate(part.updatedAt))}
      </Ui.ListRow.Meta>
    </Ui.ListRow>
  }
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
    <Ui.Live text=model.announcement testId="parts-live" />
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
          <Ui.ListGroup asList=true>
            {model.parts->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
          </Ui.ListGroup>
        }}
        {renderNewPartButton(model, ~dispatch)}
      </div>
    }}
  </div>
