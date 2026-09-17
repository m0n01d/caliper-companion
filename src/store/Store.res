// Store — the only module that touches PouchDB (SPEC.md §5, §6.1, M6). See
// Store.resi for the public contract; this file is the doc-mapping
// implementation behind it. No PouchDB calls anywhere else in the codebase.
//
// Read-path design note: SPEC §6.1 asks for two pouchdb-find indexes,
// `[type, partId]` and `[type, updatedAt]`, and `ensureIndexes` creates
// both (verified live — see StoreTest). But `facesOf`/`dimensionsOf`/
// `listParts` etc. do NOT query through `PouchDb.find`. Verified against
// the actual installed pouchdb-find: `find({selector: {type: "part"},
// sort: [{"updatedAt": "desc"}]})` throws "Cannot sort on field(s)
// 'updatedAt' when using the default index" even with an explicit
// `use_index` naming the exact compound index that covers it — a real
// limitation of this pouchdb-find version's query planner, not a typing
// gap. Every part/face/dimension id is already prefixed by its doc type
// ("part:", "face:", "dim:"), so every list/filter here is an `allDocs`
// key-range scan (the exact pattern ternpike's pouch.js uses for
// `expense::`/`amend::expense::` ids) followed by an in-memory filter and
// sort — reliable, and plenty fast at this app's single-user, dozens-of-
// docs scale. `PouchDb.find`/`createIndex` stay bound and correct for
// future use (a v1 sync-era query, or once the planner issue is
// understood), and the indexes themselves are still created as required.

type t = {db: PouchDb.t}

// -- generic doc dict helpers ---------------------------------------------

let setStr = (d: PouchDb.doc, key: string, v: string) => Dict.set(d, key, JSON.Encode.string(v))
let setBool = (d: PouchDb.doc, key: string, v: bool) => Dict.set(d, key, JSON.Encode.bool(v))
let setFloat = (d: PouchDb.doc, key: string, v: float) => Dict.set(d, key, JSON.Encode.float(v))

let setOptStr = (d: PouchDb.doc, key: string, v: option<string>) =>
  switch v {
  | Some(s) => setStr(d, key, s)
  | None => Dict.set(d, key, JSON.Null)
  }

let getStr = (d: PouchDb.doc, key: string): option<string> =>
  switch Dict.get(d, key) {
  | Some(JSON.String(s)) => Some(s)
  | _ => None
  }

let getFloat = (d: PouchDb.doc, key: string): option<float> =>
  switch Dict.get(d, key) {
  | Some(JSON.Number(n)) => Some(n)
  | _ => None
  }

let getInt = (d: PouchDb.doc, key: string): option<int> =>
  getFloat(d, key)->Option.map(Float.toInt)

let getBool = (d: PouchDb.doc, key: string): option<bool> =>
  switch Dict.get(d, key) {
  | Some(JSON.Boolean(b)) => Some(b)
  | _ => None
  }

let prefixEnd = (prefix: string): string => prefix ++ "￿0"

// -- point / anchor JSON -----------------------------------------------

let pointToJson = (p: Types.point): JSON.t => {
  let d = Dict.make()
  setFloat(d, "x", p.x)
  setFloat(d, "y", p.y)
  JSON.Encode.object(d)
}

let pointFromJson = (j: JSON.t): option<Types.point> =>
  switch j {
  | JSON.Object(d) =>
    switch (getFloat(d, "x"), getFloat(d, "y")) {
    | (Some(x), Some(y)) => Some({Types.x, y})
    | _ => None
    }
  | _ => None
  }

let anchorToJson = (a: Types.anchor): JSON.t => {
  let d = Dict.make()
  setStr(d, "family", a.family)
  Dict.set(d, "tagId", JSON.Encode.int(a.tagId))
  setFloat(d, "sizeMm", a.sizeMm)
  JSON.Encode.object(d)
}

