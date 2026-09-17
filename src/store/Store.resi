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

// -- parts ------------------------------------------------------------------

// id, createdAt = updatedAt = now, anchors = []. `slug` is M1's Slug.make
// output — not available to this module, so the caller supplies it.
let createPart: (t, ~name: string, ~slug: string, ~units: Types.units) => promise<Types.part>

// Bumps updatedAt; returns the stored record (including the bumped
// updatedAt). Used for both edits (rename, notes) and explicit re-saves.
let putPart: (t, Types.part) => promise<Types.part>

let getPart: (t, string) => promise<option<Types.part>>

// updatedAt descending.
let listParts: t => promise<array<Types.part>>

// One bulkDocs call deletes the part doc, every face of the part, every
// dimension of the part, and its dogfood timer (if any).
let deletePart: (t, string) => promise<unit>

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

// Ordered top, side, end, detail (Enums.allFaceKinds order).
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

