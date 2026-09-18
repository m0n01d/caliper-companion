# SPEC §8a A13 (Drill-down folder browsing) — pre-build review, 2026-09-18, commit `e926abd`

**Verdict: BUILD WITH EDITS.** The shape is right — route per folder, one page that re-targets on
`hashchange`, flat sections kept for search only, A12b's editors moved from section headers to
folder rows. Five things in the text are wrong against the code as it stands and would ship as a
crash, a flash, a stuck toolbar, a hung screenshot tour or a silently-passing test; nine more leave
the builder inventing state. Paste-ready text is in §4; the e2e rewrite list the spec defers to
"the reviewer" is §5. Read the A12 review first — its S5 (leaf-empty sections), S8 (delete focus)
and S10 (state paragraph) are what A13 rewrites.

## 1. Findings

| # | Sev | Finding | Recommendation | Evidence |
|---|---|---|---|---|
| B1 | blocker | Route bullet: `parse`: `["f", ...segs]` and `decodeURIComponent`. (a) Array spread in a pattern is a **syntax error** in ReScript 12.3.1 (compile-checked: "Array spread (`...`) is not supported in pattern matches"). (b) No `encodeURIComponent` / `decodeURIComponent` binding exists anywhere in `src/` (grep: none; `WebApi.Location` has `hash`/`setHash` only), and CLAUDE.md forbids `%raw`/`@val` shortcuts. (c) `decodeURIComponent` **throws** `URIError` on a malformed sequence (`#/f/%E0`), and `parse` runs inside the `hashchange` listener (Route.res:60-63) — an uncaught throw there kills routing for the session. | `WebApi.Uri` module: `@val external encodeComponent: string => string = "encodeURIComponent"`, same for decode. `parse`: `switch segs[0] { \| Some("f") => Parts(decodeAll(segs->Array.sliceToEnd(~start=1))) \| … }` where `decodeAll` maps decode inside `try … catch { \| JsExn(_) => None }` and `None` → `Parts("")` (the file's own "malformed → parts list" rule, :36-37). `#/f` and `#/f/` → `Parts("")`. | Route.res:31-47, :60-63; WebApi.res:39-45; scratch compile with `node_modules/.bin/bsc` |
| B2 | blocker | "Unknown folder (no doc and no part in or under it)" is decided from `model.folders`, which is `[]` from `init` until the one-shot migration's `FoldersLoaded` lands — one `listFolders` + `ensureFolders` + `listFolders` round trip **after** `PartsLoaded`. A reload on `#/f/Archive` (an explicit empty folder: no part under it) renders `folder-missing` first, then flips to the folder. Playwright assertions retry, so a `folder-missing` `toHaveCount(0)` after reload passes or fails on timing. | Add `foldersLoaded: bool` to the model, set by `FoldersLoaded` **and** `FoldersFailed` (the error line already shows; folders then derive from part paths). The folder view renders "Loading parts…" until `loaded && foldersLoaded`; "unknown" is judged only after both. Define *exists* (§4 B2). | PartsList.res:275-296, :364-394, :501-524 |
| B3 | blocker | "Trailing actions unchanged" + "no '+' in an unknown folder". `actions` gates Edit **and** "+" on the global `Array.length(model.parts) > 0`, and `renderEmptyCapsule` renders a "New part" capsule wherever `parts == []`. In a folder view as written: Edit shows in an unknown folder and in a folder with nothing in it; with zero parts anywhere a folder made in the picker can be renamed/deleted nowhere (no Edit); the capsule's `NewPartClicked` opens the form at `emptyDraft` (path `""`), not the current folder. | Per-view predicates (§4 B3): Edit iff the view has ≥ 1 part row or folder row, known, no form/picker; "+" (bar or capsule) iff known and no form; `NewPartClicked` presets `draft.path = model.folder`. | PartsList.res:984-1017, :545-551, :1720-1731 |
| B4 | blocker | "Edit is unavailable while a query is active (the Edit action hidden, the toolbar absent)". `footer` renders the toolbar from `editing` alone; `QueryChanged` keeps `editing` as is. Hiding the action without resetting `editing` leaves a sticky toolbar with no Done to dismiss it; resetting it throws away the A12b flow "search → select → Move" that the management test drives today. | Keep Edit available in search results: part rows in the flat sections are selectable as A12b, section headers carry **no** editors any more (they move to folder rows), folder rows in results are plain. `QueryChanged` stays as built (clears the selection only). Drop the "unavailable" sentence. | PartsList.res:543, :1079-1082; parts.spec.js:432-460 |
| B5 | blocker | Screenshot tour: the spec re-labels `12-parts-list` and adds 16/17, but steps 14 and 15 stop resolving — `part-select.nth(1)` / `.nth(2)` run at the root, where only Norcold lives after A13 (one checkbox → `.check()` waits forever), and `folder-rename[data-path="Miata/Interior"]` is on the Interior row inside `#/f/Miata`, not at root. Shot 12 is also taken (:104) *before* any folder exists (:122-146). | Reorder (§4 B5): seed first, then 12 at `#/`, 16 in `#/f/Miata/Interior`, 14 there in Edit with two checked, 15 in `#/f/Miata` renaming Interior, 17 back at `#/` with query `clip`. | screenshot-tour.mjs:104, :122-153 |
| S1 | should | Bar in a folder: static Large Title = leaf. hig-brief puts a large title at the root only ("every pushed screen below it gets a small title", Do #2) and DESIGN §11.1 says the same; the Shell's large title is static (`.shell-large-title` in the content flow, no collapse), so a subfolder two taps deep spends 60 px on a title that never gets out of the way; and the Part page — the screen Back returns *from* — already uses Headline + folder-path subtitle. | Folders use the centred **Headline** (`largeTitle = picker == None && folder == ""`): title = leaf, subtitle = parent display path, Back chevron. Same `.shell-title` locator either way. If the owner wants Files' look instead, keep the spec but amend DESIGN §11.1's "Parts root shows a static Large Title". | hig-brief.md:141, :294; DESIGN.md:186; Shell.res:49-54, :63-68; Part.res:188-205 |
| S2 | should | New Folder as "the last row of the Folders group" inside `folders-list` (`role="list"`): a button announced as a list item, and a lone "New Folder" row on every leaf-folder screen (most screens on a ≤ 50-part list). The spec also reuses "the inline field from A12's picker", but `renderNewFolder` takes a `picker` and the draft lives in `picker.newFolder` — there is no picker in the folder view. | Reuse the A12a **secondary capsule** `folder-new` (+ field, same ids) **under** the Parts group, present in the folder view whenever the query is blank (Edit mode too). Model gains `newFolder: option<string>`; `renderNewFolder` takes `(~selected, ~draft)` and both call sites pass theirs. One inline editor at a time (opening it resets `rowStates`/`folderEdit`; a rename closes it). Reminders' "Add List" / Notes' "New Folder" are bottom buttons, not rows. | PartsList.res:66-71, :1633-1699, :878-881 |
| S3 | should | Folder-row meta undefined for the plural/singular cases and for search results, where a flat list of leaves needs a location, not counts. | Direct children only (Files). `countNoun`: "2 parts · 1 folder", "1 part", "3 folders", "Empty". In search results the meta is the location: `Folder.display(parent)` or "Top level". | PartsList.res:272-273 |
| S4 | should | "matching folders" in the search Folders section: with A12b's `folderMatchesQuery` (stored *and* display path) the query `miata` lists `Miata`, `Miata/Interior` and `Miata/Interior/Dashboard` — every descendant, via its ancestor. | Folder rows match on the **leaf name** only (a folder is found by its own name); parts keep A10's name-or-path match, so "everything in Miata" is still one query. Order: `Folder.compareTree`. | PartsList.res:455-460 |
| S5 | should | `FolderChanged` says which state is kept/cleared in prose; the model has 15 fields and A13 adds three. Also "Main dispatches" — as a cmd it would be async and render one frame at the old folder. | `Main.update(RouteChanged(Parts(p)))` with `page = PartsList(m)` calls `PartsList.update(m, FolderChanged(p))` **directly**, sets `route`, maps the cmd. Field table in §4 S5. Scroll reset: `Canvas` gains `@set external setScrollTop: (Dom.element, int) => unit = "scrollTop"` (no setter exists) on `querySelector(".shell")` — `.shell` is the scroll container. | Main.res:57-63; PartsList.res:82-121; Canvas.res:62, :237-239; global.css:125-133 |
| S6 | should | "the new row appears and takes focus": `Ui.ListRow ~href` puts `data-testid` on the outer `<div role="listitem">`; the focusable element is the `<a>` inside. `focusSelector('[data-testid="folder-row"][data-path=…]')` focuses nothing. | Focus `[data-testid="folder-row"][data-path="<p>"] a` outside Edit mode; in Edit mode (no link) focus that row's `folder-rename`. Same for `a11y`: "inside a folder the first Tab lands on Back" holds (Back is first in DOM). | Ui.res:264-268; PartsList.res:248-269 |
| S7 | should | Edit-mode exit: A12b resets `editing` only when **no parts remain anywhere** (`PartsDeleted`). In a folder, moving or deleting everything leaves Edit on over an empty view with a toolbar whose buttons can never enable. | `editing` resets (and focus goes to `new-part`) when the current view has no part rows and no folder rows after a move or delete; otherwise focus as A12b (`parts-move` / `parts-edit`). | PartsList.res:672-691, :713-727 |
| S8 | should | `Route` has no unit test (`src/**/tests/` has none named for it; nothing references `Route`), and A13 gives it real parsing for the first time. | `src/app/tests/RouteTest.res`, tabled: `toHash → parse` round-trip for `""`, `Miata`, `Miata/Interior`, `Miata (NB)/v2.1/Dwight's` (`%20`, `(`, `'`), `A&B+C`; `parse` of `#/f`, `#/f/`, `#/f/Miata/`, `#/f/%20Miata%20//x` → `Miata/x`, `#/f/%E0` → `Parts("")`, `#/parts/x` unchanged. | Route.res |
| S9 | should | Docs the spec names only by section: the sentences that are now false are enumerable. | §4 S9 lists DESIGN.md and testids.md lines. | DESIGN.md:186, :195; testids.md:6-16, :44-80 |
| S10 | should | The e2e list is deferred to "the reviewer enumerates". A build agent will otherwise guess which A10/A12 assertions to keep. | Paste §5 into the spec's last bullet. | SPEC.md:779-782 |
| N1 | nit | `Parts(string)` vs `Parts(option<string>)` / a `?f=` query. | Keep `string`; `#/f/<segs>` mirrors `#/parts/<id>` and `Route.segments` already splits on `/`. `""` is root everywhere in `Folder`. | Route.res:31-34 |
| N2 | nit | `#/f/miata` (wrong case) — exists? | No: exact-string, like grouping. Renders `folder-missing`. Say so; no snap, no redirect. | Folder.res:120-137 |
| N3 | nit | Meta "n parts · m folders" vs body order (Folders group first). | Keep the spec's order — it reads as a sentence. | — |
| N4 | nit | `Part.res:548` and `Capture.res:998` render "Back to parts" links, `Settings.back`, `Debug.back`. | All `Route.Parts("")`; only `Part.back` reads the path. `PartsList.back` returns `Some(Parts(parent))` in a folder — `Shell` then hides `leading`, so the gear is root-only for free. | Part.res:193, :548; Capture.res:998; Shell.res:33-46 |
| N5 | nit | Move picker in a folder: exclude the current folder / preselect it? | Neither. Parts have no descendants; `ForMove` preselects root (A12b) and a same-folder move is A12b's silent no-op. Preselecting the current folder would make Done a no-op by default. | PartsList.res:417-427, :672-691 |

## 2. Judgements asked for

1. **Route shape: `#/f/<seg>/<seg>`, per-segment encode, `Parts("")` root — yes** (N1), with B1's
   fixes. Round-trip holds for stored paths: a validated segment has no leading/trailing/doubled
   whitespace and no `/`, so `normalize` is the identity on it and `toHash(parse(h)) == h` for
   every `h` the app emits. A hand-typed `#/f/%20Miata%20` parses to `Miata` and the bar keeps
   the typed spelling until the next push — harmless. A `%2F` typed inside a segment becomes a
   separator after `normalize` (extra depth → unknown folder) — harmless. `_ => Parts` fallback is
   unaffected because `["f", …]` is matched first.
2. **`FolderChanged` instead of re-init: yes, cleanly.** `hashchange` is the only source of
   `RouteChanged` (push and browser Back/Forward alike, Route.res:60-63), so one branch in
   `Main.update` covers both. Field table in §4 S5.
3. **Bar: Headline in a folder** (S1). Back stays a chevron (DESIGN §11.1, hig-brief:146); the
   subtitle carries the parent path, which is what a labelled back button would have said.
4. **Counts: direct children** (S3), Files' rule; the A12b "never descendants" invariant survives.
5. **Search: global, flat A10 sections — yes.** One user, ≤ 50 parts: a scope toggle is a control
   nobody would flip. Folder rows match on leaf name (S4). Edit stays available (B4).
6. **New Folder: the A12a capsule under the lists** (S2), not a row, not a bar action (the bar has
   Edit + "+" already; a third control at 390 px crowds a Headline title), not Edit-only (a folder
   should be creatable before its first part without hunting). "+" preset to the current folder is
   right; picking another folder in the form is fine — `Part.back` lands wherever the part went.
   "+" hidden in an unknown folder: consistent once B3's predicates replace the global gate.
7. **Edit mode: folders not selectable — acceptable for v1** (moving a folder is A12's stated gap).
   No picker exclusion needed (N5). Moving parts into the folder you are viewing is the A12b
   no-op. Moving them *out* removes the rows; S7 says what happens when the view empties.
8. **Unknown folder: render, never redirect — agreed**, once B2 waits for both loads. *Exists* =
   root, or a folder doc, or any part whose `path` equals or is under it (`Folder.isUnder`) — the
   `isUnder` half is what keeps a pre-migration ancestor (part path only, no doc yet) browsable.
9. **Retirements:** §5 and §4 S9.
10. **Scope: one agent, one wave.** `sectionsOf` / `renderSection` / `renderList` are one
    replacement; every cut leaves A12b's header-editor tests half-broken mid-track. If it must
    split: A13a = B1/S5 routing + folder view + search + New Folder + `Part.back`, with Edit mode
    offering part selection/Move/Delete only and the three A12b management tests `test.fixme`;
    A13b = folder-row rename/delete + those tests + tour 14/15. Serial.
11. **Gaps:** B2 (`foldersLoaded`), B3 (predicates), S2 (`newFolder` state), S3/S4 (strings,
    match rule), S5 (field table, direct call, scroll setter), S6 (focus targets), S7 (exit rule),
    plus: `folders-list` and `parts-list` are `Ui.ListGroup asList=true` with `header` "Folders" /
    "Parts" only when both groups render; `folder-row` outside Edit mode is `Ui.ListRow` with
    `href={Route.href(Parts(child))}` (a real link, like `part-row`), `chevron=true`, leading
    `Icon.Folder`; in Edit mode a plain `<div class="list-row" role="listitem">` with the pencil
    and (empty leaf only) trash trailing, `data-path` on the row and both buttons — never a
    checkbox; ordering: folder rows by lower-cased leaf, part rows `updatedAt` desc; empty texts:
    "Empty folder" (`folder-empty`), "This folder doesn't exist." (`folder-missing`), the A10
    `parts-empty` copy only at root with zero parts *and* zero folders — root with folders but no
    parts shows the copy, the capsule, then the Folders group; live region gains nothing (a focus
    move announces the new row); after `folder-delete` on a row focus → `parts-edit`; after a
    rename → that row's `folder-rename` (`focusFolderRename` already targets by `data-path`).

## 3. Verdict

**Build with edits.** Apply B1–B5 and S1–S10 to the spec text before dispatch; N1–N5 are one
sentence each. Model: sonnet from the edited spec (mechanical from a tight contract), but the
reviewer of the diff should inherit — the e2e rewrite in §5 is where a cheap agent will cut corners.

## 4. Spec edits (paste over the matching A13 text)

**B1 — Route bullet, replace the `parse` sentence:**
> `WebApi.Uri` (new): `encodeComponent` / `decodeComponent` bindings. `toHash(Parts(""))` = `#/`;
> `toHash(Parts(p))` = `"#/f/" ++ segments(p)->map(encodeComponent)->join("/")`. `parse`: when
> `segs[0] == Some("f")`, decode each of `segs->Array.sliceToEnd(~start=1)` inside a `try`; any
> `JsExn` (a malformed `%` sequence) → `Parts("")`; else `Parts(Folder.normalize(decoded->join("/")))`,
> so `#/f`, `#/f/` and `#/f/Miata/` are `Parts("")`, `Parts("")`, `Parts("Miata")`. Array spread
> is not a pattern in ReScript — index and slice. `src/app/tests/RouteTest.res` (tabled) covers the
> round-trip for `Miata (NB)/v2.1/Dwight's` and `A&B+C`, the three shapes above, `%E0` and
> `#/parts/x`.

**B2 — model + unknown folder:**
> Model gains `folder: string` (from the route), `foldersLoaded: bool` (set by `FoldersLoaded` and
> `FoldersFailed`) and `newFolder: option<string>`. The folder view renders "Loading parts…" until
> `loaded && foldersLoaded`. A folder **exists** when it is the root, or `model.folders` holds it,
> or any part's `path` equals it or `Folder.isUnder` it (pre-migration ancestors). Otherwise the
> view is `folder-missing` ("This folder doesn't exist."), no capsule, no "+", no Edit, Back to
> root. Exact-string: `#/f/miata` is unknown when the folder is `Miata`.

**B3 — bar actions, replace "Trailing actions unchanged …":**
> Trailing actions: **Edit / Done** iff the view has ≥ 1 part row or folder row, the folder
> exists, and no form or picker is open; **"+"** iff the folder exists and no form is open (the
> bar icon while any part exists, else the empty-state capsule — still exactly one `new-part`).
> `NewPartClicked` presets `draft.path = model.folder`; the form's Folder row shows it.

**B4 — Search bullet, replace the last sentence:**
> Edit stays available while a query is active: the flat sections' part rows are A12b's checkbox
> rows and the toolbar works on them; section headers carry no editors (rename/delete live on
> folder rows in the folder view); folder rows in results are plain links. `QueryChanged` keeps
> clearing the selection and the confirm strip.

**B5 — Screenshot tour:**
> Seed as today (13 stays where it is), then: `#/` → `12-parts-list` (Norcold at root, folder rows
> Archive and Miata); `#/f/Miata/Interior` → `16-parts-folder`; Edit, check both → `14-parts-edit-
> toolbar`; Done; `#/f/Miata` → Edit → `folder-rename[data-path="Miata/Interior"]` →
> `15-folder-rename`; `#/` → query `clip` → `17-parts-search`.

**S1 — Bar bullet:**
> In a folder the bar is the centred Headline `Folder.leaf(path)` with subtitle
> `Folder.display(Folder.parent(path))` (none when the parent is root); `largeTitle` is true only
> at root with no picker; `back = Some(Parts(parent))` (Shell then drops the gear).

**S2 — New Folder bullet:**
> Under the Parts group, outside search: A12a's secondary capsule `folder-new` revealing the same
> field (`folder-new-name` / `-create` / `-cancel` / `-error`, `newFolder` on the model;
> `renderNewFolder` takes `~selected` and `~draft`). Create = `join(current, name)` → `snap`
> against the current folder's children → `ensureFolder` → `folders` grows, the field closes, focus
> lands on the new `folder-row`'s link (`[data-testid="folder-row"][data-path="<p>"] a`; in Edit
> mode, its `folder-rename`). Opening it closes any row or folder rename and vice versa. Disabled
> with "Folders go six deep." at depth 6.

**S3 / S4 — Folder rows:**
> Meta: `countNoun` halves joined with " · " — "2 parts · 1 folder", "1 part", "3 folders",
> "Empty" (direct children only). In search results the meta is the location — `Folder.display
> (parent)` or "Top level" — and a folder matches on its **leaf name** (case-insensitive
> substring); parts match as A10. Folder rows sort by lower-cased leaf (results:
> `Folder.compareTree`); part rows `updatedAt` desc.

**S5 — `FolderChanged`:**
> `Main.update(RouteChanged(Parts(p)))` with `page = PartsList(m)`: `PartsList.update(m,
> FolderChanged(p))` called directly, `route` set, cmd mapped. **Kept:** `loaded`, `parts`,
> `error`, `partImages`, `folders`, `foldersLoaded`. **Set:** `folder = p`. **Cleared:** `form`,
> `rowStates`, `rowError`, `editing`, `announcement`, `query`, `picker`, `selected`,
> `confirmingDelete`, `folderEdit`, `newFolder`. Cmd: `Canvas.setScrollTop(querySelector(".shell"), 0)`
> (new `@set` binding; `.shell` is the scroll container).

**S7 — Edit mode in a folder, add:**
> After `PartsMoved` / `PartsDeleted` / `FolderDeleted`, if the view now has no part rows and no
> folder rows, `editing` resets and focus goes to `new-part`; otherwise A12b's targets.

**S9 — docs:** DESIGN §11.2 Parts: replace "rows grouped into one inset section per folder (…
uppercase '<path> · n' header)" with the browser (Folders group → Parts group, direct-count meta,
chevron rows, Headline + parent subtitle in a folder, flat sections only under a query); replace
"Section headers gain a 44 px pencil … never inside it" and "An empty leaf folder is a … header-
only row … while editing" with the folder-row editors and the two empty texts. §11.1 Layout
unchanged under S1. `docs/testids.md`: heading → "Parts list (`#/`, `#/f/…`)"; `parts-edit`
"every row" → part rows (folder rows: pencil/trash, no checkbox); `parts-search` "present once
the list is non-empty" → once any part or folder exists, on every folder screen; `parts-section`
/ `parts-section-header` → search results only, no editors; strike `parts-section-empty`,
`parts-folder`, `parts-folder-header` and the "Empty folders" bullet; "Folder rename / delete …
on the header" → on the `folder-row` while editing; add `folders-list`, `parts-list`,
`folder-row` (`data-path`, link outside Edit), `folder-empty`, `folder-missing`; `folder-new`
now also the folder view's capsule.