let anchorFromJson = (j: JSON.t): option<Types.anchor> =>
  switch j {
  | JSON.Object(d) =>
    switch (getStr(d, "family"), getInt(d, "tagId"), getFloat(d, "sizeMm")) {
    | (Some(family), Some(tagId), Some(sizeMm)) => Some({Types.family, tagId, sizeMm})
    | _ => None
    }
  | _ => None
  }

// -- shared read/write plumbing --------------------------------------------

let allDocsRange = async (t: t, ~startkey: string, ~endkey: string): array<PouchDb.allDocsRow> => {
  let result = await PouchDb.allDocs(t.db, {include_docs: true, startkey, endkey})
  result.rows
}

let getDocRaw = async (t: t, id: string): option<PouchDb.doc> =>
  try {
    let doc = await PouchDb.get(t.db, id, {})
    Some(doc)
  } catch {
  | e if PouchDb.isNotFound(e) => None
  | e => throw(e)
  }

let revOf = (doc: option<PouchDb.doc>): option<string> => doc->Option.flatMap(d => getStr(d, "_rev"))

// Fetches the current doc (if any), lets `compute` decide the next doc to
// write from it, puts it, and — on a 409 — refetches and retries exactly
// once. `compute` returns `(docToWrite, valueToReturn)` so callers that
// need to inspect the *current* doc (the timer start/stop idempotence
// rules) and callers that only need the current `_rev` (every plain
// create/rename write) share one retry path.
let readModifyWrite = async (
  t: t,
  id: string,
  compute: option<PouchDb.doc> => ('doc, 'result),
): 'result => {
  let existing = await getDocRaw(t, id)
  let (doc, result) = compute(existing)
  try {
    let _ = await PouchDb.put(t.db, doc)
    result
  } catch {
  | e if PouchDb.isConflict(e) =>
    let existing2 = await getDocRaw(t, id)
    let (doc2, result2) = compute(existing2)
    let _ = await PouchDb.put(t.db, doc2)
    result2
  | e => throw(e)
  }
}

let deletionDoc = (id: string, rev: string): PouchDb.doc => {
  let d = Dict.make()
  setStr(d, "_id", id)
  setStr(d, "_rev", rev)
  setBool(d, "_deleted", true)
  d
}

// -- construction ---------------------------------------------------------

let indexTypePartId: PouchDb.indexDef = {fields: ["type", "partId"], name: "type_partId"}
let indexTypeUpdatedAt: PouchDb.indexDef = {fields: ["type", "updatedAt"], name: "type_updatedAt"}

let ensureIndexes = async (t: t): unit => {
  let _ = await PouchDb.createIndex(t.db, {index: indexTypePartId})
  let _ = await PouchDb.createIndex(t.db, {index: indexTypeUpdatedAt})
}

let findPluginRegistered = ref(false)
let ensureFindPluginRegistered = (): unit =>
  if !findPluginRegistered.contents {
    PouchDb.registerFindPlugin()
    findPluginRegistered := true
  }

let make = (~name, ~adapter=?): t => {
  ensureFindPluginRegistered()
  let dbOptions: PouchDb.dbOptions = {?adapter}
  let t = {db: PouchDb.make(name, dbOptions)}
  // Lazy, non-blocking: index creation doesn't gate regular get/put, only
  // `find()` (which this module's own read paths don't use — see the
  // module doc comment above). Swallow errors here; a caller that needs to
  // be sure indexes exist awaits `ensureIndexes` itself.
  ensureIndexes(t)->Promise.catch(_ => Promise.resolve())->Promise.ignore
  t
}

let sharedInstance: ref<option<t>> = ref(None)
let shared = (): t =>
  switch sharedInstance.contents {
  | Some(t) => t
  | None =>
    let t = make(~name="caliper-companion")
    sharedInstance := Some(t)
    t
  }

let destroy = async (t: t): unit => {
  let _ = await PouchDb.destroy(t.db)
}

