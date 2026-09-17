// Render — the dimensioned PNG per face (SPEC §5 canvas cap, M5 bullet 1;
// SPEC §8a A3 for the amber/halo legibility scheme).
//
// Geometry is pure and sits at the top so `tests/RenderTest.res` can check
// it without a DOM (this repo's vitest runs in `node`, which has no
// canvas). The drawing functions below replay that geometry through
// `Canvas2d`; they're exercised by the e2e suite, not unit tests.

// -- pure layout --------------------------------------------------------

// SPEC §5: "anything larger [than ~16.7 MP / 4096 on the long edge] gets
// downscaled to 4096 on the long edge and the scale recorded in JSON."
// SPEC §8a A4 caps *stored* photos at 2048 on the long edge before this
// module ever sees them, so in practice `renderScale` is always `1.0` and
// this branch is unreachable today — kept (not deleted) per A4's own
// bullet ("a later tier can raise the cap"), and because `renderScale`
// staying a real, computed field (not hardcoded to `1.0`) is what makes
// raising that cap later a config change, not a code change.
let canvasCapLongEdge = 4096

// Target render size for one face. `renderScale` is `rendered / oriented`,
// `1.0` when no downscale was needed (SPEC M5 bullet 1 / §7 `renderScale`).
let targetSize = (~orientedWidth: int, ~orientedHeight: int): (int, int, float) => {
  let longEdge = Int.toFloat(Math.Int.max(orientedWidth, orientedHeight))
  if longEdge <= Int.toFloat(canvasCapLongEdge) {
    (orientedWidth, orientedHeight, 1.0)
  } else {
    let scale = Int.toFloat(canvasCapLongEdge) /. longEdge
    let w = Math.round(Int.toFloat(orientedWidth) *. scale)
    let h = Math.round(Int.toFloat(orientedHeight) *. scale)
    (Float.toInt(w), Float.toInt(h), scale)
  }
}

// SPEC §8a A3 bullet 2: "stroke 0.15% of the long edge (min 2px)" — every
// stroke (dimension line, arrowheads, extension ticks, endpoint handles)
// scales off this one value. Supersedes the pre-A3 "~0.3% of height"
// reading, which the phone dogfood found too thin to read against a busy
// photo anyway.
let strokeWidthPx = (~renderWidth: int, ~renderHeight: int): float => {
  let longEdge = Int.toFloat(Math.Int.max(renderWidth, renderHeight))
  Math.max(longEdge *. 0.0015, 2.0)
}

// SPEC §8a A3 bullet 2: "label font 1.4% of image height". The floor only
// matters for pathologically small renders; every real photo clears it by
// a wide margin (kept from the pre-A3 version, same reasoning).
let fontSizePx = (~renderHeight: int): float =>
  Math.max(Int.toFloat(renderHeight) *. 0.014, 10.0)

// SPEC §8a A3 bullet 2: "pill height 2% of image height" — a fixed
// measure now, independent of the font metrics (DESIGN.md §5's export
// paragraph lists it separately from the font-size rule).
let pillHeightPx = (~renderHeight: int): float => Int.toFloat(renderHeight) *. 0.02

// Extension-tick length at each endpoint, perpendicular to the dimension
// line — scaled with the image, unchanged by A3 (only their colour and
// dashing changed).
let tickLengthPx = (~renderHeight: int): float => Int.toFloat(renderHeight) *. 0.015

// SPEC §8a A3 bullet 1: "halo … at 2.5× the line width underneath".
let haloWidthPx = (~strokeWidthPx: float): float => strokeWidthPx *. 2.5

// SPEC §8a A3 bullet 2: "arrowheads 10×10 scaled by the same factor as the
// stroke (10px at a 2px stroke)" — i.e. 5× the stroke width.
let arrowheadSizePx = (~strokeWidthPx: float): float => strokeWidthPx *. 5.0

// Not itself in the SPEC bullet list (only line/pill/font/arrowhead sizes
// are specified) — A3 bullet 1 also asks for endpoint handles to get the
// halo treatment, so this picks a size for them. Judgment call: half the
// arrowhead size, so a handle and the arrowhead sharing an endpoint read
// as one scale, not two (see LOGBOOK.md).
let handleRadiusPx = (~strokeWidthPx: float): float => arrowheadSizePx(~strokeWidthPx) /. 2.0

type vec = {x: float, y: float}
type absLine = {p1: vec, p2: vec, mid: vec, perp: vec}

