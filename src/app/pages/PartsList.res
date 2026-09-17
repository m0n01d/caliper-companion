// PartsList — the parts list (`#/`), SPEC M2 bullet 2. Create, rename,
// delete (with confirm), empty state naming the first action, loading/error
// states as visible text (never a blank screen).
//
// P2a (docs/design/review-2026-09-17.md §3/§4 layout A, P1-P5): rename/
// delete moved behind the bar's trailing Edit/Done text action (`editing`
// below), the "+" moved into the bar as an icon button once the list is
// non-empty, and each row's leading thumbnail now shows the part's first
// captured face.
//
// A10 (SPEC §8a, docs/design/a10-folders-review.md): every part carries a
// folder path. The list is one inset grouped section per distinct folder
// (root first and always headerless, so a list with no folders renders
// exactly as it did before A10), a live search field filters by name or
// path, and one `PartForm` (Name + Folder + chips of existing folders)
// serves both create and the inline rename — editing the folder is how a
// part moves. Grouping and filtering are derived in `view` from
// `model.parts`; Store never sees a raw path.
//
// A12a (SPEC §8a, docs/design/a12-folders-review.md): folders are explicit
// `folder:` docs now (`Store.ensureFolders`), and the form's free-text
// Folder field became a **Folder row** that opens a picker — a sub-view
// that takes over the page (list, search and bar actions hidden) with a
// flat tree of every folder, a Check on the selected one, and a New Folder
// field under it. The picker remembers where it came from (the create form
// or one row's rename strip) and Done/Cancel return there. A one-shot
// migration after `PartsLoaded` prefix-snaps A10 part paths against each
// other and makes sure every one of them has a doc.

// What both forms edit (review S4). `path` is the folder the picker chose:
// already normalised, validated and snapped, never raw text (A12a).
type formDraft = {
  name: string,
  path: string,
}

type createForm = {
  draft: formDraft,
  units: Types.units,
  error: option<string>,
  submitting: bool,
}

type rowState =
  | Normal
  | Renaming(formDraft)
  | ConfirmingDelete

// A12a: where the picker returns to on Done / Cancel — the create form's
// draft or one row's rename draft. A12b adds a `ForMove`.
type pickerTarget =
  | ForCreate
  | ForRename(string)

type picker = {
  target: pickerTarget,
  selected: string,
  // `Some(draft)` while the New Folder field is open under the list.
  newFolder: option<string>,
}

type model = {
  loaded: bool,
  parts: array<Types.part>,
  error: option<string>,
  form: option<createForm>,
  rowStates: Dict.t<rowState>, // partId -> rowState; absent == Normal
  rowError: option<string>, // surfaces a rename/delete failure inline
  // P1: rename/delete only show once the bar's "Edit" is tapped ("Done"
  // toggles back). Toggling off also resets `rowStates` (closes any inline
  // rename/delete editor) — the same "no leftover state" rule
  // `FacesEditToggled` already follows on the Part page.
  editing: bool,
  // partId -> object URL for the part's first captured face (P2, DESIGN.md
  // §4 "List row (Part)": 72 px thumbnail). Loaded once per part right
  // after `PartsLoaded` (one Store round trip per part, never re-fetched on
  // re-render); absent while loading or if the part has no captured face —
  // `Ui.ListThumb`'s own placeholder covers both.
  partImages: Dict.t<string>,
  // DESIGN.md §9 "Live region" — see `Ui.Live`'s doc comment for why "" is
  // silence, not absence.
  announcement: string,
  // A10: the search field's text. Page-local, so it resets on navigation
  // (`Main.pageForRoute` re-inits this page per route change — review N4,
  // accepted for v0.1; `Route.Parts` may gain a `q` later if it bites).
  query: string,
  // A12a: every explicit folder path (`folder:` docs), from `FoldersLoaded`
  // after the one-shot migration and grown by what the picker creates.
  folders: array<string>,
  // A12a: `Some` while the folder picker has taken over the page.
  picker: option<picker>,
}

type msg =
  | PartsLoaded(array<Types.part>)
  | LoadFailed(string)
  // A12a: the migration's result — every explicit folder path, plus the
  // (rare) parts whose spelling it re-snapped and re-saved.
  | FoldersLoaded(array<string>, array<Types.part>)
  | FoldersFailed(string)
  | PartImageLoaded(string, option<string>)
  | EditToggled
  | QueryChanged(string)
  | QueryCleared
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
  // A12a: the folder picker.
  | PickerOpen(pickerTarget)
  | PickerSelect(string)
  | PickerDone
  | PickerCancel
  | NewFolderOpen
  | NewFolderChanged(string)
  | NewFolderCancel
  | NewFolderCreate
  | NewFolderCreated(string, array<string>)
  | NewFolderFailed(string)

let store = () => Store.shared()

// Errors here are PouchDB/JS exceptions the user can't act on beyond
// retrying — a generic, visible message beats trying to unwrap `JsExn`
// payloads that may not even be an `Error` instance (see PouchDb.res).
let describeError = (_exn: exn): string => "Something went wrong talking to storage. Try again."