// -- folders (SPEC §8a A12a) ------------------------------------------------
//
// `_id = "folder:" ++ path`, body `{type, path, createdAt, updatedAt}`. The
// path is already normalised, validated and snapped by the page (A10's
// rule: this module never normalises — checking *existence* is not
// normalising). The root ("") is never a doc.

let folderPrefix = "folder:"
let folderId = (path: string): string => folderPrefix ++ path

module FolderDoc = {
  let toDoc = (path: string, ~now: string): PouchDb.doc => {
    let d = Dict.make()
    setStr(d, "_id", folderId(path))
    setStr(d, "type", "folder")
    setStr(d, "path", path)
    setStr(d, "createdAt", now)
    setStr(d, "updatedAt", now)
    d
  }

  // The `path` field is the truth; an id-only fallback keeps a hand-edited
  // doc readable.
  let pathOf = (row: PouchDb.allDocsRow): string =>
    switch row.doc->Nullable.toOption->Option.flatMap(d => getStr(d, "path")) {
    | Some(path) => path
    | None => String.slice(row.id, ~start=String.length(folderPrefix))
    }
}

let folderRows = async (t: t): array<PouchDb.allDocsRow> =>
  await allDocsRange(t, ~startkey=folderPrefix, ~endkey=prefixEnd(folderPrefix))

let listFolders = async (t: t): array<string> => {
  let rows = await folderRows(t)
  rows
  ->Array.map(FolderDoc.pathOf)
  ->Array.filter(path => path != "")
  ->Array.toSorted((a, b) => String.compare(String.toLowerCase(a), String.toLowerCase(b)))
}

// One `allDocs` range on `folder:`, then one `bulkDocs` of every path in
// `paths` and every `Folder.ancestors` of them that has no doc yet. PouchDB
// reports a per-doc failure *inside* the result array (nothing throws), so
// a 409 there — a concurrent writer beat us to it — counts as already
// existing and is left out of the returned list. Returns the paths this
// call created, ancestors first.
let ensureFolders = async (t: t, ~paths: array<string>): array<string> => {
  let existing = await listFolders(t)
  let wanted = []
  paths->Array.forEach(path =>
    Array.concat(Folder.ancestors(path), [path])->Array.forEach(p =>
      if p != "" && !Array.includes(existing, p) && !Array.includes(wanted, p) {
        Array.push(wanted, p)
      }
    )
  )
  if Array.length(wanted) == 0 {
    []
  } else {
    let now = Clock.nowIso()
    let results = await PouchDb.bulkDocs(t.db, wanted->Array.map(p => FolderDoc.toDoc(p, ~now)))
    // Results come back in input order; `ok: true` is the one success shape.
    wanted->Array.filterWithIndex((_, i) =>
      switch results[i] {
      | Some(r) => getBool(r, "ok") == Some(true)
      | None => false
      }
    )
  }
}

let ensureFolder = async (t: t, ~path: string): array<string> => await ensureFolders(t, ~paths=[path])

// -- parts ------------------------------------------------------------------

module PartDoc = {
  let toDoc = (~rev: option<string>, p: Types.part): PouchDb.doc => {
    let d = Dict.make()
    setStr(d, "_id", p.id)
    switch rev {
    | Some(r) => setStr(d, "_rev", r)
    | None => ()
    }
    setStr(d, "type", "part")
    setStr(d, "partId", p.id)
    setStr(d, "name", p.name)
    setStr(d, "slug", p.slug)
    setStr(d, "path", p.path)
    setStr(d, "units", Enums.unitsToString(p.units))
    setStr(d, "notes", p.notes)
    Dict.set(d, "anchors", JSON.Encode.array(p.anchors->Array.map(anchorToJson)))
    setStr(d, "createdAt", p.createdAt)
    setStr(d, "updatedAt", p.updatedAt)
    d
  }

