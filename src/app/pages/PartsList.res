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
// folder path. A live search field filters by name or path, and one
// `PartForm` serves both create and the inline rename — editing the folder
// is how a part moves. Grouping and filtering are derived in `view` from
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
// A12b (SPEC §8a): Edit mode selects. Every part row becomes a checkbox
// row (no link, no chevron; the body is the checkbox's label, the pencil a
// sibling) and a bottom toolbar in the Shell's footer slot carries Move
// (the A12a picker, `ForMove`) and Delete (one confirm strip,
// `Store.deleteParts`) — the per-row delete and its strip are gone.
//
// A13 (SPEC §8a, docs/design/a13-drilldown-review.md): the list is a
// **folder browser** — one folder per screen (`#/` and `#/f/<path>`,
// `model.folder`), a Folders group of chevron rows over a Parts group of
// the parts sitting directly in it, Back to the parent. A folder change is
// `FolderChanged` on the *same* mounted page (Main calls it directly off
// `RouteChanged`), which keeps the loaded parts and images and clears the
// per-screen state. A10's flat sections with full-path headers survive as
// **search results** only (the query is global: every folder, whatever the
// current one). A12b's folder rename / delete moved from the section
// headers onto the subfolder rows in Edit mode, and the picker's New Folder
// capsule now also sits under the lists in the folder view.

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

// A12b: the folder rename form (A13: on a subfolder row). `error` is a
// store refusal (`Exists`), shown until the draft changes; the live
// `Folder.validateSegment` rule is derived in the view.
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
  // A10: the search field's text. Page-local; A13 clears it on every folder
  // change (`FolderChanged`) and a full route change re-inits the page.
  query: string,
  // A12a: every explicit folder path (`folder:` docs), from `FoldersLoaded`
  // after the one-shot migration and grown by what New Folder creates.
  folders: array<string>,
  // A12a: `Some` while the folder picker has taken over the page.
  picker: option<picker>,
  // A12b: the part ids checked in Edit mode. Cleared by Done, by a query
  // change, and after a move or delete lands.
  selected: array<string>,
  // A12b: the toolbar's Delete confirm strip is open.
  confirmingDelete: bool,
  // A12b: the inline folder-rename editor on one subfolder row. One inline
  // editor at a time (review S9): opening it resets `rowStates` and closes
  // the New Folder field; a row's `RenameStart` closes it.
  folderEdit: option<folderEdit>,
  // A13: the folder this screen shows (`""` = root), from the route.
  folder: string,
  // A13 (review B2): `FoldersLoaded` / `FoldersFailed` has landed. Whether
  // a folder *exists* is judged only once both loads are in — `folders` is
  // `[]` until the migration's round trips finish, one hop after
  // `PartsLoaded`, and judging earlier flashes "doesn't exist" on a reload
  // of an empty explicit folder.
  foldersLoaded: bool,
  // A13 (review S2): the folder view's New Folder draft — `Some` while its
  // field is open under the lists. The picker keeps its own.
  newFolder: option<string>,
}

type msg =
  | PartsLoaded(array<Types.part>)
  | LoadFailed(string)
  // A12a: the migration's result — every explicit folder path, plus the
  // (rare) parts whose spelling it re-snapped and re-saved.
  | FoldersLoaded(array<string>, array<Types.part>)
  | FoldersFailed(string)
  | PartImageLoaded(string, option<string>)
  // A13: the route moved to another folder while this page is mounted.
  | FolderChanged(string)
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
  // A12b: folder rename / delete (A13: on a subfolder row).
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
  // A12a / A13: the New Folder field — the picker's while it is open, the
  // folder view's otherwise.
  | NewFolderOpen
  | NewFolderChanged(string)
  | NewFolderCancel
  | NewFolderCreate
  // A17-ii: the document-level Escape (`Main.KeyPressed`); see `update`.
  | Escape
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

// A12b: one folder row's pencil — several rows carry the same
// `folder-rename` id, told apart by `data-path`.
let focusFolderRename = (path: string): Tea.cmd<msg> =>
  focusSelector(`[data-testid="folder-rename"][data-path="${path}"]`)

// A13 (review S6): a folder row's *link* — the testid sits on the row's
// outer `<div>`, the focusable element is the `<a>` inside it.
let focusFolderRowLink = (path: string): Tea.cmd<msg> =>
  focusSelector(`[data-testid="folder-row"][data-path="${path}"] a`)

// A13 (review S5): a folder change starts the new screen at the top —
// `Shell.scrollToTop` since A16, which every cross-page route change
// batches too.
let scrollToTop: Tea.cmd<msg> = Shell.scrollToTop

