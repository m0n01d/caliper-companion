// StoreTest — exercises Store.res (SPEC.md M2 acceptance criteria) against
// the real pouchdb package. Runs in node (vitest.config.js), so `pouchdb`
// resolves to its LevelDB adapter: each test gets a fresh `mkdtemp`
// directory under os.tmpdir() (`freshStore`/`openStore`), and `afterEach`
// destroys every Store the test opened — on failure too, so a broken
// assertion never leaves a LevelDB handle open for the next test.
//
// A couple of tests open a second, raw `PouchDb.t` handle on the same
// on-disk directory a test's Store already owns (verified live: two
// PouchDB handles on the same leveldown path coexist fine, no lock
// conflict). That's the only way to check `db.getIndexes()` and a raw
// `allDocs` doc count from outside Store's opaque `t` — Store.resi doesn't
// (and per CLAUDE.md, other app code shouldn't) expose the underlying
// PouchDb.t. It's test-only verification of what's on disk, not a second
// production access path.

open Vitest

@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:path") external pathJoin: (string, string) => string = "join"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("vitest") external afterEach: (unit => promise<unit>) => unit = "afterEach"

let freshDbPath = (): string => mkdtempSync(pathJoin(tmpdir(), "caliper-store-test-"))

// Every Store a test opens, destroyed after it whether it passed or not.
let opened: array<Store.t> = []

let openStore = (dir: string): Store.t => {
  let store = Store.make(~name=dir)
  opened->Array.push(store)
  store
}

let freshStore = (): Store.t => openStore(freshDbPath())

afterEach(async () => {
  let stores = opened->Array.copy
  opened->Array.splice(~start=0, ~remove=Array.length(opened), ~insert=[])
  for i in 0 to Array.length(stores) - 1 {
    switch stores[i] {
    | Some(store) => await Store.destroy(store)
    | None => ()
    }
  }
})

// The clock is `Clock.nowIso()` at millisecond resolution, so two writes in
// the same millisecond get the same `updatedAt`; a test that asserts an
// order by that field waits for the clock to move past a given stamp first.
let sleep = (ms: int): promise<unit> =>
  Promise.make((resolve, _reject) => {
    let _ = setTimeout(() => resolve(), ms)
  })

let rec clockPast = async (stamp: string): unit =>
  if Clock.nowIso() <= stamp {
    await sleep(1)
    await clockPast(stamp)
  }

let onePixelBlob = () => PouchDb.blobFromBytes(Uint8Array.fromArray([1]))

let mkFace = (~partId: string, ~kind: Types.faceKind, ~label: option<string>=?): Types.face => {
  id: Ids.face(),
  partId,
  kind,
  label: label->Option.getOr(Enums.faceKindToString(kind)),
  imageAttachment: "image.jpg",
  pixelWidth: 1,
  pixelHeight: 1,
  levelDegrees: None,
  outline: None,
  capturedAt: Clock.nowIso(),
}

let mkDim = (~faceId: string, ~name: string, ~createdAt: string): Types.dimension => {
  id: Ids.dimension(),
  faceId,
  name,
  kind: Types.Length,
  value: 1.0,
  tolerance: 0.1,
  p1: {x: 0.0, y: 0.0},
  p2: {x: 1.0, y: 1.0},
  source: Types.Typed,
  createdAt,
}

