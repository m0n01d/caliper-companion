// EdgeSnapTest — SPEC §8a A5 bullet 5's unit tests, on synthetic patches
// built directly (no DOM, no ImageData.res — EdgeSnap.res never needs
// either, and that's the point of keeping it pure).

open Vitest

let makePatch = (width: int, height: int, f: (int, int) => int): EdgeSnap.patch => {
  let luma = Uint8Array.fromLength(width * height)
  for y in 0 to height - 1 {
    for x in 0 to width - 1 {
      luma->TypedArray.set(y * width + x, f(x, y))
    }
  }
  {width, height, luma}
}

// A hard vertical step: dark (40) left of `edgeX`, light (220) right of it.
let stepPatch = (width: int, height: int, edgeX: int): EdgeSnap.patch =>
  makePatch(width, height, (x, _y) => x < edgeX ? 40 : 220)

// A dark bar `[a, b)` on a light field — two vertical edges.
let barPatch = (width: int, height: int, ~a: int, ~b: int): EdgeSnap.patch =>
  makePatch(width, height, (x, _y) => x >= a && x < b ? 40 : 220)

// A diagonal edge: light where `x + y > c`, dark otherwise.
let obliquePatch = (width: int, height: int, ~c: int): EdgeSnap.patch =>
  makePatch(width, height, (x, y) => x + y > c ? 220 : 40)

let flatPatch = (width: int, height: int, value: int): EdgeSnap.patch =>
  makePatch(width, height, (_x, _y) => value)

// Deterministic "noise": a small LCG (`state = state * 25173 + 13849 mod
// 65536`, classic Turbo Pascal constants — chosen small enough that the
// arithmetic never overflows the 32-bit `int` ReScript compiles to, so
// there's no truncation surprise to reason about), threaded across the
// patch in raster order from `seed`. Not `Math.random` — the same `seed`
// always produces the same patch, so this can never be a flaky test.
// Amplitude ±6 around a mid-gray field (128). A position-based hash
// (`x * bigPrime + y * bigPrime2 mod …`) was tried first and rejected: it
// reads as noise to the eye but is linear in `x`/`y`, so neighbouring
// pixels ramp smoothly enough for the Sobel kernel to read a fake edge —
// exactly the false positive this test exists to rule out. A threaded LCG
// doesn't have that structure.
let noisePatch = (width: int, height: int, ~seed: int): EdgeSnap.patch => {
  let luma = Uint8Array.fromLength(width * height)
  let state = ref(Int.mod(seed, 65536))
  for i in 0 to width * height - 1 {
    state := Int.mod(state.contents * 25173 + 13849, 65536)
    luma->TypedArray.set(i, 128 + Int.mod(state.contents, 13) - 6)
  }
  {width, height, luma}
}

let expectSnappedNear = (result: option<EdgeSnap.result>, expected: EdgeSnap.px, tol: float) => {
  let r = result->Option.getOrThrow
  expect(Math.abs(r.point.x -. expected.x) <= tol)->toBeTruthy
  expect(Math.abs(r.point.y -. expected.y) <= tol)->toBeTruthy
}

describe("EdgeSnap.snapPoint — vertical step edge", () => {
  test("snaps within 1px of the edge from up to radius away, at radii 8/16/24", () => {
    let patch = stepPatch(100, 40, 50)
    [8.0, 16.0, 24.0]->Array.forEach(radius => {
      // Several offsets on both sides, including right at the radius limit.
      [-.radius, -.radius /. 2.0, 0.0, radius /. 2.0, radius]->Array.forEach(offset => {
        let at: EdgeSnap.px = {x: 50.0 +. offset, y: 20.0}
        let result = EdgeSnap.snapPoint(patch, ~at, ~radius, ~threshold=EdgeSnap.defaultThreshold)
        expectSnappedNear(result, {x: 50.0, y: 20.0}, 1.0)
      })
    })
  })
})

describe("EdgeSnap.snapPoint — leaves the tap alone with nothing to snap to", () => {
  test("a flat patch never snaps", () => {
    let patch = flatPatch(40, 40, 128)
    let result =
      EdgeSnap.snapPoint(patch, ~at={x: 20.0, y: 20.0}, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
    expect(result)->toEqual(None)
  })

  test("a low-amplitude noise patch never snaps, at radii 8/16/24", () => {
    // Centred well away from the patch border: the Sobel kernel's edge
    // clamping (SPEC bullet 1's "edges clamped") replicates the border
    // pixel, and replicating *noise* right at a border can manufacture a
    // spurious edge — real photos don't have that problem (the patch is
    // built from a whole downscaled image, not a crop), so the fix here is
    // keeping the tap interior, not weakening the algorithm.
    let patch = noisePatch(80, 80, ~seed=12345)
    [8.0, 16.0, 24.0]->Array.forEach(radius => {
      let result =
        EdgeSnap.snapPoint(patch, ~at={x: 40.0, y: 40.0}, ~radius, ~threshold=EdgeSnap.defaultThreshold)
      expect(result)->toEqual(None)
    })
  })
})

describe("EdgeSnap.snapPair — a bar's two edges", () => {
  let patch = barPatch(100, 50, ~a=30, ~b=70)

  test("taps just inside both edges land on both edges", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 33.0, y: 25.0},
        ~p2={x: 67.0, y: 25.0},
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expectSnappedNear(r1, {x: 30.0, y: 25.0}, 1.0)
    expectSnappedNear(r2, {x: 70.0, y: 25.0}, 1.0)
  })

  test("taps just outside both edges land on both edges too", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 27.0, y: 25.0},
        ~p2={x: 73.0, y: 25.0},
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expectSnappedNear(r1, {x: 30.0, y: 25.0}, 1.0)
    expectSnappedNear(r2, {x: 70.0, y: 25.0}, 1.0)
  })

  test("mixed — one tap inside, the other outside — still lands on both edges", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 33.0, y: 25.0},
        ~p2={x: 73.0, y: 25.0},
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expectSnappedNear(r1, {x: 30.0, y: 25.0}, 1.0)
    expectSnappedNear(r2, {x: 70.0, y: 25.0}, 1.0)
  })

  test("a tap pair placed entirely inside a flat region snaps neither end", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 5.0, y: 25.0},
        ~p2={x: 15.0, y: 25.0},
        ~radius=8.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expect(r1)->toEqual(None)
    expect(r2)->toEqual(None)
  })

  test("identical p1/p2 has no segment direction to search along; both ends are None", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 30.0, y: 25.0},
        ~p2={x: 30.0, y: 25.0},
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expect(r1)->toEqual(None)
    expect(r2)->toEqual(None)
  })
})

