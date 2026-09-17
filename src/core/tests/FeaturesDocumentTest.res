// Test-only binding: reading the checked-in golden file. Allowed here per
// M1's instructions even though core/ itself never touches Node/DOM APIs.
@module("node:fs") external readFileSync: (string, string) => string = "readFileSync"

open Vitest

let faces: array<FeaturesDocument.faceExport> = Array.map(Fixture.faces, (face: Types.face) =>
  ({face, renderScale: 1.0}: FeaturesDocument.faceExport)
)

let goldenPath = "fixtures/hinge_pin/features.json"

describe("FeaturesDocument.make — golden fixture", () => {
  test("matches the checked-in golden features.json byte-for-byte", () => {
    let golden = readFileSync(goldenPath, "utf8")
    switch FeaturesDocument.make(
      ~part=Fixture.part,
      ~faces,
      ~dimensions=Fixture.dimensions,
      ~exportedAt="2026-09-17T14:12:03Z",
      ~appVersion="0.1.0",
      ~handsOnSeconds=Some(187),
    ) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) => expect(text)->toBe(golden)
    }
  })

  test("ends with exactly one trailing newline", () => {
    switch FeaturesDocument.make(
      ~part=Fixture.part,
      ~faces,
      ~dimensions=Fixture.dimensions,
      ~exportedAt="2026-09-17T14:12:03Z",
      ~appVersion="0.1.0",
      ~handsOnSeconds=Some(187),
    ) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      expect(String.endsWith(text, "\n"))->toBeTruthy
      expect(String.endsWith(text, "\n\n"))->toBeFalsy
    }
  })

  test("re-export with a different exportedAt differs only on that line", () => {
    let run = exportedAt =>
      FeaturesDocument.make(
        ~part=Fixture.part,
        ~faces,
        ~dimensions=Fixture.dimensions,
        ~exportedAt,
        ~appVersion="0.1.0",
        ~handsOnSeconds=Some(187),
      )
    switch (run("2026-09-17T14:12:03Z"), run("2026-09-18T09:00:00Z")) {
    | (Ok(a), Ok(b)) =>
      let linesA = String.split(a, "\n")
      let linesB = String.split(b, "\n")
      expect(Array.length(linesA))->toEqual(Array.length(linesB))
      let diffIndexes =
        Array.mapWithIndex(linesA, (line, i) =>
          line == Array.getUnsafe(linesB, i) ? None : Some(i)
        )->Array.filterMap(x => x)
      expect(diffIndexes)->toEqual([2])
      expect(Array.getUnsafe(linesA, 2))->toBe(`  "exportedAt": "2026-09-17T14:12:03Z",`)
      expect(Array.getUnsafe(linesB, 2))->toBe(`  "exportedAt": "2026-09-18T09:00:00Z",`)
    | _ => expect(false)->toBeTruthy
    }
  })

  test("handsOnSeconds = None encodes telemetry as null", () => {
    switch FeaturesDocument.make(
      ~part=Fixture.part,
      ~faces,
      ~dimensions=Fixture.dimensions,
      ~exportedAt="2026-09-17T14:12:03Z",
      ~appVersion="0.1.0",
      ~handsOnSeconds=None,
    ) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) => expect(String.includes(text, "\"handsOnSeconds\": null"))->toBeTruthy
    }
  })
})

describe("FeaturesDocument — internal helpers", () => {
  test("encodeOptPoints encodes a populated outline as [x, y] pairs", () => {
    let outline = Some([{x: 0.0, y: 0.0}: Types.point, {x: 1.0, y: 1.0}])
    expect(FeaturesDocument.encodeOptPoints(outline))->toEqual(
      JSON.Array([JSON.Array([JSON.Number(0.0), JSON.Number(0.0)]), JSON.Array([JSON.Number(1.0), JSON.Number(1.0)])]),
    )
  })

  test("faceKindRank orders Detail last", () => {
    expect(FeaturesDocument.faceKindRank(Detail))->toBe(3)
  })

  test("measurementsFor breaks a same-createdAt tie by faceId", () => {
    let dims: array<Types.dimension> = [
      {...Fixture.pinDia, id: "dim:tie-b", faceId: "face:b", createdAt: "2026-01-01T00:00:00Z"},
      {...Fixture.pinDia, id: "dim:tie-a", faceId: "face:a", createdAt: "2026-01-01T00:00:00Z"},
    ]
    let ordered = FeaturesDocument.measurementsFor(dims, "pin_dia")
    let faceIdsInOrder = Array.map(ordered, m =>
      switch m {
      | Object(fields) =>
        switch Dict.get(fields, "faceId") {
        | Some(String(id)) => id
        | _ => ""
        }
      | _ => ""
      }
    )
    expect(faceIdsInOrder)->toEqual(["face:a", "face:b"])
  })

  test("measurementsFor orders distinct createdAt ascending, ignoring insertion order", () => {
    let dims: array<Types.dimension> = [
      {...Fixture.pinDia, id: "dim:later", faceId: "face:a", createdAt: "2026-01-01T00:00:05Z"},
      {...Fixture.pinDia, id: "dim:earlier", faceId: "face:a", createdAt: "2026-01-01T00:00:01Z"},
    ]
    let ordered = FeaturesDocument.measurementsFor(dims, "pin_dia")
    let atsInOrder = Array.map(ordered, m =>
      switch m {
      | Object(fields) =>
        switch Dict.get(fields, "at") {
        | Some(String(at)) => at
        | _ => ""
        }
      | _ => ""
      }
    )
    expect(atsInOrder)->toEqual(["2026-01-01T00:00:01Z", "2026-01-01T00:00:05Z"])
  })
})

describe("FeaturesDocument.make — errors", () => {
  test("propagates a KindConflict from Reconcile", () => {
    let conflicting: array<Types.dimension> = [
      {
        id: "dim:a",
        faceId: "face:a",
        name: "wall",
        kind: Length,
        value: 1.0,
        tolerance: 0.05,
        p1: {x: 0.1, y: 0.1},
        p2: {x: 0.2, y: 0.2},
        source: Typed,
        createdAt: "2026-01-01T00:00:00Z",
      },
      {
        id: "dim:b",
        faceId: "face:b",
        name: "wall",
        kind: Depth,
        value: 1.1,
        tolerance: 0.05,
        p1: {x: 0.1, y: 0.1},
        p2: {x: 0.2, y: 0.2},
        source: Typed,
        createdAt: "2026-01-01T00:00:01Z",
      },
    ]
    expect(
      FeaturesDocument.make(
        ~part=Fixture.part,
        ~faces,
        ~dimensions=conflicting,
        ~exportedAt="2026-09-17T14:12:03Z",
        ~appVersion="0.1.0",
        ~handsOnSeconds=None,
      ),
    )->toEqual(Error(Reconcile.KindConflict("wall")))
  })
})