describe("Store — parts", () => {
  testAsync("create, list, rename (putPart), and delete a part", async () => {
    let store = freshStore()

    let part = await Store.createPart(store, ~name="Hinge Pin", ~slug="hinge_pin", ~path="", ~units=Types.Mm)
    expect(part.name)->toBe("Hinge Pin")
    expect(part.slug)->toBe("hinge_pin")
    expect(part.anchors)->toEqual([])
    expect(part.createdAt)->toBe(part.updatedAt)

    let listed = await Store.listParts(store)
    expect(listed->Array.map(p => p.id))->toEqual([part.id])

    let renamed = {...part, name: "Hinge Pin v2"}
    let saved = await Store.putPart(store, renamed)
    expect(saved.name)->toBe("Hinge Pin v2")
    expect(saved.id)->toBe(part.id)

    let fetched = await Store.getPart(store, part.id)
    expect(fetched->Option.map(p => p.name))->toEqual(Some("Hinge Pin v2"))

    await Store.deletePart(store, part.id)
    let afterDelete = await Store.getPart(store, part.id)
    expect(afterDelete)->toEqual(None)
    let listedAfter = await Store.listParts(store)
    expect(listedAfter)->toEqual([])
  })

  testAsync("listParts orders updatedAt descending", async () => {
    let store = freshStore()
    let a = await Store.createPart(store, ~name="A", ~slug="a", ~path="", ~units=Types.Mm)
    let b = await Store.createPart(store, ~name="B", ~slug="b", ~path="", ~units=Types.Mm)
    // Re-save `a` so its updatedAt is the most recent — strictly: `putPart`
    // stamps `Clock.nowIso()`, and in the same millisecond as `b`'s
    // creation the two would tie and sort in id (random uuid) order.
    await clockPast(b.updatedAt)
    let saved = await Store.putPart(store, a)
    expect(saved.updatedAt > b.updatedAt)->toBeTruthy

    let listed = await Store.listParts(store)
    expect(listed->Array.map(p => p.id))->toEqual([a.id, b.id])
  })

  testAsync(
    "deletePart removes its faces, dimensions, and timer in one bulk write",
    async () => {
      let dir = freshDbPath()
      let store = openStore(dir)
      // `Store.make` kicks off `ensureIndexes` in the background, and each
      // index is a `_design/` doc that `allDocs().total_rows` counts. Under
      // the parallel full-suite run the second index write could land
      // between the two counts below (observed: "expected 2 to be 1" —
      // one design doc in `before`, two in `after`). Awaiting the
      // idempotent `ensureIndexes` first makes the doc set stable.
      await Store.ensureIndexes(store)
      let part = await Store.createPart(store, ~name="P5", ~slug="p5", ~path="", ~units=Types.Mm)
      let face = await Store.putFace(
        store,
        mkFace(~partId=part.id, ~kind=Types.Top),
        ~image=onePixelBlob(),
        ~contentType="image/jpeg",
      )
      let dim = await Store.putDimension(
        store,
        ~partId=part.id,
        mkDim(~faceId=face.id, ~name="l", ~createdAt=Clock.nowIso()),
      )
      let _ = await Store.startTimer(store, ~partId=part.id)

      let raw = PouchDb.make(dir, {})
      let beforeCount = (await PouchDb.allDocs(raw, {})).total_rows

      await Store.deletePart(store, part.id)

      let afterCount = (await PouchDb.allDocs(raw, {})).total_rows
      // part + face + dimension + timer = 4 docs gone, in one write.
      expect(afterCount)->toBe(beforeCount - 4)

      expect(await Store.getFace(store, face.id))->toEqual(None)
      expect(await Store.getDimension(store, dim.id))->toEqual(None)
      expect(await Store.getTimer(store, ~partId=part.id))->toEqual(None)
    },
  )
})

