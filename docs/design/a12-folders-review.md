# SPEC §8a A12 (Folder management) — pre-build review, 2026-09-17, commit `04b51e2`

**Verdict: BUILD WITH EDITS.** The store half is sound (explicit `folder:` docs, one `bulkDocs` per
subtree rename, page-side validation, no index). Five things in the spec text are wrong against the
code as it stands and would ship as bugs or red tests; ten more leave a builder guessing. Ready-to-
paste text is in §3. Read A10's review first — its N7 is what A12 fills, and its S3 ("Store stays
dumb") still holds: `ensureFolder` checks *existence*, it never rewrites a path.

## 1. Findings

| # | Sev | Finding | Recommendation | Evidence |
|---|---|---|---|---|
| B1 | blocker | "`edit-toolbar`: `position: sticky; bottom: 0` inside `.shell`". A page's view renders *inside* `<main class="shell-content">` (padding-bottom `cc-space-5 + safe-area`), wrapped in `.stack-lg.parts-page`, which is not stretched. A sticky element is confined to its containing block, so on the dogfood list (1–3 parts) the toolbar sits mid-screen under the last row, and on a long list it is inset above `main`'s bottom padding. | Give `Shell` a `~footer: option<React.element>=?` rendered as a sibling **after** `<main>` directly in `.shell` (a flex column; `main` is `flex: 1 1 auto`, so a short list still pushes the footer to the bottom edge, and a long one lets `sticky; bottom: 0` catch it). `PartsList` exports `footer` next to `actions`/`leading`; `Main.res` threads it. | global.css:125-133, :224-228; PartsList.res:866-895; Shell.res:61-63 |
| B2 | blocker | Playwright bullet: "in Edit mode the first Tab lands on the first `part-select`". DOM order in the bar is leading (`settings-link` `<a>`) → actions (`parts-edit`, `new-part`) → content (`parts-search`) → rows. First Tab lands on the gear. The test fails as written. | Assert what matters: while editing, `parts-section` contains no `<a>` (`getByRole('link')` count 0), the first `part-select` is reachable by Tab (loop until focused, ≤ 6 presses) and `Space` toggles it (`toBeChecked`). | Shell.res:24-50; Main.res:159-171; a11y.spec.js:85-88 |
| B3 | blocker | "bar title 'Choose Folder'" / "Move 2 Parts". `Main.view` hard-codes `largeTitle = true` for `PartsList` and `Shell` renders **no** bar title when `largeTitle` is on; `PartsList.title` is the constant `"Parts"`. As written the bar centre is empty and a Large Title "Parts" stays in the content flow above the picker. | `PartsList.title(model)` returns the picker title while it is open; add `let largeTitle: model => bool` (false while the picker is open) and have `Main.view` read it instead of the hard-coded switch. Cancel/Done then flank a centred Headline, the HIG picker shape. | Main.res:152-155; Shell.res:38-44; PartsList.res:456 |
| B4 | blocker | "`folder-new-name` … one segment — a `/` fails the A10 segment rule". `Folder.validate("a/b")` is `Ok("a/b")`: `/` is the separator, never a bad character. There is no function that rejects `a/b`; the e2e line "rejects `a/b` … inline" cannot pass. | Add `Folder.validateSegment: string => result<string, error>`: `normalizeSegment`, then `Error(BadSegment(s))` when empty or containing `/`, else `isValidSegment`. Tabled: `"Interior"` Ok, `" interior "` → `"interior"`, `"a/b"` Error, `"?"` Error, `""` Error, 33 chars Error. | Folder.res:45-54; FolderTest.res:35-47 |
| B5 | blocker | `renameFolder` "refuses `Exists` when `to` or a case-insensitive twin is a folder doc" — `from` is itself a case-insensitive twin of `to` on a case-only rename (`Miata` → `miata`), so the one rename `snap` can never do is refused with "already exists". | Exempt `from`: `Exists` iff some folder doc `≠ from` equals `to` case-insensitively. Case-only rename is otherwise a normal subtree rewrite. Store test: `renameFolder(~from="Miata", ~to="miata")` is `Ok`. | SPEC.md:176-180 |
| S1 | should | Header buttons and the inline rename field live "on the section header", but `Ui.ListGroup ~header` is `option<string>` rendered as an `<h2>`. Buttons inside an `<h2>` also leak into the heading's accessible name ("MIATA · 2 Rename folder Delete folder"). | `ListGroup` gains `~headerTrailing: option<React.element>=?` and `~headerEl: option<React.element>=?` (replaces the `<h2>` outright, for the rename form); both render in a `.list-group-header-row` flex wrapper as **siblings** of the `<h2>`. | Ui.res:150-173; global.css:472-478 |
| S2 | should | "tapping anywhere on the row toggles it" — with `Ui.ListRow ~onClick` the row is a `<button>` wrapping the checkbox and the pencil: nested interactive content, the exact bug wave 3a removed. | Editing row = `<div class="list-row" role="listitem">`: leading `<input type="checkbox" id=… data-testid="part-select" aria-label="Select <name>">`, body wrapped in `<label for=…>` (thumbnail, title, meta), trailing pencil as a sibling outside the label; no `href`, no chevron. "Anywhere" = the body, not the pencil. | Ui.res:236-256; PartsList.res:680-686 |
| S3 | should | Migration = one `ensureFolder` per distinct path "after `PartsLoaded`". Dispatched as a `Tea.batch` they run concurrently and race on shared ancestors: `bulkDocs` reports a 409 **per doc in the result array** (the binding returns `array<doc>`, nothing throws), so an unchecked result silently "succeeds" and a checked one fails spuriously. | `Store.ensureFolders(t, ~paths: array<string>): promise<array<string>>` — one `allDocs` range on `folder:`, compute the missing set incl. ancestors, one `bulkDocs`; per-doc 409 = already exists. `ensureFolder(~path)` = `ensureFolders([path])`. `PartsList` runs it once (`FoldersLoaded(paths)`). | PouchDb.res:82; Store.res:99-102; PartsList.res:279-285 |
| S4 | should | `Folder.snap` matches whole paths only. A10 data can already hold `Miata/Interior` **and** `miata/Exterior` (`snap` compared full paths). Migration then creates twin ancestors `folder:Miata` / `folder:miata`; the picker shows both `Miata` rows for ever. | `snap` becomes prefix-wise: each ancestor prefix is snapped against `existing` in turn (`snap("miata/exterior", ~existing=["Miata/Interior"]) = "Miata/exterior"`; tabled). Migration snaps each part path against the running folder set and `putPart`s the (rare) changed ones before `ensureFolders`. | Folder.res:59-65; PartsList.res:240-243 |
| S5 | should | "An empty explicit folder renders as a section too". Every *intermediate* folder (no direct parts, ≥ 1 subfolder — `Miata` above `Miata/Interior`) is empty by that definition, so each ancestor gets a `· 0` + "Empty folder" section. That is most folders. | `· 0` sections only for **leaf** empties (no parts, no subfolders — the deletable set). Intermediates render nothing outside Edit mode and a header-only row (`<h2>` + pencil, no container) while editing, so they stay renamable. | SPEC.md:196-199; PartsList.res:262-273 |
| S6 | should | DESIGN §11.1 Materials: "Glass in **exactly one place**: the navigation bar". A glass `edit-toolbar` contradicts it; the spec only amends §11.2. | Keep glass (a bottom toolbar is chrome — liquid-glass-web §1, §5 #2/#6) and amend §11.1 to "the navigation bar and the Parts edit toolbar, both sticky". Same pseudo-child recipe; hairline on top. | DESIGN.md:184; liquid-glass-web.md:184, :214 |
| S7 | should | Picker rows: `role="option"` with a 20 px indent carries no hierarchy to VoiceOver; `aria-level` is invalid on `option`; a plain `<div role=option>` is not focusable, yet "opening the picker focuses the selected row". | Each option is `<button type="button" role="option" aria-selected data-path aria-label="<Folder.display path>">` (visible text = leaf; root `aria-label="None, top level"`). Focus the selected one on open; Enter/Space activate for free. | SPEC.md:189-192 |
| S8 | should | Toolbar Delete = "each part is deleted as today": N parallel `Store.deletePart` = 2N full `face:`/`dim:` scans and N `DeleteDone` messages each announcing "Part deleted"; the spec wants one "Deleted 2 parts". Focus after: today `new-part`; in Edit mode with parts left, Edit/Done is the survivor. | `Store.deleteParts(t, ~partIds)` (sequential loop in one promise) → `PartsDeleted(ids)`: filter, clear selection + strip, announce, focus `parts-edit`. If the list is now empty: `editing = false` (Edit is gone from the bar), focus `new-part`. | Store.res:286-320; PartsList.res:437-452 |
| S9 | should | `part-path-error` is reused by the picker's new-folder field and the header rename; a row rename strip and a header rename can be open at once (`rowStates` vs the new folder-edit state) → two matching elements → Playwright strict-mode failure and a confusing screen. | Ids `folder-new-error` and `folder-rename-error`; one inline editor at a time: starting a folder rename resets `rowStates`, `RenameStart` cancels a folder rename. | PartsList.res:206-213, :383 |
| S10 | should | Unspecified state the builder must invent (each is a place two agents would diverge): model fields, picker target, Cancel focus, "Done with nothing changed", a folder created then Cancelled, singular live texts, moving into the current folder, selection vs search. | Text in §3 S10. | — |
| N1 | nit | A12 sits at SPEC.md:161, inside §7, while A10/A11 are in §8a (:484, :555). | Move it after A11. | SPEC.md:161, :373 |
| N2 | nit | "a folder glyph leading" — `Icon.res` has `FolderPlus` but no `Folder`. | Add Lucide `folder` (`M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z`). `FolderPlus` on the New Folder capsule. | Icon.res:13-31 |
| N3 | nit | `folder` docs carry `createdAt` only; §5 says every doc has `updatedAt` for v1 sync. | Add `updatedAt` (= `createdAt`; bumped on rename). | SPEC.md:39 |
| N4 | nit | In the inline rename strip, `part-folder-row` as a `.list-row` sits inside the row's own `.list-row` — a row in a row. | In the strip render it as a `.parts-form-field` button with the same testid/role; `.list-row` only in the create form. | PartsList.res:719-741 |
| N5 | nit | While `folder-rename-input` has the keyboard, the sticky toolbar is either under the keyboard (Safari: layout viewport keeps `100dvh`) or above it (standalone may resize). Harmless — Move/Delete are not needed mid-typing. Not verified on device. | Note in LOGBOOK; no code. | §5 iOS rules |
| N6 | nit | `deleteFolder`'s `NotEmpty` and `renameFolder`'s `Nested` are unreachable from the UI (delete only on empty leaves; rename keeps the parent). | Keep as store guards with Store tests only; no inline copy for them. | SPEC.md:174-180 |

## 2. Judgements asked for

- **Flat tree vs drill-down: flat.** ≤ 30 rows, ≤ 6 deep, one tap selects; drill-down costs a tap
  per level plus a "choose this folder" control at every level (Files' pattern) — for a one-handed
  phone user that is strictly worse below ~50 folders. 6 × 20 px = 120 px of indent leaves 220 px
  for the leaf at 390 wide; fine. The a11y cost is real and S7 fixes it (name = full path).
- **Per-row delete → toolbar: yes.** Mail/Notes/Files all do select → bottom toolbar; per-row
  trash + inline strip was the pre-Edit-mode compromise. **Keep the pencil trailing** for v0.1:
  the inline rename strip already exists, `part-rename` tests stay green, and "select one →
  Rename" needs a third toolbar button and a single-selection rule. Revisit if the row feels busy.
- **Rows stop navigating in Edit mode: HIG-consistent** (`UITableView` editing +
  `allowsMultipleSelectionDuringEditing`; hig-brief:148 "iOS requires an explicit edit mode before
  selecting rows"). The trap is leaving the `<a href>` in place with `preventDefault` — VoiceOver
  double-tap still navigates. S2 removes the anchor entirely.
- **Sticky bottom toolbar: right material, wrong container (B1).** `overscroll-behavior-y:
  contain` on `.shell` is irrelevant to sticky. Glass follows the top bar's pseudo-child recipe
  and S6 records the second glass surface. Keyboard: N5.
- **`_id = "folder:" ++ path`: keep.** PouchDB ids accept `/`, spaces and Unicode; rename is one
  deletion + one creation inside the same `bulkDocs` as the subtree, so no worse than a
  random-id `path` field (which would still rewrite every descendant). Key order is code-point
  order — irrelevant, `listFolders` sorts in memory. Twins are the page's job: S4 (prefix snap)
  and B5 (case-only rename).
- **`ensureFolder` in Store: acceptable.** Existence is not normalisation; A10's rule holds as
  long as the input is already snapped. The **migration** belongs in the page (S3: one call).
  `createPart`/`putPart` calling `ensureFolders` adds one `folder:` range read per write —
  `putPart` is called only from the rename strip, so cost is nil.
- **Empty folders outside Edit mode: leaf empties yes, intermediates no (S5).** A folder just
  created (then Cancelled) or just emptied by a move must stay visible or it "vanished"; an
  ancestor never needed its own section.
- **Scope: too much for one agent.** Cut line — **A12a**: Store (`ensureFolders`, `listFolders`,
  `moveParts`, `createPart`/`putPart` hook), `Folder` helpers, the picker in both forms
  (`part-path`/chips retired), `leading`/`largeTitle` threading, migration, leaf-empty sections;
  single-part moves already work through the rename strip. **A12b**: Edit-mode selection,
  `footer` toolbar, `moveParts`/`deleteParts` UI, folder rename/delete, `renameFolder`/
  `deleteFolder`. Serial, not parallel — both edit `PartsList.res`.

## 3. Spec edits (paste over the matching A12 text)

**B1 / S6 — toolbar bullet, first sentence:**
> A **selection toolbar** (`edit-toolbar`) renders in a new `Shell ~footer` slot — a sibling
> **after** `<main class="shell-content">` inside `.shell`, `position: sticky; bottom: 0`, the nav
> bar's glass on a pseudo-child, hairline on top, `padding-bottom: env(safe-area-inset-bottom)`;
> never `fixed` (§5). `PartsList` exports `footer` (Some while editing and no form/picker is open)
> and `Main.res` threads it like `actions`. DESIGN.md §11.1 Materials becomes "the navigation bar
> and the Parts edit toolbar".

**B2 — a11y line:**
> `a11y.spec.js`: while editing, `parts-section` contains no link (`getByRole('link')` count 0);
> pressing Tab (at most 6 times) reaches the first `part-select`, `Space` checks it; the picker's
> `folder-option`s are `<button role="option">`s whose `aria-label` is the display path and whose
> `aria-selected` is truthful.

**B3 — picker bullet, after "takes over the page":**
> `PartsList.title` returns "Choose Folder" (or "Move n Parts") while the picker is open and the
> new `PartsList.largeTitle: model => bool` returns false; `Main.view` reads `largeTitle` from the
> page instead of its hard-coded switch, so the title sits in the bar between Cancel and Done.

**B4 — `Folder` bullet, add:**
> `validateSegment(name)`: `normalizeSegment`, then `Error(BadSegment(name))` when empty or
> containing `/`, else the segment rule (`"Interior"` Ok, `" interior "` → `"interior"`, `"a/b"`,
> `"?"`, `""`, 33 chars → Error). The picker's new-folder field and the header rename use it;
> `validate` stays for whole paths.

**B5 — `renameFolder`:**
> refuses `Exists` when a folder doc **other than `from`** equals `to` case-insensitively (a
> case-only rename `Miata` → `miata` is allowed), `Nested` when `to` is under `from`.

**S1 — folder rename/delete bullet, add:**
> `Ui.ListGroup` gains `~headerTrailing` (the two icon buttons, siblings of the `<h2>` in a
> `.list-group-header-row`) and `~headerEl` (replaces the `<h2>` with the rename form).

**S2 — Edit bullet, replace "tapping anywhere … chevron hides":**
> an editing row is a plain `<div class="list-row" role="listitem">` — no `href`, no chevron —
> whose body (thumbnail, title, meta) is a `<label for>` the checkbox, so tapping the body toggles;
> the pencil is a trailing sibling outside the label.

**S3 / S4 — Store bullet, replace the `ensureFolder` and migration sentences:**
> `ensureFolders(t, ~paths): promise<array<string>>` — one `allDocs` range on `folder:`, one
> `bulkDocs` of every missing path and ancestor; a per-doc 409 in the result counts as existing;
> returns the paths created. `ensureFolder(~path)` is `ensureFolders([path])`. Migration:
> `PartsList` runs it **once** after `PartsLoaded` over the distinct part paths (each first
> prefix-snapped — `Folder.snap` now snaps every ancestor prefix against `~existing` — and any part
> whose spelling changed is `putPart`ed first) → `FoldersLoaded(array<string>)`.

**S5 — empty-folder bullet:**
> A **leaf** explicit folder (no parts, no subfolders) renders as a section: header
> "`<display> · 0`" and one Footnote row "Empty folder" (`parts-section-empty`). A folder with
> subfolders but no direct parts renders no section outside Edit mode and a header-only row (no
> container) while editing, so it can be renamed. Counts never include descendants.

**S7 — picker body:**
> each row `<button type="button" role="option" data-testid="folder-option" data-path
> aria-selected aria-label="<Folder.display path>">` (root: `aria-label="None, top level"`).

**S8 — Delete sentence:**
> Delete → confirm strip → `Store.deleteParts(~partIds)` (one promise, sequential `deletePart`)
> → `PartsDeleted(ids)`: rows removed, selection and strip cleared, live region "Deleted 2 parts"
> ("Deleted 1 part"), focus to `parts-edit`; if no parts remain, `editing` resets to false and
> focus goes to `new-part`.

**S9 — ids:** `folder-new-error` (picker field), `folder-rename-error` (header); one inline
editor at a time (a folder rename resets `rowStates`; `RenameStart` cancels a folder rename).

**S10 — add a "State" paragraph:**
> Model: `folders: array<string>` (explicit docs, from `FoldersLoaded`/`ensureFolders` results),
> `picker: option<{target: ForCreate | ForRename(partId) | ForMove(array<partId>), selected:
> string, newFolder: option<string>}>`, `selected: array<partId>`, `confirmingDelete: bool`,
> `folderEdit: option<{path: string, draft: string, error: option<string>}>`. Cancel and Done
> both return focus to `part-folder-row` (Move: to `parts-move`); Done with an unchanged selection
> is a no-op return. A folder created in the picker persists even if the picker is then Cancelled
> (it shows as a `· 0` section). `moveParts` skips parts already in the target and the live text
> counts only moved ones; moving into the current folder with nothing to move announces nothing.
> A query change clears the selection. Store errors from move/rename/delete surface in the
> existing `rowError` line.

**N1:** move A12 under §8a after A11. **N2:** `Icon.Folder` (Lucide `folder`) on options,
`FolderPlus` on the capsule. **N3:** folder docs carry `updatedAt`.

## 4. Existing e2e that must change

`parts.spec.js`: "delete with confirm returns to the empty state" (`part-delete` → select +
`parts-delete` + `parts-delete-confirm`); "sections with counts … rename moves and re-sorts"
(`part-path`/`part-path-chip` → `part-folder-row` → `folder-option[data-path]` →
`folder-picker-done`); "folder field: a//b normalises, ? is rejected inline, a different case
snaps …" (retire `a//b`; `?` and snap move to `folder-new-name`); helper `createPartIn`
(`part-path` → picker). `a11y.spec.js`: "parts list — rename autofocuses …; deleting a part sends
focus to New part" (toolbar delete; focus target per S8). Unchanged: "rename persists after
reload", `shell.spec.js` (the gear must keep rendering through the threaded `leading`),
`export.spec.js`.