  let fromDoc = (d: PouchDb.doc): option<Types.part> =>
    switch (
      getStr(d, "_id"),
      getStr(d, "name"),
      getStr(d, "slug"),
      getStr(d, "units")->Option.flatMap(Enums.unitsFromString),
      getStr(d, "notes"),
      getStr(d, "createdAt"),
      getStr(d, "updatedAt"),
    ) {
    | (Some(id), Some(name), Some(slug), Some(units), Some(notes), Some(createdAt), Some(updatedAt)) =>
      let anchors = switch Dict.get(d, "anchors") {
      | Some(JSON.Array(arr)) => arr->Array.filterMap(anchorFromJson)
      | _ => []
      }
      // SPEC §8a A10: `path` is additive — part docs written before A10
      // carry none and read back at the root (the A7 `label` precedent).
      let path = getStr(d, "path")->Option.getOr("")
      Some({Types.id, name, slug, path, units, notes, anchors, createdAt, updatedAt})
    | _ => None
    }
}

let createPart = async (
  t: t,
  ~name: string,
  ~slug: string,
  ~path: string,
  ~units: Types.units,
): Types.part => {
  let now = Clock.nowIso()
  let part: Types.part = {
    id: Ids.part(),
    name,
    slug,
    path,
    units,
    notes: "",
    anchors: [],
    createdAt: now,
    updatedAt: now,
  }
  // A12a: every path a part carries has a folder doc (and its ancestors).
  if path != "" {
    let _ = await ensureFolder(t, ~path)
  }
  let _ = await PouchDb.put(t.db, PartDoc.toDoc(~rev=None, part))
  part
}

let putPart = async (t: t, part: Types.part): Types.part => {
  if part.path != "" {
    let _ = await ensureFolder(t, ~path=part.path)
  }
  await readModifyWrite(t, part.id, existing => {
    let updated = {...part, updatedAt: Clock.nowIso()}
    (PartDoc.toDoc(~rev=revOf(existing), updated), updated)
  })
}

let getPart = async (t: t, id: string): option<Types.part> =>
  switch await getDocRaw(t, id) {
  | Some(doc) => PartDoc.fromDoc(doc)
  | None => None
  }

let listParts = async (t: t): array<Types.part> => {
  let rows = await allDocsRange(t, ~startkey="part:", ~endkey=prefixEnd("part:"))
  let parts = rows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) => PartDoc.fromDoc(doc)
    | None => None
    }
  )
  parts->Array.toSorted((a, b) => String.compare(b.updatedAt, a.updatedAt))
}

let timerId = (~partId: string): string => "timer:" ++ partId

let deletePart = async (t: t, partId: string): unit => {
  let partDoc = await getDocRaw(t, partId)
  let faceRows = await allDocsRange(t, ~startkey="face:", ~endkey=prefixEnd("face:"))
  let dimRows = await allDocsRange(t, ~startkey="dim:", ~endkey=prefixEnd("dim:"))
  let timerDoc = await getDocRaw(t, timerId(~partId))

  let deletions = []
  switch revOf(partDoc) {
  | Some(rev) => Array.push(deletions, deletionDoc(partId, rev))
  | None => ()
  }
  faceRows->Array.forEach(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "partId") == Some(partId) =>
      Array.push(deletions, deletionDoc(row.id, row.value.rev))
    | _ => ()
    }
  )
  dimRows->Array.forEach(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "partId") == Some(partId) =>
      Array.push(deletions, deletionDoc(row.id, row.value.rev))
    | _ => ()
    }
  )
  switch revOf(timerDoc) {
  | Some(rev) => Array.push(deletions, deletionDoc(timerId(~partId), rev))
  | None => ()
  }

  if Array.length(deletions) > 0 {
    let _ = await PouchDb.bulkDocs(t.db, deletions)
  }
}

// -- faces --------------------------------------------------------------

let kindRank = (k: Types.faceKind): int =>
  switch k {
  | Top => 0
  | Side => 1
  | End => 2
  | Detail => 3
  }

