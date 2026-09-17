// Draw — 2D-context drawing for the annotate canvas (SPEC M4 bullets 2 and
// 8): the oriented image, dimension lines with extension ticks and a name
// label, and the draggable endpoint handles. Every function takes a context
// plus plain values and returns unit; no state lives here. Coordinates are
// canvas CSS pixels — `Annotate.res` applies the devicePixelRatio transform
// to the context before calling in, so line widths and hit radii are the
// same physical size at any DPR.
//
// Colours are the theme.css tokens by value: a canvas can't read CSS custom
// properties, and getComputedStyle on every redraw isn't worth it for four
// constants.

type style =
  | Dimmed // an existing dimension on this face, not selected
  | Selected // the existing dimension being edited
  | Pending // the dimension being placed

let rust = "#b85c38"
let forest = "#2d3a22"
let cream = "#f2ede3"
let ink = "#1e2818"

let handleRadius = 9.0 // drawn; the hit radius (24 px) is Annotate's business
let tickHalf = 8.0
let labelFont = "600 13px ui-monospace, 'SF Mono', Menlo, monospace"

let image = (
  ctx: Canvas.Ctx.t,
  bitmap: Canvas.imageBitmap,
  vp: Viewport.t,
  ~imageW: float,
  ~imageH: float,
): unit => {
  ctx->Canvas.Ctx.setImageSmoothingEnabled(true)
  ctx->Canvas.Ctx.drawImage(bitmap, vp.tx, vp.ty, imageW *. vp.scale, imageH *. vp.scale)
}

let colourFor = (style: style): string =>
  switch style {
  | Dimmed => forest
  | Selected => rust
  | Pending => rust
  }

let handle = (ctx: Canvas.Ctx.t, p: Viewport.pt, ~style: style): unit => {
  ctx->Canvas.Ctx.save
  ctx->Canvas.Ctx.setGlobalAlpha(style == Dimmed ? 0.45 : 1.0)
  ctx->Canvas.Ctx.beginPath
  ctx->Canvas.Ctx.arc(p.x, p.y, handleRadius, 0.0, 2.0 *. Math.Constants.pi)
  ctx->Canvas.Ctx.setFillStyle(cream)
  ctx->Canvas.Ctx.fill
  ctx->Canvas.Ctx.setLineWidth(2.5)
  ctx->Canvas.Ctx.setStrokeStyle(colourFor(style))
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.beginPath
  ctx->Canvas.Ctx.arc(p.x, p.y, 2.0, 0.0, 2.0 *. Math.Constants.pi)
  ctx->Canvas.Ctx.setFillStyle(colourFor(style))
  ctx->Canvas.Ctx.fill
  ctx->Canvas.Ctx.restore
}

// A short segment perpendicular to a–b, centred on `p` (one at each end of
// a dimension line, in the drafting sense of an extension tick).
let tick = (ctx: Canvas.Ctx.t, p: Viewport.pt, ~nx: float, ~ny: float): unit => {
  ctx->Canvas.Ctx.beginPath
  ctx->Canvas.Ctx.moveTo(p.x -. nx *. tickHalf, p.y -. ny *. tickHalf)
  ctx->Canvas.Ctx.lineTo(p.x +. nx *. tickHalf, p.y +. ny *. tickHalf)
  ctx->Canvas.Ctx.stroke
}

// A solid pill with the label text, offset perpendicular to the line so it
// doesn't sit on top of the ticks.
let label = (ctx: Canvas.Ctx.t, text: string, ~at: Viewport.pt, ~style: style): unit => {
  ctx->Canvas.Ctx.setFont(labelFont)
  ctx->Canvas.Ctx.setTextAlign("center")
  ctx->Canvas.Ctx.setTextBaseline("middle")
  let w = ctx->Canvas.Ctx.measureText(text)->Canvas.Ctx.textWidth +. 12.0
  let h = 20.0
  ctx->Canvas.Ctx.setFillStyle(style == Dimmed ? cream : colourFor(style))
  ctx->Canvas.Ctx.fillRect(at.x -. w /. 2.0, at.y -. h /. 2.0, w, h)
  ctx->Canvas.Ctx.setFillStyle(style == Dimmed ? ink : cream)
  ctx->Canvas.Ctx.fillText(text, at.x, at.y)
}

// The full dimension glyph: line, extension ticks at both ends, endpoint
// handles, and (when given) the name label. `a`/`b` are screen points.
let dimension = (
  ctx: Canvas.Ctx.t,
  ~a: Viewport.pt,
  ~b: Viewport.pt,
  ~text: option<string>,
  ~style: style,
): unit => {
  ctx->Canvas.Ctx.save
  ctx->Canvas.Ctx.setGlobalAlpha(style == Dimmed ? 0.45 : 1.0)
  ctx->Canvas.Ctx.setStrokeStyle(colourFor(style))
  ctx->Canvas.Ctx.setLineWidth(style == Selected ? 3.0 : 2.0)
  ctx->Canvas.Ctx.setLineCap("round")

  ctx->Canvas.Ctx.beginPath
  ctx->Canvas.Ctx.moveTo(a.x, a.y)
  ctx->Canvas.Ctx.lineTo(b.x, b.y)
  ctx->Canvas.Ctx.stroke

  let len = Viewport.distance(a, b)
  if len > 0.0 {
    // Unit normal to the line.
    let nx = -.(b.y -. a.y) /. len
    let ny = (b.x -. a.x) /. len
    tick(ctx, a, ~nx, ~ny)
    tick(ctx, b, ~nx, ~ny)
    switch text {
    | Some(t) =>
      let mid = Viewport.midpoint(a, b)
      label(ctx, t, ~at={x: mid.x +. nx *. 16.0, y: mid.y +. ny *. 16.0}, ~style)
    | None => ()
    }
  }
  ctx->Canvas.Ctx.restore

  handle(ctx, a, ~style)
  handle(ctx, b, ~style)
}