describe("Store — faces", () => {
  testAsync(
    "putFace stores the doc and its attachment atomically; getFaceImage reads it back",
    async () => {
      let store = freshStore()
      let part = await Store.createPart(store, ~name="P", ~slug="p", ~path="", ~units=Types.Mm)
      let face = mkFace(~partId=part.id, ~kind=Types.Top)
      let bytes = Uint8Array.fromArray([1, 2, 3, 4, 5, 6, 7, 8])
      let saved = await Store.putFace(
        store,
        face,
        ~image=PouchDb.blobFromBytes(bytes),
        ~contentType="image/jpeg",
      )
      expect(saved.id)->toBe(face.id)

      let fetched = await Store.getFace(store, face.id)
      expect(fetched->Option.map(f => f.kind))->toEqual(Some(Types.Top))

      let image = await Store.getFaceImage(store, face.id)
      expect(image->Option.map(PouchDb.blobSize))->toEqual(Some(8))
    },
  )

  // SPEC M2: "A face doc is written only after its image attachment write
  // resolves; failure leaves no orphan doc." Store.putFace enforces this by
  // construction — the doc and its `_attachments` entry are one `put` call,
  // so PouchDB either writes both or neither; there is no separate
  // "attachment write" step that can fail after the doc commits. We can't
  // force a real PouchDB rejection from outside PouchDb.res without a
  // dedicated mistyped test-only binding (not allowed), so this tests the
  // observable contract instead: an id that was never successfully put has
  // no doc and no attachment, and a successful put always yields both
  // together.
  testAsync(
    "face writes are atomic: an unwritten id has no doc; a successful put yields doc + attachment together",
    async () => {
      let store = freshStore()

      let neverWrittenId = Ids.face()
      expect(await Store.getFace(store, neverWrittenId))->toEqual(None)
      expect(await Store.getFaceImage(store, neverWrittenId))->toEqual(None)

      let part = await Store.createPart(store, ~name="P2", ~slug="p2", ~path="", ~units=Types.Mm)
      let face = mkFace(~partId=part.id, ~kind=Types.Side)
      let _ = await Store.putFace(
        store,
        face,
        ~image=PouchDb.blobFromBytes(Uint8Array.fromArray([9, 9, 9])),
        ~contentType="image/jpeg",
      )

      let doc = await Store.getFace(store, face.id)
      let image = await Store.getFaceImage(store, face.id)
      expect(doc->Option.isSome)->toBeTruthy
      expect(image->Option.map(PouchDb.blobSize))->toEqual(Some(3))
    },
  )

  testAsync("facesOf orders top, side, end, detail regardless of write order", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P3", ~slug="p3", ~path="", ~units=Types.Mm)
    let put = kind =>
      Store.putFace(
        store,
        mkFace(~partId=part.id, ~kind),
        ~image=onePixelBlob(),
        ~contentType="image/jpeg",
      )
    let _ = await put(Types.Detail)
    let _ = await put(Types.Top)
    let _ = await put(Types.End)
    let _ = await put(Types.Side)

    let faces = await Store.facesOf(store, ~partId=part.id)
    expect(faces->Array.map(f => f.kind))->toEqual([Types.Top, Types.Side, Types.End, Types.Detail])
  })

  testAsync("deleteFace removes the face and its dimensions", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P6", ~slug="p6", ~path="", ~units=Types.Mm)
    let face = await Store.putFace(
      store,
      mkFace(~partId=part.id, ~kind=Types.Top),
      ~image=onePixelBlob(),
      ~contentType="image/jpeg",
    )
    let dim = await Store.putDimension(
      store,
      ~partId=part.id,
      mkDim(~faceId=face.id, ~name="l", ~createdAt=Clock.nowIso()),
    )

    await Store.deleteFace(store, face.id)

    expect(await Store.getFace(store, face.id))->toEqual(None)
    expect(await Store.getDimension(store, dim.id))->toEqual(None)
  })
})

describe("Store — dimensions", () => {
  testAsync("dimensionsOf and dimensionsOfFace order createdAt ascending", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P4", ~slug="p4", ~path="", ~units=Types.Mm)
    let face = await Store.putFace(
      store,
      mkFace(~partId=part.id, ~kind=Types.Top),
      ~image=onePixelBlob(),
      ~contentType="image/jpeg",
    )

    let _ = await Store.putDimension(
      store,
      ~partId=part.id,
      mkDim(~faceId=face.id, ~name="b", ~createdAt="2026-01-02T00:00:00.000Z"),
    )
    let _ = await Store.putDimension(
      store,
      ~partId=part.id,
      mkDim(~faceId=face.id, ~name="a", ~createdAt="2026-01-01T00:00:00.000Z"),
    )
    let _ = await Store.putDimension(
      store,
      ~partId=part.id,
      mkDim(~faceId=face.id, ~name="c", ~createdAt="2026-01-03T00:00:00.000Z"),
    )

    let byPart = await Store.dimensionsOf(store, ~partId=part.id)
    expect(byPart->Array.map(d => d.name))->toEqual(["a", "b", "c"])

    let byFace = await Store.dimensionsOfFace(store, ~faceId=face.id)
    expect(byFace->Array.map(d => d.name))->toEqual(["a", "b", "c"])
  })

  testAsync("deleteDimension removes a single dimension", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P7", ~slug="p7", ~path="", ~units=Types.Mm)
    let face = await Store.putFace(
      store,
      mkFace(~partId=part.id, ~kind=Types.Top),
      ~image=onePixelBlob(),
      ~contentType="image/jpeg",
    )
    let dim = await Store.putDimension(
      store,
      ~partId=part.id,
      mkDim(~faceId=face.id, ~name="l", ~createdAt=Clock.nowIso()),
    )

    await Store.deleteDimension(store, dim.id)
    expect(await Store.getDimension(store, dim.id))->toEqual(None)
  })
})