let optFloatToJson = (v: option<float>): JSON.t =>
  switch v {
  | Some(f) => JSON.Encode.float(f)
  | None => JSON.Null
  }

let outlineToJson = (v: option<array<Types.point>>): JSON.t =>
  switch v {
  | Some(pts) => JSON.Encode.array(pts->Array.map(pointToJson))
  | None => JSON.Null
  }

module FaceDoc = {
  let fromDoc = (d: PouchDb.doc): option<Types.face> =>
    switch (
      getStr(d, "_id"),
      getStr(d, "partId"),
      getStr(d, "kind")->Option.flatMap(Enums.faceKindFromString),
      getStr(d, "imageAttachment"),
      getInt(d, "pixelWidth"),
      getInt(d, "pixelHeight"),
      getStr(d, "capturedAt"),
    ) {
    | (
        Some(id),
        Some(partId),
        Some(kind),
        Some(imageAttachment),
        Some(pixelWidth),
        Some(pixelHeight),
        Some(capturedAt),
      ) =>
      // SPEC §8a A7: `label` is additive — docs written before A7 (the
      // owner's phone) have none and read back as the default face of
      // their kind, so their export paths are unchanged.
      let label = getStr(d, "label")->Option.getOr(Enums.faceKindToString(kind))
      let levelDegrees = getFloat(d, "levelDegrees")
      let outline = switch Dict.get(d, "outline") {
      | Some(JSON.Array(arr)) => Some(arr->Array.filterMap(pointFromJson))
      | _ => None
      }
      Some({
        Types.id,
        partId,
        kind,
        label,
        imageAttachment,
        pixelWidth,
        pixelHeight,
        levelDegrees,
        outline,
        capturedAt,
      })
    | _ => None
    }
}

// A separate record type (not PouchDb.doc = Dict.t<JSON.t>) because
// `_attachments[name].data` is a base64 string PouchDb builds via
// `PouchDb.blobToBase64` — see PouchDb.res's attachments section for why
// that's the one payload shape PouchDB accepts identically on every
// platform. `PouchDb.put` is generic, so this instantiates it directly;
// still fully typed, no escape hatch.
type inlineAttachmentEntry = {content_type: string, data: string}
type faceWriteDoc = {
  _id: string,
  _rev?: string,
  @as("type") docType: string,
  partId: string,
  kind: string,
  label: string,
  imageAttachment: string,
  pixelWidth: int,
  pixelHeight: int,
  levelDegrees: JSON.t,
  outline: JSON.t,
  capturedAt: string,
  updatedAt: string,
  _attachments: Dict.t<inlineAttachmentEntry>,
}

let putFace = async (
  t: t,
  face: Types.face,
  ~image: PouchDb.blob,
  ~contentType: string,
): Types.face => {
  let base64 = await PouchDb.blobToBase64(image)
  let attachments = Dict.make()
  Dict.set(attachments, face.imageAttachment, {content_type: contentType, data: base64})
  await readModifyWrite(t, face.id, existing => {
    let _rev = revOf(existing)
    let doc: faceWriteDoc = {
      _id: face.id,
      ?_rev,
      docType: "face",
      partId: face.partId,
      kind: Enums.faceKindToString(face.kind),
      label: face.label,
      imageAttachment: face.imageAttachment,
      pixelWidth: face.pixelWidth,
      pixelHeight: face.pixelHeight,
      levelDegrees: optFloatToJson(face.levelDegrees),
      outline: outlineToJson(face.outline),
      capturedAt: face.capturedAt,
      updatedAt: Clock.nowIso(),
      _attachments: attachments,
    }
    (doc, face)
  })
}

let getFace = async (t: t, id: string): option<Types.face> =>
  switch await getDocRaw(t, id) {
  | Some(doc) => FaceDoc.fromDoc(doc)
  | None => None
  }

