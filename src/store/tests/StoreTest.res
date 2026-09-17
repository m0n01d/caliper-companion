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

    let part = await Store.createPart(store, ~name="Hinge Pin", ~slug="hinge_pin", ~units=Types.Mm)
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
    let a = await Store.createPart(store, ~name="A", ~slug="a", ~units=Types.Mm)
    let b = await Store.createPart(store, ~name="B", ~slug="b", ~units=Types.Mm)
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
      let part = await Store.createPart(store, ~name="P5", ~slug="p5", ~units=Types.Mm)
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
      let part = await Store.createPart(store, ~name="P", ~slug="p", ~units=Types.Mm)
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

      let part = await Store.createPart(store, ~name="P2", ~slug="p2", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P3", ~slug="p3", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P6", ~slug="p6", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P4", ~slug="p4", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P7", ~slug="p7", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P7", ~slug="p7", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P8", ~slug="p8", ~units=Types.Mm)
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
    let part = await Store.createPart(store, ~name="P9", ~slug="p9", ~units=Types.Mm)
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