describe("Store — settings", () => {
  testAsync("defaults when absent, then round-trips a write", async () => {
    let store = freshStore()

    let initial = await Store.getSettings(store)
    expect(initial)->toEqual(Store.defaultSettings)

    let updated: Store.settings = {
      wedge: true,
      snap: false,
      lastToleranceMm: 0.2,
      lastToleranceIn: 0.008,
    }
    await Store.putSettings(store, updated)
    let fetched = await Store.getSettings(store)
    expect(fetched)->toEqual(updated)

    // A second write (e.g. toggling wedge back) must not 409 — putSettings
    // fetches the current _rev internally.
    let updated2 = {...updated, wedge: false, snap: true}
    await Store.putSettings(store, updated2)
    let fetched2 = await Store.getSettings(store)
    expect(fetched2)->toEqual(updated2)
  })

  // SPEC §8a A5: `snap` defaults on. A settings doc written before the field
  // existed (the owner's phone has one) has no `snap` at all and must read
  // back as on — written through a raw handle because Store itself can no
  // longer produce such a doc.
  testAsync("a settings doc written without snap reads back with snap = true", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)

    let raw = PouchDb.make(dir, {})
    let doc: PouchDb.doc = Dict.make()
    Dict.set(doc, "_id", JSON.Encode.string("settings"))
    Dict.set(doc, "type", JSON.Encode.string("settings"))
    Dict.set(doc, "partId", JSON.Encode.string(""))
    Dict.set(doc, "wedge", JSON.Encode.bool(true))
    Dict.set(doc, "lastToleranceMm", JSON.Encode.float(0.3))
    Dict.set(doc, "lastToleranceIn", JSON.Encode.float(0.01))
    Dict.set(doc, "updatedAt", JSON.Encode.string(Clock.nowIso()))
    let _ = await PouchDb.put(raw, doc)

    let fetched = await Store.getSettings(store)
    expect(fetched)->toEqual({
      Store.wedge: true,
      snap: true,
      lastToleranceMm: 0.3,
      lastToleranceIn: 0.01,
    })
    expect(Store.defaultSettings.snap)->toBe(true)
  })
})

describe("Store — dogfood timer (M6)", () => {
  testAsync("start/stop are idempotent; handsOnSeconds and listTimers work", async () => {
    let store = freshStore()
    let partId = "part:timer-test"

    expect(await Store.getTimer(store, ~partId))->toEqual(None)

    let started = await Store.startTimer(store, ~partId)
    expect(started.startedAt->Option.isSome)->toBeTruthy
    expect(started.stoppedAt)->toEqual(None)

    // Idempotent: starting again does not move startedAt.
    let startedAgain = await Store.startTimer(store, ~partId)
    expect(startedAgain.startedAt)->toEqual(started.startedAt)

    let stopped = await Store.stopTimer(store, ~partId)
    expect(stopped.stoppedAt->Option.isSome)->toBeTruthy

    // Idempotent: stopping again does not move stoppedAt.
    let stoppedAgain = await Store.stopTimer(store, ~partId)
    expect(stoppedAgain.stoppedAt)->toEqual(stopped.stoppedAt)

    expect(Store.handsOnSeconds(stopped)->Option.isSome)->toBeTruthy
    expect(Store.handsOnSeconds({Store.partId, startedAt: None, stoppedAt: None}))->toEqual(None)

    let timers = await Store.listTimers(store, ~limit=10)
    expect(timers->Array.map(tm => tm.partId))->toEqual([partId])
  })
})

describe("Store — indexes", () => {
  testAsync(
    "ensureIndexes creates the [type,partId] and [type,updatedAt] indexes",
    async () => {
      let dir = freshDbPath()
      let store = openStore(dir)
      await Store.ensureIndexes(store)

      // Read indexes back through a second raw handle on the same
      // directory — see the module doc comment above for why.
      let raw = PouchDb.make(dir, {})
      let result = await PouchDb.getIndexes(raw)
      let names = result.indexes->Array.map(i => i.name)
      expect(names->Array.includes("type_partId"))->toBeTruthy
      expect(names->Array.includes("type_updatedAt"))->toBeTruthy
    },
  )
})

