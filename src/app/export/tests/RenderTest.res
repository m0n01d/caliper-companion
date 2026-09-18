// RenderTest — the pure geometry in Render.res (SPEC §5 canvas cap, M5
// bullet 1; SPEC §8a A3's halo/ink legibility scheme, A14b's mono
// `Overlay` palette). Only the DOM-free half: no canvas exists in vitest's
// `node` environment (vitest.config.js), so the actual drawing is
// exercised by e2e/specs/export.spec.js instead.

open Vitest

describe("Render.targetSize", () => {
  test("under the cap: renders at oriented size, scale 1.0", () => {
    expect(Render.targetSize(~orientedWidth=1600, ~orientedHeight=1200))->toEqual((
      1600,
      1200,
      1.0,
    ))
  })

  test("exactly at the cap: still scale 1.0", () => {
    expect(Render.targetSize(~orientedWidth=4096, ~orientedHeight=3000))->toEqual((
      4096,
      3000,
      1.0,
    ))
  })

  test("over the cap: downscales so the long edge is exactly 4096", () => {
    let (w, h, scale) = Render.targetSize(~orientedWidth=8000, ~orientedHeight=6000)
    expect(w)->toBe(4096)
    expect(h)->toBe(3072)
    expect(scale)->toBeCloseTo(0.512, 3)
  })

  test("over the cap, portrait: the long edge (height) hits 4096", () => {
    let (w, h, _scale) = Render.targetSize(~orientedWidth=3000, ~orientedHeight=8000)
    expect(h)->toBe(4096)
    expect(w)->toBe(1536)
  })
})

describe("Render.strokeWidthPx / fontSizePx / pillHeightPx (SPEC §8a A3 bullet 2)", () => {
  test("stroke is 0.15% of the long edge, whichever axis that is", () => {
    expect(Render.strokeWidthPx(~renderWidth=1000, ~renderHeight=2000))->toBeCloseTo(3.0, 5)
    expect(Render.strokeWidthPx(~renderWidth=2000, ~renderHeight=1000))->toBeCloseTo(3.0, 5)
  })

  test("font is 1.4% of image height, pill height 2% of image height", () => {
    expect(Render.fontSizePx(~renderHeight=1200))->toBeCloseTo(16.8, 5)
    expect(Render.pillHeightPx(~renderHeight=1200))->toBeCloseTo(24.0, 5)
  })

  test("stroke floors at 2px min; font floors out on a tiny render instead of vanishing", () => {
    expect(Render.strokeWidthPx(~renderWidth=10, ~renderHeight=10))->toBe(2.0)
    expect(Render.fontSizePx(~renderHeight=10))->toBe(10.0)
  })
})

describe("Render.haloWidthPx / arrowheadSizePx / handleRadiusPx (SPEC §8a A3 bullets 1–2)", () => {
  test("halo is 2.5x the stroke width", () => {
    expect(Render.haloWidthPx(~strokeWidthPx=2.0))->toBeCloseTo(5.0, 5)
    expect(Render.haloWidthPx(~strokeWidthPx=4.0))->toBeCloseTo(10.0, 5)
  })

  test("arrowhead is 10px at a 2px stroke, scaling with it (5x the stroke width)", () => {
    expect(Render.arrowheadSizePx(~strokeWidthPx=2.0))->toBeCloseTo(10.0, 5)
    expect(Render.arrowheadSizePx(~strokeWidthPx=4.0))->toBeCloseTo(20.0, 5)
  })

  test("handle radius scales with the arrowhead (half its size)", () => {
    expect(Render.handleRadiusPx(~strokeWidthPx=2.0))->toBeCloseTo(5.0, 5)
    expect(Render.handleRadiusPx(~strokeWidthPx=4.0))->toBeCloseTo(10.0, 5)
  })
})

describe("Render.absLineOf", () => {
  test("places normalized points in the render's pixel space", () => {
    let line = Render.absLineOf(
      ~p1={x: 0.171, y: 0.448},
      ~p2={x: 0.811, y: 0.448},
      ~renderWidth=1600,
      ~renderHeight=1200,
    )
    expect(line.p1.x)->toBeCloseTo(273.6, 5)
    expect(line.p1.y)->toBeCloseTo(537.6, 5)
    expect(line.p2.x)->toBeCloseTo(1297.6, 5)
    expect(line.mid.x)->toBeCloseTo(785.6, 5)
    expect(line.mid.y)->toBeCloseTo(537.6, 5)
  })

  test("perpendicular is a unit vector, orthogonal to the line", () => {
    let line = Render.absLineOf(
      ~p1={x: 0.2, y: 0.2},
      ~p2={x: 0.2, y: 0.75},
      ~renderWidth=1600,
      ~renderHeight=1200,
    )
    let len = Math.sqrt(line.perp.x *. line.perp.x +. line.perp.y *. line.perp.y)
    expect(len)->toBeCloseTo(1.0, 6)
    let dot =
      (line.p2.x -. line.p1.x) *. line.perp.x +. (line.p2.y -. line.p1.y) *. line.perp.y
    expect(dot)->toBeCloseTo(0.0, 6)
  })

  test("a horizontal line's perpendicular points up (y <= 0)", () => {
    let line = Render.absLineOf(
      ~p1={x: 0.1, y: 0.5},
      ~p2={x: 0.9, y: 0.5},
      ~renderWidth=1000,
      ~renderHeight=1000,
    )
    expect(line.perp.y <= 0.0)->toBeTruthy
  })

  test("a vertical line's perpendicular breaks the tie toward -x", () => {
    let line = Render.absLineOf(
      ~p1={x: 0.3, y: 0.3},
      ~p2={x: 0.3, y: 0.55},
      ~renderWidth=1000,
      ~renderHeight=1000,
    )
    expect(line.perp.y)->toBeCloseTo(0.0, 6)
    expect(line.perp.x < 0.0)->toBeTruthy
  })

  test("a zero-length line still returns a well-defined perpendicular", () => {
    let line = Render.absLineOf(
      ~p1={x: 0.5, y: 0.5},
      ~p2={x: 0.5, y: 0.5},
      ~renderWidth=1000,
      ~renderHeight=1000,
    )
    expect(line.perp)->toEqual({x: 0.0, y: -1.0})
  })
})