// DESIGN.md §9 "Focus management": focus a target by testid soon after this
// msg's own model update. `Tea.res`'s `dispatch` runs a msg's cmd
// synchronously, right after handing the new model to React's `setState` —
// before React has actually re-rendered/committed the DOM (see Tea.res's
// doc comment on `use`) — so looking a target up immediately would miss one
// that only exists in the model this same msg just produced (a
// newly-opened form's input, in particular).
//
// A single microtask is enough when the dispatch that opened the target
// came from a real click and the target's own DOM node is stable once
// mounted (true for every other call site here). P2a's `DeleteDone` is the
// exception on both counts: it fires from `Store.deletePart`'s own promise
// resolving, not a click, so React's commit isn't guaranteed to land before
// one queued microtask — and deleting the *last* part swaps the bar's "+"
// icon for the empty state's `new-part` capsule (a different DOM node, not
// the single always-mounted button this pattern was written against; see
// `renderEmptyCapsule`'s doc comment). Verified against a throwaway
// MutationObserver+focus-event script before writing this: the naive
// "stop at the first match" version focuses the *old* bar icon (still
// mounted when the earliest microtask runs), which is then removed from
// the DOM a frame later as React catches up — losing focus to `<body>`
// with nothing to notice and refocus the capsule that replaced it. So this
// keeps refocusing on every attempt (never stops early on a match) across a
// few animation frames (`Canvas.requestAnimationFrame`, already exported
// read-only from Canvas.res): once the DOM has actually settled, the last
// attempt lands on whatever node is really there by then.
// Takes a CSS selector rather than a testid (A12a): the picker's options
// share one testid and are told apart by `data-path`. `since` is whatever
// had focus when the cmd started (the tapped button, usually).
let rec focusWhenReady = (selector: string, ~since: option<Dom.element>, attemptsLeft: int): unit => {
  let target = Canvas.querySelector(selector)
  // Stop the moment another field has focus: the user tapped it before these
  // frames ran out. Seen as a Playwright `fill` on Folder landing in Name
  // (the loop yanked focus back mid-fill) — a quick thumb on a phone does
  // exactly the same thing. Likewise the moment focus has moved to any
  // third control (A12a): tapping the New Folder field's Create within a
  // few frames of opening it otherwise let this loop refocus the field
  // right before it unmounted, and the *next* focus cmd then saw a field
  // with focus and gave up — the created option never got focus.
  if !Canvas.userIsTypingElsewhere(target) && !Canvas.focusMovedElsewhere(~since, ~target) {
    switch target {
    | Some(el) => el->Canvas.focus
    | None => ()
    }
    if attemptsLeft > 0 {
      Canvas.requestAnimationFrame(_ => focusWhenReady(selector, ~since, attemptsLeft - 1))->ignore
    }
  }
}

let focusSelector = (selector: string): Tea.cmd<msg> =>
  Tea.effect(_dispatch => {
    let since = Canvas.activeElement(Canvas.document)
    Promise.resolve()
    ->Promise.then(() => {
        focusWhenReady(selector, ~since, 6)
        Promise.resolve()
      })
    ->ignore
  })

let focusTestId = (id: string): Tea.cmd<msg> => focusSelector(`[data-testid="${id}"]`)

// A folder path never holds `"` or `\` (`Folder.segmentRe`), so it can sit
// in a double-quoted attribute selector as is.
let focusFolderOption = (path: string): Tea.cmd<msg> =>
  focusSelector(`[data-testid="folder-option"][data-path="${path}"]`)

let init = (): (model, Tea.cmd<msg>) => (
  {
    loaded: false,
    parts: [],
    error: None,
    form: None,
    rowStates: Dict.make(),
    rowError: None,
    editing: false,
    partImages: Dict.make(),
    announcement: "",
    query: "",
    folders: [],
    picker: None,
  },
  Tea.fromPromise(() => Store.listParts(store()), parts => PartsLoaded(parts), e => LoadFailed(
    describeError(e),
  )),
)