## 5. Existing e2e that must change

- `parts.spec.js` "parts — folders (SPEC §8a A10) › sections with counts, root first and
  headerless; search filters; rename moves and re-sorts": root shows one `part-row` (Hinge pin)
  and one `folder-row` Miata (meta "1 folder"), `parts-section` count 0; search assertions stay
  (`bezel` → 1 row, header `Miata / Interior · 1`; `interior` → 2; `zzz` → `parts-search-empty`;
  clear → root view again); the rename-move: `part-rename` on the only root row → picker → Done →
  save → root has 0 `part-row`; `#/f/Miata/Interior` has 3 with Hinge pin first; reload there.
- `parts.spec.js` A12a "New Folder nests under the selection; Done fills the row; …": the two
  `parts-section-header` checks → `folder-row` Miata "1 folder" at root / `#/f/Miata/Interior`
  1 row; the root-part move: `part-rename` (only root row) … after save root 0 rows, the folder 2.
- `parts.spec.js` A12b "an empty folder is a · 0 section; Edit selects rows; Move 2 …": root =
  2 `part-row` + `folder-row`s Archive ("Empty") and Miata ("1 folder"); search `arch` → Folders
  section `folder-row` Archive, `bezel` → header `Miata / Interior · 1`; Edit: `parts-list` has no
  link, 2 `part-select`, pencil check as today; Move 2 → Archive → root 0 rows, Archive meta
  "2 parts", live text, `parts-move` focused; the no-op move and Delete 1 run inside
  `#/f/Archive`; after delete the folder shows 1 row (not `· 0`); reload there.