// SPEC §8a A7 — face labels in the store.
describe("Store — face labels (SPEC §8a A7)", () => {
  testAsync("putFace stores label and reads it back; replace-by-id keeps it", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P7", ~slug="p7", ~path="", ~units=Types.Mm)
    let face = mkFace(~partId=part.id, ~kind=Types.Side, ~label="left_side")
    let _ = await Store.putFace(store, face, ~image=onePixelBlob(), ~contentType="image/jpeg")
    let fetched = await Store.getFace(store, face.id)
    expect(fetched->Option.map(f => (f.kind, f.label)))->toEqual(Some((Types.Side, "left_side")))

    // Recapture = same id, same label, new image (SPEC A7: "replaces by face").
    let _ = await Store.putFace(
      store,
      {...face, pixelWidth: 2},
      ~image=PouchDb.blobFromBytes(Uint8Array.fromArray([1, 2])),
      ~contentType="image/jpeg",
    )
    let faces = await Store.facesOf(store, ~partId=part.id)
    expect(faces->Array.map(f => (f.label, f.pixelWidth)))->toEqual([("left_side", 2)])
  })

  testAsync("facesOf orders by kind, then label; same-kind faces coexist", async () => {
    let store = freshStore()
    let part = await Store.createPart(store, ~name="P8", ~slug="p8", ~path="", ~units=Types.Mm)
    let put = (kind, label) =>
      Store.putFace(
        store,
        mkFace(~partId=part.id, ~kind, ~label),
        ~image=onePixelBlob(),
        ~contentType="image/jpeg",
      )
    let _ = await put(Types.End, "end")
    let _ = await put(Types.Side, "side")
    let _ = await put(Types.Side, "left_side")
    let _ = await put(Types.Top, "top")
    let _ = await put(Types.Top, "underside")

    let faces = await Store.facesOf(store, ~partId=part.id)
    expect(faces->Array.map(f => f.label))->toEqual(["top", "underside", "left_side", "side", "end"])
  })

  // The owner's phone already holds face docs written before A7 — no
  // `label` field at all. They must keep reading back, as the default face
  // of their kind. Written through a second raw handle on the same
  // directory (see the module doc comment) because Store itself can no
  // longer produce such a doc.
  testAsync("a face doc written without label reads back with label = kind", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)
    let part = await Store.createPart(store, ~name="P9", ~slug="p9", ~path="", ~units=Types.Mm)
    let legacyId = Ids.face()

    let raw = PouchDb.make(dir, {})
    let doc: PouchDb.doc = Dict.make()
    Dict.set(doc, "_id", JSON.Encode.string(legacyId))
    Dict.set(doc, "type", JSON.Encode.string("face"))
    Dict.set(doc, "partId", JSON.Encode.string(part.id))
    Dict.set(doc, "kind", JSON.Encode.string("end"))
    Dict.set(doc, "imageAttachment", JSON.Encode.string("image.jpg"))
    Dict.set(doc, "pixelWidth", JSON.Encode.int(1200))
    Dict.set(doc, "pixelHeight", JSON.Encode.int(1600))
    Dict.set(doc, "levelDegrees", JSON.Null)
    Dict.set(doc, "outline", JSON.Null)
    Dict.set(doc, "capturedAt", JSON.Encode.string(Clock.nowIso()))
    Dict.set(doc, "updatedAt", JSON.Encode.string(Clock.nowIso()))
    let _ = await PouchDb.put(raw, doc)

    let fetched = await Store.getFace(store, legacyId)
    expect(fetched->Option.map(f => (f.kind, f.label)))->toEqual(Some((Types.End, "end")))
    let faces = await Store.facesOf(store, ~partId=part.id)
    expect(faces->Array.map(f => f.label))->toEqual(["end"])
  })
})

// SPEC §8a A10 — folder paths in the store: stored as given, defaulted to
// "" (root) for part docs written before the field existed.
describe("Store — part path (SPEC §8a A10)", () => {
  testAsync("createPart persists path; putPart moves a part between folders", async () => {
    let store = freshStore()
    let part = await Store.createPart(
      store,
      ~name="Window switch bezel",
      ~slug="window_switch_bezel",
      ~path="Miata/Interior",
      ~units=Types.Mm,
    )
    expect(part.path)->toBe("Miata/Interior")
    let fetched = await Store.getPart(store, part.id)
    expect(fetched->Option.map(p => p.path))->toEqual(Some("Miata/Interior"))

    let moved = await Store.putPart(store, {...part, path: "Miata/Exterior"})
    expect(moved.path)->toBe("Miata/Exterior")
    let listed = await Store.listParts(store)
    expect(listed->Array.map(p => p.path))->toEqual(["Miata/Exterior"])
  })

  // A store written by the app before A10 has part docs with no `path`
  // field at all. They must keep reading back, at the root.
  testAsync("a part doc written without path reads back with path = \"\"", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)
    let legacyId = Ids.part()

    // A pre-A10 part doc: every field PartDoc.toDoc wrote then, no `path`.
    let raw = PouchDb.make(dir, {})
    let doc: PouchDb.doc = Dict.make()
    Dict.set(doc, "_id", JSON.Encode.string(legacyId))
    Dict.set(doc, "type", JSON.Encode.string("part"))
    Dict.set(doc, "partId", JSON.Encode.string(legacyId))
    Dict.set(doc, "name", JSON.Encode.string("Old"))
    Dict.set(doc, "slug", JSON.Encode.string("old"))
    Dict.set(doc, "units", JSON.Encode.string("mm"))
    Dict.set(doc, "notes", JSON.Encode.string(""))
    Dict.set(doc, "anchors", JSON.Encode.array([]))
    Dict.set(doc, "createdAt", JSON.Encode.string(Clock.nowIso()))
    Dict.set(doc, "updatedAt", JSON.Encode.string(Clock.nowIso()))
    let _ = await PouchDb.put(raw, doc)

    let fetched = await Store.getPart(store, legacyId)
    expect(fetched->Option.map(p => (p.name, p.path)))->toEqual(Some(("Old", "")))
    let listed = await Store.listParts(store)
    expect(listed->Array.map(p => p.path))->toEqual([""])

    // Re-saving it writes the field explicitly, still at the root.
    switch fetched {
    | Some(p) =>
      let saved = await Store.putPart(store, p)
      expect(saved.path)->toBe("")
    | None => expect(false)->toBeTruthy
    }
  })
})

