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
//
// A12b (SPEC §8a): Edit mode selects. Every row becomes a checkbox row (no
// link, no chevron; the body is the checkbox's label, the pencil a sibling)
// and a bottom toolbar in the Shell's footer slot carries Move (the A12a
// picker, `ForMove`) and Delete (one confirm strip, `Store.deleteParts`) —
// the per-row delete and its strip are gone. Section headers gain Rename
// (an inline one-segment form, `Store.renameFolder`, the subtree follows)
// and, on an empty leaf, Delete. Leaf folders with no parts render as
// "<display> · 0" sections with one "Empty folder" row; a folder with
// subfolders but no direct parts is a header-only row while editing.

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

// A12a: where the picker returns to on Done / Cancel — the create form's
// draft or one row's rename draft. A12b: `ForMove` carries the selected
// part ids; Done moves them and returns to the list.
type pickerTarget =
  | ForCreate
  | ForRename(string)
  | ForMove(array<string>)

type picker = {
  target: pickerTarget,
  selected: string,
  // `Some(draft)` while the New Folder field is open under the list.
  newFolder: option<string>,
}

// A12b: the header rename form. `error` is a store refusal (`Exists`),
// shown until the draft changes; the live `Folder.validateSegment` rule is
// derived in the view.
type folderEdit = {
  path: string,
  draft: string,
  error: option<string>,
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
  // A12b: the part ids checked in Edit mode. Cleared by Done, by a query
  // change, and after a move or delete lands.
  selected: array<string>,
  // A12b: the toolbar's Delete confirm strip is open.
  confirmingDelete: bool,
  // A12b: the inline folder-rename editor on one section header. One inline
  // editor at a time (review S9): opening it resets `rowStates`, and a
  // row's `RenameStart` closes it.
  folderEdit: option<folderEdit>,
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
  // A12b: Edit-mode selection and the bottom toolbar. Move goes through
  // `PickerOpen(ForMove(ids))` / `PickerDone`.
  | SelectToggled(string)
  | PartsMoved(array<Types.part>, string)
  | MoveFailed(string)
  | DeleteStart
  | DeleteCancel
  | DeleteConfirm
  | PartsDeleted(array<string>)
  | DeleteFailed(string)
  // A12b: folder rename / delete on a section header.
  | FolderRenameStart(string)
  | FolderRenameChanged(string)
  | FolderRenameCancel
  | FolderRenameSubmit
  | FolderRenamed(string, string, result<unit, Store.folderError>)
  | FolderRenameFailed(string)
  | FolderDeleteClicked(string)
  | FolderDeleted(string, result<unit, Store.folderError>)
  | FolderDeleteFailed(string)
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
// mounted (true for every other call site here). `PartsDeleted` (A12b;
// P2a's `DeleteDone` before it) is the exception on both counts: it fires
// from `Store.deleteParts`'s own promise resolving, not a click, so React's
// commit isn't guaranteed to land before one queued microtask — and
// deleting the *last* part swaps the bar's "+" icon for the empty state's
// `new-part` capsule (a different DOM node, not
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
  // with focus and gave up — the created option never got focus. The one
  // editable that is never "elsewhere" is `since` itself (A12b): Enter in
  // the folder-rename field (or the New Folder field) submits it, and that
  // field still has focus while React tears it down — the user has not
  // moved on, the field is going away, and the target (the renamed
  // header's pencil) only exists once it has.
  let stillOnSince = switch (Canvas.activeElement(Canvas.document), since) {
  | (Some(active), Some(s)) => active === s
  | (Some(_), None) | (None, _) => false
  }
  if (stillOnSince || !Canvas.userIsTypingElsewhere(target)) &&
    !Canvas.focusMovedElsewhere(~since, ~target) {
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

// A12b: one folder's header pencil — several sections carry the same
// `folder-rename` id, told apart by `data-path`.
let focusFolderRename = (path: string): Tea.cmd<msg> =>
  focusSelector(`[data-testid="folder-rename"][data-path="${path}"]`)

// "2 parts" / "1 part" — the toolbar labels, titles and live texts.
let countNoun = (n: int, noun: string): string =>
  Int.toString(n) ++ " " ++ noun ++ (n == 1 ? "" : "s")

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
    selected: [],
    confirmingDelete: false,
    folderEdit: None,
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
    | Normal => ""
    }
  // A12b: a move preselects the root.
  | ForMove(_) => ""
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

// A12b (review S5): what a section is.
type sectionKind =
  // Rows of parts (the ones matching the query).
  | Parts
  // An explicit leaf folder with no parts and no subfolders — the deletable
  // set: header "<display> · 0" and one "Empty folder" row.
  | EmptyLeaf
  // A folder with subfolders but no direct parts: nothing outside Edit
  // mode, a header-only row (rename, no container) while editing.
  | Intermediate

type section = {path: string, rows: array<Types.part>, kind: sectionKind}

// The same case-insensitive substring match `matchesQuery` gives a part's
// path, for a folder on its own (A12b: search hides an empty folder unless
// its path matches).
let folderMatchesQuery = (query: string, path: string): bool => {
  let q = query->String.trim->String.toLowerCase
  q == "" ||
  String.includes(String.toLowerCase(path), q) ||
  String.includes(String.toLowerCase(Folder.display(path)), q)
}

// Root first (only when it has rows — after a move empties it, the section
// is gone), then folders sorted case-insensitively. Grouping is exact-
// string: `Folder.snap` keeps spellings unique on save (review S2), so the
// uppercase `.list-group-header` can't show two look-alike sections. Row
// order inside a section is `parts` order (updatedAt desc). A12b: the
// folder set is every known path — explicit docs ∪ the parts' paths ∪ their
// ancestors, whatever the query — classified per `sectionKind`; a folder
// whose parts all fail the query is hidden (A10), an empty one shows only
// when the query is blank or matches its path. Counts are direct parts only.
let sectionsOf = (model: model): array<section> => {
  let visible = model.parts->Array.filter(part => matchesQuery(model.query, part))
  let root = visible->Array.filter(p => p.path == "")
  let known = Folder.tree(Array.concat(model.folders, foldersOf(model.parts)))
  let hasSub = (path: string): bool => known->Array.some(q => Folder.isUnder(q, ~folder=path))
  let hasParts = (path: string): bool => model.parts->Array.some(p => p.path == path)
  let folderSections =
    known
    ->Array.toSorted((a, b) => String.compare(String.toLowerCase(a), String.toLowerCase(b)))
    ->Array.filterMap(path => {
      let rows = visible->Array.filter(p => p.path == path)
      if Array.length(rows) > 0 {
        Some({path, rows, kind: Parts})
      } else if hasParts(path) || !folderMatchesQuery(model.query, path) {
        None
      } else if hasSub(path) {
        model.editing ? Some({path, rows: [], kind: Intermediate}) : None
      } else {
        Some({path, rows: [], kind: EmptyLeaf})
      }
    })
  Array.length(root) > 0
    ? Array.concat([({path: "", rows: root, kind: Parts}: section)], folderSections)
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
  // Done clears the selection and any open editor or strip (P1's
  // no-leftover-state rule); so does a query change, for the selection.
  | EditToggled => (
      {
        ...model,
        editing: !model.editing,
        rowStates: Dict.make(),
        selected: [],
        confirmingDelete: false,
        folderEdit: None,
      },
      Tea.none,
    )
  | QueryChanged(query) => ({...model, query, selected: [], confirmingDelete: false}, Tea.none)
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
      // One inline editor at a time (A12b, review S9): a folder rename
      // closes.
      {
        ...model,
        rowStates: setRowState(model, id, Renaming(draft)),
        folderEdit: None,
        rowError: None,
      },
      focusTestId("part-rename-input"),
    )
  | RenameDraftChanged(id, name) =>
    switch rowStateOf(model, id) {
    | Renaming(draft) => (
        {...model, rowStates: setRowState(model, id, Renaming({...draft, name}))},
        Tea.none,
      )
    | Normal => (model, Tea.none)
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
  // ---- A12b: selection and the bottom toolbar ---------------------------
  | SelectToggled(id) => (
      {
        ...model,
        selected: Array.includes(model.selected, id)
          ? model.selected->Array.filter(s => s != id)
          : Array.concat(model.selected, [id]),
      },
      Tea.none,
    )
  // `moveParts` returns only the parts it rewrote (bumped `updatedAt`), so
  // they re-sort to the top of their new section; the live text counts
  // those only — moving into the current folder announces nothing. The
  // selection clears either way; Edit mode stays on.
  | PartsMoved(moved, path) =>
    let count = Array.length(moved)
    (
      {
        ...model,
        parts: model.parts
        ->Array.map(p => moved->Array.find(m => m.id == p.id)->Option.getOr(p))
        ->Array.toSorted(byUpdatedAtDesc),
        folders: path == "" ? model.folders : withFolders(model.folders, [path]),
        selected: [],
        rowError: None,
        announcement: count == 0
          ? model.announcement
          : `Moved ${countNoun(count, "part")} to ${path == ""
                ? "the top level"
                : Folder.display(path)}`,
      },
      Tea.none,
    )
  | MoveFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  // The strip replaces the Move/Delete pair, so the tapped button is gone:
  // focus lands on the strip's Cancel — the safe one.
  | DeleteStart =>
    Array.length(model.selected) == 0
      ? (model, Tea.none)
      : ({...model, confirmingDelete: true, rowError: None}, focusTestId("parts-delete-cancel"))
  | DeleteCancel => ({...model, confirmingDelete: false}, focusTestId("parts-delete"))
  | DeleteConfirm =>
    let ids = model.selected
    (
      model,
      Tea.fromPromise(
        () => Store.deleteParts(store(), ~partIds=ids),
        () => PartsDeleted(ids),
        e => DeleteFailed(describeError(e)),
      ),
    )
  // DESIGN.md §9 "Focus management" (review S8): the rows are gone, so
  // focus goes to Edit/Done, which survives while parts remain; with none
  // left Edit leaves the bar (`actions`), `editing` resets, and focus goes
  // to the empty state's `new-part` capsule.
  | PartsDeleted(ids) =>
    let parts = model.parts->Array.filter(p => !Array.includes(ids, p.id))
    let none = Array.length(parts) == 0
    (
      {
        ...model,
        parts,
        selected: [],
        confirmingDelete: false,
        editing: none ? false : model.editing,
        rowError: None,
        announcement: `Deleted ${countNoun(Array.length(ids), "part")}`,
      },
      focusTestId(none ? "new-part" : "parts-edit"),
    )
  | DeleteFailed(msg) => ({...model, confirmingDelete: false, rowError: Some(msg)}, Tea.none)
  // ---- A12b: folder rename / delete on the section header -----------------
  | FolderRenameStart(path) => (
      {
        ...model,
        folderEdit: Some({path, draft: Folder.leaf(path), error: None}),
        rowStates: Dict.make(),
        confirmingDelete: false,
        rowError: None,
      },
      focusTestId("folder-rename-input"),
    )
  | FolderRenameChanged(draft) => (
      {...model, folderEdit: model.folderEdit->Option.map(f => {...f, draft, error: None})},
      Tea.none,
    )
  | FolderRenameCancel =>
    switch model.folderEdit {
    | Some({path}) => ({...model, folderEdit: None}, focusFolderRename(path))
    | None => (model, Tea.none)
    }
  // Rename keeps the parent (one segment): `to = join(parent(from), name)`.
  // Save is disabled while invalid or unchanged; this guards a stray Enter.
  | FolderRenameSubmit =>
    switch model.folderEdit {
    | Some({path: from, draft}) =>
      switch Folder.validateSegment(draft) {
      | Ok(name) if name != Folder.leaf(from) =>
        let to = Folder.join(~parent=Folder.parent(from), ~name)
        (
          model,
          Tea.fromPromise(
            () => Store.renameFolder(store(), ~from, ~to),
            result => FolderRenamed(from, to, result),
            e => FolderRenameFailed(describeError(e)),
          ),
        )
      | Ok(_) | Error(_) => (model, Tea.none)
      }
    | None => (model, Tea.none)
    }
  // The store rewrote the subtree; the page rebases its own copies the same
  // way (`updatedAt` stays as loaded until the next reload — only the meta
  // line could tell) and sections re-derive from the new spellings.
  | FolderRenamed(from, to, Ok()) =>
    let rebase = (p: string): string => Folder.rebase(p, ~from, ~to)
    (
      {
        ...model,
        parts: model.parts->Array.map(p => {...p, path: rebase(p.path)}),
        folders: withFolders(model.folders->Array.map(rebase), [to]),
        folderEdit: None,
        rowError: None,
      },
      focusFolderRename(to),
    )
  | FolderRenamed(_, to, Error(Store.Exists)) => (
      {
        ...model,
        folderEdit: model.folderEdit->Option.map(f => {
          ...f,
          error: Some(`A folder named "${Folder.leaf(to)}" already exists here.`),
        }),
      },
      Tea.none,
    )
  // Unreachable from this UI (rename keeps the parent) — store guards only.
  | FolderRenamed(_, _, Error(Store.NotEmpty | Store.Nested)) => (
      {...model, rowError: Some("Couldn't rename that folder.")},
      Tea.none,
    )
  | FolderRenameFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  // No confirm: the button only exists on an empty leaf.
  | FolderDeleteClicked(path) => (
      model,
      Tea.fromPromise(
        () => Store.deleteFolder(store(), ~path),
        result => FolderDeleted(path, result),
        e => FolderDeleteFailed(describeError(e)),
      ),
    )
  | FolderDeleted(path, Ok()) => (
      {
        ...model,
        folders: model.folders->Array.filter(p => p != path),
        announcement: `Deleted folder ${Folder.display(path)}`,
        rowError: None,
      },
      focusTestId("parts-edit"),
    )
  | FolderDeleted(_, Error(_)) => (
      {...model, rowError: Some("Couldn't delete that folder.")},
      Tea.none,
    )
  | FolderDeleteFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
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
      | Normal => model.rowStates
      }
      ({...model, rowStates, picker: None}, focusTestId("part-folder-row"))
    // A12b: Done on a move closes the picker at once (the toolbar is back,
    // focus returns to Move) and hands the ids to `moveParts`.
    | Some({target: ForMove(ids), selected}) => (
        {...model, picker: None},
        Tea.batch([
          Tea.fromPromise(
            () => Store.moveParts(store(), ~partIds=ids, ~path=selected),
            moved => PartsMoved(moved, selected),
            e => MoveFailed(describeError(e)),
          ),
          focusTestId("parts-move"),
        ]),
      )
    }
  | PickerCancel =>
    switch model.picker {
    // A12b: Cancel on a move keeps the selection; focus back on Move.
    | Some({target: ForMove(_)}) => ({...model, picker: None}, focusTestId("parts-move"))
    | Some(_) | None => ({...model, picker: None}, focusTestId("part-folder-row"))
    }
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
  | Some({target: ForMove(ids)}) => `Move ${countNoun(Array.length(ids), "Part")}`
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

