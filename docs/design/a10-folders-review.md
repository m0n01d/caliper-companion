# SPEC §8a A10 (Folders) — pre-build review, 2026-09-17

**Verdict: BUILD WITH CHANGES.** The schema half is sound (one additive string, one golden line,
`label` precedent for read-time defaulting, no index change, planner already tolerates it). Four
things must change in the spec text before an agent is dispatched:

1. **B1** — the bullet 1 / Playwright bullet contradiction on `a//b` (normalise *or* reject; pick one).
2. **B2** — the Part-page subtitle slot is claimed twice: A10 (path) and layout A (`n faces · n
   features · unit`). Decide which, in writing, before either lands.
3. **S1** — the segment regex admits a trailing space (`"Miata "`), so "normalised away" must include
   per-segment trim; put the normaliser in `core/` (a `Folder` module), not `Store`.
4. **S2** — case handling is unspecified; `Miata` and `miata` become two sections. Snap to an
   existing spelling on save.

Everything else is a should/nit. Ready-to-paste text is in §3–§5.

## 1. Findings

| # | Sev | Spec bullet | Finding | Fix | Source checked |
|---|---|---|---|---|---|
| B1 | blocker | 1 vs 7 | Bullet 1: "leading/trailing/double slashes are normalised away". Bullet 7: "an invalid segment (`a//b`, `?`) is rejected inline". Both cannot be true. | Normalise (friendlier on a phone: chips + `/` on the 123 keyboard layer). Test: `a//b` **saves as** `a/b`; `?` is rejected. | SPEC.md:383, :389 |
| B2 | blocker | 4 | `docs/design/review-2026-09-17.md` §4 "DESIGN.md lines that change" → Part bar: "subtitle 'n faces · n features · unit'". A10 puts the path there. `Shell` has one `~subtitle` slot (Shell.res:14) and layout A is being applied *now*. DESIGN §11 intro: spec wins over DESIGN. | Spec states it: subtitle = folder path (root → none); layout A's stats line moves to the features group header (`Ui.ListGroup ~header`, which layout A already reduces to "group header only"). Tell the layout-A implementer. | review-2026-09-17.md:209-210, DESIGN.md:169, Shell.res:8-16 |
| S1 | should | 1 | `^[A-Za-z0-9][A-Za-z0-9 _-]{0,31}$` accepts `"Miata "` and `"Miata  Interior"` — two folders that look identical. It also rejects `.`, `'`, `(`, `)`, `&`, `+` and every non-ASCII letter ("v2.1", "Miata (NB)", "Süd"). Fusion's Data Panel takes any string. | Normaliser: split on `/`, trim each segment, collapse internal whitespace, drop empty segments, join. Validator on the result. Widen the alphabet to `^[\p{L}\p{N}][\p{L}\p{N} _.()&'+-]{0,31}$` (`u` flag; ReScript `RegExp.fromString(_, ~flags="u")`) and reject an all-dots segment (`^\.+$`, keeps v1's on-disk staging safe). If ASCII-only is preferred, say so as a known limit — but trim regardless. | SPEC.md:383, Slug.res:4-7 (same regex style) |
| S2 | should | 1, 2 | Exact-string grouping: `miata/interior` typed once creates a second section under `Miata/Interior`; `.list-group-header` is `text-transform: uppercase`, so the two headers even *look* identical. | `Folder.snap(~existing, path)`: if a normalised path equals an existing folder case-insensitively, save the existing spelling. Group exact, sort folders case-insensitively. Pure, one function, tabled. | global.css:463-469, PartsList.res:139 (`createPart` call site) |
| S3 | should | 1 | Where does normalising live? Precedent: `Slug.make` is caller-side; `Store.createPart` takes `~slug` ("not available to this module, so the caller supplies it"). `Store` stays dumb. | New pure module `src/core/Folder.res` (`normalize`, `validate`, `snap`, `display`), unit-tested like `Slug`/`FeatureName`. Pages call it before `createPart`/`putPart`. `createPart` gains `~path: string`. Read-time default `""` in **both** `Codec.decodePart` (Codec.res:225) and `Store.PartDoc.fromDoc` (Store.res:214), same shape as `label` (Codec.res:189-191, Store.res:352-355). | Store.resi:23-25, CLAUDE.md "core/ is pure" |
| S4 | should | 3 | The rename strip (`PartsList.res:317-345`) and the create form (`:246-311`) now both need Name + Folder + chips + inline error. Layout A also moves Rename behind Edit mode (review P1). Two copies will drift. | One `PartForm` (name, folder, chips, error, primary/cancel) rendered by both; keep the existing testids (`part-name`, `part-rename-input`) and add `part-path` on both. Rename stays an inline strip — layout A doesn't move it to the Part page. | PartsList.res:246-345, review-2026-09-17.md:20 |
| S5 | should | 3 | "most recently used first, then alphabetical" — timestamps never tie, so "then alphabetical" does nothing; "used" is undefined. | Chips = distinct non-root folders from `model.parts` (already loaded; no new Store call), ordered by max `part.updatedAt` in that folder, desc (= last time any part in it was written; `putPart` bumps it, Store.res:252). Cap 8, `Ui.ChipRow` (scrolls). Tap fills the field (never submits) so `/Sub` can be appended. | Ui.res:99-104, Store.res:250-253 |
| S6 | should | 2, 7 | `RenameSaved` (PartsList.res:188-196) swaps the record in place and never re-sorts. After a folder move the part appears in the new section (grouping derives from the record — good) but at a stale updatedAt position until reload. The e2e "moves it between sections" passes; the order inside the section is wrong. | Re-sort `parts` by `updatedAt` desc in `RenameSaved` (one line; `putPart` returns the bumped record). | PartsList.res:188-196 |
| S7 | should | 7 | Playwright bullet names no parts, so "search `bezel` filters to one" is untestable as written; "export carries `"path"`" lives in `export.spec.js` (which already parses `doc.part`, :156-161), not `parts.spec.js`. | Name them (§3). Add `expect(doc.part.path).toBe('')` to the existing golden export test, and one folder export assertion. | export.spec.js:156-161 |
| S8 | should | 6 | "the Fusion project folder named by `path`" — Fusion's hierarchy is Team → Project → Folder. Is the first segment a project or a folder? | Say: relative to the active project's root folder (`app.data.activeProject.rootFolder`); the first segment is a folder, never a project. The planner already reads `part.get("path")` with `""` default (import_ccpart.py:206, exposed as `plan["part_path"]`, :372) — no planner change. | import_ccpart.py:206,372; LOGBOOK.md:1622 |
| N1 | nit | 1 | No depth or total-length cap. The subtitle is one ellipsised Footnote line in the bar's centre column (~250 px at 390): "Miata / Interior / Dashboard" fits; four segments truncate. | Cap 6 segments; document that the subtitle ellipsises. | global.css:183-191 |
| N2 | nit | 1 | `path` vs `folder`: §7 says "Paths in JSON are bundle-relative either way" — `part.path` becomes the one exception. But `part.path` is already the name in SKILL.md:170, IMPORT-SKILL-SPEC.md:172 and the planner. | Keep `path`; add "(`part.path` is a folder path, not a file path)" to §7. Renaming buys a nicer word for four touch points. | SPEC.md:157 |
| N3 | nit | 2 | Section headers render uppercase (`.list-group-header`), so display-name case is lost in the header ("MIATA / INTERIOR · 2"). HIG grouped headers are uppercase; iOS Files does the same. | Accept. S2's snap keeps the underlying spelling unique. Count goes in the same string: `"Miata / Interior · 2"`. | global.css:467 |
| N4 | nit | 2 | Search resets on navigation: `Main.pageForRoute` re-inits `PartsList` on every route change (Main.res:59-63), so the query is gone when Back returns from a Part. | Acceptable for v0.1 (native `UISearchController` keeps it; nobody will notice at ≤ 20 parts). If it bites, `Route.Parts` gains an optional `q` — not now. | Main.res:59-63, Route.res:6-12 |
| N5 | nit | 2 | HIG puts search in the nav bar and collapses it on scroll. | On the web, a plain field directly under the static Large Title (already in the content flow, Shell.res:52-56) is the honest equivalent. Hide it in the empty state only. Attrs in §3. | hig-brief.md:136-141 |
| N6 | nit | — | Name uniqueness is not enforced today (`CreateSubmit` checks only empty, PartsList.res:133) and A10 adds none, so two "Bracket" parts in one folder are allowed. `Slug.make(name)` ignores the folder (PartsList.res:139), so `<slug>.ccpart.zip` filenames collide across folders too. | State both in the spec ("no uniqueness; slug is from the name only, unchanged"). Fine for one user. Aside, pre-existing: rename never recomputes the slug (`{...part, name: trimmed}`, :180). | PartsList.res:133,139,180 |
| N7 | nit | 5 | Folders are implicit — nothing to delete, nothing to create; a folder vanishes when its last part moves or is deleted; renaming a folder means editing each part. | Say so in the spec (one line). Folder rename is a v1 gap, not a v0.1 blocker. | — |

**Confirmed, no change needed.** Golden: `fixtures/hinge_pin/features.json` is one key per line;
`"path": ""` between `"slug"` (:12) and `"units"` (:13) is exactly one added line (`FeaturesDocument.encodePart`
:44-51 gets the field after `slug`; `Codec.encodePart` :211-223 likewise). Additive under the same
schema id follows A7 (`label`). Indexes: §6.1's `[type, partId]`, `[type, updatedAt]` stay; `listParts`
is an `allDocs` range + in-memory sort by design (Store.res:5-21), so in-memory grouping is the same
scale — no path index. Sync: a plain string on a doc that already carries `type`/`partId`/`updatedAt`.
`Fixture.res:13-22` must gain `path: ""` or M1 tests stop compiling. `parameters.csv` is untouched
(`ParametersCsv` never reads the part beyond units/slug). Skill v1 note is right to leave.

**Six folders, one part each.** Six headers ≈ 150 px per part (header + 96 px row + 24 px gap) vs
96 px flat — 900 px for six parts. Acceptable: no extra tap, search sees everything, and it is the
iOS Settings/Files idiom. Drill-down would cost a tap per part for a single-user list of ≤ 20. When
no part has a folder the root section renders **without** a header, so existing users see no change.

## 2. Replacement text for A10 bullets 1, 2, 3, 4, 7 (+ one new)

- [ ] `Types.part` gains `path: string` (`""` = root; a folder path, not a file path — carve-out in
  §7). `core/Folder.res` (pure, tabled tests): `normalize` splits on `/`, trims each segment,
  collapses internal whitespace, drops empty segments and rejoins (`" /Miata//Interior /"` →
  `"Miata/Interior"`); `validate` then requires each segment to match
  `^[\p{L}\p{N}][\p{L}\p{N} _.()&'+-]{0,31}$` (`u`), not be all dots, and ≤ 6 segments;
  `snap(~existing)` replaces a path that equals an existing folder case-insensitively with that
  spelling; `display` joins with `" / "`. Pages call `normalize → validate → snap` before
  `Store.createPart(~path)` / `putPart`; `Store` never normalises. `Codec.decodePart` and
  `Store.PartDoc.fromDoc` read a missing `path` as `""` (the `label` precedent). `FeaturesDocument`
  emits `"path"` after `"slug"`; the golden gains that one line; `Fixture.part` gains the field.
- [ ] Parts list: derived in `view` from `model.parts` — root section first (header omitted when no
  part has a folder), then one `Ui.ListGroup` per distinct path, sorted case-insensitively, header
  `"<display path> · <count>"` (`parts-section`, `parts-section-header`); rows inside keep
  `listParts` order (updatedAt desc; `RenameSaved` re-sorts). Above the list, hidden in the empty
  state: `<input type="search" inputmode="search" enterkeyhint="search" autocapitalize="none"
  autocorrect="off" placeholder="Search" aria-label="Search parts">` (`parts-search`, 17 px; keep the
  clear button — `::-webkit-search-cancel-button` — or `-webkit-appearance: none` plus our own, not
  neither) filtering by name **or** path, case-insensitive substring, live, sections preserved;
  no match → one Footnote line `No parts match "<q>".` (`parts-search-empty`). Query is page-local
  and resets on navigation.
- [ ] Create and rename share one `PartForm`: Name, then **Folder** (`part-path`, `type="text"
  autocapitalize="words" autocorrect="off" spellcheck="false" enterkeyhint="done"`, placeholder
  `Miata/Interior`), under it a `Ui.ChipRow` of existing folders (`part-path-chip`, at most 8,
  ordered by the newest `updatedAt` of any part in that folder; tapping a chip fills the field and
  keeps focus there). Invalid → the rule inline (`part-path-error`) and the primary button disabled.
  Rename lets a part be moved by editing its folder; two parts may share a name in one folder; the
  slug is still `Slug.make(name)` and ignores the folder.
- [ ] Part page: the folder is the Shell subtitle (`Folder.display`, "Miata / Interior / Dashboard";
  none at root). Layout A's "n faces · n features · unit" line goes in the features group header,
  not the subtitle. Contract in §3.
- [ ] Folders are implicit: none to create or delete; one disappears when its last part leaves.
  Renaming a folder = editing each part (v1).
- [ ] Playwright (`parts.spec.js`): create `Window switch bezel` and `Door card clip` in
  `Miata/Interior`, then `Hinge pin` at root → `parts-section` count 2, headers in order `["", "Miata /
  Interior · 2"]` (root header absent → assert `parts-section-header` count 1 and its text); search
  `bezel` → one `part-row`; rename `Hinge pin`'s folder to `Miata/Interior` → header reads `· 3`,
  root section gone; `a//b` saves and the header reads `A / B · 1`; `?` → `part-path-error` visible,
  `part-create` disabled; `miata/interior` on a new part snaps into the existing section. `export.spec.js`:
  `doc.part.path === ''` on the golden test; one part with a folder exports it verbatim.

## 3. Subtitle contract (`Main.res` + every page)

Every page module gains, next to `title`/`back` (elm-spa shape, CLAUDE.md "Architecture"):

```rescript
let subtitle = (_model: model): option<string> => None        // PartsList, Capture, Annotate, Settings, Debug

// Part.res
let subtitle = (model: model): option<string> =>
  switch model.partStatus {
  | Found(p) => Folder.display(p.path)   // Some("Miata / Interior / Dashboard"); None when p.path == ""
  | Pending | Missing => None
  }
```

`Main.view` (Main.res:109-150) widens the tuple and threads it; `Shell` already takes
`~subtitle: option<string>=?` (Shell.res:14), so pass the option straight through:

```rescript
let (title, back, subtitle, body) = switch model.page {
| Part(pageModel) => (
    Part.title(pageModel), Part.back(pageModel), Part.subtitle(pageModel),
    Part.view(pageModel, ~dispatch=m => dispatch(PartMsg(m))),
  )
| … // same four-tuple for the other five pages
}
…
<Shell title back ?subtitle largeTitle> {body} </Shell>
```

The bar grows from 44 px to ~62 px on the Part page only (`grid-template-rows: minmax(44px, auto)`,
global.css:132; `.shell-subtitle` is already styled, :183-191). No CSS change.

## 4. Core unit test table — `src/core/tests/FolderTest.res`

| input | `normalize` | `validate` |
|---|---|---|
| `""`, `"/"`, `"//"`, `"  "` | `""` | Ok (root) |
| `"Miata"` | `"Miata"` | Ok |
| `" /Miata//Interior /"` | `"Miata/Interior"` | Ok |
| `"Miata  Interior/Dash"` | `"Miata Interior/Dash"` | Ok |
| `"Miata (NB)/v2.1/Dwight's"` | unchanged | Ok |
| `"Süd/Tür"` | unchanged | Ok |
| `"a/?/b"` | `"a/?/b"` | Error(BadSegment("?")) |
| `"-lead"`, `" .hidden"` | — | Error(BadSegment) |
| `"a/../b"` | — | Error(BadSegment("..")) |
| 33-char segment | — | Error(SegmentTooLong) |
| 7 segments | — | Error(TooDeep) |
| `snap(~existing=["Miata/Interior"], "miata/INTERIOR")` | `"Miata/Interior"` | — |
| `snap(~existing=["Miata/Interior"], "Miata/Exterior")` | unchanged | — |
| `display("")` → `None`; `display("a/b")` → `Some("a / b")` | | |

Codec/FeaturesDocument: round-trip a part with `path = "Miata/Interior"`; decode an object without
`path` → `""`; golden byte-for-byte with the added line. Store (vitest, LevelDB adapter, existing
pattern): a pre-A10 part doc reads back with `path = ""`; `createPart(~path)` persists it.

## 5. `docs/testids.md` additions

`parts-search`, `parts-search-empty`, `parts-section` (one per section incl. root),
`parts-section-header` (absent for root), `part-path`, `part-path-chip`, `part-path-error`
(both forms). `Ui.ListGroup` needs a `~headerTestId` (it has `~header` and `~testId` only,
Ui.res:148-160).