describe("Render.dirOf", () => {
  test("unit vector from a to b", () => {
    let d = Render.dirOf({x: 0.0, y: 0.0}, {x: 3.0, y: 4.0})
    expect(d.x)->toBeCloseTo(0.6, 5)
    expect(d.y)->toBeCloseTo(0.8, 5)
  })

  test("a zero-length pair falls back to a fixed direction instead of NaN", () => {
    expect(Render.dirOf({x: 1.0, y: 1.0}, {x: 1.0, y: 1.0}))->toEqual({x: 1.0, y: 0.0})
  })
})

describe("Render.arrowheadTriangle (SPEC §8a A3 bullet 2)", () => {
  test("tip at the given point, base of width `size` centred behind it along -dir", () => {
    let t = Render.arrowheadTriangle(~tip={x: 100.0, y: 100.0}, ~dir={x: 1.0, y: 0.0}, ~size=10.0)
    expect(t.tip)->toEqual({x: 100.0, y: 100.0})
    expect(t.baseA.x)->toBeCloseTo(90.0, 5)
    expect(t.baseB.x)->toBeCloseTo(90.0, 5)
    expect(t.baseA.y)->toBeCloseTo(105.0, 5)
    expect(t.baseB.y)->toBeCloseTo(95.0, 5)
  })
})

describe("Render.pillFor", () => {
  test("centred on the midpoint, offset off the line along the perpendicular", () => {
    let pill = Render.pillFor(
      ~mid={x: 100.0, y: 100.0},
      ~perp={x: 0.0, y: -1.0},
      ~textWidth=40.0,
      ~pillHeightPx=24.0,
      ~fontSizePx=20.0,
    )
    // Horizontally centred on the midpoint.
    expect(pill.x +. pill.w /. 2.0)->toBeCloseTo(100.0, 5)
    // Offset upward (away from the line) — entirely above the midpoint.
    expect(pill.y +. pill.h < 100.0)->toBeTruthy
    // Sized to the text plus padding, and exactly the given pill height.
    expect(pill.w > 40.0)->toBeTruthy
    expect(pill.h)->toBeCloseTo(24.0, 6)
    // A stadium shape: corner radius is half the height.
    expect(pill.radius)->toBeCloseTo(pill.h /. 2.0, 6)
  })
})

describe("Render.labelText", () => {
  test("name = formatted value unit (SPEC M5 bullet 1)", () => {
    let dim: Types.dimension = {
      id: "dim:1",
      faceId: "face:1",
      name: "overall_l",
      kind: Length,
      value: 42.18,
      tolerance: 0.1,
      p1: {x: 0.0, y: 0.0},
      p2: {x: 1.0, y: 0.0},
      source: Typed,
      createdAt: "2026-09-17T14:02:01Z",
    }
    expect(Render.labelText(dim, Mm))->toBe("overall_l = 42.18 mm")
  })

  test("inch units use NumberParse's 3-decimal formatting", () => {
    let dim: Types.dimension = {
      id: "dim:2",
      faceId: "face:1",
      name: "pin_dia",
      kind: Diameter,
      value: 0.256,
      tolerance: 0.01,
      p1: {x: 0.0, y: 0.0},
      p2: {x: 1.0, y: 0.0},
      source: Typed,
      createdAt: "2026-09-17T14:02:01Z",
    }
    expect(Render.labelText(dim, Inch))->toBe("pin_dia = 0.256 in")
  })
})

describe("Render.contrastRatio (SPEC §8a A3 bullet 3: pill/text contrast >= 4.5:1)", () => {
  test("identical colours have a contrast ratio of exactly 1", () => {
    expect(Render.contrastRatio("#ffffff", "#ffffff"))->toBeCloseTo(1.0, 6)
    expect(Render.contrastRatio("#000000", "#000000"))->toBeCloseTo(1.0, 6)
  })

  test("black on white is the WCAG maximum, 21:1", () => {
    expect(Render.contrastRatio("#000000", "#ffffff"))->toBeCloseTo(21.0, 3)
  })

  test("order doesn't matter — the lighter colour is always the numerator", () => {
    let ab = Render.contrastRatio("#000000", "#ffffff")
    let ba = Render.contrastRatio("#ffffff", "#000000")
    expect(ab)->toBeCloseTo(ba, 6)
  })

  test("the pill fill/text colours clear WCAG AA (>= 4.5:1)", () => {
    let ratio = Render.contrastRatio(Render.pillFillColor, Render.pillTextColor)
    expect(ratio >= 4.5)->toBeTruthy
  })
})

// SPEC §8a A14b: `Overlay.inkOn` is the label/border colour drawn on top of
// `Overlay.ink` fills (the active canvas pill, the export pill) — this is
// the module-level guarantee `Render.contrastRatio` exists to check,
// independent of which of Render's `pill*Color` bindings currently point
// at which `Overlay` constant.
describe("Overlay contrast (SPEC §8a A14b)", () => {
  test("inkOn on ink clears WCAG AA (>= 4.5:1)", () => {
    let ratio = Render.contrastRatio(Overlay.inkOn, Overlay.ink)
    expect(ratio >= 4.5)->toBeTruthy
  })
})
