// Store — the only module that touches PouchDB (SPEC.md §5, §6.1, M6).
// This file is the public contract; downstream modules (app/, tests) code
// against it, never against PouchDb.res directly.

type t

// -- construction ---------------------------------------------------------

// Creates the DB, registers the pouchdb-find plugin (process-wide, once),
// and kicks off `ensureIndexes` in the background (non-blocking — see
// Store.res for why that's safe). `~adapter` is for tests (a fresh
// LevelDB path per test); production code omits it and gets PouchDB's own
// platform default (IndexedDB in the browser).
let make: (~name: string, ~adapter: string=?) => t

// Memoized singleton named "caliper-companion", browser-default adapter.
let shared: unit => t

let destroy: t => promise<unit>

// [type, partId] and [type, updatedAt]. Idempotent — safe to call anytime,
// including redundantly after `make`'s own background call.
let ensureIndexes: t => promise<unit>

// -- folders (SPEC §8a A12a) ------------------------------------------------
//
// Explicit folder docs, app-internal (never exported): `_id = "folder:" ++
// path`, body `{type: "folder", path, createdAt, updatedAt}` (`updatedAt` =
// `createdAt` until a rename bumps it — §5's every-doc rule). `path` is
// always normalised, validated and snapped by the page before it gets here;
// this module checks *existence* only, it never normalises (A10's rule).
// The root ("") is never a doc.

// Every folder doc's path, sorted case-insensitively.
let listFolders: t => promise<array<string>>

// One `allDocs` range on `folder:`, then one `bulkDocs` of every path in
// `paths` and every `Folder.ancestors` of them that has no doc. A per-doc
// 409 in the `bulkDocs` result (a concurrent writer) counts as already
// existing. Returns the paths this call created, ancestors first; `[]` when
// everything already existed. Idempotent.
let ensureFolders: (t, ~paths: array<string>) => promise<array<string>>

// `ensureFolders([path])`.
let ensureFolder: (t, ~path: string) => promise<array<string>>

// -- parts ------------------------------------------------------------------

// id, createdAt = updatedAt = now, anchors = []. `slug` is M1's Slug.make
// output — not available to this module, so the caller supplies it. `path`
// (SPEC §8a A10, "" = root) is stored as given: the caller runs
// `Folder.normalize → validate → snap` first; this module never normalises.
// Part docs written before A10 have no `path` and read back as "". A12a: a
// non-empty path gets `ensureFolder` before the part is written, so every
// path a part carries always has a folder doc.
let createPart: (
  t,
  ~name: string,
  ~slug: string,
  ~path: string,
  ~units: Types.units,
) => promise<Types.part>

// Bumps updatedAt; returns the stored record (including the bumped
// updatedAt). Used for both edits (rename, notes) and explicit re-saves.
// A12a: like `createPart`, a non-empty path gets `ensureFolder` first.
let putPart: (t, Types.part) => promise<Types.part>

let getPart: (t, string) => promise<option<Types.part>>

// updatedAt descending.
let listParts: t => promise<array<Types.part>>

// One bulkDocs call deletes the part doc, every face of the part, every
// dimension of the part, and its dogfood timer (if any).
let deletePart: (t, string) => promise<unit>

// -- folder management (SPEC §8a A12b) ---------------------------------------
//
// Refusals are `result`s, not exceptions; `NotEmpty` and `Nested` are
// unreachable from the A12b UI (delete only shows on empty leaves, an inline
// rename keeps the parent) and exist as store guards. Every multi-doc write
// is one `bulkDocs`; a per-doc rejection in its result throws, so the page
// shows its generic storage message rather than a silent half-move.
type folderError = NotEmpty | Exists | Nested

// `ensureFolder` first, then one `bulkDocs` rewriting each part whose `path`
// differs (`updatedAt` bumped, as `putPart`); parts already there are
// skipped. Returns the moved records only — `[]` when nothing moved.
let moveParts: (t, ~partIds: array<string>, ~path: string) => promise<array<Types.part>>

