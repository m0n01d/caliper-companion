// Render — the dimensioned PNG per face (SPEC §5 canvas cap, M5 bullet 1).
//
// Geometry is pure and sits at the top so `tests/RenderTest.res` can check
// it without a DOM (this repo's vitest runs in `node`, which has no
// canvas). The drawing functions below replay that geometry through
// `Canvas2d`; they're exercised by the e2e suite, not unit tests.

// -- pure layout --------------------------------------------------------

// SPEC §5: "anything larger [than ~16.7 MP / 4096 on the long edge] gets
// downscaled to 4096 on the long edge and the scale recorded in JSON."
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

// SPEC M5 bullet 1: "stroke widths scaled with the image (≈0.3% of
// height, min 2 px)".
let strokeWidthPx = (~renderHeight: int): float =>
  Math.max(Int.toFloat(renderHeight) *. 0.003, 2.0)

// SPEC M5 bullet 1 / M4: "font size ≥ 2% of the rendered image height".
// The 10px floor only matters for pathologically small renders; every real
// photo clears it by a wide margin.
let fontSizePx = (~renderHeight: int): float =>
  Math.max(Int.toFloat(renderHeight) *. 0.02, 10.0)

// Extension-tick length at each endpoint, perpendicular to the dimension
// line — scaled with the image like the stroke width.
let tickLengthPx = (~renderHeight: int): float => Int.toFloat(renderHeight) *. 0.015

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

type pillRect = {x: float, y: float, w: float, h: float, radius: float}

// The solid pill a label sits on (SPEC M5 bullet 1: "name + value labels
// on solid pills"): a stadium shape sized to the measured text, centred on
// the line's midpoint and offset off the line along its perpendicular so
// it doesn't overlap the dimension line itself.
let pillFor = (~mid: vec, ~perp: vec, ~textWidth: float, ~fontSizePx: float): pillRect => {
  let paddingX = fontSizePx *. 0.6
  let paddingY = fontSizePx *. 0.35
  let h = fontSizePx +. paddingY *. 2.0
  let w = textWidth +. paddingX *. 2.0
  let offset = fontSizePx *. 1.1 +. h /. 2.0
  let cx = mid.x +. perp.x *. offset
  let cy = mid.y +. perp.y *. offset
  {x: cx -. w /. 2.0, y: cy -. h /. 2.0, w, h, radius: h /. 2.0}
}

let labelText = (d: Types.dimension, units: Types.units): string =>
  d.name ++ " = " ++ NumberParse.format(d.value, units) ++ " " ++ NumberParse.unitsLabel(units)

// -- drawing --------------------------------------------------------------

let lineColor = "#14213d"
let pillFillColor = "#14213d"
let pillTextColor = "#ffffff"

let drawTick = (ctx: Canvas2d.ctx, p: vec, perp: vec, length: float): unit => {
  let half = length /. 2.0
  Canvas2d.beginPath(ctx)
  Canvas2d.moveTo(ctx, p.x -. perp.x *. half, p.y -. perp.y *. half)
  Canvas2d.lineTo(ctx, p.x +. perp.x *. half, p.y +. perp.y *. half)
  Canvas2d.stroke(ctx)
}

let drawDimension = (
  ctx: Canvas2d.ctx,
  ~dimension: Types.dimension,
  ~units: Types.units,
  ~renderWidth: int,
  ~renderHeight: int,
): unit => {
  let sw = strokeWidthPx(~renderHeight)
  let line = absLineOf(~p1=dimension.p1, ~p2=dimension.p2, ~renderWidth, ~renderHeight)
  let tick = tickLengthPx(~renderHeight)

  Canvas2d.setStrokeStyle(ctx, lineColor)
  Canvas2d.setLineWidth(ctx, sw)
  Canvas2d.beginPath(ctx)
  Canvas2d.moveTo(ctx, line.p1.x, line.p1.y)
  Canvas2d.lineTo(ctx, line.p2.x, line.p2.y)
  Canvas2d.stroke(ctx)
  drawTick(ctx, line.p1, line.perp, tick)
  drawTick(ctx, line.p2, line.perp, tick)

  let fs = fontSizePx(~renderHeight)
  Canvas2d.setFont(ctx, Int.toString(Float.toInt(Math.round(fs))) ++ "px sans-serif")
  Canvas2d.setTextAlign(ctx, "center")
  Canvas2d.setTextBaseline(ctx, "middle")
  let label = labelText(dimension, units)
  let textWidth = Canvas2d.measureText(ctx, label)->Canvas2d.metricsWidth
  let pill = pillFor(~mid=line.mid, ~perp=line.perp, ~textWidth, ~fontSizePx=fs)

  Canvas2d.setFillStyle(ctx, pillFillColor)
  Canvas2d.beginPath(ctx)
  Canvas2d.roundRect(ctx, pill.x, pill.y, pill.w, pill.h, pill.radius)
  Canvas2d.fill(ctx)

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