let getFaceImage = async (t: t, faceId: string): option<PouchDb.blob> =>
  switch await getFace(t, faceId) {
  | None => None
  | Some(face) =>
    try {
      let raw = await PouchDb.getAttachment(t.db, faceId, face.imageAttachment)
      Some(PouchDb.blobOfRaw(raw))
    } catch {
    | e if PouchDb.isNotFound(e) => None
    | e => throw(e)
    }
  }

let facesOf = async (t: t, ~partId: string): array<Types.face> => {
  let rows = await allDocsRange(t, ~startkey="face:", ~endkey=prefixEnd("face:"))
  let faces = rows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "partId") == Some(partId) => FaceDoc.fromDoc(doc)
    | _ => None
    }
  )
  // Kind order, then label (SPEC §8a A7: several faces may share a kind).
  faces->Array.toSorted((a, b) => {
    let byKind = Ordering.fromInt(kindRank(a.kind) - kindRank(b.kind))
    Ordering.isEqual(byKind) ? String.compare(a.label, b.label) : byKind
  })
}

let deleteFace = async (t: t, faceId: string): unit => {
  let faceDoc = await getDocRaw(t, faceId)
  let dimRows = await allDocsRange(t, ~startkey="dim:", ~endkey=prefixEnd("dim:"))

  let deletions = []
  switch revOf(faceDoc) {
  | Some(rev) => Array.push(deletions, deletionDoc(faceId, rev))
  | None => ()
  }
  dimRows->Array.forEach(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "faceId") == Some(faceId) =>
      Array.push(deletions, deletionDoc(row.id, row.value.rev))
    | _ => ()
    }
  )

  if Array.length(deletions) > 0 {
    let _ = await PouchDb.bulkDocs(t.db, deletions)
  }
}

let deleteDimensionsOfFace = async (t: t, faceId: string): unit => {
  let dimRows = await allDocsRange(t, ~startkey="dim:", ~endkey=prefixEnd("dim:"))
  let deletions = dimRows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "faceId") == Some(faceId) => Some(deletionDoc(row.id, row.value.rev))
    | _ => None
    }
  )
  if Array.length(deletions) > 0 {
    let _ = await PouchDb.bulkDocs(t.db, deletions)
  }
}

// -- dimensions ------------------------------------------------------------

module DimensionDoc = {
  let toDoc = (~rev: option<string>, ~partId: string, d: Types.dimension): PouchDb.doc => {
    let doc = Dict.make()
    setStr(doc, "_id", d.id)
    switch rev {
    | Some(r) => setStr(doc, "_rev", r)
    | None => ()
    }
    setStr(doc, "type", "dimension")
    setStr(doc, "partId", partId)
    setStr(doc, "faceId", d.faceId)
    setStr(doc, "name", d.name)
    setStr(doc, "kind", Enums.dimensionKindToString(d.kind))
    setFloat(doc, "value", d.value)
    setFloat(doc, "tolerance", d.tolerance)
    Dict.set(doc, "p1", pointToJson(d.p1))
    Dict.set(doc, "p2", pointToJson(d.p2))
    setStr(doc, "source", Enums.readingSourceToString(d.source))
    setStr(doc, "createdAt", d.createdAt)
    setStr(doc, "updatedAt", Clock.nowIso())
    doc
  }

  let fromDoc = (doc: PouchDb.doc): option<Types.dimension> =>
    switch (
      getStr(doc, "_id"),
      getStr(doc, "faceId"),
      getStr(doc, "name"),
      getStr(doc, "kind")->Option.flatMap(Enums.dimensionKindFromString),
      getFloat(doc, "value"),
      getFloat(doc, "tolerance"),
      Dict.get(doc, "p1")->Option.flatMap(pointFromJson),
      Dict.get(doc, "p2")->Option.flatMap(pointFromJson),
      getStr(doc, "source")->Option.flatMap(Enums.readingSourceFromString),
      getStr(doc, "createdAt"),
    ) {
    | (
        Some(id),
        Some(faceId),
        Some(name),
        Some(kind),
        Some(value),
        Some(tolerance),
        Some(p1),
        Some(p2),
        Some(source),
        Some(createdAt),
      ) =>
      Some({Types.id, faceId, name, kind, value, tolerance, p1, p2, source, createdAt})
    | _ => None
    }
}