// A dimension's two normalized points, placed in the render's pixel space,
// plus their midpoint and a unit vector perpendicular to the line. The
// perpendicular is oriented consistently (y ≤ 0, i.e. "up" in image space,
// breaking a vertical line's tie toward -x) so a face's labels don't flip
// from one side of the line to the other dimension to dimension.
let absLineOf = (
  ~p1: Types.point,
  ~p2: Types.point,
  ~renderWidth: int,
  ~renderHeight: int,
): absLine => {
  let rw = Int.toFloat(renderWidth)
  let rh = Int.toFloat(renderHeight)
  let a = {x: p1.x *. rw, y: p1.y *. rh}
  let b = {x: p2.x *. rw, y: p2.y *. rh}
  let dx = b.x -. a.x
  let dy = b.y -. a.y
  let len = Math.sqrt(dx *. dx +. dy *. dy)
  let perp = if len == 0.0 {
    {x: 0.0, y: -1.0}
  } else {
    let ux = -.dy /. len
    let uy = dx /. len
    if uy < 0.0 || (uy == 0.0 && ux < 0.0) {
      {x: ux, y: uy}
    } else {
      {x: -.ux, y: -.uy}
    }
  }
  {p1: a, p2: b, mid: {x: (a.x +. b.x) /. 2.0, y: (a.y +. b.y) /. 2.0}, perp}
}

// Unit vector from `a` to `b`, used to point each end's arrowhead
// (SPEC §8a A3) outward along the line. Zero-length falls back to a fixed
// direction instead of NaN — mirrors `absLineOf`'s own guard on `perp`.
let dirOf = (a: vec, b: vec): vec => {
  let dx = b.x -. a.x
  let dy = b.y -. a.y
  let len = Math.sqrt(dx *. dx +. dy *. dy)
  len == 0.0 ? {x: 1.0, y: 0.0} : {x: dx /. len, y: dy /. len}
}

type triangle = {tip: vec, baseA: vec, baseB: vec}

// The filled triangle for one end's arrowhead (SPEC §8a A3 bullet 2:
// "10×10-equivalent arrowheads"): tip at the dimension line's endpoint,
// pointing along `dir`, base of width `size` centred `size` behind the
// tip along `-dir`.
let arrowheadTriangle = (~tip: vec, ~dir: vec, ~size: float): triangle => {
  let backX = tip.x -. dir.x *. size
  let backY = tip.y -. dir.y *. size
  let px = -.dir.y
  let py = dir.x
  let half = size /. 2.0
  {
    tip,
    baseA: {x: backX +. px *. half, y: backY +. py *. half},
    baseB: {x: backX -. px *. half, y: backY -. py *. half},
  }
}

type pillRect = {x: float, y: float, w: float, h: float, radius: float}

// The solid pill a label sits on (SPEC M5 bullet 1: "name + value labels
// on solid pills"): a stadium shape `pillHeightPx` tall, wide enough for
// the measured text, centred on the line's midpoint and offset off the
// line along its perpendicular so it doesn't overlap the dimension line
// itself.
let pillFor = (
  ~mid: vec,
  ~perp: vec,
  ~textWidth: float,
  ~pillHeightPx: float,
  ~fontSizePx: float,
): pillRect => {
  let paddingX = fontSizePx *. 0.6
  let h = pillHeightPx
  let w = textWidth +. paddingX *. 2.0
  let clearance = fontSizePx *. 0.5
  let offset = clearance +. h /. 2.0
  let cx = mid.x +. perp.x *. offset
  let cy = mid.y +. perp.y *. offset
  {x: cx -. w /. 2.0, y: cy -. h /. 2.0, w, h, radius: h /. 2.0}
}

let labelText = (d: Types.dimension, units: Types.units): string =>
  d.name ++ " = " ++ NumberParse.format(d.value, units) ++ " " ++ NumberParse.unitsLabel(units)

// -- WCAG contrast (SPEC §8a A3 bullet 3: pill/text contrast ≥ 4.5:1) ----

let srgbToLinear = (channel255: float): float => {
  let c = channel255 /. 255.0
  c <= 0.03928 ? c /. 12.92 : Math.pow((c +. 0.055) /. 1.055, ~exp=2.4)
}

// One 2-hex-digit channel out of a "#RRGGBB" string, as 0.0–255.0. The
// single source of truth for this module's colour constants doubles as
// both their `Canvas2d.setFillStyle`/`setStrokeStyle` hex string and (via
// `contrastRatio` below) their WCAG contrast — the two can never drift.
let hexChannel = (hex: string, ~at: int): float =>
  Int.fromString(String.slice(hex, ~start=at, ~end=at + 2), ~radix=16)
  ->Option.getOr(0)
  ->Int.toFloat

// WCAG 2.1 relative luminance of a "#RRGGBB" colour.
let relativeLuminance = (hex: string): float => {
  let r = srgbToLinear(hexChannel(hex, ~at=1))
  let g = srgbToLinear(hexChannel(hex, ~at=3))
  let b = srgbToLinear(hexChannel(hex, ~at=5))
  0.2126 *. r +. 0.7152 *. g +. 0.0722 *. b
}

