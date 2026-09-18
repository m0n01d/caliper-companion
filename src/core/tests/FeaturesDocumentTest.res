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

// SPEC §8a A7 — face labels: `"label"` right after `"kind"`, bundle paths
// named by the label, faces sorted by kind order then label.
describe("FeaturesDocument — face labels (SPEC §8a A7)", () => {
  let leftSide: Types.face = {
    ...Fixture.sideFace,
    id: "face:00000000-0000-4000-8000-000000000009",
    label: "left_side",
  }
  let run = (faceList: array<Types.face>): string =>
    switch FeaturesDocument.make(
      ~part=Fixture.part,
      ~faces=Array.map(faceList, (face: Types.face) =>
        ({face, renderScale: 1.0}: FeaturesDocument.faceExport)
      ),
      ~dimensions=Fixture.dimensions,
      ~exportedAt="2026-09-17T14:12:03Z",
      ~appVersion="0.1.0",
      ~handsOnSeconds=None,
    ) {
    | Ok(text) => text
    | Error(_) => ""
    }

  test("emits label on the line right after kind", () => {
    let text = run(Fixture.faces)
    expect(String.includes(text, "\"kind\": \"side\",\n      \"label\": \"side\","))->toBeTruthy
  })

  test("default faces keep their pre-A7 paths", () => {
    let text = run(Fixture.faces)
    expect(String.includes(text, "\"image\": \"faces/top.jpg\""))->toBeTruthy
    expect(String.includes(text, "\"annotated\": \"faces/end_dimensioned.png\""))->toBeTruthy
  })

  test("a custom label names the image and annotated paths", () => {
    let text = run(Array.concat(Fixture.faces, [leftSide]))
    expect(String.includes(text, "\"kind\": \"side\",\n      \"label\": \"left_side\","))->toBeTruthy
    expect(String.includes(text, "\"image\": \"faces/left_side.jpg\""))->toBeTruthy
    expect(String.includes(text, "\"annotated\": \"faces/left_side_dimensioned.png\""))->toBeTruthy
  })

  test("faces sort by kind order, then label, regardless of input order", () => {
    let aSide: Types.face = {...leftSide, id: "face:a", label: "a_side"}
    let text = run([Fixture.endFace, Fixture.sideFace, leftSide, aSide, Fixture.topFace])
    let at = label => String.indexOf(text, "\"label\": \"" ++ label ++ "\"")
    expect(at("top") >= 0)->toBeTruthy
    expect(at("top") < at("a_side"))->toBeTruthy
    expect(at("a_side") < at("left_side"))->toBeTruthy
    expect(at("left_side") < at("side"))->toBeTruthy
    expect(at("side") < at("end"))->toBeTruthy
  })
})

// SPEC §8a A10 — the part's folder path rides in features.json right after
// `slug`; "" at the root (the golden above covers that case).
describe("FeaturesDocument — part path (SPEC §8a A10)", () => {
  let linesFor = (path: string): array<string> =>
    switch FeaturesDocument.make(
      ~part={...Fixture.part, path},
      ~faces,
      ~dimensions=Fixture.dimensions,
      ~exportedAt="2026-09-17T14:12:03Z",
      ~appVersion="0.1.0",
      ~handsOnSeconds=Some(187),
    ) {
    | Ok(text) => String.split(text, "\n")
    | Error(_) => []
    }

  test("emits path on the line right after slug, verbatim", () => {
    let lines = linesFor("Miata/Interior")
    let slugAt = Array.findIndex(lines, l => l == `    "slug": "norcold_freezer_hinge_pin",`)
    expect(slugAt >= 0)->toBeTruthy
    expect(Array.get(lines, slugAt + 1))->toEqual(Some(`    "path": "Miata/Interior",`))
  })

  test("a folder path changes the golden output on exactly that one line", () => {
    let root = linesFor("")
    let folder = linesFor("Miata (NB)/Interior")
    expect(Array.length(folder))->toBe(Array.length(root))
    let differing = root->Array.filterWithIndex((line, i) => Array.get(folder, i) != Some(line))
    expect(differing)->toEqual([`    "path": "",`])
  })
})