let putDimension = async (t: t, ~partId: string, dim: Types.dimension): Types.dimension =>
  await readModifyWrite(t, dim.id, existing =>
    (DimensionDoc.toDoc(~rev=revOf(existing), ~partId, dim), dim)
  )

let getDimension = async (t: t, id: string): option<Types.dimension> =>
  switch await getDocRaw(t, id) {
  | Some(doc) => DimensionDoc.fromDoc(doc)
  | None => None
  }

let dimensionsOf = async (t: t, ~partId: string): array<Types.dimension> => {
  let rows = await allDocsRange(t, ~startkey="dim:", ~endkey=prefixEnd("dim:"))
  let dims = rows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "partId") == Some(partId) => DimensionDoc.fromDoc(doc)
    | _ => None
    }
  )
  dims->Array.toSorted((a, b) => String.compare(a.createdAt, b.createdAt))
}

let dimensionsOfFace = async (t: t, ~faceId: string): array<Types.dimension> => {
  let rows = await allDocsRange(t, ~startkey="dim:", ~endkey=prefixEnd("dim:"))
  let dims = rows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) if getStr(doc, "faceId") == Some(faceId) => DimensionDoc.fromDoc(doc)
    | _ => None
    }
  )
  dims->Array.toSorted((a, b) => String.compare(a.createdAt, b.createdAt))
}

let deleteDimension = async (t: t, id: string): unit =>
  switch revOf(await getDocRaw(t, id)) {
  | Some(rev) =>
    let _ = await PouchDb.removeById(t.db, id, rev)
  | None => ()
  }

// -- settings ---------------------------------------------------------------

type settings = {
  wedge: bool,
  snap: bool, // SPEC §8a A5: snap taps to edges on the annotate canvas
  lastToleranceMm: float,
  lastToleranceIn: float,
}

let defaultSettings: settings = {
  wedge: false,
  snap: true,
  lastToleranceMm: 0.10,
  lastToleranceIn: 0.005,
}

let settingsId = "settings"

module SettingsDoc = {
  let toDoc = (~rev: option<string>, s: settings): PouchDb.doc => {
    let d = Dict.make()
    setStr(d, "_id", settingsId)
    switch rev {
    | Some(r) => setStr(d, "_rev", r)
    | None => ()
    }
    setStr(d, "type", "settings")
    setStr(d, "partId", "")
    setBool(d, "wedge", s.wedge)
    setBool(d, "snap", s.snap)
    setFloat(d, "lastToleranceMm", s.lastToleranceMm)
    setFloat(d, "lastToleranceIn", s.lastToleranceIn)
    setStr(d, "updatedAt", Clock.nowIso())
    d
  }

  // `snap` arrived with SPEC §8a A5; a settings doc written before it has
  // no such field and reads back with the default (on), same as a doc
  // that was never written at all.
  let fromDoc = (d: PouchDb.doc): option<settings> =>
    switch (getBool(d, "wedge"), getFloat(d, "lastToleranceMm"), getFloat(d, "lastToleranceIn")) {
    | (Some(wedge), Some(lastToleranceMm), Some(lastToleranceIn)) =>
      Some({
        wedge,
        snap: getBool(d, "snap")->Option.getOr(defaultSettings.snap),
        lastToleranceMm,
        lastToleranceIn,
      })
    | _ => None
    }
}

let getSettings = async (t: t): settings =>
  switch await getDocRaw(t, settingsId) {
  | Some(doc) =>
    switch SettingsDoc.fromDoc(doc) {
    | Some(s) => s
    | None => defaultSettings
    }
  | None => defaultSettings
  }

