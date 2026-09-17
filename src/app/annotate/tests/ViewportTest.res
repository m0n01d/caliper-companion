// ViewportTest — SPEC M4 bullet 1 in unit form: the same feature tapped at
// 1× and 3× must yield the same normalized point, and every gesture is a
// change to the transform, never to a stored point.

open Vitest

let imageW = 1200.0 // fixtures/hinge_pin/end.jpg, oriented (portrait)
let imageH = 1600.0
let viewW = 390.0
let viewH = 600.0

let fitT = () => Viewport.fit(~imageW, ~imageH, ~viewW, ~viewH)

let expectPt = (actual: Viewport.pt, expected: Viewport.pt) => {
  expect(actual.x)->toBeCloseTo(expected.x, 6)
  expect(actual.y)->toBeCloseTo(expected.y, 6)
}

let expectNorm = (actual: Types.point, expected: Types.point) => {
  expect(actual.x)->toBeCloseTo(expected.x, 6)
  expect(actual.y)->toBeCloseTo(expected.y, 6)
}

describe("Viewport.fit", () => {
  test("contains a portrait image in a portrait view and centres the slack", () => {
    let t = fitT()
    // 390/1200 = 0.325 wins over 600/1600 = 0.375
    expect(t.scale)->toBeCloseTo(0.325, 6)
    expect(t.tx)->toBeCloseTo(0.0, 6)
    expect(t.ty)->toBeCloseTo((600.0 -. 1600.0 *. 0.325) /. 2.0, 6)
  })

  test("contains a landscape image in a portrait view", () => {
    let t = Viewport.fit(~imageW=1600.0, ~imageH=1200.0, ~viewW, ~viewH)
    expect(t.scale)->toBeCloseTo(390.0 /. 1600.0, 6)
    expect(t.tx)->toBeCloseTo(0.0, 6)
    expect(t.ty)->toBeCloseTo((600.0 -. 1200.0 *. (390.0 /. 1600.0)) /. 2.0, 6)
  })

  test("degenerate sizes fall back to identity instead of NaN", () => {
    expect(Viewport.fit(~imageW=0.0, ~imageH, ~viewW, ~viewH))->toEqual(Viewport.identity)
    expect(Viewport.fit(~imageW, ~imageH, ~viewW=0.0, ~viewH))->toEqual(Viewport.identity)
  })
})

describe("Viewport normalized ↔ screen round trip", () => {
  let hole: Types.point = {x: 0.55, y: 0.30} // fixtures/README.md, oriented end.jpg

  test("fromNormalized ∘ toNormalized is identity at fit scale", () => {
    let t = fitT()
    let s = Viewport.fromNormalized(t, ~imageW, ~imageH, hole)
    expectNorm(Viewport.toNormalized(t, ~imageW, ~imageH, s), hole)
  })

  test("round-trips at several scales and offsets", () => {
    let transforms = [
      Viewport.identity,
      fitT(),
      {Viewport.scale: 0.9, tx: -120.5, ty: 33.25},
      {Viewport.scale: 2.7, tx: -900.0, ty: -410.0},
      {Viewport.scale: 8.0 *. 0.325, tx: -2000.0, ty: -3000.0},
    ]
    let points: array<Types.point> = [
      {x: 0.0, y: 0.0},
      {x: 1.0, y: 1.0},
      hole,
      {x: 0.171, y: 0.448},
      {x: 0.811, y: 0.448},
    ]
    transforms->Array.forEach(t =>
      points->Array.forEach(n => {
        let s = Viewport.fromNormalized(t, ~imageW, ~imageH, n)
        expectNorm(Viewport.toNormalized(t, ~imageW, ~imageH, s), n)
        expectPt(Viewport.toScreen(t, Viewport.toImage(t, s)), s)
      })
    )
  })

  test("the same feature maps to the same normalized point at 1× and 3× (SPEC M4 bullet 1)", () => {
    let t1 = fitT()
    let t3 = Viewport.zoomAbout(t1, ~factor=3.0, ~screenAnchor={x: viewW /. 2.0, y: viewH /. 2.0})
    expect(t3.scale /. t1.scale)->toBeCloseTo(3.0, 9)
    // Where the hole is on screen differs at each zoom…
    let s1 = Viewport.fromNormalized(t1, ~imageW, ~imageH, hole)
    let s3 = Viewport.fromNormalized(t3, ~imageW, ~imageH, hole)
    expect(Viewport.distance(s1, s3) > 1.0)->toBeTruthy
    // …but tapping it yields the same stored point.
    expectNorm(Viewport.toNormalized(t1, ~imageW, ~imageH, s1), hole)
    expectNorm(Viewport.toNormalized(t3, ~imageW, ~imageH, s3), hole)
  })
})