- `parts.spec.js` A12b "folder rename: an intermediate folder is a header-only row …": at root
  `folder-rename` count 2 (Archive, Miata), no `parts-folder-header`; rename Miata → MX-5 on the
  row (prefill, `a/b` refused, Save) → row reads MX-5, focus on its pencil; `#/f/MX-5` → Interior
  row; case-only `interior` there; the twin (`archive`) error on MX-5's row at root; the
  one-editor-at-a-time check needs a root part (add one); Part page subtitle `MX-5 / interior`.
- `parts.spec.js` A12b "folder delete: only on an empty leaf …": at root `folder-delete` on the
  Archive row only, live text, focus `parts-edit`; delete the last part from `#/f/Miata/Interior`
  → `folder-empty`, Edit gone, `new-part` focused; `#/` → `parts-empty` copy + `folder-row` Miata.
- `a11y.spec.js` "parts list — Edit mode: Tab reaches the gear, Edit, +, search, then the first
  part-select": `parts-section` → `parts-list` (the current locator would pass on zero matches).
- `screenshot-tour.mjs` steps 12, 14, 15 (B5).
- **Unchanged:** `parts.spec.js` "creating a part…", "rename persists…", "delete with confirm…",
  A12a "new-folder field…", "at six deep…" and helpers `pickFolder` / `createPartIn` /
  `createEmptyFolder`; `a11y.spec.js` "#/ …", "parts list — folder picker …", "parts list —
  rename autofocuses …"; `shell.spec.js` (gear at root, `Settings.back` → `#/`);
  `export.spec.js` (`createPart` walks the picker; asserts the Part page only).
