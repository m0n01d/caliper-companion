// PouchDb — typed surface over `pouchdb` + `pouchdb-find` for what Store
// needs (SPEC.md §5, §6.1). Ported from the *patterns* in ternpike's
// src/pouch.js (construct, get/put/remove, bulkDocs, allDocs key-range
// scans) plus the pouchdb-find / attachments API ternpike doesn't use.
//
// Docs cross the boundary as `Dict.t<JSON.t>` — Store.res converts to/from
// the typed records in Types.res. This file never knows about parts, faces
// or dimensions.
//
// No `%raw`, no `Obj.magic`. All PouchDB access lives behind this module and
// Store.res — nowhere else.

type t

// -- construction & plugin registration -------------------------------

type dbOptions = {adapter?: string}

// Two bindings of the same `pouchdb` default export: `make` constructs
// instances (`@new`), `pouchDbClass` is the constructor value itself so we
// can call its static `.plugin(...)`.
@new @module("pouchdb") external make: (string, dbOptions) => t = "default"

type pouchDbClass
@module("pouchdb") external pouchDbClass: pouchDbClass = "default"

type findPluginT
@module("pouchdb-find") external findPlugin: findPluginT = "default"

@send external registerPlugin: (pouchDbClass, findPluginT) => unit = "plugin"

// Registers pouchdb-find on the PouchDB constructor. Idempotent at the
// PouchDB level (registering twice is harmless — PouchDB no-ops a repeat
// plugin), but Store.res only calls it once per process.
let registerFindPlugin = (): unit => registerPlugin(pouchDbClass, findPlugin)

// -- errors --------------------------------------------------------------
//
// PouchDB rejects with an object carrying `status`/`name`, not necessarily
// an `Error` instance. Any thrown/rejected JS value we catch comes back as
// the `JsExn(_)` exn constructor (see @rescript/runtime's Promise.catch
// doc example); `status` is read off it with a plain typed `@get`.

@get external errorStatus: JsExn.t => Nullable.t<int> = "status"

let hasStatus = (exn: exn, status: int): bool =>
  switch exn {
  | JsExn(err) =>
    switch errorStatus(err)->Nullable.toOption {
    | Some(s) => s == status
    | None => false
    }
  | _ => false
  }

let isNotFound = (exn: exn): bool => hasStatus(exn, 404)

// Not one of the required deliverables, but Store's "fetch _rev, retry once
// on 409" rule (SPEC M2 doc-mapping note) needs the same status inspection,
// so it lives here next to isNotFound rather than duplicating the JsExn
// dance privately in Store.
let isConflict = (exn: exn): bool => hasStatus(exn, 409)

// -- docs ------------------------------------------------------------------

type doc = Dict.t<JSON.t>

type putResult = {ok: bool, id: string, rev: string}