// SPEC §8a A12a — explicit folder docs. `ensureFolders` fills in every
// ancestor in one `bulkDocs`, is idempotent, and `createPart`/`putPart`
// call it for a non-empty path.
describe("Store — folders (SPEC §8a A12a)", () => {
  testAsync("ensureFolders creates the paths and every ancestor once; a second call creates nothing", async () => {
    let store = freshStore()
    expect(await Store.listFolders(store))->toEqual([])
    let created = await Store.ensureFolders(store, ~paths=["a/b/c", "a/x"])
    expect(created)->toEqual(["a", "a/b", "a/b/c", "a/x"])
    expect(await Store.listFolders(store))->toEqual(["a", "a/b", "a/b/c", "a/x"])
    let again = await Store.ensureFolders(store, ~paths=["a/b/c", "a/x"])
    expect(again)->toEqual([])
    expect(await Store.listFolders(store))->toEqual(["a", "a/b", "a/b/c", "a/x"])
    // The root is never a doc; a new sibling only adds itself.
    expect(await Store.ensureFolders(store, ~paths=["", "a/y"]))->toEqual(["a/y"])
  })

  testAsync("folder docs carry type, path, createdAt and updatedAt", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)
    let _ = await Store.ensureFolder(store, ~path="Miata")
    let raw = PouchDb.make(dir, {})
    let doc = await PouchDb.get(raw, "folder:Miata", {})
    expect(Dict.get(doc, "type"))->toEqual(Some(JSON.String("folder")))
    expect(Dict.get(doc, "path"))->toEqual(Some(JSON.String("Miata")))
    let createdAt = Dict.get(doc, "createdAt")
    expect(createdAt->Option.isSome)->toBeTruthy
    expect(Dict.get(doc, "updatedAt"))->toEqual(createdAt)
  })

  testAsync("listFolders sorts case-insensitively", async () => {
    let store = freshStore()
    let _ = await Store.ensureFolders(store, ~paths=["b", "A", "c"])
    expect(await Store.listFolders(store))->toEqual(["A", "b", "c"])
  })

  testAsync("createPart and putPart leave folder docs behind for their path", async () => {
    let store = freshStore()
    let part = await Store.createPart(
      store,
      ~name="Window switch bezel",
      ~slug="window_switch_bezel",
      ~path="Miata/Interior",
      ~units=Types.Mm,
    )
    expect(await Store.listFolders(store))->toEqual(["Miata", "Miata/Interior"])
    let _ = await Store.putPart(store, {...part, path: "Miata/Exterior"})
    expect(await Store.listFolders(store))->toEqual(["Miata", "Miata/Exterior", "Miata/Interior"])
    // A root part touches no folder doc.
    let _ = await Store.createPart(store, ~name="Hinge pin", ~slug="hinge_pin", ~path="", ~units=Types.Mm)
    expect(await Store.listFolders(store))->toEqual(["Miata", "Miata/Exterior", "Miata/Interior"])
  })

  testAsync("a folder doc written by someone else counts as existing", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)
    let raw = PouchDb.make(dir, {})
    let doc: PouchDb.doc = Dict.make()
    Dict.set(doc, "_id", JSON.Encode.string("folder:Archive"))
    Dict.set(doc, "type", JSON.Encode.string("folder"))
    Dict.set(doc, "path", JSON.Encode.string("Archive"))
    Dict.set(doc, "createdAt", JSON.Encode.string(Clock.nowIso()))
    Dict.set(doc, "updatedAt", JSON.Encode.string(Clock.nowIso()))
    let _ = await PouchDb.put(raw, doc)
    expect(await Store.ensureFolders(store, ~paths=["Archive/2025"]))->toEqual(["Archive/2025"])
    expect(await Store.listFolders(store))->toEqual(["Archive", "Archive/2025"])
  })
})