describe("Viewport.zoomAbout", () => {
  test("keeps the anchor fixed on screen", () => {
    let t = fitT()
    let anchor: Viewport.pt = {x: 123.0, y: 456.0}
    let before = Viewport.toImage(t, anchor)
    let after = Viewport.zoomAbout(t, ~factor=2.5, ~screenAnchor=anchor)
    expectPt(Viewport.toImage(after, anchor), before)
    expect(after.scale)->toBeCloseTo(t.scale *. 2.5, 9)
  })

  test("zooming in then out by the reciprocal restores the transform", () => {
    let t = fitT()
    let anchor: Viewport.pt = {x: 10.0, y: 590.0}
    let back =
      Viewport.zoomAbout(t, ~factor=1.5, ~screenAnchor=anchor)->Viewport.zoomAbout(
        ~factor=1.0 /. 1.5,
        ~screenAnchor=anchor,
      )
    expect(back.scale)->toBeCloseTo(t.scale, 9)
    expect(back.tx)->toBeCloseTo(t.tx, 9)
    expect(back.ty)->toBeCloseTo(t.ty, 9)
  })
})

describe("Viewport.pinch", () => {
  test("fingers that keep their distance produce a pure pan", () => {
    let t = fitT()
    let prev = (Viewport.pt(100.0, 100.0), Viewport.pt(200.0, 200.0))
    let next = (Viewport.pt(130.0, 110.0), Viewport.pt(230.0, 210.0))
    let after = Viewport.pinch(t, ~prev, ~next)
    expect(after.scale)->toBeCloseTo(t.scale, 9)
    expect(after.tx)->toBeCloseTo(t.tx +. 30.0, 9)
    expect(after.ty)->toBeCloseTo(t.ty +. 10.0, 9)
  })

  test("spreading fingers scales by the distance ratio about the midpoint", () => {
    let t = fitT()
    let prev = (Viewport.pt(100.0, 100.0), Viewport.pt(200.0, 100.0))
    let next = (Viewport.pt(50.0, 100.0), Viewport.pt(250.0, 100.0))
    let mid: Viewport.pt = {x: 150.0, y: 100.0}
    let under = Viewport.toImage(t, mid)
    let after = Viewport.pinch(t, ~prev, ~next)
    expect(after.scale)->toBeCloseTo(t.scale *. 2.0, 9)
    expectPt(Viewport.toImage(after, mid), under)
  })

  test("a zero previous distance is a pan, not a division by zero", () => {
    let t = fitT()
    let same = Viewport.pt(100.0, 100.0)
    let after = Viewport.pinch(t, ~prev=(same, same), ~next=(Viewport.pt(110.0, 100.0), Viewport.pt(110.0, 100.0)))
    expect(after.scale)->toBeCloseTo(t.scale, 9)
    expect(after.tx)->toBeCloseTo(t.tx +. 10.0, 9)
  })
})

describe("Viewport.clamp", () => {
  let fitScale = fitT().scale
  let clampT = t =>
    Viewport.clamp(t, ~minScale=fitScale, ~maxScale=8.0 *. fitScale, ~imageW, ~imageH, ~viewW, ~viewH)

  test("scale never drops below fit and a smaller-than-view axis is centred", () => {
    let t = fitT()->Viewport.zoomAbout(~factor=0.5, ~screenAnchor={x: 0.0, y: 0.0})
    let c = clampT(t)
    expect(c.scale)->toBeCloseTo(fitScale, 9)
    expect(c.tx)->toBeCloseTo(0.0, 6)
    expect(c.ty)->toBeCloseTo((viewH -. imageH *. fitScale) /. 2.0, 6)
  })

  test("scale never exceeds 8× fit", () => {
    let t = fitT()->Viewport.zoomAbout(~factor=20.0, ~screenAnchor={x: 100.0, y: 100.0})
    expect(clampT(t).scale)->toBeCloseTo(8.0 *. fitScale, 9)
  })

  test("a zoomed image can be panned until its edge reaches the view centre, no further", () => {
    let t = fitT()->Viewport.zoomAbout(~factor=3.0, ~screenAnchor={x: viewW /. 2.0, y: viewH /. 2.0})
    let extentW = imageW *. t.scale
    let farRight = clampT(t->Viewport.pan(~dx=10000.0, ~dy=0.0))
    expect(farRight.tx)->toBeCloseTo(viewW /. 2.0, 6)
    let farLeft = clampT(t->Viewport.pan(~dx=-10000.0, ~dy=0.0))
    expect(farLeft.tx)->toBeCloseTo(viewW /. 2.0 -. extentW, 6)
    // A transform already within bounds is left alone.
    let inside = clampT(t)
    expect(inside.tx)->toBeCloseTo(t.tx, 9)
    expect(inside.ty)->toBeCloseTo(t.ty, 9)
  })
})

describe("Viewport.distanceToSegment", () => {
  test("perpendicular distance inside the segment, endpoint distance outside it", () => {
    let a = Viewport.pt(0.0, 0.0)
    let b = Viewport.pt(100.0, 0.0)
    expect(Viewport.distanceToSegment(Viewport.pt(50.0, 12.0), ~a, ~b))->toBeCloseTo(12.0, 9)
    expect(Viewport.distanceToSegment(Viewport.pt(130.0, 40.0), ~a, ~b))->toBeCloseTo(50.0, 9)
    expect(Viewport.distanceToSegment(Viewport.pt(3.0, 4.0), ~a, ~b=a))->toBeCloseTo(5.0, 9)
  })
})
