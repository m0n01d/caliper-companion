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

// -- A5 hardening (agent/a5-blur): window-local Gaussian smoothing,
// non-max suppression, distance-weighted scoring, cached median ----------

// Same LCG as `noisePatch` above, but applied as an *additive* perturbation
// on top of another patch (a step or a bar) instead of standing alone —
// amplitude ±20 per the upgrade's own acceptance bullet ("deterministic
// LCG noise of ±20 per pixel"), clamped back into 0..255.
let withNoise = (patch: EdgeSnap.patch, ~seed: int): EdgeSnap.patch => {
  let luma = Uint8Array.fromLength(patch.width * patch.height)
  let state = ref(Int.mod(seed, 65536))
  for i in 0 to patch.width * patch.height - 1 {
    state := Int.mod(state.contents * 25173 + 13849, 65536)
    let delta = Int.mod(state.contents, 41) - 20 // -20..20
    let base = switch patch.luma->TypedArray.get(i) {
    | Some(v) => v
    | None => 0
    }
    luma->TypedArray.set(i, Math.Int.max(0, Math.Int.min(255, base + delta)))
  }
  {width: patch.width, height: patch.height, luma}
}

// A linear brightness ramp from 40 to 220 over `rampWidth` columns starting
// at `x0` — a soft edge, as opposed to `stepPatch`'s hard one.
let rampPatch = (width: int, height: int, ~x0: int, ~rampWidth: int): EdgeSnap.patch =>
  makePatch(width, height, (x, _y) =>
    if x < x0 {
      40
    } else if x >= x0 + rampWidth {
      220
    } else {
      let t = Int.toFloat(x - x0) /. Int.toFloat(rampWidth - 1)
      Float.toInt(Math.round(40.0 +. t *. (220.0 -. 40.0)))
    }
  )