// `deletePart` for each id in sequence, inside one promise.
let deleteParts: (t, ~partIds: array<string>) => promise<unit>

// Removes the folder doc; `Error(NotEmpty)` while any part sits in it or
// under it (`Folder.isUnder`) or any folder doc is under it. A path with
// no doc is `Ok` (already gone).
let deleteFolder: (t, ~path: string) => promise<result<unit, folderError>>

// `to` is already validated by the page. `Error(Exists)` when a folder doc
// other than `from` equals `to` case-insensitively (a case-only rename is
// allowed); `Error(Nested)` when `to` is under `from`. Otherwise one
// `bulkDocs` deletes the old folder doc, creates the new one (`createdAt`
// kept, `updatedAt` bumped), rewrites every descendant folder doc
// (`Folder.rebase`) and every part whose `path == from` or is under it
// (`updatedAt` bumped), so the subtree follows. `from == to` is a no-op.
let renameFolder: (t, ~from: string, ~to: string) => promise<result<unit, folderError>>

// -- faces --------------------------------------------------------------

// Single `put` with an inline `_attachments` entry, so the doc and its
// image land in one atomic write — if the write rejects, no doc is
// created. Replaces an existing face doc with the same id (fetches the
// current `_rev` first).
let putFace: (
  t,
  Types.face,
  ~image: PouchDb.blob,
  ~contentType: string,
) => promise<Types.face>

let getFace: (t, string) => promise<option<Types.face>>
let getFaceImage: (t, string) => promise<option<PouchDb.blob>>

// Ordered top, side, end, detail (Enums.allFaceKinds order), then by
// `label` within a kind (SPEC §8a A7: a part may hold several faces of one
// kind). Face docs written before A7 carry no `label`; they read back with
// `label = Enums.faceKindToString(kind)`.
let facesOf: (t, ~partId: string) => promise<array<Types.face>>

// Face + its dimensions, one bulkDocs call.
let deleteFace: (t, string) => promise<unit>
let deleteDimensionsOfFace: (t, string) => promise<unit>

// -- dimensions ------------------------------------------------------------
//
// Dimension docs carry `partId` too (SPEC §6.1: every doc does), so writes
// take it explicitly — `Types.dimension` itself has no partId field.

let putDimension: (t, ~partId: string, Types.dimension) => promise<Types.dimension>
let getDimension: (t, string) => promise<option<Types.dimension>>

// createdAt ascending.
let dimensionsOf: (t, ~partId: string) => promise<array<Types.dimension>>
let dimensionsOfFace: (t, ~faceId: string) => promise<array<Types.dimension>>

let deleteDimension: (t, string) => promise<unit>

// -- settings ---------------------------------------------------------------
//
// Singleton doc `_id: "settings"`, type "settings".

// `snap` (SPEC §8a A5, default on): docs written before the field existed
// read back with the default.
type settings = {
  wedge: bool,
  snap: bool,
  lastToleranceMm: float,
  lastToleranceIn: float,
}

let defaultSettings: settings

let getSettings: t => promise<settings>
let putSettings: (t, settings) => promise<unit>

// -- dogfood timer (SPEC M6) ------------------------------------------------
//
// Doc `_id: "timer:" ++ partId`, type "timer".

type timer = {
  partId: string,
  startedAt: option<string>,
  stoppedAt: option<string>,
}

let getTimer: (t, ~partId: string) => promise<option<timer>>

// Sets startedAt = now only if unset (idempotent).
let startTimer: (t, ~partId: string) => promise<timer>

// Sets stoppedAt = now only if startedAt is set and stoppedAt is unset
// (idempotent).
let stopTimer: (t, ~partId: string) => promise<timer>

// Most recently updated first.
let listTimers: (t, ~limit: int) => promise<array<timer>>

// stopped − started, whole seconds. None unless both are set.
let handsOnSeconds: timer => option<int>
