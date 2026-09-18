// ParametersCsvTest — SPEC §8a A11. Mirrors FeaturesDocumentTest.res's
// style: the golden fixture check byte-for-byte, plus ad hoc dimension
// records (spread syntax over Fixture values, same pattern
// FeaturesDocumentTest and ReconcileTest already use) for the cases the
// golden fixture doesn't exercise on its own — every feature in
// fixtures/hinge_pin has exactly one contributing dimension, so inches,
// a flagged spread, and a two-face "faces" clause all need their own
// small scenarios here.

@module("node:fs") external readFileSync: (string, string) => string = "readFileSync"

open Vitest

let goldenPath = "fixtures/hinge_pin/parameters.csv"

describe("ParametersCsv.make — golden fixture", () => {
  test("matches the checked-in golden parameters.csv byte-for-byte", () => {
    let golden = readFileSync(goldenPath, "utf8")
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) => expect(text)->toBe(golden)
    }
  })

  test("ends with exactly one trailing newline", () => {
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      expect(String.endsWith(text, "\n"))->toBeTruthy
      expect(String.endsWith(text, "\n\n"))->toBeFalsy
    }
  })

  test("one line per feature, same feature order as features.json", () => {
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      // Drop the trailing "" produced by the trailing newline before split.
      let lines = text->String.split("\n")->Array.filter(line => line != "")
      expect(Array.length(lines))->toBe(9)
      let names = Array.map(lines, line =>
        switch line->String.split(",")->Array.get(0) {
        | Some(n) => n
        | None => ""
        }
      )
      expect(names)->toEqual(Fixture.dimensionNames->Array.toSorted(String.compare))
    }
  })

  test("no commas inside any field (SPEC §8a A11): every row splits into exactly 4 fields", () => {
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      let lines = text->String.split("\n")->Array.filter(line => line != "")
      Array.forEach(lines, line => expect(Array.length(String.split(line, ",")))->toBe(4))
    }
  })
})

describe("ParametersCsv.make — inch part (SPEC §8a A11)", () => {
  let inchPart: Types.part = {...Fixture.part, units: Inch, slug: "inch_test_part"}
  let dims: array<Types.dimension> = [
    {...Fixture.overallL, id: "dim:inch-1", name: "overall_l", value: 1.375, tolerance: 0.005},
  ]

  test("unit is \"in\" and expression carries it verbatim (1.375 in)", () => {
    switch ParametersCsv.make(~part=inchPart, ~faces=Fixture.faces, ~dimensions=dims) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      expect(text)->toBe(
        "overall_l,in,1.375 in,±0.005 in · faces top · ccpart:inch_test_part\n",
      )
    }
  })
})

describe("ParametersCsv.make — flagged feature (SPEC §8a A11)", () => {
  // Mirrors the SPEC bullet's own illustrative numbers: spread 0.12 >
  // tolerance 0.05.
  let dims: array<Types.dimension> = [
    {...Fixture.overallL, id: "dim:flag-a", name: "flagged_dim", value: 42.10, tolerance: 0.05},
    {...Fixture.overallL, id: "dim:flag-b", name: "flagged_dim", value: 42.22, tolerance: 0.05},
  ]

  test("comment is prefixed with FLAGGED spread <spread> > ±<tolerance> ·", () => {
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=dims) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      expect(text)->toBe(
        "flagged_dim,mm,42.16 mm,FLAGGED spread 0.12 > ±0.05 · ±0.05 mm · faces top · ccpart:norcold_freezer_hinge_pin\n",
      )
    }
  })
})

describe("ParametersCsv.make — faces clause (SPEC §8a A11)", () => {
  // Same feature name contributed from two different faces: faceIds come
  // back sorted by id (Reconcile.reconcile, SPEC §6.3) — topFaceId <
  // sideFaceId — so the labels should join in that same order.
  let dims: array<Types.dimension> = [
    {...Fixture.overallL, id: "dim:multi-a", faceId: Fixture.topFaceId, name: "shared", value: 42.18, tolerance: 0.1},
    {...Fixture.overallL, id: "dim:multi-b", faceId: Fixture.sideFaceId, name: "shared", value: 42.20, tolerance: 0.1},
  ]

  test("labels of every contributing face are joined by a single space", () => {
    switch ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=dims) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(text) =>
      expect(text)->toBe("shared,mm,42.19 mm,±0.1 mm · faces top side · ccpart:norcold_freezer_hinge_pin\n")
    }
  })
})

describe("ParametersCsv — internal helpers", () => {
  // The compiler inlines `formatNumber`'s body at every call site inside
  // this module (it's a one-line wrapper), so nothing here exercises the
  // exported binding itself unless a test calls it directly.
  test("formatNumber renders a float with no trailing-zero padding", () => {
    expect(ParametersCsv.formatNumber(2.0))->toBe("2")
    expect(ParametersCsv.formatNumber(42.18))->toBe("42.18")
  })

  test("labelFor falls back to the raw id when the face isn't in the list", () => {
    expect(ParametersCsv.labelFor([], "face:missing"))->toBe("face:missing")
  })

  test("labelFor resolves a known face id to its label", () => {
    expect(ParametersCsv.labelFor(Fixture.faces, Fixture.topFaceId))->toBe("top")
  })
})

describe("ParametersCsv.make — errors", () => {
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
      ParametersCsv.make(~part=Fixture.part, ~faces=Fixture.faces, ~dimensions=conflicting),
    )->toEqual(Error(Reconcile.KindConflict("wall")))
  })
})