// A12b: the selection toolbar — Move (the A12a picker, `ForMove`) and
// Delete (an inline confirm strip in the same slot), both disabled until a
// row is checked, the count in the label. Rendered by `footer` below into
// the Shell's footer slot, which is what makes it sticky at the bottom of
// the scroll container (review B1) rather than mid-page.
let renderToolbar = (model: model, ~dispatch: msg => unit): React.element => {
  let n = Array.length(model.selected)
  let labelled = (label: string): string => n == 0 ? label : label ++ " " ++ Int.toString(n)
  <div className="edit-toolbar" dataTestId="edit-toolbar">
    {model.confirmingDelete
      ? <div className="stack edit-toolbar-confirm">
          <p className="t-footnote">
            {React.string(
              `Delete ${countNoun(n, "part")}? This removes ${n == 1
                  ? "its"
                  : "their"} faces and dimensions.`,
            )}
          </p>
          <div className="btn-row">
            <Ui.Button
              variant=Ui.Button.Danger
              testId="parts-delete-confirm"
              onClick={_ => dispatch(DeleteConfirm)}
            >
              {React.string("Delete")}
            </Ui.Button>
            <Ui.Button
              variant=Ui.Button.Secondary
              testId="parts-delete-cancel"
              onClick={_ => dispatch(DeleteCancel)}
            >
              {React.string("Cancel")}
            </Ui.Button>
          </div>
        </div>
      : <div className="edit-toolbar-actions">
          <Ui.Button
            variant=Ui.Button.Plain
            className="bar-action"
            testId="parts-move"
            disabled={n == 0}
            onClick={_ => dispatch(PickerOpen(ForMove(model.selected)))}
          >
            {React.string(labelled("Move"))}
          </Ui.Button>
          <Ui.Button
            variant=Ui.Button.Plain
            className="bar-action edit-toolbar-danger"
            testId="parts-delete"
            disabled={n == 0}
            onClick={_ => dispatch(DeleteStart)}
          >
            {React.string(labelled("Delete"))}
          </Ui.Button>
        </div>}
  </div>
}

