open Vitest

let mkDim = (
  ~id,
  ~faceId,
  ~name,
  ~kind,
  ~value,
  ~tolerance,
  ~createdAt,
): Types.dimension => {
  id,
  faceId,
  name,
  kind,
  value,
  tolerance,
  p1: {x: 0.1, y: 0.1},
  p2: {x: 0.2, y: 0.2},
  source: Typed,
  createdAt,
}

describe("Reconcile.reconcile — fixture", () => {
  test("returns 9 features, sorted by name", () => {
    switch Reconcile.reconcile(Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(features) =>
      expect(Array.length(features))->toBe(9)
      expect(Array.map(features, (f: Types.feature) => f.name))->toEqual([
        "chamfer",
        "groove_depth",
        "groove_w",
        "head_dia",
        "head_h",
        "overall_l",
        "overall_w",
        "pin_dia",
        "wall",
      ])
    }
  })

  test("a single-measurement feature has spread 0 and isn't flagged", () => {
    switch Reconcile.reconcile(Fixture.dimensions) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok(features) =>
      switch Array.find(features, (f: Types.feature) => f.name == "overall_l") {
      | None => expect(false)->toBeTruthy
      | Some(f) =>
        expect(f.value)->toBe(42.18)
        expect(f.tolerance)->toBe(0.1)
        expect(f.spread)->toBe(0.0)
        expect(f.flagged)->toBeFalsy
        expect(f.faceIds)->toEqual([Fixture.topFaceId])
      }
    }
  })
})

describe("Reconcile.reconcile — two-face pin_dia", () => {
  let dims = (a, b) => [
    mkDim(
      ~id="dim:a",
      ~faceId="face:a",
      ~name="pin_dia",
      ~kind=Types.Diameter,
      ~value=a,
      ~tolerance=0.05,
      ~createdAt="2026-01-01T00:00:00Z",
    ),
    mkDim(
      ~id="dim:b",
      ~faceId="face:b",
      ~name="pin_dia",
      ~kind=Types.Diameter,
      ~value=b,
      ~tolerance=0.05,
      ~createdAt="2026-01-01T00:00:01Z",
    ),
  ]

  test("6.50/6.52 tol 0.05 -> value 6.51, spread 0.02, not flagged", () => {
    switch Reconcile.reconcile(dims(6.50, 6.52)) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok([feature]) =>
      expect(feature.value)->toBe(6.51)
      expect(feature.spread)->toBe(0.02)
      expect(feature.tolerance)->toBe(0.05)
      expect(feature.flagged)->toBeFalsy
      expect(feature.faceIds)->toEqual(["face:a", "face:b"])
    | Ok(_) => expect(false)->toBeTruthy
    }
  })

  test("6.40/6.52 tol 0.05 -> flagged true", () => {
    switch Reconcile.reconcile(dims(6.40, 6.52)) {
    | Error(_) => expect(false)->toBeTruthy
    | Ok([feature]) => expect(feature.flagged)->toBeTruthy
    | Ok(_) => expect(false)->toBeTruthy
    }
  })
})

describe("Reconcile — kind conflicts", () => {
  test("wall as Length on one face and Depth on another -> KindConflict(\"wall\")", () => {
    let dims = [
      mkDim(
        ~id="dim:a",
        ~faceId="face:a",
        ~name="wall",
        ~kind=Types.Length,
        ~value=1.8,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:00Z",
      ),
      mkDim(
        ~id="dim:b",
        ~faceId="face:b",
        ~name="wall",
        ~kind=Types.Depth,
        ~value=1.9,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:01Z",
      ),
    ]
    expect(Reconcile.reconcile(dims))->toEqual(Error(Reconcile.KindConflict("wall")))
    expect(Reconcile.conflicts(dims))->toEqual(["wall"])
  })

  test("reports the alphabetically first conflicting name when several conflict", () => {
    let conflict = (name, kindA, kindB) => [
      mkDim(
        ~id="dim:" ++ name ++ "a",
        ~faceId="face:a",
        ~name,
        ~kind=kindA,
        ~value=1.0,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:00Z",
      ),
      mkDim(
        ~id="dim:" ++ name ++ "b",
        ~faceId="face:b",
        ~name,
        ~kind=kindB,
        ~value=1.1,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:01Z",
      ),
    ]
    let dims =
      conflict("wall", Types.Length, Types.Depth)->Array.concat(
        conflict("axle", Types.Length, Types.Diameter),
      )
    expect(Reconcile.reconcile(dims))->toEqual(Error(Reconcile.KindConflict("axle")))
    expect(Reconcile.conflicts(dims))->toEqual(["axle", "wall"])
  })
})

describe("Reconcile.conflicts", () => {
  test("empty when there are no conflicts", () => {
    expect(Reconcile.conflicts(Fixture.dimensions))->toEqual([])
  })
})

describe("Reconcile — internal helpers", () => {
  test("conflictingNames treats a name with no dimensions as not conflicting", () => {
    let table = Dict.fromArray([("ghost", [])])
    expect(Reconcile.conflictingNames(["ghost"], table))->toEqual([])
  })

  test("two measurements of the same name on the same face dedupe faceIds", () => {
    let dims = [
      mkDim(
        ~id="dim:a",
        ~faceId="face:a",
        ~name="pin_dia",
        ~kind=Types.Diameter,
        ~value=6.50,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:00Z",
      ),
      mkDim(
        ~id="dim:b",
        ~faceId="face:a",
        ~name="pin_dia",
        ~kind=Types.Diameter,
        ~value=6.52,
        ~tolerance=0.05,
        ~createdAt="2026-01-01T00:00:01Z",
      ),
    ]
    switch Reconcile.reconcile(dims) {
    | Ok([feature]) => expect(feature.faceIds)->toEqual(["face:a"])
    | _ => expect(false)->toBeTruthy
    }
  })
})