// WCAG 2.1 contrast ratio between two "#RRGGBB" colours (order doesn't
// matter — the lighter one is always the numerator).
let contrastRatio = (hexA: string, hexB: string): float => {
  let la = relativeLuminance(hexA)
  let lb = relativeLuminance(hexB)
  let (lighter, darker) = la >= lb ? (la, lb) : (lb, la)
  (lighter +. 0.05) /. (darker +. 0.05)
}

// -- drawing --------------------------------------------------------------
//
// SPEC §8a A3 bullet 1: every stroke is drawn twice, a near-black halo
// underneath then amber on top — replacing the old navy scheme, which the
// phone dogfood found unreadable on dark photos.

let haloColor = "rgba(23,24,26,0.85)" // cc-ground at 85% alpha (DESIGN.md §2)
let lineColor = "#F2A33A" // cc-amber
let pillFillColor = "#F2A33A" // cc-amber
let pillTextColor = "#2B1A02" // cc-amber-ink
let pillBorderColor = "#17181A" // cc-ground, "near-black"
let pillBorderWidthPx = 1.0 // SPEC §8a A3 bullet 1: "1px near-black border" — literal, not scaled
let labelFontFamily = "\"IBM Plex Mono\", ui-monospace, Menlo, monospace" // cc-font-mono, DESIGN.md §2

// Strokes `path` twice on `ctx`: a halo pass (near-black, `haloWidthPx`
// wide) underneath, then the amber line on top at `strokeWidthPx` — SPEC
// §8a A3 bullet 1. `path` only issues `moveTo`/`lineTo` calls; this
// function owns `beginPath`/`stroke` for each pass so the same path can be
// replayed twice with different line widths and colours.
let strokeHaloed = (
  ctx: Canvas2d.ctx,
  ~strokeWidthPx: float,
  ~dash: array<float>=[],
  ~path: unit => unit,
): unit => {
  Canvas2d.setLineDash(ctx, dash)

  Canvas2d.setStrokeStyle(ctx, haloColor)
  Canvas2d.setLineWidth(ctx, haloWidthPx(~strokeWidthPx))
  Canvas2d.beginPath(ctx)
  path()
  Canvas2d.stroke(ctx)

  Canvas2d.setStrokeStyle(ctx, lineColor)
  Canvas2d.setLineWidth(ctx, strokeWidthPx)
  Canvas2d.beginPath(ctx)
  path()
  Canvas2d.stroke(ctx)

  Canvas2d.setLineDash(ctx, [])
}

// Fills `path` twice: a halo pass (fill, then a `haloWidthPx` outline
// stroke so the halo also bleeds past the shape's own edge) underneath,
// then the amber fill on top — the filled-shape equivalent of
// `strokeHaloed`, for the arrowheads and endpoint handles (SPEC §8a A3
// bullet 1 lists both alongside the line and ticks).
let fillHaloed = (ctx: Canvas2d.ctx, ~strokeWidthPx: float, ~path: unit => unit): unit => {
  Canvas2d.setLineDash(ctx, [])

  Canvas2d.beginPath(ctx)
  path()
  Canvas2d.setFillStyle(ctx, haloColor)
  Canvas2d.fill(ctx)
  Canvas2d.setStrokeStyle(ctx, haloColor)
  Canvas2d.setLineWidth(ctx, haloWidthPx(~strokeWidthPx))
  Canvas2d.stroke(ctx)

  Canvas2d.beginPath(ctx)
  path()
  Canvas2d.setFillStyle(ctx, lineColor)
  Canvas2d.fill(ctx)
}

let tickPath = (ctx: Canvas2d.ctx, p: vec, perp: vec, length: float): unit => {
  let half = length /. 2.0
  Canvas2d.moveTo(ctx, p.x -. perp.x *. half, p.y -. perp.y *. half)
  Canvas2d.lineTo(ctx, p.x +. perp.x *. half, p.y +. perp.y *. half)
}

let trianglePath = (ctx: Canvas2d.ctx, t: triangle): unit => {
  Canvas2d.moveTo(ctx, t.tip.x, t.tip.y)
  Canvas2d.lineTo(ctx, t.baseA.x, t.baseA.y)
  Canvas2d.lineTo(ctx, t.baseB.x, t.baseB.y)
  Canvas2d.closePath(ctx)
}

let fullCirclePi = 2.0 *. Math.Constants.pi