// Shell footer slot (A12b): `Some` while editing and neither the create
// form nor the picker has taken over the page.
let footer = (model: model, ~dispatch: msg => unit): option<React.element> =>
  model.editing && model.form->Option.isNone && model.picker->Option.isNone
    ? Some(renderToolbar(model, ~dispatch))
    : None

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

// A row's Normal content out of Edit mode is a single Ui.ListRow: thumbnail
// leading, name + meta body wrapped in a real <a> (`~href`, chevron
// included) — never a <button> wrapping other buttons, which is invalid
// HTML (design wave 3a's fix for the Ui.res gap wave 2 reported; see
// LOGBOOK.md). Renaming replaces a row's content in place with its own
// plain container (not Ui.ListRow — it's a form, not a navigable row),
// still under the same `part-row` testid.
//
// A12b (review S2): while editing, a Normal row is a plain `<div
// class="list-row" role="listitem">` — no `href`, no chevron — whose
// leading `<input type="checkbox">` (drawn as a selection circle) is
// labelled by the body: thumbnail, title and meta sit in a `<label for>`,
// so tapping any of them toggles; the pencil is a trailing sibling outside
// the label and never toggles. A real checkbox, never `Ui.ListRow ~onClick`
// (a <button> around the checkbox and the pencil — nested interactive
// content).
let renderRow = (model: model, part: Types.part, ~dispatch: msg => unit): React.element => {
  let state = rowStateOf(model, part.id)
  let meta = Enums.unitsToString(part.units) ++ " · updated " ++ relativeDate(part.updatedAt)

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
  | Normal if model.editing =>
    let inputId = "part-select-" ++ part.id
    <div
      key={part.id} className="list-row part-row-selectable" role="listitem" dataTestId="part-row"
    >
      <input
        type_="checkbox"
        id=inputId
        className="part-select"
        dataTestId="part-select"
        ariaLabel={"Select " ++ part.name}
        checked={Array.includes(model.selected, part.id)}
        onChange={_ => dispatch(SelectToggled(part.id))}
      />
      <label className="part-row-label" htmlFor=inputId>
        <Ui.ListThumb src={Dict.get(model.partImages, part.id)} alt={part.name} />
        <span className="list-row-body">
          <Ui.ListRow.Title> {React.string(part.name)} </Ui.ListRow.Title>
          <Ui.ListRow.Meta> {React.string(meta)} </Ui.ListRow.Meta>
        </span>
      </label>
      <span className="list-row-trailing">
        <Ui.Button
          variant=Ui.Button.Icon
          testId="part-rename"
          ariaLabel="Rename"
          onClick={_ => dispatch(RenameStart(part.id))}
        >
          <Icon name=Pencil size=20 />
        </Ui.Button>
      </span>
    </div>
  // Out of edit mode the row is purely navigational (P1: no permanent
  // per-row icon buttons — a real HIG list row carries one trailing
  // element, the chevron).
  | Normal =>
    <Ui.ListRow
      key={part.id}
      testId="part-row"
      href={Route.href(Route.Part(part.id))}
      chevron=true
      leading={<Ui.ListThumb src={Dict.get(model.partImages, part.id)} alt={part.name} />}
    >
      <Ui.ListRow.Title> {React.string(part.name)} </Ui.ListRow.Title>
      <Ui.ListRow.Meta> {React.string(meta)} </Ui.ListRow.Meta>
    </Ui.ListRow>
  }
}