describe("EdgeSnap.snapPoint — noisy step edge (Gaussian smoothing, upgrade 1)", () => {
  // Raw Sobel on this patch would be pulled toward whichever noise pixel
  // in the window happens to spike highest — the point of this test is
  // that the window-local smoothing (which averages the ±20 noise down
  // before Sobel ever sees it) keeps the result on the real edge instead.
  // Per the task brief's "or simply assert the upgraded result" option:
  // asserting the upgraded result directly, not also the raw failure mode.
  //
  // Checks only the *x* distance to the edge (the vertical line `x = 50`),
  // not `y` — landing at a different row is still "within 1px of the
  // edge" for a vertical edge; staying near the tap's own row under noise
  // is a separate property, upgrade 3's job, covered by the "distance
  // weighting" test below. Offsets stop just short of the exact radius
  // (14, not 16): at offset == radius exactly, only a single pixel is
  // geometrically admissible at all, so a noise realization that happens
  // to push *that one pixel* below threshold or off the NMS test returns
  // `None` outright — a real but separate edge case from what this test
  // is checking (confirmed empirically: harmless at radius-1, happens on
  // roughly 1 in 12 seeds at radius exactly).
  test("lands within 1px of the edge from up to 14px away on either side (radius 16)", () => {
    let patch = withNoise(stepPatch(100, 40, 50), ~seed=777)
    [-14.0, -7.0, 0.0, 7.0, 14.0]->Array.forEach(offset => {
      let at: EdgeSnap.px = {x: 50.0 +. offset, y: 20.0}
      let result = EdgeSnap.snapPoint(patch, ~at, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
      let r = result->Option.getOrThrow
      expect(Math.abs(r.point.x -. 50.0) <= 1.0)->toBeTruthy
    })
  })
})

describe("EdgeSnap.snapPoint — soft ramp (non-max suppression, upgrade 2)", () => {
  test("lands on the ramp's centre, not its first or last pixel", () => {
    // Ramp over columns 50..55 (6 px, 40 → 220); centre = 52.5.
    let patch = rampPatch(100, 40, ~x0=50, ~rampWidth=6)
    let result =
      EdgeSnap.snapPoint(
        patch,
        ~at={x: 52.5, y: 20.0},
        ~radius=10.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expectSnappedNear(result, {x: 52.5, y: 20.0}, 1.0)
  })
})

describe("EdgeSnap — thin 2-px line (non-max suppression keeps both edges distinct)", () => {
  let patch = barPatch(100, 40, ~a=50, ~b=52) // dark columns 50,51 on a light field

  test("snapPoint returns whichever of the line's two edges is nearer the tap", () => {
    let nearLeft = EdgeSnap.snapPoint(
      patch,
      ~at={x: 47.0, y: 20.0},
      ~radius=8.0,
      ~threshold=EdgeSnap.defaultThreshold,
    )
    expectSnappedNear(nearLeft, {x: 50.0, y: 20.0}, 1.0)

    let nearRight = EdgeSnap.snapPoint(
      patch,
      ~at={x: 55.0, y: 20.0},
      ~radius=8.0,
      ~threshold=EdgeSnap.defaultThreshold,
    )
    expectSnappedNear(nearRight, {x: 52.0, y: 20.0}, 1.0)
  })

  test("snapPair across the line lands both ends on the line's two edges", () => {
    let (r1, r2) =
      EdgeSnap.snapPair(
        patch,
        ~p1={x: 44.0, y: 20.0},
        ~p2={x: 58.0, y: 20.0},
        ~radius=8.0,
        ~threshold=EdgeSnap.defaultThreshold,
      )
    expectSnappedNear(r1, {x: 50.0, y: 20.0}, 1.0)
    expectSnappedNear(r2, {x: 52.0, y: 20.0}, 1.0)
  })
})

describe("EdgeSnap.snapPair — noisy bar (Gaussian smoothing, upgrade 1)", () => {
  test("both ends still land within 1px of the bar's edges", () => {
    let patch = withNoise(barPatch(100, 50, ~a=30, ~b=70), ~seed=4242)
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
})

describe("EdgeSnap — flat and pure-noise patches still don't snap, after smoothing", () => {
  test("a flat patch never snaps", () => {
    let patch = flatPatch(40, 40, 128)
    let result =
      EdgeSnap.snapPoint(patch, ~at={x: 20.0, y: 20.0}, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
    expect(result)->toEqual(None)
  })

  test("a low-amplitude noise patch never snaps, at radii 8/16/24", () => {
    let patch = noisePatch(80, 80, ~seed=98765)
    [8.0, 16.0, 24.0]->Array.forEach(radius => {
      let result =
        EdgeSnap.snapPoint(patch, ~at={x: 40.0, y: 40.0}, ~radius, ~threshold=EdgeSnap.defaultThreshold)
      expect(result)->toEqual(None)
    })
  })
})

describe("EdgeSnap.snapPoint — distance-weighted scoring keeps a tap from sliding along a long edge (upgrade 3)",
  () => {
    test("a tap 6px off a long noisy edge, 10px along from an arbitrary origin, stays within 1px along the edge", () => {
      // Tall vertical edge (not just the 40px-tall patches above) so there's
      // real room for a raw magnitude-only search to slide along it: many
      // rows are within `radius` of the tap, and the ±20 noise means their
      // smoothed magnitudes are close but not exactly equal — without the
      // distance falloff, a strict "highest magnitude wins" comparison can
      // pick a noise-favoured row several pixels away instead of the row
      // straight across from the tap. (Verified empirically across a wide
      // sweep of seeds/offsets during development — see the LOGBOOK entry
      // on why the weighting coefficient ended up 1.0, not the wiring
      // agent's illustrative 0.35.)
      let patch = withNoise(stepPatch(100, 140, 50), ~seed=13)
      let origin = 40.0 // arbitrary — the edge itself has no privileged row
      let at: EdgeSnap.px = {x: 50.0 +. 6.0, y: origin +. 10.0}
      let result =
        EdgeSnap.snapPoint(patch, ~at, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
      let r = result->Option.getOrThrow
      expect(Math.abs(r.point.y -. at.y) <= 1.0)->toBeTruthy
    })
  },
)

describe("EdgeSnap — optional ~median gives identical results to computing it fresh (upgrade 4)", () => {
  test("snapPoint", () => {
    let patch = withNoise(stepPatch(100, 40, 50), ~seed=777)
    let median = EdgeSnap.medianGradient(patch)
    let at: EdgeSnap.px = {x: 42.0, y: 20.0}
    let withoutCache =
      EdgeSnap.snapPoint(patch, ~at, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
    let withCache =
      EdgeSnap.snapPoint(patch, ~at, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold, ~median)
    expect(withCache)->toEqual(withoutCache)
  })

  test("snapPair", () => {
    let patch = withNoise(barPatch(100, 50, ~a=30, ~b=70), ~seed=4242)
    let median = EdgeSnap.medianGradient(patch)
    let p1: EdgeSnap.px = {x: 33.0, y: 25.0}
    let p2: EdgeSnap.px = {x: 67.0, y: 25.0}
    let withoutCache =
      EdgeSnap.snapPair(patch, ~p1, ~p2, ~radius=12.0, ~threshold=EdgeSnap.defaultThreshold)
    let withCache =
      EdgeSnap.snapPair(patch, ~p1, ~p2, ~radius=12.0, ~threshold=EdgeSnap.defaultThreshold, ~median)
    expect(withCache)->toEqual(withoutCache)
  })
})

describe("EdgeSnap window locality — bounded per-call cost", () => {
  test("a huge patch with the edge far from the tap returns None", () => {
    let patch = stepPatch(1024, 768, 900)
    let result =
      EdgeSnap.snapPoint(patch, ~at={x: 50.0, y: 50.0}, ~radius=16.0, ~threshold=EdgeSnap.defaultThreshold)
    expect(result)->toEqual(None)
  })

  test("1000 snaps on a huge patch finish quickly — nothing touches the whole patch per call", () => {
    let patch = stepPatch(1024, 768, 900)
    // `medianGradient` is the one thing the hard rules allow to touch the
    // whole patch (it stride-samples) — computed once here, exactly the
    // upgrade-4 usage the wiring agent needs (two searches per tap), so
    // this measures what the per-call cost bound actually promises: with
    // the median cached, every one of the 1000 calls below is genuinely
    // window-local.
    let median = EdgeSnap.medianGradient(patch)
    let start = Date.now()
    for _ in 1 to 1000 {
      EdgeSnap.snapPoint(
        patch,
        ~at={x: 50.0, y: 50.0},
        ~radius=16.0,
        ~threshold=EdgeSnap.defaultThreshold,
        ~median,
      )->ignore
    }
    let elapsed = Date.now() -. start
    // Generous on purpose — this is a "didn't accidentally scan the whole
    // 1024×768 patch 1000 times" smoke test, not a tight perf budget. The
    // whole-patch version measured ~16 s here, so 3 s still discriminates
    // by 5× while surviving the parallel full-suite run on a loaded CPU
    // (500 ms failed under contention, passed standalone).
    expect(elapsed < 3000.0)->toBeTruthy
  })
})

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