let drawDimension = (
  ctx: Canvas2d.ctx,
  ~dimension: Types.dimension,
  ~units: Types.units,
  ~renderWidth: int,
  ~renderHeight: int,
): unit => {
  let sw = strokeWidthPx(~renderWidth, ~renderHeight)
  let line = absLineOf(~p1=dimension.p1, ~p2=dimension.p2, ~renderWidth, ~renderHeight)
  let tick = tickLengthPx(~renderHeight)
  let arrow = arrowheadSizePx(~strokeWidthPx=sw)
  let handleR = handleRadiusPx(~strokeWidthPx=sw)
  // Extension-tick dash, scaled the same way as the arrowhead (SPEC §8a A3
  // bullet 2's "scaled by the same factor as the stroke") off DESIGN.md
  // §5's live-canvas dash (4/3 at a 2px stroke).
  let dashScale = sw /. 2.0
  let tickDash = [4.0 *. dashScale, 3.0 *. dashScale]

  // Dimension line.
  strokeHaloed(ctx, ~strokeWidthPx=sw, ~path=() => {
    Canvas2d.moveTo(ctx, line.p1.x, line.p1.y)
    Canvas2d.lineTo(ctx, line.p2.x, line.p2.y)
  })

  // Extension ticks — dashed (SPEC §8a A3 bullet 2).
  strokeHaloed(ctx, ~strokeWidthPx=sw, ~dash=tickDash, ~path=() => {
    tickPath(ctx, line.p1, line.perp, tick)
    tickPath(ctx, line.p2, line.perp, tick)
  })

  // Arrowheads at both ends, tips at the endpoints, pointing outward.
  let arrowAtP1 = arrowheadTriangle(~tip=line.p1, ~dir=dirOf(line.p2, line.p1), ~size=arrow)
  let arrowAtP2 = arrowheadTriangle(~tip=line.p2, ~dir=dirOf(line.p1, line.p2), ~size=arrow)
  [arrowAtP1, arrowAtP2]->Array.forEach(t =>
    fillHaloed(ctx, ~strokeWidthPx=sw, ~path=() => trianglePath(ctx, t))
  )

  // Endpoint handles.
  [line.p1, line.p2]->Array.forEach(p =>
    fillHaloed(ctx, ~strokeWidthPx=sw, ~path=() =>
      Canvas2d.arc(ctx, p.x, p.y, handleR, 0.0, fullCirclePi)
    )
  )

  // Label pill.
  let fs = fontSizePx(~renderHeight)
  let pillH = pillHeightPx(~renderHeight)
  Canvas2d.setFont(ctx, Int.toString(Float.toInt(Math.round(fs))) ++ "px " ++ labelFontFamily)
  Canvas2d.setTextAlign(ctx, "center")
  Canvas2d.setTextBaseline(ctx, "middle")
  let label = labelText(dimension, units)
  let textWidth = Canvas2d.measureText(ctx, label)->Canvas2d.metricsWidth
  let pill = pillFor(~mid=line.mid, ~perp=line.perp, ~textWidth, ~pillHeightPx=pillH, ~fontSizePx=fs)

  Canvas2d.setFillStyle(ctx, pillFillColor)
  Canvas2d.beginPath(ctx)
  Canvas2d.roundRect(ctx, pill.x, pill.y, pill.w, pill.h, pill.radius)
  Canvas2d.fill(ctx)

  Canvas2d.setStrokeStyle(ctx, pillBorderColor)
  Canvas2d.setLineWidth(ctx, pillBorderWidthPx)
  Canvas2d.beginPath(ctx)
  Canvas2d.roundRect(ctx, pill.x, pill.y, pill.w, pill.h, pill.radius)
  Canvas2d.stroke(ctx)

  Canvas2d.setFillStyle(ctx, pillTextColor)
  Canvas2d.fillText(ctx, label, pill.x +. pill.w /. 2.0, pill.y +. pill.h /. 2.0)
}

// Decodes `faceImage` oriented (SPEC §5's `from-image` rule, applied again
// here — the app never trusts a stored width/height over a fresh decode),
// draws it at the target size, then every dimension on that face. Returns
// the rendered PNG plus the render size actually used and its scale
// relative to the oriented image, for `FeaturesDocument`'s `renderScale`.
let renderFace = async (
  ~faceImage: Canvas2d.blob,
  ~dimensions: array<Types.dimension>,
  ~units: Types.units,
): (Canvas2d.blob, int, int, float) => {
  let bitmap = await Canvas2d.decodeOriented(faceImage)
  let orientedWidth = Canvas2d.bitmapWidth(bitmap)
  let orientedHeight = Canvas2d.bitmapHeight(bitmap)
  let (renderWidth, renderHeight, renderScale) = targetSize(~orientedWidth, ~orientedHeight)

  let target = Canvas2d.makeTarget(~width=renderWidth, ~height=renderHeight)
  let ctx = Canvas2d.context2d(target)
  Canvas2d.drawImage(ctx, bitmap, 0.0, 0.0, Int.toFloat(renderWidth), Int.toFloat(renderHeight))
  dimensions->Array.forEach(dimension =>
    drawDimension(ctx, ~dimension, ~units, ~renderWidth, ~renderHeight)
  )

  let blob = await Canvas2d.toBlob(target)
  (blob, renderWidth, renderHeight, renderScale)
}