// A12b: the header's Rename/Delete icon buttons carry `data-path`, so a
// focus cmd (and a test) can find *this* folder's — every section shows
// the same `folder-rename` id. `JsxDOM.domProps` can't express a data
// attribute, so, like `OptionButton` below, the element is created through
// the jsx-runtime call with exactly the attributes it needs.
module PathButton = {
  type props = {
    @as("type") type_: string,
    className: string,
    @as("data-testid") dataTestId: string,
    @as("data-path") dataPath: string,
    @as("aria-label") ariaLabel: string,
    onClick: JsxEvent.Mouse.t => unit,
    children: React.element,
  }

  @module("react/jsx-runtime") external jsx: (string, props) => React.element = "jsx"

  let make = (props: props): React.element => jsx("button", props)
}

// A12b: the trailing controls on a folder header while editing — Rename on
// every folder, Delete only on an empty leaf (no parts, no subfolders: the
// one case `deleteFolder` never refuses, so no confirm).
let renderFolderActions = (section: section, ~dispatch: msg => unit): React.element => <>
  {PathButton.make({
    type_: "button",
    className: "btn btn-icon",
    dataTestId: "folder-rename",
    dataPath: section.path,
    ariaLabel: "Rename folder",
    onClick: _ => dispatch(FolderRenameStart(section.path)),
    children: <Icon name=Pencil size=20 />,
  })}
  {section.kind == EmptyLeaf
    ? PathButton.make({
        type_: "button",
        className: "btn btn-icon",
        dataTestId: "folder-delete",
        dataPath: section.path,
        ariaLabel: "Delete folder",
        onClick: _ => dispatch(FolderDeleteClicked(section.path)),
        children: <Icon name=Trash size=20 />,
      })
    : React.null}