// SPEC bullet 1's closing line: "an oblique segment snaps along its own
// direction, not the image axes" — a segment perpendicular to a diagonal
// edge snaps; the identical segment, rotated 90° to run *along* the edge,
// scores near-zero (directional dot product) and does not.
describe("EdgeSnap.snapPair — oblique edge, directional scoring", () => {
  let patch = obliquePatch(80, 80, ~c=50) // edge: x + y == 50

  test("a segment perpendicular to the edge snaps both ends onto it", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 21.0, y: 21.0}, // x+y = 42, dark side
        ~p2={x: 29.0, y: 29.0}, // x+y = 58, light side
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    let onEdge = (r: option<EdgeSnap.result>) => {
      let p = (r->Option.getOrThrow).point
      expect(Math.abs(p.x +. p.y -. 50.0) <= 1.0)->toBeTruthy
    }
    onEdge(r1)
    onEdge(r2)
  })

  test("the same segment, run parallel to the edge instead, does not snap", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 20.0, y: 30.0}, // x+y = 50, on the edge
        ~p2={x: 30.0, y: 20.0}, // x+y = 50, on the edge — direction is along it
        ~radius=12.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expect(r1)->toEqual(None)
    expect(r2)->toEqual(None)
  })
})

describe("EdgeSnap coordinate helpers", () => {
  test("toPatch / toNormalized round-trip", () => {
    let n: Types.point = {x: 0.3, y: 0.7}
    let p = EdgeSnap.toPatch(n, ~width=200, ~height=100)
    expect(p.x)->toBeCloseTo(60.0, 6)
    expect(p.y)->toBeCloseTo(70.0, 6)
    let back = EdgeSnap.toNormalized(p, ~width=200, ~height=100)
    expect(back.x)->toBeCloseTo(n.x, 6)
    expect(back.y)->toBeCloseTo(n.y, 6)
  })

  test("toNormalized clamps outside-the-image patch pixels to 0..1", () => {
    let clamped = EdgeSnap.toNormalized({x: -10.0, y: 250.0}, ~width=200, ~height=100)
    expect(clamped.x)->toBeCloseTo(0.0, 6)
    expect(clamped.y)->toBeCloseTo(1.0, 6)
  })
})

describe("EdgeSnap.gradientMagnitude / medianGradient on known patches", () => {
  test("a hard step's Sobel magnitude is exact on its two edge columns, zero elsewhere", () => {
    let patch = stepPatch(100, 40, 50)
    expect(EdgeSnap.gradientMagnitude(patch, 49, 20))->toBeCloseTo(720.0, 6)
    expect(EdgeSnap.gradientMagnitude(patch, 50, 20))->toBeCloseTo(720.0, 6)
    expect(EdgeSnap.gradientMagnitude(patch, 10, 10))->toBeCloseTo(0.0, 6)
  })

  test("median is 0 when almost every stride-sampled pixel is flat (step patch)", () => {
    expect(EdgeSnap.medianGradient(stepPatch(100, 40, 50)))->toBeCloseTo(0.0, 6)
  })

  test("median is 0 when almost every stride-sampled pixel is flat (bar patch, odd sample count)", () => {
    expect(EdgeSnap.medianGradient(barPatch(100, 50, ~a=30, ~b=70)))->toBeCloseTo(0.0, 6)
  })

  test("median is small but nonzero for the noise patch — the self-scaling relative floor", () => {
    let median = EdgeSnap.medianGradient(noisePatch(80, 80, ~seed=12345))
    expect(median > 0.0)->toBeTruthy
    expect(median < EdgeSnap.defaultThreshold.absolute)->toBeTruthy
  })

  test("a degenerate zero-width patch has a defined (zero) median instead of crashing", () => {
    let degenerate: EdgeSnap.patch = {width: 0, height: 5, luma: Uint8Array.fromLength(0)}
    expect(EdgeSnap.medianGradient(degenerate))->toBeCloseTo(0.0, 6)
  })
})

describe("EdgeSnap.lumaAt — defensive edge-clamped sampling", () => {
  test("a coordinate outside the patch reads the nearest border pixel", () => {
    let patch = stepPatch(10, 10, 5)
    expect(EdgeSnap.lumaAt(patch, -5, -5))->toBeCloseTo(EdgeSnap.lumaAt(patch, 0, 0), 6)
    expect(EdgeSnap.lumaAt(patch, 50, 50))->toBeCloseTo(EdgeSnap.lumaAt(patch, 9, 9), 6)
  })

  test("falls back to 0 for an index a malformed (undersized) buffer doesn't have", () => {
    let malformed: EdgeSnap.patch = {width: 4, height: 4, luma: Uint8Array.fromLength(1)}
    expect(EdgeSnap.lumaAt(malformed, 3, 3))->toBeCloseTo(0.0, 6)
  })
})