// Generic on purpose: most callers pass `doc` (Dict.t<JSON.t>), but a face
// write needs an inline `_attachments` dict whose `data` is a `blob`, which
// isn't representable in JSON.t. Store.res defines that record type locally
// and instantiates `put` with it — still fully typed, no escape hatch.
@send external put: (t, 'doc) => promise<putResult> = "put"

type getOptions = {attachments?: bool, binary?: bool, rev?: string}
@send external get: (t, string, getOptions) => promise<doc> = "get"

type removeResult = {ok: bool, id: string, rev: string}
@send external removeById: (t, string, string) => promise<removeResult> = "remove"

@send external bulkDocs: (t, array<doc>) => promise<array<doc>> = "bulkDocs"

// -- allDocs -----------------------------------------------------------

type allDocsOptions = {
  include_docs?: bool,
  startkey?: string,
  endkey?: string,
  descending?: bool,
}

type allDocsRowValue = {rev: string}
type allDocsRow = {id: string, key: string, value: allDocsRowValue, doc: Nullable.t<doc>}
type allDocsResult = {total_rows: int, offset: int, rows: array<allDocsRow>}

@send external allDocs: (t, allDocsOptions) => promise<allDocsResult> = "allDocs"

// -- find / createIndex (pouchdb-find) ----------------------------------

type findOptions = {
  selector: doc,
  sort?: array<JSON.t>,
  use_index?: string,
  limit?: int,
}
type findResult = {docs: array<doc>, warning: option<string>}

@send external find: (t, findOptions) => promise<findResult> = "find"

type indexDef = {fields: array<string>, name?: string}
type createIndexOptions = {index: indexDef}
type createIndexResult = {result: string}

@send
external createIndex: (t, createIndexOptions) => promise<createIndexResult> = "createIndex"

// Single-key objects, e.g. `{"partId": "asc"}` — one per indexed field.
type indexFieldEntry = Dict.t<JSON.t>
type indexDefInfo = {fields: array<indexFieldEntry>}
type indexEntry = {
  ddoc: Nullable.t<string>,
  name: string,
  @as("type") kind: string,
  def: indexDefInfo,
}
type getIndexesResult = {indexes: array<indexEntry>}

@send external getIndexes: t => promise<getIndexesResult> = "getIndexes"

// -- attachments -----------------------------------------------------------
//
// `blob` is the payload type for both directions: a real `Blob` (native in
// the browser; Node 22 also has a global `Blob`). Tests build one from raw
// bytes with `blobFromBytes`.
//
// Two runtime facts, both verified against this repo's actual pouchdb
// package (not assumed from docs), drive the rest of this section:
//
// 1. `getAttachment` does NOT return a `blob` on every platform: PouchDB's
//    Node build ("In Node, we store the buffer directly" — pouchdb's own
//    source comment) hands back a `Buffer`, which has no `.size`. The
//    browser build hands back a real `Blob`. `rawAttachment` names that
//    platform-shaped, honestly-opaque result; `blobOfRaw` normalizes it by
//    passing it through `new Blob([raw])` — valid because a `Buffer` is a
//    `BufferSource` (a legal Blob part) and an existing `Blob` is itself a
//    legal Blob part, so the same constructor call normalizes either.
// 2. Inline `_attachments[name].data` on `put` rejects a `Blob` on the same
//    Node build (`binaryMd5` hashes it with Node's `crypto`, which throws on
//    a `Blob`). The one payload shape PouchDB accepts identically on both
//    platforms is a base64 string, so `blobToBase64` is how Store.putFace
//    turns a `blob` into doc-safe data before the atomic `put` — this is
//    PouchDB's own attachment encoding, not a hand-rolled base64 field on
//    the doc body (the "never inline base64 in a doc body" rule is about
//    not adding a redundant custom field next to the real attachment).

type blob

@new external makeBlobFromParts: array<Uint8Array.t> => blob = "Blob"
let blobFromBytes = (bytes: Uint8Array.t): blob => makeBlobFromParts([bytes])

@get external blobSize: blob => int = "size"

@send external blobArrayBuffer: blob => promise<ArrayBuffer.t> = "arrayBuffer"

@val external btoa: string => string = "btoa"

// V8 (and this project's targets generally) throw "Maximum call stack size
// exceeded" if `String.fromCharCode` is spread over a whole multi-megabyte
// JPEG in one call, so this walks the bytes in bounded chunks.
let binaryStringChunkSize = 8192
let bytesToBinaryString = (bytes: Uint8Array.t): string => {
  let len = TypedArray.length(bytes)
  let chunks = []
  let i = ref(0)
  while i.contents < len {
    let chunkEnd = i.contents + binaryStringChunkSize > len
      ? len
      : i.contents + binaryStringChunkSize
    let chunkLen = chunkEnd - i.contents
    let codes = Array.fromInitializer(~length=chunkLen, j =>
      TypedArray.get(bytes, i.contents + j)->Option.getOr(0)
    )
    Array.push(chunks, String.fromCharCodeMany(codes))
    i := chunkEnd
  }
  Array.join(chunks, "")
}

let blobToBase64 = async (b: blob): string => {
  let buf = await blobArrayBuffer(b)
  btoa(bytesToBinaryString(Uint8Array.fromBuffer(buf)))
}

// Opaque: a `Buffer` on Node, a `Blob` in the browser. Never inspect it
// directly — normalize with `blobOfRaw`.
type rawAttachment
@new external wrapRawAsBlob: array<rawAttachment> => blob = "Blob"
let blobOfRaw = (raw: rawAttachment): blob => wrapRawAsBlob([raw])

// `rev` is required here: every caller in this codebase attaches to a doc
// that already exists (Store writes new face images via a single `put` with
// an inline `_attachments` entry instead — see Store.putFace — precisely so
// a brand-new face doesn't need this two-step, rev-less form of the API).
@send
external putAttachment: (t, string, string, string, blob, string) => promise<putResult> =
  "putAttachment"

@send
external getAttachment: (t, string, string) => promise<rawAttachment> = "getAttachment"

@send
external removeAttachment: (t, string, string, string) => promise<removeResult> =
  "removeAttachment"

// -- lifecycle -----------------------------------------------------------

type destroyResult = {ok: bool}
@send external destroy: t => promise<destroyResult> = "destroy"

type info = {db_name: string, doc_count: int}
@send external info: t => promise<info> = "info"