</>

// A12b: the header as an inline one-segment form — the leaf name prefilled,
// `Folder.validateSegment` live (the rule shows once there is something to
// judge), Save disabled while invalid or unchanged, a store `Exists` shown
// in the same line until the draft changes. Enter saves, Escape cancels.
let renderFolderRename = (edit: folderEdit, ~dispatch: msg => unit): React.element => {
  let validation = Folder.validateSegment(edit.draft)
  let unchanged = switch validation {
  | Ok(name) => name == Folder.leaf(edit.path)
  | Error(_) => false
  }
  let liveError = switch validation {
  | Error(e) if String.trim(edit.draft) != "" => Some(Folder.errorMessage(e))
  | Error(_) | Ok(_) => None
  }
  let error = switch edit.error {
  | Some(_) => edit.error
  | None => liveError
  }
  let canSave = Result.isOk(validation) && !unchanged
  <div className="folder-rename" dataTestId="folder-rename-form">
    <Ui.Field
      label="Rename folder"
      htmlFor="folder-rename-input-id"
      error=?error
      errorTestId="folder-rename-error"
    >
      {Canvas.Input.make({
        dataTestId: "folder-rename-input",
        id: "folder-rename-input-id",
        type_: "text",
        autoCapitalize: "words",
        autoCorrect: "off",
        autoComplete: "off",
        spellCheck: false,
        enterKeyHint: "done",
        ariaInvalid: error->Option.isSome,
        value: edit.draft,
        onChange: e => dispatch(FolderRenameChanged(inputValue(e))),
        onKeyDown: e =>
          switch JsxEvent.Keyboard.key(e) {
          | "Enter" =>
            e->JsxEvent.Keyboard.preventDefault
            if canSave {
              dispatch(FolderRenameSubmit)
            }
          | "Escape" => dispatch(FolderRenameCancel)
          | _ => ()
          },
      })}
    </Ui.Field>
    <div className="btn-row">
      <Ui.Button
        variant=Ui.Button.Primary
        testId="folder-rename-save"
        disabled={!canSave}
        onClick={_ => dispatch(FolderRenameSubmit)}
      >
        {React.string("Save")}
      </Ui.Button>
      <Ui.Button
        variant=Ui.Button.Secondary
        testId="folder-rename-cancel"
        onClick={_ => dispatch(FolderRenameCancel)}
      >
        {React.string("Cancel")}
      </Ui.Button>
    </div>
  </div>
}