// SPEC §8a A12b — bulk moves and deletes, folder rename / delete. Every
// rename is one `bulkDocs` over the subtree; the refusals are `result`s.
describe("Store — folder management (SPEC §8a A12b)", () => {
  let mkPart = async (store, ~name, ~path) =>
    await Store.createPart(store, ~name, ~slug=Slug.make(name), ~path, ~units=Types.Mm)

  testAsync("renameFolder Miata → MX-5 moves the subtree's folder docs and parts, bumping only those", async () => {
    let dir = freshDbPath()
    let store = openStore(dir)
    let dashboard = await mkPart(store, ~name="Dash clip", ~path="Miata/Interior/Dashboard")
    let direct = await mkPart(store, ~name="Badge", ~path="Miata")
    let root = await mkPart(store, ~name="Hinge pin", ~path="")
    let other = await mkPart(store, ~name="Bracket", ~path="Miatas/Old")
    let raw = PouchDb.make(dir, {})
    let before = await PouchDb.get(raw, "folder:Miata", {})
    let createdAt = Dict.get(before, "createdAt")
    await clockPast(dashboard.updatedAt)
    await clockPast(other.updatedAt)

    expect(await Store.renameFolder(store, ~from="Miata", ~to="MX-5"))->toEqual(Ok())
    expect(await Store.listFolders(store))->toEqual([
      "Miatas",
      "Miatas/Old",
      "MX-5",
      "MX-5/Interior",
      "MX-5/Interior/Dashboard",
    ])
    let byId = id => Store.getPart(store, id)
    let movedDash = await byId(dashboard.id)
    expect(movedDash->Option.map(p => p.path))->toEqual(Some("MX-5/Interior/Dashboard"))
    expect(movedDash->Option.map(p => p.updatedAt > dashboard.updatedAt))->toEqual(Some(true))
    let movedDirect = await byId(direct.id)
    expect(movedDirect->Option.map(p => p.path))->toEqual(Some("MX-5"))
    expect(movedDirect->Option.map(p => p.updatedAt > direct.updatedAt))->toEqual(Some(true))
    // A root part and a look-alike prefix (`Miatas`, not under `Miata`) are untouched.
    expect((await byId(root.id))->Option.map(p => (p.path, p.updatedAt)))->toEqual(Some(("", root.updatedAt)))
    expect((await byId(other.id))->Option.map(p => (p.path, p.updatedAt)))->toEqual(
      Some(("Miatas/Old", other.updatedAt)),
    )
    // The new folder doc keeps `createdAt` and bumps `updatedAt`.
    let after = await PouchDb.get(raw, "folder:MX-5", {})
    expect(Dict.get(after, "createdAt"))->toEqual(createdAt)
    expect(Dict.get(after, "updatedAt") != createdAt)->toBeTruthy
    expect(Dict.get(after, "path"))->toEqual(Some(JSON.String("MX-5")))
  })

  testAsync("a case-only rename is Ok; a sibling twin is Exists; a nested target is Nested", async () => {
    let store = freshStore()
    let _ = await mkPart(store, ~name="Badge", ~path="Miata/Interior")
    let _ = await Store.ensureFolder(store, ~path="Archive")
    expect(await Store.renameFolder(store, ~from="Miata", ~to="miata"))->toEqual(Ok())
    expect(await Store.listFolders(store))->toEqual(["Archive", "miata", "miata/Interior"])
    expect((await Store.listParts(store))->Array.map(p => p.path))->toEqual(["miata/Interior"])
    expect(await Store.renameFolder(store, ~from="miata", ~to="archive"))->toEqual(Error(Store.Exists))
    expect(await Store.renameFolder(store, ~from="miata", ~to="miata/Sub"))->toEqual(Error(Store.Nested))
    // Refusals write nothing.
    expect(await Store.listFolders(store))->toEqual(["Archive", "miata", "miata/Interior"])
    // Same spelling is a no-op.
    expect(await Store.renameFolder(store, ~from="Archive", ~to="Archive"))->toEqual(Ok())
    expect(await Store.listFolders(store))->toEqual(["Archive", "miata", "miata/Interior"])
  })

  testAsync("deleteFolder refuses NotEmpty with a part in or under it or a subfolder; deletes an empty leaf", async () => {
    let store = freshStore()
    let _ = await mkPart(store, ~name="Dash clip", ~path="Miata/Interior/Dashboard")
    let _ = await Store.ensureFolders(store, ~paths=["Archive/2025", "Empty"])
    expect(await Store.deleteFolder(store, ~path="Miata"))->toEqual(Error(Store.NotEmpty))
    expect(await Store.deleteFolder(store, ~path="Miata/Interior/Dashboard"))->toEqual(
      Error(Store.NotEmpty),
    )
    expect(await Store.deleteFolder(store, ~path="Archive"))->toEqual(Error(Store.NotEmpty))
    expect(await Store.deleteFolder(store, ~path="Archive/2025"))->toEqual(Ok())
    expect(await Store.deleteFolder(store, ~path="Archive"))->toEqual(Ok())
    expect(await Store.deleteFolder(store, ~path="Empty"))->toEqual(Ok())
    // Already gone is still Ok.
    expect(await Store.deleteFolder(store, ~path="Empty"))->toEqual(Ok())
    expect(await Store.listFolders(store))->toEqual(["Miata", "Miata/Interior", "Miata/Interior/Dashboard"])
  })

  testAsync("moveParts rewrites only the parts not already there and returns them", async () => {
    let store = freshStore()
    let a = await mkPart(store, ~name="A", ~path="")
    let b = await mkPart(store, ~name="B", ~path="")
    let c = await mkPart(store, ~name="C", ~path="Miata")
    await clockPast(c.updatedAt)
    let moved = await Store.moveParts(store, ~partIds=[a.id, c.id], ~path="Miata")
    expect(moved->Array.map(p => p.id))->toEqual([a.id])
    expect(moved->Array.map(p => p.path))->toEqual(["Miata"])
    expect((await Store.getPart(store, a.id))->Option.map(p => (p.path, p.updatedAt > a.updatedAt)))->toEqual(
      Some(("Miata", true)),
    )
    expect((await Store.getPart(store, b.id))->Option.map(p => (p.path, p.updatedAt)))->toEqual(Some(("", b.updatedAt)))
    expect((await Store.getPart(store, c.id))->Option.map(p => (p.path, p.updatedAt)))->toEqual(
      Some(("Miata", c.updatedAt)),
    )
    // A new target gets its folder docs; the root never does.
    let toArchive = await Store.moveParts(store, ~partIds=[b.id], ~path="Archive/2025")
    expect(toArchive->Array.map(p => p.path))->toEqual(["Archive/2025"])
    expect(await Store.listFolders(store))->toEqual(["Archive", "Archive/2025", "Miata"])
    expect(await Store.moveParts(store, ~partIds=[a.id, b.id], ~path=""))->toHaveLength(2)
    expect((await Store.listParts(store))->Array.map(p => p.path)->Array.toSorted(String.compare))->toEqual([
      "",
      "",
      "Miata",
    ])
    // Nothing to move: no write, empty result.
    expect(await Store.moveParts(store, ~partIds=[c.id], ~path="Miata"))->toEqual([])
    expect(await Store.moveParts(store, ~partIds=[], ~path="Miata"))->toEqual([])
  })

  testAsync("deleteParts removes each part with its faces, in one promise", async () => {
    let store = freshStore()
    let a = await mkPart(store, ~name="A", ~path="")
    let b = await mkPart(store, ~name="B", ~path="Miata")
    let keep = await mkPart(store, ~name="Keep", ~path="")
    let _ = await Store.putFace(store, mkFace(~partId=a.id, ~kind=Types.Top), ~image=onePixelBlob(), ~contentType="image/jpeg")
    let _ = await Store.putFace(store, mkFace(~partId=b.id, ~kind=Types.Side), ~image=onePixelBlob(), ~contentType="image/jpeg")
    await Store.deleteParts(store, ~partIds=[a.id, b.id])
    expect((await Store.listParts(store))->Array.map(p => p.id))->toEqual([keep.id])
    expect(await Store.facesOf(store, ~partId=a.id))->toEqual([])
    expect(await Store.facesOf(store, ~partId=b.id))->toEqual([])
    // The folder doc outlives its last part (A12b: an empty leaf section).
    expect(await Store.listFolders(store))->toEqual(["Miata"])
  })
})