let putSettings = async (t: t, s: settings): unit => {
  let _ = await readModifyWrite(t, settingsId, existing => (
    SettingsDoc.toDoc(~rev=revOf(existing), s),
    (),
  ))
}

// -- dogfood timer (SPEC M6) ------------------------------------------------

type timer = {
  partId: string,
  startedAt: option<string>,
  stoppedAt: option<string>,
}

module TimerDoc = {
  let toDoc = (~rev: option<string>, tm: timer): PouchDb.doc => {
    let d = Dict.make()
    setStr(d, "_id", timerId(~partId=tm.partId))
    switch rev {
    | Some(r) => setStr(d, "_rev", r)
    | None => ()
    }
    setStr(d, "type", "timer")
    setStr(d, "partId", tm.partId)
    setOptStr(d, "startedAt", tm.startedAt)
    setOptStr(d, "stoppedAt", tm.stoppedAt)
    setStr(d, "updatedAt", Clock.nowIso())
    d
  }

  let fromDoc = (d: PouchDb.doc): option<timer> =>
    switch getStr(d, "partId") {
    | Some(partId) => Some({partId, startedAt: getStr(d, "startedAt"), stoppedAt: getStr(d, "stoppedAt")})
    | None => None
    }
}

let getTimer = async (t: t, ~partId: string): option<timer> =>
  switch await getDocRaw(t, timerId(~partId)) {
  | Some(doc) => TimerDoc.fromDoc(doc)
  | None => None
  }

let startTimer = async (t: t, ~partId: string): timer =>
  await readModifyWrite(t, timerId(~partId), existing => {
    let current = existing->Option.flatMap(TimerDoc.fromDoc)
    let updated = switch current {
    | Some(tm) if tm.startedAt->Option.isSome => tm
    | Some(tm) => {...tm, startedAt: Some(Clock.nowIso())}
    | None => {partId, startedAt: Some(Clock.nowIso()), stoppedAt: None}
    }
    (TimerDoc.toDoc(~rev=revOf(existing), updated), updated)
  })

let stopTimer = async (t: t, ~partId: string): timer =>
  await readModifyWrite(t, timerId(~partId), existing => {
    let current = existing->Option.flatMap(TimerDoc.fromDoc)
    let updated = switch current {
    | Some(tm) if tm.startedAt->Option.isSome && tm.stoppedAt->Option.isNone => {
        ...tm,
        stoppedAt: Some(Clock.nowIso()),
      }
    | Some(tm) => tm
    | None => {partId, startedAt: None, stoppedAt: None}
    }
    (TimerDoc.toDoc(~rev=revOf(existing), updated), updated)
  })

let listTimers = async (t: t, ~limit: int): array<timer> => {
  let rows = await allDocsRange(t, ~startkey="timer:", ~endkey=prefixEnd("timer:"))
  let withUpdatedAt = rows->Array.filterMap(row =>
    switch row.doc->Nullable.toOption {
    | Some(doc) =>
      switch (TimerDoc.fromDoc(doc), getStr(doc, "updatedAt")) {
      | (Some(tm), Some(updatedAt)) => Some((updatedAt, tm))
      | _ => None
      }
    | None => None
    }
  )
  let sorted = withUpdatedAt->Array.toSorted(((aUpdatedAt, _), (bUpdatedAt, _)) =>
    String.compare(bUpdatedAt, aUpdatedAt)
  )
  sorted->Array.slice(~start=0, ~end=limit)->Array.map(((_, tm)) => tm)
}

let handsOnSeconds = (tm: timer): option<int> =>
  switch (tm.startedAt, tm.stoppedAt) {
  | (Some(start), Some(stop)) =>
    let startMs = Date.fromString(start)->Date.getTime
    let stopMs = Date.fromString(stop)->Date.getTime
    Some(Float.toInt((stopMs -. startMs) /. 1000.0))
  | _ => None
  }