// A10: one inset grouped section per folder. The root section never gets a
// header (a folder-less list is byte-for-byte the pre-A10 list); a folder's
// header is `"<display path> · <count>"` — `.list-group-header` uppercases
// it on screen, `Folder.snap` keeps the underlying spelling unique. A12b:
// while editing the header carries Rename (and Delete on an empty leaf) as
// siblings of the `<h2>`, or becomes the rename form; an empty leaf is a
// section with one "Empty folder" row; an intermediate folder is a
// header-only row (`parts-folder-header`, no container — and not
// `parts-section-header`, which stays one per real section).
let renderSection = (model: model, section: section, ~dispatch: msg => unit): React.element => {
  let key = section.path == "" ? "/" : section.path
  let editable = model.editing && section.path != ""
  let renaming = switch model.folderEdit {
  | Some(edit) if editable && edit.path == section.path => Some(edit)
  | Some(_) | None => None
  }
  let headerEl = renaming->Option.map(edit => renderFolderRename(edit, ~dispatch))
  let headerTrailing =
    editable && renaming->Option.isNone ? Some(renderFolderActions(section, ~dispatch)) : None
  switch section.kind {
  | Intermediate =>
    <section key className="list-group-section" dataTestId="parts-folder">
      {switch headerEl {
      | Some(el) => el
      | None =>
        <Ui.ListGroup.Header
          text={Folder.display(section.path)} testId="parts-folder-header" trailing=?headerTrailing
        />
      }}
    </section>
  | Parts | EmptyLeaf =>
    <Ui.ListGroup
      key
      asList=true
      header=?{section.path == ""
        ? None
        : Some(Folder.display(section.path) ++ " · " ++ Int.toString(Array.length(section.rows)))}
      headerTestId="parts-section-header"
      ?headerTrailing
      ?headerEl
      testId="parts-section"
    >
      {section.kind == EmptyLeaf
        ? <div className="list-row" role="listitem" dataTestId="parts-section-empty">
            <span className="list-row-body">
              <Ui.ListRow.Meta> {React.string("Empty folder")} </Ui.ListRow.Meta>
            </span>
          </div>
        : section.rows->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
    </Ui.ListGroup>
  }
}

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
  let sections = sectionsOf(model)
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

// A12b: with no parts at all, the empty leaf folders (a folder made in the
// picker then Cancelled; the folder the last part was deleted from) still
// show as their `· 0` sections under the empty state, so they never
// "vanish" (review S5). Edit needs a part (`actions`), so they are rename/
// delete-able again once one exists.
let renderEmptyFolders = (model: model, ~dispatch: msg => unit): React.element =>
  if !model.loaded || Array.length(model.parts) > 0 {
    React.null
  } else {
    let sections = sectionsOf(model)
    Array.length(sections) == 0
      ? React.null
      : <div className="parts-sections">
          {sections->Array.map(section => renderSection(model, section, ~dispatch))->React.array}
        </div>
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
        {renderEmptyFolders(model, ~dispatch)}
      </div>
    }}
  </div>