// DESIGN.md §4 "List row (Part)": the row's leading thumbnail is the part's
// *first* captured face, `cover`. One promise chain per part (facesOf, then
// getFaceImage on its first result) so this is exactly one Store round trip
// per part — same shape as Part.res's own `loadFaceImageCmd`, just chained
// through `facesOf` first since a part (unlike a face) doesn't carry its
// image directly. `None` either way (no faces yet, or the image fetch
// failed) leaves the thumbnail on `Ui.ListThumb`'s placeholder.
let loadFirstFaceImageCmd = (partId: string): Tea.cmd<msg> =>
  Tea.fromPromise(
    () =>
      Store.facesOf(store(), ~partId)->Promise.then(faces =>
        switch Array.get(faces, 0) {
        | Some(face) =>
          Store.getFaceImage(store(), face.id)->Promise.then(blobOpt =>
            Promise.resolve(blobOpt->Option.map(Download.objectUrlOfImage))
          )
        | None => Promise.resolve(None)
        }
      ),
    urlOpt => PartImageLoaded(partId, urlOpt),
    _e => PartImageLoaded(partId, None),
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

// ---- A10: folders, derived from `model.parts` ---------------------------

let byUpdatedAtDesc = (a: Types.part, b: Types.part): Ordering.t =>
  String.compare(b.updatedAt, a.updatedAt)

// Distinct non-root folders in `parts` order. `parts` is updatedAt desc
// (`Store.listParts`; `RenameSaved` re-sorts, review S6), so first-seen
// order *is* "newest updatedAt of any part in that folder, desc" — with no
// second pass and no new Store call.
let foldersOf = (parts: array<Types.part>): array<string> => {
  let seen = []
  parts->Array.forEach(p =>
    if p.path != "" && !Array.includes(seen, p.path) {
      Array.push(seen, p.path)
    }
  )
  seen
}

// A12a migration for A10 data, run **once** from `PartsLoaded` (never on a
// re-render). Existing folder docs seed the running set (their spelling is
// canonical); then each distinct part path, in `parts` order (updatedAt
// desc — the most recently touched spelling wins), is prefix-snapped
// against what has been seen so far and any part whose spelling changed is
// `putPart`ed (rare: A10's whole-path snap let `Miata/Interior` and
// `miata/Exterior` coexist). One `ensureFolders` over the result, then the
// full doc list becomes `model.folders`. Sequential on purpose: parallel
// `ensureFolder`s would race on shared ancestors (review S3).
let migrateFoldersCmd = (parts: array<Types.part>): Tea.cmd<msg> =>
  Tea.fromPromise(
    async () => {
      let store = store()
      let seen = await Store.listFolders(store)
      let changed = []
      parts->Array.forEach(p =>
        if p.path != "" {
          let snapped = Folder.snap(p.path, ~existing=seen)
          if !Array.includes(seen, snapped) {
            Array.push(seen, snapped)
          }
          if snapped != p.path {
            Array.push(changed, {...p, path: snapped})
          }
        }
      )
      let saved = []
      for i in 0 to Array.length(changed) - 1 {
        switch changed[i] {
        | Some(p) => Array.push(saved, await Store.putPart(store, p))
        | None => ()
        }
      }
      let _ = await Store.ensureFolders(store, ~paths=seen)
      let folders = await Store.listFolders(store)
      (folders, saved)
    },
    ((folders, saved)) => FoldersLoaded(folders, saved),
    e => FoldersFailed(describeError(e)),
  )

// A12a: what the picker lists (root aside) — explicit folder docs ∪ the
// loaded parts' paths ∪ their ancestors ∪ the current selection, as a
// depth-first flat tree. The same set is what a new folder name snaps
// against, so `interior` under `Miata` finds the existing `Interior`.
let pickerPaths = (model: model, picker: picker): array<string> =>
  Folder.tree(Array.concat(Array.concat(model.folders, foldersOf(model.parts)), [picker.selected]))

// Explicit folders after the picker created some: docs ∪ created ∪ the
// path itself (a per-doc 409 means it exists even if it isn't in `created`).
let withFolders = (folders: array<string>, added: array<string>): array<string> =>
  Array.concat(folders, added)
  ->Array.filter(p => p != "")
  ->Array.reduce([], (acc, p) => {
    if !Array.includes(acc, p) {
      Array.push(acc, p)
    }
    acc
  })
  ->Array.toSorted((a, b) => String.compare(String.toLowerCase(a), String.toLowerCase(b)))

// The draft path the picker starts from for its target.
let draftPathFor = (model: model, target: pickerTarget): string =>
  switch target {
  | ForCreate => model.form->Option.map(f => f.draft.path)->Option.getOr("")
  | ForRename(id) =>
    switch rowStateOf(model, id) {
    | Renaming(draft) => draft.path
    | Normal | ConfirmingDelete => ""
    }
  }

// Case-insensitive substring on the name, the stored path and its display
// form — so "miata / int" matches what the section header shows, too.
let matchesQuery = (query: string, part: Types.part): bool => {
  let q = query->String.trim->String.toLowerCase
  q == "" ||
  String.includes(String.toLowerCase(part.name), q) ||
  String.includes(String.toLowerCase(part.path), q) ||
  String.includes(String.toLowerCase(Folder.display(part.path)), q)
}

type section = {path: string, rows: array<Types.part>}

// Root first (only when it has rows — after a move empties it, the section
// is gone), then folders sorted case-insensitively. Grouping is exact-
// string: `Folder.snap` keeps spellings unique on save (review S2), so the
// uppercase `.list-group-header` can't show two look-alike sections. Row
// order inside a section is `parts` order (updatedAt desc).
let sectionsOf = (parts: array<Types.part>): array<section> => {
  let root = parts->Array.filter(p => p.path == "")
  let folders =
    foldersOf(parts)->Array.toSorted((a, b) =>
      String.compare(String.toLowerCase(a), String.toLowerCase(b))
    )
  let folderSections =
    folders->Array.map(path => ({path, rows: parts->Array.filter(p => p.path == path)}: section))
  Array.length(root) > 0
    ? Array.concat([({path: "", rows: root}: section)], folderSections)
    : folderSections
}

let emptyDraft: formDraft = {name: "", path: ""}

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | PartsLoaded(parts) => (
      {...model, loaded: true, parts, error: None},
      // One cmd per part (see `loadFirstFaceImageCmd`'s doc comment) plus
      // the A12a folder migration; this only ever runs off the one
      // `PartsLoaded` that follows `init`'s own `Store.listParts` — never
      // re-triggered by a later re-render.
      Tea.batch(
        Array.concat(parts->Array.map(p => loadFirstFaceImageCmd(p.id)), [migrateFoldersCmd(parts)]),
      ),
    )
  | LoadFailed(msg) => ({...model, loaded: true, error: Some(msg)}, Tea.none)
  | FoldersLoaded(folders, saved) => (
      {
        ...model,
        folders,
        parts: Array.length(saved) == 0
          ? model.parts
          : model.parts
            ->Array.map(p => saved->Array.find(s => s.id == p.id)->Option.getOr(p))
            ->Array.toSorted(byUpdatedAtDesc),
      },
      Tea.none,
    )
  | FoldersFailed(msg) => ({...model, error: Some(msg)}, Tea.none)
  | PartImageLoaded(partId, Some(url)) =>
    let next = Dict.copy(model.partImages)
    Dict.set(next, partId, url)
    ({...model, partImages: next}, Tea.none)
  | PartImageLoaded(_, None) => (model, Tea.none)
  | EditToggled => ({...model, editing: !model.editing, rowStates: Dict.make()}, Tea.none)
  | QueryChanged(query) => ({...model, query}, Tea.none)
  | QueryCleared => ({...model, query: ""}, focusTestId("parts-search"))
  | NewPartClicked => (
      {
        ...model,
        form: Some({draft: emptyDraft, units: Types.Mm, error: None, submitting: false}),
      },
      focusTestId("part-name"),
    )
  | FormNameChanged(name) => (
      {
        ...model,
        form: model.form->Option.map(f => {...f, draft: {...f.draft, name}, error: None}),
      },
      Tea.none,
    )
  | FormUnitsChanged(units) => ({...model, form: model.form->Option.map(f => {...f, units})}, Tea.none)
  | FormCancel => ({...model, form: None}, Tea.none)
  | CreateSubmit =>
    switch model.form {
    | None => (model, Tea.none)
    | Some(f) =>
      let trimmed = String.trim(f.draft.name)
      if trimmed == "" {
        ({...model, form: Some({...f, error: Some("Name can't be empty")})}, Tea.none)
      } else {
        // The draft's path came out of the picker (already snapped), so it
        // goes to Store as is; `createPart` ensures its folder doc (A12a).
        (
          {...model, form: Some({...f, submitting: true, error: None})},
          Tea.fromPromise(
            () =>
              Store.createPart(
                store(),
                ~name=trimmed,
                ~slug=Slug.make(trimmed),
                ~path=f.draft.path,
                ~units=f.units,
              ),
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
    let draft =
      model.parts
      ->Array.find(p => p.id == id)
      ->Option.map(p => ({name: p.name, path: p.path}: formDraft))
      ->Option.getOr(emptyDraft)
    (
      {...model, rowStates: setRowState(model, id, Renaming(draft)), rowError: None},
      focusTestId("part-rename-input"),
    )
  | RenameDraftChanged(id, name) =>
    switch rowStateOf(model, id) {
    | Renaming(draft) => (
        {...model, rowStates: setRowState(model, id, Renaming({...draft, name}))},
        Tea.none,
      )
    | Normal | ConfirmingDelete => (model, Tea.none)
    }
  | RenameCancel(id) => ({...model, rowStates: setRowState(model, id, Normal)}, Tea.none)
  | RenameSubmit(id) =>
    switch (rowStateOf(model, id), model.parts->Array.find(p => p.id == id)) {
    | (Renaming(draft), Some(part)) =>
      let trimmed = String.trim(draft.name)
      trimmed == ""
        ? (model, Tea.none)
        : (
            model,
            Tea.fromPromise(
              () => Store.putPart(store(), {...part, name: trimmed, path: draft.path}),
              p => RenameSaved(p),
              e => RenameFailed(describeError(e)),
            ),
          )
    | _ => (model, Tea.none)
    }
  | RenameSaved(part) => (
      {
        ...model,
        // `putPart` returns the bumped `updatedAt`, so the edited part
        // re-sorts to the top of its (possibly new) section rather than
        // sitting at its stale position until reload (review S6).
        parts: model.parts
        ->Array.map(p => p.id == part.id ? part : p)
        ->Array.toSorted(byUpdatedAtDesc),
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
      // `new-part` always exists somewhere on screen once the list has
      // loaded, either the bar icon (list still non-empty) or the empty
      // state's own capsule (`renderEmptyCapsule`, list now empty) — never
      // both (see `actions`'s own doc comment).
      focusTestId("new-part"),
    )
  | DeleteFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  // ---- A12a: the folder picker ----------------------------------------
  | PickerOpen(target) =>
    let selected = draftPathFor(model, target)
    (
      {...model, picker: Some({target, selected, newFolder: None}), rowError: None},
      // DESIGN.md §9: opening the picker focuses the selected option.
      focusFolderOption(selected),
    )
  | PickerSelect(path) => (
      {...model, picker: model.picker->Option.map(p => {...p, selected: path})},
      Tea.none,
    )
  // Done applies the selection to the target's draft and returns there;
  // Create / Save then proceed exactly as before. Cancel discards only the
  // picker's selection — never the form's other fields. Both send focus
  // back to the Folder row (with two rename strips open that is the first
  // `part-folder-row` in the DOM — the same accepted edge as
  // `part-rename-input`'s focus).
  | PickerDone =>
    switch model.picker {
    | None => (model, Tea.none)
    | Some({target: ForCreate, selected}) => (
        {
          ...model,
          form: model.form->Option.map(f => {...f, draft: {...f.draft, path: selected}}),
          picker: None,
        },
        focusTestId("part-folder-row"),
      )
    | Some({target: ForRename(id), selected}) =>
      let rowStates = switch rowStateOf(model, id) {
      | Renaming(draft) => setRowState(model, id, Renaming({...draft, path: selected}))
      | Normal | ConfirmingDelete => model.rowStates
      }
      ({...model, rowStates, picker: None}, focusTestId("part-folder-row"))
    }
  | PickerCancel => ({...model, picker: None}, focusTestId("part-folder-row"))
  | NewFolderOpen => (
      {...model, picker: model.picker->Option.map(p => {...p, newFolder: Some("")})},
      focusTestId("folder-new-name"),
    )
  | NewFolderChanged(draft) => (
      {...model, picker: model.picker->Option.map(p => {...p, newFolder: Some(draft)})},
      Tea.none,
    )
  | NewFolderCancel => (
      {...model, picker: model.picker->Option.map(p => {...p, newFolder: None})},
      focusTestId("folder-new"),
    )
  // `join` under the selection, `snap` against everything the picker knows
  // (so `interior` under `Miata` selects the existing `Interior` instead of
  // making a twin), then `ensureFolder`. `Error` only reaches here if a
  // submit slips past the disabled Create; the depth cap disables the
  // capsule before the field can even open.
  | NewFolderCreate =>
    switch model.picker {
    | Some({selected, newFolder: Some(draft)} as picker)
      if Folder.depth(selected) < Folder.maxDepth =>
      switch Folder.validateSegment(draft) {
      | Error(_) => (model, Tea.none)
      | Ok(name) =>
        let path = Folder.snap(
          Folder.join(~parent=selected, ~name),
          ~existing=pickerPaths(model, picker),
        )
        (
          model,
          Tea.fromPromise(
            () => Store.ensureFolder(store(), ~path),
            created => NewFolderCreated(path, created),
            e => NewFolderFailed(describeError(e)),
          ),
        )
      }
    | _ => (model, Tea.none)
    }
  // The created (or snapped-onto) folder becomes the selection; the field
  // closes and focus moves to its option. It is a real folder from here on
  // — Cancelling the picker afterwards does not undo it.
  | NewFolderCreated(path, created) => (
      {
        ...model,
        folders: withFolders(model.folders, Array.concat(created, [path])),
        picker: model.picker->Option.map(p => {...p, selected: path, newFolder: None}),
        rowError: None,
      },
      focusFolderOption(path),
    )
  | NewFolderFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  }

// A12a (review B3): while the picker is open the bar carries a centred
// Headline "Choose Folder" between Cancel and Done, the HIG picker shape;
// otherwise the root's static Large Title "Parts".
let title = (model: model): string =>
  switch model.picker {
  | Some(_) => "Choose Folder"
  | None => "Parts"
  }
let largeTitle = (model: model): bool => model.picker->Option.isNone
let back = (_model: model): option<Route.t> => None

let subtitle = (_model: model): option<string> => None

// Bar leading slot. Normally the gear: Settings and Debug have no other way
// in from an installed app (no URL bar), so the Parts root carries one bar
// button on the root (HIG); Settings then links on to Debug. While the
// picker is open it is a Cancel text action instead — `Shell.back` can only
// push a route, and cancelling is a page message.
let leading = (model: model, ~dispatch: msg => unit): option<React.element> =>
  switch model.picker {
  | Some(_) =>
    Some(
      <Ui.Button
        variant=Ui.Button.Plain
        className="bar-action"
        testId="folder-picker-cancel"
        onClick={_ => dispatch(PickerCancel)}>
        {React.string("Cancel")}
      </Ui.Button>,
    )
  | None =>
    Some(
      <a
        className="btn btn-icon"
        href={Route.href(Route.Settings)}
        ariaLabel="Settings"
        dataTestId="settings-link">
        <Icon name=Settings size=22 />
      </a>,
    )
  }

// Bar trailing actions (DESIGN.md §11.2, review-2026-09-17.md P1/P3): the
// Edit/Done text action and, once the list is non-empty, the "+" icon
// button — both live here now instead of in the body. Neither renders
// while the create form is open (nothing to edit/add to yet) or before the
// list has loaded. `new-part` only ever exists once on screen at a time:
// this bar icon while the list is non-empty, or the empty state's own body
// capsule (`renderEmptyCapsule`) while it isn't — never both, which is what
// keeps `getByTestId('new-part')` a single-element (Playwright strict-mode)
// match either way.
let actions = (model: model, ~dispatch: msg => unit): option<React.element> =>
  switch model.picker {
  | Some(_) =>
    Some(
      <Ui.Button
        variant=Ui.Button.Plain
        className="bar-action bar-action-strong"
        testId="folder-picker-done"
        onClick={_ => dispatch(PickerDone)}>
        {React.string("Done")}
      </Ui.Button>,
    )
  | None =>
    model.loaded && model.form->Option.isNone && Array.length(model.parts) > 0
      ? Some(
        <>
          <Ui.Button
            variant=Ui.Button.Plain
            className="bar-action"
            testId="parts-edit"
            onClick={_ => dispatch(EditToggled)}>
            {React.string(model.editing ? "Done" : "Edit")}
          </Ui.Button>
          <Ui.Button
            variant=Ui.Button.Icon
            testId="new-part"
            ariaLabel="New part"
            onClick={_ => dispatch(NewPartClicked)}>
            <Icon name=Plus size=22 />
          </Ui.Button>
        </>,
      )
      : None
  }

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

let inputValue = (e: JsxEvent.Form.t): string => e->Canvas.Form.target->Canvas.value

// A10 (review S4): the one form both create and the inline rename render —
// Name, then the Folder row (A12a: a button that opens the picker, showing
// the chosen folder in display form or "None"), then the caller's own extra
// rows (create's units) and its primary/cancel pair. `grouped` renders the
// fields as inset grouped rows (the create form, DESIGN.md §11.2) — there
// the Folder row is a `.list-row` with a chevron; the rename strip lays
// them out plainly inside its row, where the same control is a
// `.part-folder-field` button under a Caption label (review N4: no row
// inside a row). Field ids take `idSuffix` so two open rename strips never
// share a DOM id; the create form keeps its pre-A10 `part-name-input` id
// (suffix "").
module PartForm = {
  let folderValue = (draft: formDraft): string =>
    draft.path == "" ? "None" : Folder.display(draft.path)

  let view = (
    ~draft: formDraft,
    ~idSuffix: string,
    ~nameTestId: string,
    ~nameError: option<string>,
    ~onName: string => unit,
    ~onFolder: unit => unit,
    ~extraRows: array<React.element>,
    ~primaryLabel: string,
    ~primaryTestId: string,
    ~submitting: bool,
    ~onSubmit: unit => unit,
    ~cancelTestId: option<string>,
    ~onCancel: unit => unit,
    ~grouped: bool,
  ): React.element => {
    let nameId = "part-name-input" ++ idSuffix
    let nameField =
      <Ui.Field label="Name" htmlFor=nameId error=?nameError>
        <input
          id=nameId
          type_="text"
          dataTestId=nameTestId
          autoCapitalize="words"
          maxLength=60
          value={draft.name}
          onChange={evt => onName(ReactEvent.Form.target(evt)["value"])}
        />
      </Ui.Field>
    let chevron = <span className="list-row-chevron"> <Icon name=ChevronRight size=20 /> </span>
    let folderRow = grouped
      ? <button
          type_="button"
          className="list-row part-folder-row"
          dataTestId="part-folder-row"
          onClick={_ => onFolder()}>
          <span className="list-row-body">
            <span className="list-row-title"> {React.string("Folder")} </span>
          </span>
          <span className="list-row-trailing part-folder-value">
            {React.string(folderValue(draft))}
          </span>
          chevron
        </button>
      : <div className="field">
          <span className="field-label"> {React.string("Folder")} </span>
          <button
            type_="button"
            className="part-folder-field"
            dataTestId="part-folder-row"
            onClick={_ => onFolder()}>
            <span className="part-folder-value"> {React.string(folderValue(draft))} </span>
            chevron
          </button>
        </div>
    let keyedExtra = (className: string) =>
      extraRows
      ->Array.mapWithIndex((row, i) => <div key={Int.toString(i)} className> row </div>)
      ->React.array
    let fields = grouped
      ? <Ui.ListGroup>
          <div className="list-row parts-form-row"> nameField </div>
          folderRow
          {keyedExtra("list-row parts-form-row")}
        </Ui.ListGroup>
      : <div className="stack">
          <div className="parts-form-field"> nameField </div>
          <div className="parts-form-field"> folderRow </div>
          {keyedExtra("parts-form-field")}
        </div>
    <div className="stack">
      fields
      <div className="btn-row">
        <Ui.Button
          variant=Ui.Button.Primary testId=primaryTestId disabled=submitting onClick={_ => onSubmit()}>
          {React.string(primaryLabel)}
        </Ui.Button>
        <Ui.Button variant=Ui.Button.Secondary testId=?cancelTestId onClick={_ => onCancel()}>
          {React.string("Cancel")}
        </Ui.Button>
      </div>
    </div>
  }
}

// DESIGN.md §11.2: inset grouped Field + Segmented, a visually-hidden real
// <select> kept in sync so parts.spec.js's `selectOption('mm')` still works
// (Ui.Segmented has no <select> semantics of its own — see the report).
let unitsRow = (form: createForm, ~dispatch: msg => unit): React.element =>
  <div className="field">
    <span className="field-label"> {React.string("Units")} </span>
    <Ui.Segmented
      options=unitsSegOptions
      selected={Enums.unitsToString(form.units)}
      onSelect={raw => dispatch(FormUnitsChanged(Enums.unitsFromString(raw)->Option.getOr(Types.Mm)))}
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

let renderForm = (form: createForm, ~dispatch: msg => unit): React.element =>
  PartForm.view(
    ~draft=form.draft,
    ~idSuffix="",
    ~nameTestId="part-name",
    ~nameError=form.error,
    ~onName=name => dispatch(FormNameChanged(name)),
    ~onFolder=() => dispatch(PickerOpen(ForCreate)),
    ~extraRows=[unitsRow(form, ~dispatch)],
    ~primaryLabel=form.submitting ? "Creating…" : "Create",
    ~primaryTestId="part-create",
    ~submitting=form.submitting,
    ~onSubmit=() => dispatch(CreateSubmit),
    ~cancelTestId=None,
    ~onCancel=() => dispatch(FormCancel),
    ~grouped=true,
  )

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
  let trailingEl = model.editing
    ? Some(
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
        </>,
      )
    : None

  switch state {
  // A10: the rename strip is the same `PartForm` as create (minus units),
  // so picking a Folder here is how a part moves between sections.
  | Renaming(draft) =>
    <div key={part.id} className="list-row" role="listitem" dataTestId="part-row">
      <div className="part-row-edit">
        {PartForm.view(
          ~draft,
          ~idSuffix="-" ++ part.id,
          ~nameTestId="part-rename-input",
          ~nameError=None,
          ~onName=name => dispatch(RenameDraftChanged(part.id, name)),
          ~onFolder=() => dispatch(PickerOpen(ForRename(part.id))),
          ~extraRows=[],
          ~primaryLabel="Save",
          ~primaryTestId="part-rename-save",
          ~submitting=false,
          ~onSubmit=() => dispatch(RenameSubmit(part.id)),
          ~cancelTestId=Some("part-rename-cancel"),
          ~onCancel=() => dispatch(RenameCancel(part.id)),
          ~grouped=false,
        )}
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
  // Out of edit mode the row is purely navigational (P1: no permanent
  // per-row icon buttons — a real HIG list row carries one trailing
  // element, the chevron). `trailing` is `None` rather than an empty
  // fragment so `Ui.ListRow` doesn't wrap a `.list-row-trailing` span
  // around nothing.
  | Normal =>
    <Ui.ListRow
      key={part.id}
      testId="part-row"
      href={Route.href(Route.Part(part.id))}
      chevron=true
      leading={<Ui.ListThumb src={Dict.get(model.partImages, part.id)} alt={part.name} />}
      trailing=?trailingEl>
      <Ui.ListRow.Title> {React.string(part.name)} </Ui.ListRow.Title>
      <Ui.ListRow.Meta>
        {React.string(Enums.unitsToString(part.units) ++ " · updated " ++ relativeDate(part.updatedAt))}
      </Ui.ListRow.Meta>
    </Ui.ListRow>
  }
}

// A10: one inset grouped section per folder. The root section never gets a
// header (a folder-less list is byte-for-byte the pre-A10 list); a folder's
// header is `"<display path> · <count>"` — `.list-group-header` uppercases
// it on screen, `Folder.snap` keeps the underlying spelling unique.
let renderSection = (model: model, section: section, ~dispatch: msg => unit): React.element =>
  <Ui.ListGroup
    key={section.path == "" ? "/" : section.path}
    asList=true
    header=?{section.path == ""
      ? None
      : Some(Folder.display(section.path) ++ " · " ++ Int.toString(Array.length(section.rows)))}
    headerTestId="parts-section-header"
    testId="parts-section">
    {section.rows->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
  </Ui.ListGroup>

// A10: a plain 17 px search field under the static Large Title — on the web
// that's the honest equivalent of HIG's nav-bar search (review N5). Live
// filter, sections preserved. `global.css`'s `-webkit-appearance: none`
// strips WebKit's native cancel button along with the rest of the chrome,
// so the page supplies its own (`parts-search-clear`) while there is
// something to clear; clearing returns focus to the field.
let renderSearch = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="parts-search">
    {Canvas.Input.make({
      dataTestId: "parts-search",
      id: "parts-search-input",
      type_: "search",
      inputMode: "search",
      enterKeyHint: "search",
      autoCapitalize: "none",
      autoCorrect: "off",
      autoComplete: "off",
      spellCheck: false,
      placeholder: "Search",
      ariaLabel: "Search parts",
      value: model.query,
      onChange: e => dispatch(QueryChanged(inputValue(e))),
    })}
    {model.query == ""
      ? React.null
      : <Ui.Button
          variant=Ui.Button.Icon
          className="parts-search-clear"
          testId="parts-search-clear"
          ariaLabel="Clear search"
          onClick={_ => dispatch(QueryCleared)}>
          <Icon name=X size=20 />
        </Ui.Button>}
  </div>

let renderList = (model: model, ~dispatch: msg => unit): React.element => {
  let sections = sectionsOf(model.parts->Array.filter(part => matchesQuery(model.query, part)))
  <>
    {renderSearch(model, ~dispatch)}
    {Array.length(sections) == 0
      ? <p className="t-footnote muted" dataTestId="parts-search-empty">
          {React.string(`No parts match "${String.trim(model.query)}".`)}
        </p>
      : <div className="parts-sections">
          {sections->Array.map(section => renderSection(model, section, ~dispatch))->React.array}
        </div>}
  </>
}

// ---- A12a: the folder picker ---------------------------------------------

// An option is a real <button> (focusable, Enter/Space for free — review
// S7) carrying `role="option"`, `data-path` and `aria-selected`, which
// `JsxDOM.domProps` cannot express — so, like Annotate's `RowButton`, it is
// created through the `react/jsx-runtime` call with exactly the attributes
// the spec names. `aria-label` is the full display path (the visible text
// is only the leaf), so VoiceOver hears the hierarchy the indent shows.
module OptionButton = {
  type props = {
    @as("type") type_: string,
    className: string,
    role: string,
    @as("data-testid") dataTestId: string,
    @as("data-path") dataPath: string,
    @as("aria-selected") ariaSelected: bool,
    @as("aria-label") ariaLabel: string,
    style: JsxDOMStyle.t,
    onClick: JsxEvent.Mouse.t => unit,
    children: React.element,
  }

  @module("react/jsx-runtime") external jsxKeyed: (string, props, string) => React.element = "jsx"

  let make = (~key: string, props: props): React.element => jsxKeyed("button", props, key)
}

// The row's own 16 px padding plus `depth × 20 px` (SPEC A12a): the root
// "None" sits at depth 0, top-level folders one step in under it.
let optionIndentPx = 20
let rowPaddingPx = 16

let renderFolderOption = (picker: picker, path: string, ~dispatch: msg => unit): React.element => {
  let isRoot = path == ""
  let selected = picker.selected == path
  OptionButton.make(
    ~key=isRoot ? "/" : path,
    {
      type_: "button",
      className: "list-row folder-option",
      role: "option",
      dataTestId: "folder-option",
      dataPath: path,
      ariaSelected: selected,
      ariaLabel: isRoot ? "None, top level" : Folder.display(path),
      style: {
        paddingLeft: Int.toString(rowPaddingPx + Folder.depth(path) * optionIndentPx) ++ "px",
      },
      onClick: _ => dispatch(PickerSelect(path)),
      children: <>
        <span className="folder-option-glyph" ariaHidden=true>
          {isRoot ? React.null : <Icon name=Folder size=22 />}
        </span>
        <span className="list-row-body">
          <span className="list-row-title"> {React.string(isRoot ? "None" : Folder.leaf(path))} </span>
          {isRoot
            ? <span className="list-row-meta"> {React.string("Top level")} </span>
            : React.null}
        </span>
        {selected
          ? <span className="list-row-trailing folder-option-check"> <Icon name=Check size=20 /> </span>
          : React.null}
      </>,
    },
  )
}

// Under the list: a secondary New Folder capsule that reveals an inline
// one-segment field (`Folder.validateSegment` live: Create disabled while
// invalid or empty, the rule inline once there is something to judge), or
// — at six deep already — the capsule disabled with a Footnote saying why.
let renderNewFolder = (picker: picker, ~dispatch: msg => unit): React.element => {
  let maxed = Folder.depth(picker.selected) >= Folder.maxDepth
  switch picker.newFolder {
  | None =>
    <div className="stack folder-picker-new">
      <Ui.Button
        variant=Ui.Button.Secondary
        block=true
        testId="folder-new"
        disabled=maxed
        onClick={_ => dispatch(NewFolderOpen)}>
        <Icon name=FolderPlus size=20 />
        {React.string("New Folder")}
      </Ui.Button>
      {maxed
        ? <p className="t-footnote muted" dataTestId="folder-new-depth">
            {React.string("Folders go six deep.")}
          </p>
        : React.null}
    </div>
  | Some(draft) =>
    let invalid = Folder.validateSegment(draft)->Result.isError
    let error = switch Folder.validateSegment(draft) {
    | Error(e) if String.trim(draft) != "" => Some(Folder.errorMessage(e))
    | Error(_) | Ok(_) => None
    }
    <div className="stack folder-picker-new">
      <Ui.Field
        label="New folder" htmlFor="folder-new-name-input" error=?error errorTestId="folder-new-error">
        {Canvas.Input.make({
          dataTestId: "folder-new-name",
          id: "folder-new-name-input",
          type_: "text",
          autoCapitalize: "words",
          autoCorrect: "off",
          autoComplete: "off",
          spellCheck: false,
          enterKeyHint: "done",
          placeholder: "Folder name",
          ariaInvalid: error->Option.isSome,
          value: draft,
          onChange: e => dispatch(NewFolderChanged(inputValue(e))),
          onKeyDown: e =>
            if JsxEvent.Keyboard.key(e) == "Enter" {
              e->JsxEvent.Keyboard.preventDefault
              if !invalid {
                dispatch(NewFolderCreate)
              }
            },
        })}
      </Ui.Field>
      <div className="btn-row">
        <Ui.Button
          variant=Ui.Button.Primary
          testId="folder-new-create"
          disabled=invalid
          onClick={_ => dispatch(NewFolderCreate)}>
          {React.string("Create")}
        </Ui.Button>
        <Ui.Button
          variant=Ui.Button.Secondary testId="folder-new-cancel" onClick={_ => dispatch(NewFolderCancel)}>
          {React.string("Cancel")}
        </Ui.Button>
      </div>
    </div>
  }
}

// The picker takes over the page the way the create form does: one
// `role="listbox"` group — root first, then every known folder as a flat
// tree (children after their parent, indented) — and the New Folder area.
let renderPicker = (model: model, picker: picker, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg folder-picker" dataTestId="folder-picker">
    <Ui.ListGroup role="listbox" testId="folder-picker-list">
      {renderFolderOption(picker, "", ~dispatch)}
      {pickerPaths(model, picker)
      ->Array.map(path => renderFolderOption(picker, path, ~dispatch))
      ->React.array}
    </Ui.ListGroup>
    {renderNewFolder(picker, ~dispatch)}
  </div>

// DESIGN.md §7 / §11.2: "one line of copy … and the primary button; no
// illustration" — the empty state's own capsule. Once the list is
// non-empty, "+" lives in the bar instead (`actions` above, P3); this
// stops rendering entirely then, rather than becoming a second, redundant
// "New part" affordance under the list.
let renderEmptyCapsule = (model: model, ~dispatch: msg => unit): React.element =>
  if !model.loaded || Array.length(model.parts) > 0 {
    React.null
  } else {
    <Ui.Button
      variant=Ui.Button.Primary
      block=true
      testId="new-part"
      onClick={_ => dispatch(NewPartClicked)}>
      {React.string("New part")}
    </Ui.Button>
  }

// `.parts-page` scopes PartsList.css's 72 px thumbnail override to this
// page's rows only — `Ui.ListThumb`/`.list-thumb` (global.css) is also used
// by Part.res's face-edit list at its own 52 px, and CSS here is unscoped
// app-wide (see PartsList.css), so an unscoped override would leak there.
let view = (model: model, ~dispatch: msg => unit): React.element =>
  <div className="stack-lg parts-page">
    <Ui.Live text=model.announcement testId="parts-live" />
    {switch model.error {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch model.rowError {
    | Some(msg) => <p className="page-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    {switch (model.picker, model.form) {
    | (Some(picker), _) => renderPicker(model, picker, ~dispatch)
    | (None, Some(f)) => renderForm(f, ~dispatch)
    | (None, None) =>
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
          renderList(model, ~dispatch)
        }}
        {renderEmptyCapsule(model, ~dispatch)}
      </div>
    }}
  </div>