// "2 parts" / "1 part" — the toolbar labels, titles and live texts.
let countNoun = (n: int, noun: string): string =>
  Int.toString(n) ++ " " ++ noun ++ (n == 1 ? "" : "s")

// A13 (review S3): a folder row's meta — its *direct* children, halves
// joined with " · ", a zero half omitted: "2 parts · 1 folder", "1 part",
// "3 folders", "Empty". Never descendants (A12b's invariant survives).
let folderMeta = (~parts: int, ~folders: int): string =>
  switch (parts, folders) {
  | (0, 0) => "Empty"
  | (p, 0) => countNoun(p, "part")
  | (0, f) => countNoun(f, "folder")
  | (p, f) => countNoun(p, "part") ++ " · " ++ countNoun(f, "folder")
  }

let init = (~folder: string): (model, Tea.cmd<msg>) => (
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
    folder,
    foldersLoaded: false,
    newFolder: None,
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

// Every folder the page knows — explicit folder docs ∪ the loaded parts'
// paths ∪ their ancestors — as a depth-first flat tree. Parts' paths are
// unioned in so a folder in use is browsable before `FoldersLoaded` lands
// (and stays so should the migration fail).
let knownFolders = (model: model): array<string> =>
  Folder.tree(Array.concat(model.folders, foldersOf(model.parts)))

// A12a: what the picker lists (root aside) — the known folders plus the
// current selection. The same set is what a new folder name snaps against,
// so `interior` under `Miata` finds the existing `Interior`.
let pickerPaths = (model: model, picker: picker): array<string> =>
  Folder.tree(Array.concat(Array.concat(model.folders, foldersOf(model.parts)), [picker.selected]))

// Explicit folders after New Folder created some: docs ∪ created ∪ the
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
  // A move preselects where the parts already are: their common folder when
  // the selection shares one, else the folder being viewed (search results
  // can mix folders). So the picker shows the current location and Done with
  // nothing changed is a no-op. (A12b preselected the root — seen on the
  // phone as "None" checked while standing in Miata / Interior / Upgrades.)
  | ForMove(ids) =>
    let paths = model.parts->Array.filter(p => Array.includes(ids, p.id))->Array.map(p => p.path)
    switch paths->Array.get(0) {
    | None => model.folder
    | Some(first) => paths->Array.every(path => path == first) ? first : model.folder
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

// A13 (review S4): a folder is found by its **own** name only — never
// through an ancestor's, or `miata` would list every descendant of Miata.
let folderLeafMatches = (query: string, path: string): bool =>
  String.includes(String.toLowerCase(Folder.leaf(path)), query->String.trim->String.toLowerCase)

// ---- A13: the folder view and the search results, derived in `view` -----

// Both loads are in (review B2) — before that the body is "Loading parts…"
// and the bar carries no actions, whatever the folder.
let ready = (model: model): bool => model.loaded && model.foldersLoaded

// A folder *exists* when it is the root, or it has a doc, or any part sits
// in it or under it (`Folder.isUnder` — the half that keeps a pre-migration
// ancestor with no doc yet browsable). Exact-string: `#/f/miata` is unknown
// when the folder is `Miata` — no snap, no redirect.
let folderExists = (model: model, path: string): bool =>
  path == "" ||
  Array.includes(model.folders, path) ||
  model.parts->Array.some(p => p.path == path || Folder.isUnder(p.path, ~folder=path))

let byLeaf = (a: string, b: string): Ordering.t =>
  String.compare(String.toLowerCase(Folder.leaf(a)), String.toLowerCase(Folder.leaf(b)))

// The direct subfolders of `path`, by lower-cased leaf.
let childrenOf = (known: array<string>, path: string): array<string> =>
  known->Array.filter(p => Folder.parent(p) == path)->Array.toSorted(byLeaf)

// The parts sitting directly in `path`, in `parts` order (updatedAt desc).
let partsIn = (parts: array<Types.part>, path: string): array<Types.part> =>
  parts->Array.filter(p => p.path == path)

// What the current folder's screen lists (the query aside).
type folderView = {children: array<string>, rows: array<Types.part>}

let folderViewOf = (model: model): folderView => {
  children: childrenOf(knownFolders(model), model.folder),
  rows: partsIn(model.parts, model.folder),
}

// Edit / Done is offered while the view has something to edit (review B3),
// and Edit mode ends when a move or delete leaves it with nothing (S7).
let viewHasRows = (model: model): bool => {
  let {children, rows} = folderViewOf(model)
  Array.length(children) > 0 || Array.length(rows) > 0
}

// A13 (review S7): after `PartsMoved` / `PartsDeleted` / `FolderDeleted`,
// Edit mode stays on while the view still has rows; otherwise it resets and
// focus goes to `new-part` (the bar icon, or the empty state's capsule when
// no part is left anywhere) instead of A12b's own target.
let afterRowsLeft = (model: model, ~otherwise: string): (model, Tea.cmd<msg>) =>
  model.editing && !viewHasRows(model)
    ? ({...model, editing: false}, focusTestId("new-part"))
    : (model, focusTestId(otherwise))

// Search results (A10's shape): first the folders whose leaf matches, in
// tree order; then one flat section per folder holding the matching parts —
// root first and headerless, then folders case-insensitively, rows in
// `parts` order. Every folder, whatever the current one.
type section = {path: string, rows: array<Types.part>}
type results = {folders: array<string>, sections: array<section>}

let resultsOf = (model: model): results => {
  let folders =
    knownFolders(model)->Array.filter(p => folderLeafMatches(model.query, p))->Array.toSorted(Folder.compareTree)
  let visible = model.parts->Array.filter(part => matchesQuery(model.query, part))
  let root = partsIn(visible, "")
  let folderSections =
    foldersOf(visible)
    ->Array.toSorted((a, b) => String.compare(String.toLowerCase(a), String.toLowerCase(b)))
    ->Array.map(path => {path, rows: partsIn(visible, path)})
  {
    folders,
    sections: Array.length(root) > 0
      ? Array.concat([({path: "", rows: root}: section)], folderSections)
      : folderSections,
  }
}

let searching = (model: model): bool => String.trim(model.query) != ""

let emptyDraft: formDraft = {name: "", path: ""}

// A17-ii: the one row whose inline rename is open, if any (`rowStates` is
// absent == Normal, and one inline editor is open at a time, review S9).
let renamingRow = (model: model): option<string> =>
  model.rowStates
  ->Dict.toArray
  ->Array.find(((_, state)) =>
    switch state {
    | Renaming(_) => true
    | Normal => false
    }
  )
  ->Option.map(((id, _)) => id)

let rec update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  // SPEC §8a A17-ii: Escape, routed here from `Main.KeyPressed` by a direct
  // `update` call. Closes the first open take-over or inline editor,
  // outermost first — the picker's New Folder field, the picker, the
  // create form, the Delete confirm strip, a row's rename, the folder
  // rename, the root New Folder field — by re-entering the msg its own
  // Cancel control sends, so focus lands where that Cancel puts it. The
  // folder rename strip's own `onKeyDown` claims the key first
  // (`preventDefault`, so `WebApi.Keyboard` never dispatches it).
  | Escape =>
    switch model {
    | {picker: Some({newFolder: Some(_)})} => update(model, NewFolderCancel)
    | {picker: Some(_)} => update(model, PickerCancel)
    | {form: Some(_)} => update(model, FormCancel)
    | {confirmingDelete: true} => update(model, DeleteCancel)
    | _ =>
      switch (renamingRow(model), model.folderEdit, model.newFolder) {
      | (Some(id), _, _) => update(model, RenameCancel(id))
      | (None, Some(_), _) => update(model, FolderRenameCancel)
      | (None, None, Some(_)) => update(model, NewFolderCancel)
      | (None, None, None) => (model, Tea.none)
      }
    }
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
  // The migration only ever runs off `PartsLoaded`, so nothing else would
  // mark the folders loaded — without this the error line would sit under
  // "Loading parts…" for good.
  | LoadFailed(msg) => ({...model, loaded: true, foldersLoaded: true, error: Some(msg)}, Tea.none)
  | FoldersLoaded(folders, saved) => (
      {
        ...model,
        folders,
        foldersLoaded: true,
        parts: Array.length(saved) == 0
          ? model.parts
          : model.parts
            ->Array.map(p => saved->Array.find(s => s.id == p.id)->Option.getOr(p))
            ->Array.toSorted(byUpdatedAtDesc),
      },
      Tea.none,
    )
  // Folders then derive from the parts' paths alone; the error line shows.
  | FoldersFailed(msg) => ({...model, foldersLoaded: true, error: Some(msg)}, Tea.none)
  | PartImageLoaded(partId, Some(url)) =>
    let next = Dict.copy(model.partImages)
    Dict.set(next, partId, url)
    ({...model, partImages: next}, Tea.none)
  | PartImageLoaded(_, None) => (model, Tea.none)
  // A13 (review S5): the same page re-targeted. Kept: what was loaded
  // (`loaded`, `parts`, `error`, `partImages`, `folders`, `foldersLoaded`).
  // Cleared: everything that belongs to one screen — the form, the row and
  // folder editors, Edit mode and its selection and strip, the query, the
  // picker, the New Folder draft, the live text.
  | FolderChanged(folder) => (
      {
        ...model,
        folder,
        form: None,
        rowStates: Dict.make(),
        rowError: None,
        editing: false,
        announcement: "",
        query: "",
        picker: None,
        selected: [],
        confirmingDelete: false,
        folderEdit: None,
        newFolder: None,
      },
      scrollToTop,
    )
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
        newFolder: None,
      },
      Tea.none,
    )
  | QueryChanged(query) => ({...model, query, selected: [], confirmingDelete: false}, Tea.none)
  | QueryCleared => ({...model, query: ""}, focusTestId("parts-search"))
  // A13 (review B3): the form's Folder row starts at the folder on screen.
  | NewPartClicked => (
      {
        ...model,
        form: Some({
          draft: {...emptyDraft, path: model.folder},
          units: Types.Mm,
          error: None,
          submitting: false,
        }),
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
      // One inline editor at a time (A12b, review S9): a folder rename and
      // the New Folder field close.
      {
        ...model,
        rowStates: setRowState(model, id, Renaming(draft)),
        folderEdit: None,
        newFolder: None,
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
        // re-sorts to the top of its (possibly new) folder rather than
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
  // they re-sort to the top of their new folder; the live text counts
  // those only — moving into the current folder announces nothing. The
  // selection clears either way; Edit mode stays on while the view still
  // has rows (A13: moving everything out of a folder ends it — `PickerDone`
  // already sent focus to Move, so nothing more to do otherwise).
  | PartsMoved(moved, path) =>
    let count = Array.length(moved)
    let next = {
      ...model,
      parts: model.parts
      ->Array.map(p => moved->Array.find(m => m.id == p.id)->Option.getOr(p))
      ->Array.toSorted(byUpdatedAtDesc),
      folders: path == "" ? model.folders : withFolders(model.folders, [path]),
      selected: [],
      rowError: None,
      announcement: count == 0
        ? model.announcement
        : `Moved ${countNoun(count, "part")} to ${path == "" ? "the top level" : Folder.display(path)}`,
    }
    next.editing && !viewHasRows(next)
      ? ({...next, editing: false}, focusTestId("new-part"))
      : (next, Tea.none)
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
  // focus goes to Edit/Done, which survives while the view keeps a row;
  // with none left Edit leaves the bar (`actions`), `editing` resets, and
  // focus goes to `new-part` (A13, review S7).
  | PartsDeleted(ids) =>
    afterRowsLeft(
      {
        ...model,
        parts: model.parts->Array.filter(p => !Array.includes(ids, p.id)),
        selected: [],
        confirmingDelete: false,
        rowError: None,
        announcement: `Deleted ${countNoun(Array.length(ids), "part")}`,
      },
      ~otherwise="parts-edit",
    )
  | DeleteFailed(msg) => ({...model, confirmingDelete: false, rowError: Some(msg)}, Tea.none)
  // ---- A12b: folder rename / delete on a subfolder row ------------------
  | FolderRenameStart(path) => (
      {
        ...model,
        folderEdit: Some({path, draft: Folder.leaf(path), error: None}),
        rowStates: Dict.make(),
        newFolder: None,
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
  // line could tell) and the rows re-derive from the new spellings. The
  // renamed row is a child of the folder on screen, so `folder` itself is
  // never under `from`.
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
  | FolderDeleted(path, Ok()) =>
    afterRowsLeft(
      {
        ...model,
        folders: model.folders->Array.filter(p => p != path),
        announcement: `Deleted folder ${Folder.display(path)}`,
        rowError: None,
      },
      ~otherwise="parts-edit",
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
  // ---- A12a / A13: the New Folder field ---------------------------------
  // Under the picker's list while it is open; under the folder view's
  // lists otherwise (A13, review S2), where opening it closes any row or
  // folder rename — one inline editor at a time.
  | NewFolderOpen =>
    switch model.picker {
    | Some(_) => (
        {...model, picker: model.picker->Option.map(p => {...p, newFolder: Some("")})},
        focusTestId("folder-new-name"),
      )
    | None => (
        {...model, newFolder: Some(""), rowStates: Dict.make(), folderEdit: None, rowError: None},
        focusTestId("folder-new-name"),
      )
    }
  | NewFolderChanged(draft) =>
    switch model.picker {
    | Some(_) => (
        {...model, picker: model.picker->Option.map(p => {...p, newFolder: Some(draft)})},
        Tea.none,
      )
    | None => ({...model, newFolder: Some(draft)}, Tea.none)
    }
  | NewFolderCancel =>
    switch model.picker {
    | Some(_) => (
        {...model, picker: model.picker->Option.map(p => {...p, newFolder: None})},
        focusTestId("folder-new"),
      )
    | None => ({...model, newFolder: None}, focusTestId("folder-new"))
    }
  // `join` under the selection (the picker's, or the folder on screen),
  // `snap` against everything the page knows (so `interior` under `Miata`
  // finds the existing `Interior` instead of making a twin — prefix-wise,
  // so the result is always a direct child of the parent), then
  // `ensureFolder`. `Error` only reaches here if a submit slips past the
  // disabled Create; the depth cap disables the capsule before the field
  // can even open.
  | NewFolderCreate =>
    let create = (~parent: string, ~draft: string, ~existing: array<string>) =>
      switch Folder.validateSegment(draft) {
      | Error(_) => (model, Tea.none)
      | Ok(name) =>
        let path = Folder.snap(Folder.join(~parent, ~name), ~existing)
        (
          model,
          Tea.fromPromise(
            () => Store.ensureFolder(store(), ~path),
            created => NewFolderCreated(path, created),
            e => NewFolderFailed(describeError(e)),
          ),
        )
      }
    switch (model.picker, model.newFolder) {
    | (Some({selected, newFolder: Some(draft)} as picker), _)
      if Folder.depth(selected) < Folder.maxDepth =>
      create(~parent=selected, ~draft, ~existing=pickerPaths(model, picker))
    | (None, Some(draft)) if Folder.depth(model.folder) < Folder.maxDepth =>
      create(~parent=model.folder, ~draft, ~existing=knownFolders(model))
    | _ => (model, Tea.none)
    }
  // The created (or snapped-onto) folder becomes the picker's selection and
  // its option takes focus; in the folder view the field closes and focus
  // lands on the new row — its link, or its pencil in Edit mode (review
  // S6). It is a real folder from here on — Cancelling the picker
  // afterwards does not undo it.
  | NewFolderCreated(path, created) =>
    let folders = withFolders(model.folders, Array.concat(created, [path]))
    switch model.picker {
    | Some(_) => (
        {
          ...model,
          folders,
          picker: model.picker->Option.map(p => {...p, selected: path, newFolder: None}),
          rowError: None,
        },
        focusFolderOption(path),
      )
    | None => (
        {...model, folders, newFolder: None, rowError: None},
        model.editing ? focusFolderRename(path) : focusFolderRowLink(path),
      )
    }
  | NewFolderFailed(msg) => ({...model, rowError: Some(msg)}, Tea.none)
  }

// A12a (review B3): while the picker is open the bar carries a centred
// Headline "Choose Folder" between Cancel and Done, the HIG picker shape;
// otherwise the root's static Large Title "Parts" — or, in a folder (A13,
// review S1), the centred Headline of the folder's leaf name over its
// parent path, every other pushed screen's shape.
let title = (model: model): string =>
  switch model.picker {
  | Some({target: ForMove(ids)}) => `Move ${countNoun(Array.length(ids), "Part")}`
  | Some(_) => "Choose Folder"
  | None => model.folder == "" ? "Parts" : Folder.leaf(model.folder)
  }
let largeTitle = (model: model): bool => model.picker->Option.isNone && model.folder == ""

// SPEC §8a A17 (review S2): the Shell's reading column at medium and
// expanded — the create form and the folder picker take the narrow one
// (560), the list itself the 720 column. `Main.view` maps it beside
// `largeTitle`; compact ignores it.
let column = (model: model): Shell.column =>
  model.picker->Option.isSome || model.form->Option.isSome ? Shell.Narrow : Shell.Column

// A13: Back to the parent folder — or to the root from a folder that
// doesn't exist. None at the root, and none while the picker is open (its
// leading slot is Cancel, and `Shell` renders Back over `leading`).
let back = (model: model): option<Route.t> =>
  switch model.picker {
  | Some(_) => None
  | None if model.folder == "" => None
  | None =>
    Some(
      Route.Parts(
        ready(model) && !folderExists(model, model.folder) ? "" : Folder.parent(model.folder),
      ),
    )
  }

let subtitle = (model: model): option<string> =>
  switch model.picker {
  | Some(_) => None
  | None =>
    let parent = Folder.parent(model.folder)
    model.folder != "" && parent != "" ? Some(Folder.display(parent)) : None
  }

// Bar leading slot. Normally the gear: Settings and Debug have no other way
// in from an installed app (no URL bar), so the Parts root carries one bar
// button on the root (HIG); Settings then links on to Debug — in a folder
// `Shell` shows Back instead and drops this slot (A13). While the picker is
// open it is a Cancel text action — `Shell.back` can only push a route,
// and cancelling is a page message.
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

// Bar trailing actions (DESIGN.md §11.2, review-2026-09-17.md P1/P3), per
// view (A13, review B3): **Edit / Done** while the folder on screen has a
// part row or a folder row, exists, and neither the create form nor the
// picker is open; **"+"** while the folder exists and no form is open — the
// bar icon while any part exists anywhere, else the empty state's own body
// capsule (`renderEmptyCapsule`). `new-part` only ever exists once on
// screen at a time, which is what keeps `getByTestId('new-part')` a
// single-element (Playwright strict-mode) match either way. Nothing before
// both loads are in, and nothing in a folder that doesn't exist.
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
    let known = ready(model) && folderExists(model, model.folder) && model.form->Option.isNone
    let editable = known && viewHasRows(model)
    let addable = known && Array.length(model.parts) > 0
    editable || addable
      ? Some(
        <>
          {editable
            ? <Ui.Button
                variant=Ui.Button.Plain
                className="bar-action"
                testId="parts-edit"
                onClick={_ => dispatch(EditToggled)}>
                {React.string(model.editing ? "Done" : "Edit")}
              </Ui.Button>
            : React.null}
          {addable
            ? <Ui.Button
                variant=Ui.Button.Icon
                testId="new-part"
                ariaLabel="New part"
                onClick={_ => dispatch(NewPartClicked)}>
                <Icon name=Plus size=22 />
              </Ui.Button>
            : React.null}
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

// A16: `.parts-form` is the create form's outermost element — the take-over
// that rises on mount (`cc-rise`, PartsList.css). The rename strip renders
// the same `PartForm.view` inside a list row and does not get the wrapper:
// nothing inside a `.list-group` gets a transform (the group clips overflow).
let renderForm = (form: createForm, ~dispatch: msg => unit): React.element =>
  <div className="parts-form">
    {PartForm.view(
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
  )}
  </div>

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
  // so picking a Folder here is how a part moves between folders.
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

// A12b: a folder row's Rename/Delete icon buttons carry `data-path`, so a
// focus cmd (and a test) can find *this* folder's — every row shows the
// same `folder-rename` id. `JsxDOM.domProps` can't express a data
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

// A13: a folder row's outer `<div role="listitem">`, which carries
// `data-testid="folder-row"` and `data-path` — the same jsx-runtime route
// as `PathButton`, for the same reason.
module PathDiv = {
  type props = {
    className: string,
    role: string,
    @as("data-testid") dataTestId: string,
    @as("data-path") dataPath: string,
    children: React.element,
  }

  @module("react/jsx-runtime") external jsxKeyed: (string, props, string) => React.element = "jsx"

  let make = (~key: string, props: props): React.element => jsxKeyed("div", props, key)
}

// A12b (A13: on the subfolder row): the trailing controls while editing —
// Rename on every folder, Delete only on an empty leaf (no parts, no
// subfolders: the one case `deleteFolder` never refuses, so no confirm).
let renderFolderActions = (~path: string, ~deletable: bool, ~dispatch: msg => unit): React.element => <>
  {PathButton.make({
    type_: "button",
    className: "btn btn-icon",
    dataTestId: "folder-rename",
    dataPath: path,
    ariaLabel: "Rename folder",
    onClick: _ => dispatch(FolderRenameStart(path)),
    children: <Icon name=Pencil size=20 />,
  })}
  {deletable
    ? PathButton.make({
        type_: "button",
        className: "btn btn-icon",
        dataTestId: "folder-delete",
        dataPath: path,
        ariaLabel: "Delete folder",
        onClick: _ => dispatch(FolderDeleteClicked(path)),
        children: <Icon name=Trash size=20 />,
      })
    : React.null}
</>

// A12b: the row as an inline one-segment form — the leaf name prefilled,
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
          | "Escape" =>
            // A17-ii: claim the key so the document listener
            // (`WebApi.Keyboard` → `Main.KeyPressed`) stands down.
            e->JsxEvent.Keyboard.preventDefault
            dispatch(FolderRenameCancel)
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

// A13: a folder row. The folder glyph leads; the body is the leaf name over
// `meta` (direct-child counts in the folder view, the location in search
// results). Outside Edit mode the body and chevron are a real `<a>` to the
// folder's own route — `Ui.ListRow ~href`'s shape, hand-rolled only because
// the outer `<div>` needs `data-path` (`PathDiv`). While editing (folder
// view only; result rows stay plain links) it is a plain listitem with
// Rename and, on an empty leaf, Delete trailing — never a checkbox (folders
// are not selectable in v1) — or the inline rename form in its place.
let folderGlyph = <span className="folder-row-glyph" ariaHidden=true> <Icon name=Folder size=28 /> </span>

let renderFolderLink = (~path: string, ~meta: string): React.element =>
  PathDiv.make(
    ~key=path,
    {
      className: "list-row",
      role: "listitem",
      dataTestId: "folder-row",
      dataPath: path,
      children: <>
        folderGlyph
        <a className="list-row-link" href={Route.href(Route.Parts(path))}>
          <span className="list-row-body">
            <Ui.ListRow.Title> {React.string(Folder.leaf(path))} </Ui.ListRow.Title>
            <Ui.ListRow.Meta> {React.string(meta)} </Ui.ListRow.Meta>
          </span>
          <span className="list-row-chevron"> <Icon name=ChevronRight size=20 /> </span>
        </a>
      </>,
    },
  )

let renderFolderEditRow = (
  model: model,
  ~path: string,
  ~meta: string,
  ~deletable: bool,
  ~dispatch: msg => unit,
): React.element =>
  PathDiv.make(
    ~key=path,
    {
      className: "list-row",
      role: "listitem",
      dataTestId: "folder-row",
      dataPath: path,
      children: switch model.folderEdit {
      | Some(edit) if edit.path == path =>
        <div className="folder-row-edit"> {renderFolderRename(edit, ~dispatch)} </div>
      | Some(_) | None =>
        <>
          folderGlyph
          <span className="list-row-body">
            <Ui.ListRow.Title> {React.string(Folder.leaf(path))} </Ui.ListRow.Title>
            <Ui.ListRow.Meta> {React.string(meta)} </Ui.ListRow.Meta>
          </span>
          <span className="list-row-trailing">
            {renderFolderActions(~path, ~deletable, ~dispatch)}
          </span>
        </>
      },
    },
  )

// The two groups of the folder view. Each carries its header only when the
// other renders too — alone, the group needs no label. The header is
// `headerHidden` (A14 G5, "fewer words"): the rows say what they are (folder
// glyph vs thumbnail), so the label is for the accessibility tree only — it
// keeps the two adjacent lists named for VoiceOver and every e2e heading
// count as it was.
let renderFoldersGroup = (~header: bool, rows: array<React.element>): React.element =>
  <Ui.ListGroup
    asList=true header=?{header ? Some("Folders") : None} headerHidden=true testId="folders-list">
    {React.array(rows)}
  </Ui.ListGroup>

let renderPartsGroup = (~header: bool, rows: array<React.element>): React.element =>
  <Ui.ListGroup
    asList=true header=?{header ? Some("Parts") : None} headerHidden=true testId="parts-list">
    {React.array(rows)}
  </Ui.ListGroup>

// A10: a plain 17 px search field under the title — on the web that's the
// honest equivalent of HIG's nav-bar search (review N5). Live filter across
// every folder (A13). `global.css`'s `-webkit-appearance: none` strips
// WebKit's native cancel button along with the rest of the chrome, so the
// page supplies its own (`parts-search-clear`) while there is something to
// clear; clearing returns focus to the field.
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

// Search results (A13): A10's shape — a Folders section of the folders
// whose leaf matches (meta = where it lives), then one flat section per
// folder with a full-path header (root first and headerless), the part rows
// as they are in the folder view (A12b's checkbox rows while editing);
// folder rows here are plain links. Nothing at all → the one Footnote.
let renderResults = (model: model, ~dispatch: msg => unit): React.element => {
  let {folders, sections} = resultsOf(model)
  if Array.length(folders) == 0 && Array.length(sections) == 0 {
    <p className="t-footnote muted" dataTestId="parts-search-empty">
      {React.string(`No parts match "${String.trim(model.query)}".`)}
    </p>
  } else {
    let location = (path: string): string => {
      let parent = Folder.parent(path)
      parent == "" ? "Top level" : Folder.display(parent)
    }
    <div className="parts-sections">
      {Array.length(folders) == 0
        ? React.null
        : renderFoldersGroup(
            ~header=true,
            folders->Array.map(path => renderFolderLink(~path, ~meta=location(path))),
          )}
      {sections
      ->Array.map(section =>
        <Ui.ListGroup
          key={section.path == "" ? "/" : section.path}
          asList=true
          header=?{section.path == ""
            ? None
            : Some(Folder.display(section.path) ++ " · " ++ Int.toString(Array.length(section.rows)))}
          headerTestId="parts-section-header"
          testId="parts-section"
        >
          {section.rows->Array.map(part => renderRow(model, part, ~dispatch))->React.array}
        </Ui.ListGroup>
      )
      ->React.array}
    </div>
  }
}

// Under the lists: a secondary New Folder capsule that reveals an inline
// one-segment field (`Folder.validateSegment` live: Create disabled while
// invalid or empty, the rule inline once there is something to judge), or
// — at six deep already — the capsule disabled with a Footnote saying why.
// `selected` is the parent the new folder nests under (the picker's
// selection, or the folder on screen); `draft` is whichever New Folder
// draft the caller owns (A13, review S2).
let renderNewFolder = (~selected: string, ~draft: option<string>, ~dispatch: msg => unit): React.element => {
  let maxed = Folder.depth(selected) >= Folder.maxDepth
  switch draft {
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

// DESIGN.md §7 / §11.2: "one line of copy … and the primary button; no
// illustration" — the empty state's own capsule, while no part exists
// anywhere. Once one does, "+" lives in the bar instead (`actions` above,
// P3); this stops rendering entirely then, rather than becoming a second,
// redundant "New part" affordance under the list.
let renderEmptyCapsule = (model: model, ~dispatch: msg => unit): React.element =>
  Array.length(model.parts) > 0
    ? React.null
    : <Ui.Button
        variant=Ui.Button.Primary
        block=true
        testId="new-part"
        onClick={_ => dispatch(NewPartClicked)}>
        {React.string("New part")}
      </Ui.Button>

// A13: one folder's screen. Order: at the root with no part anywhere, A10's
// empty-state copy and its capsule; the Folders group (direct subfolders,
// chevron rows, direct-count meta; Rename/Delete trailing while editing);
// the Parts group (the parts sitting directly here, `updatedAt` desc); a
// folder with neither says "Empty folder"; a non-root folder with no part
// anywhere gets the capsule after that; then the New Folder capsule.
let renderFolder = (model: model, ~dispatch: msg => unit): React.element => {
  let known = knownFolders(model)
  let {children, rows} = folderViewOf(model)
  let isRoot = model.folder == ""
  let both = Array.length(children) > 0 && Array.length(rows) > 0
  let noParts = Array.length(model.parts) == 0
  let folderRows = children->Array.map(child => {
    let parts = Array.length(partsIn(model.parts, child))
    let folders = Array.length(childrenOf(known, child))
    let meta = folderMeta(~parts, ~folders)
    model.editing
      ? renderFolderEditRow(model, ~path=child, ~meta, ~deletable=parts == 0 && folders == 0, ~dispatch)
      : renderFolderLink(~path=child, ~meta)
  })
  <>
    {isRoot && noParts
      ? <div className="parts-empty" dataTestId="parts-empty">
          <p className="t-footnote muted">
            {React.string("No parts yet. A part is a set of photographed faces.")}
          </p>
        </div>
      : React.null}
    {isRoot ? renderEmptyCapsule(model, ~dispatch) : React.null}
    {Array.length(children) == 0 && Array.length(rows) == 0
      ? isRoot
          ? React.null
          : <p className="t-footnote muted" dataTestId="folder-empty">
              {React.string("Empty folder")}
            </p>
      : <div className="parts-sections">
          {Array.length(children) == 0 ? React.null : renderFoldersGroup(~header=both, folderRows)}
          {Array.length(rows) == 0
            ? React.null
            : renderPartsGroup(~header=both, rows->Array.map(part => renderRow(model, part, ~dispatch)))}
        </div>}
    {isRoot ? React.null : renderEmptyCapsule(model, ~dispatch)}
    {renderNewFolder(~selected=model.folder, ~draft=model.newFolder, ~dispatch)}
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
    {renderNewFolder(~selected=picker.selected, ~draft=picker.newFolder, ~dispatch)}
  </div>

// `.parts-page` scopes PartsList.css's 72 px thumbnail override to this
// page's rows only — `Ui.ListThumb`/`.list-thumb` (global.css) is also used
// by Part.res's face-edit list at its own 52 px, and CSS here is unscoped
// app-wide (see PartsList.css), so an unscoped override would leak there.
//
// A13: the body is "Loading parts…" until both loads are in, then the
// unknown-folder Footnote (no search, no capsule — the bar's Back leads to
// the root), else the search field (whenever any part or folder exists
// anywhere) over the results while a query is active or the folder itself.
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
        {if !ready(model) {
          <p className="t-footnote muted"> {React.string("Loading parts…")} </p>
        } else if !folderExists(model, model.folder) {
          <p className="t-footnote muted" dataTestId="folder-missing">
            {React.string("This folder doesn't exist.")}
          </p>
        } else {
          let anyContent =
            Array.length(model.parts) > 0 || Array.length(knownFolders(model)) > 0
          <>
            {anyContent ? renderSearch(model, ~dispatch) : React.null}
            {searching(model) ? renderResults(model, ~dispatch) : renderFolder(model, ~dispatch)}
          </>
        }}
      </div>
    }}
  </div>
