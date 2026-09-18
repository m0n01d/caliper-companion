// Draw — 2D-context drawing for the annotate canvas (SPEC M4 bullets 2 and
// 8; SPEC §8a A3 halo strokes; DESIGN.md §5 overlay rules): the oriented
// image, dimension lines with arrowheads, dashed extension lines and a
// value pill, and the endpoint handles. Every function takes a context plus
// plain values and returns unit; no state and no DOM lookups live here.
// Coordinates are canvas CSS pixels — `Annotate.res` applies the
// devicePixelRatio transform to the context before calling in, so widths
// and radii are the same physical size at any DPR.
//
// Legibility on any photo (SPEC §8a A3): every stroke is drawn twice — a
// near-black halo at 2.5× the width underneath, then the colour on top —
// so ink reads on a bright part and on a dark one alike. The exported PNG
// (export/) uses the same rule at image resolution; this is the live copy.
//
// Colours are the `Overlay` module (SPEC §8a A14b; DESIGN.md §2/§5 tokens by
// value) — a canvas can't read CSS custom properties, and getComputedStyle
// on every redraw isn't worth it for a handful of constants.

type style =
  | Dimmed // a saved dimension on this face, not selected
  | Selected // the saved dimension being edited
  | Pending // the dimension being placed

let lineWidth = 2.0
let extensionWidth = 1.5
let extensionDash = [4.0, 3.0]
let haloFactor = 2.5
let handleRadius = 11.0 // a 22 px handle; the 22 px hit *radius* (44 px target) is Annotate's
let handleRing = 3.0
let handleDotRadius = 3.0 // 6 px dot
let tickHalf = 8.0 // extension line: through the endpoint, 6 px past the line plus the cap
let arrow = 10.0 // 10×10 arrowheads
let pillHeight = 28.0
let pillPadX = 12.0
let pillClearance = 8.0
let savedPillHeight = 20.0
let activeFont = "500 15px \"IBM Plex Mono\", ui-monospace, Menlo, monospace" // cc-font-mono
let savedFont = "500 12px \"IBM Plex Mono\", ui-monospace, Menlo, monospace"

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

// Mono overlays (SPEC §8a A14b overlay table): the line, extensions and
// arrowheads paint `Overlay.ink` regardless of style — Pending, Selected
// and Dimmed differ only in the pill (`pill`) and in the group alpha
// (`alphaFor`) below. `Overlay.live` survives only as the snap ring's
// colour (`snapRing`).
let colourFor = (style: style): string =>
  switch style {
  | Dimmed | Selected | Pending => Overlay.ink
  }

// Saved, unselected dimensions sit back at Overlay.savedAlpha (halo included).
let alphaFor = (style: style): float => style == Dimmed ? Overlay.savedAlpha : 1.0

// Stroke `path` twice: the halo underneath at haloFactor × width, then the
// colour. `path` re-issues the geometry (beginPath is done here).
let stroked = (
  ctx: Canvas.Ctx.t,
  ~width: float,
  ~colour: string,
  ~dash: array<float>,
  path: unit => unit,
): unit => {
  ctx->Canvas.Ctx.setLineDash(dash)
  ctx->Canvas.Ctx.setLineWidth(width *. haloFactor)
  ctx->Canvas.Ctx.setStrokeStyle(Overlay.halo)
  ctx->Canvas.Ctx.beginPath
  path()
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.setLineWidth(width)
  ctx->Canvas.Ctx.setStrokeStyle(colour)
  ctx->Canvas.Ctx.beginPath
  path()
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.setLineDash([])
}

// Fill `path` with a halo around it: the outline stroked in the halo at
// the line's halo width, then the fill on top.
let filled = (ctx: Canvas.Ctx.t, ~colour: string, path: unit => unit): unit => {
  ctx->Canvas.Ctx.setLineDash([])
  ctx->Canvas.Ctx.setLineWidth(lineWidth *. haloFactor)
  ctx->Canvas.Ctx.setStrokeStyle(Overlay.halo)
  ctx->Canvas.Ctx.beginPath
  path()
  ctx->Canvas.Ctx.closePath
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.setFillStyle(colour)
  ctx->Canvas.Ctx.beginPath
  path()
  ctx->Canvas.Ctx.closePath
  ctx->Canvas.Ctx.fill
}

let circle = (ctx: Canvas.Ctx.t, p: Viewport.pt, r: float): unit =>
  ctx->Canvas.Ctx.arc(p.x, p.y, r, 0.0, 2.0 *. Math.Constants.pi)

// DESIGN.md §5 handle: 22 px disc in `Overlay.ink`, 3 px ring and 6 px
// centre dot in `Overlay.inkOn` (with the disc's own colour the ring and
// dot would vanish into it, SPEC §8a A14b overlay table) — mono, so this no
// longer varies by style; only Pending and Selected ever call `handle`
// (`dimension` below), both at alpha 1, so it draws at full alpha
// unconditionally. `~style` stays on the signature to match those call
// sites and the one in `Annotate.res`.
let handle = (ctx: Canvas.Ctx.t, p: Viewport.pt, ~style as _: style): unit => {
  ctx->Canvas.Ctx.save
  ctx->Canvas.Ctx.setGlobalAlpha(1.0)
  ctx->Canvas.Ctx.setLineDash([])
  ctx->Canvas.Ctx.setLineWidth(handleRing *. haloFactor)
  ctx->Canvas.Ctx.setStrokeStyle(Overlay.halo)
  ctx->Canvas.Ctx.beginPath
  circle(ctx, p, handleRadius)
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.setFillStyle(Overlay.ink)
  ctx->Canvas.Ctx.beginPath
  circle(ctx, p, handleRadius)
  ctx->Canvas.Ctx.fill
  ctx->Canvas.Ctx.setLineWidth(handleRing)
  ctx->Canvas.Ctx.setStrokeStyle(Overlay.inkOn)
  ctx->Canvas.Ctx.beginPath
  circle(ctx, p, handleRadius)
  ctx->Canvas.Ctx.stroke
  ctx->Canvas.Ctx.setFillStyle(Overlay.inkOn)
  ctx->Canvas.Ctx.beginPath
  circle(ctx, p, handleDotRadius)
  ctx->Canvas.Ctx.fill
  ctx->Canvas.Ctx.restore
}

// SPEC §8a A5 feedback: the ring a snapped point draws for 150 ms — a
// second circle growing from the handle's edge to `ringGrowth` × its radius
// while it fades out. `progress` is 0..1; Annotate.res drives it from the
// same frame machinery as the A6 viewport tween (and skips it under reduced
// motion). `Overlay.live` over the halo — the one place `live` still paints
// (SPEC §8a A14b overlay table).
let ringGrowth = 1.6

let snapRing = (ctx: Canvas.Ctx.t, p: Viewport.pt, ~progress: float): unit => {
  let k = Math.min(Math.max(progress, 0.0), 1.0)
  let r = handleRadius *. (1.0 +. (ringGrowth -. 1.0) *. k)
  ctx->Canvas.Ctx.save
  ctx->Canvas.Ctx.setGlobalAlpha(1.0 -. k)
  ctx->Canvas.Ctx.setLineCap("round")
  stroked(ctx, ~width=lineWidth, ~colour=Overlay.live, ~dash=[], () => circle(ctx, p, r))
  ctx->Canvas.Ctx.restore
}

// A dashed extension line through `p`, perpendicular to the dimension line
// (unit normal nx, ny).
let extension = (ctx: Canvas.Ctx.t, p: Viewport.pt, ~nx: float, ~ny: float): unit => {
  ctx->Canvas.Ctx.moveTo(p.x -. nx *. tickHalf, p.y -. ny *. tickHalf)
  ctx->Canvas.Ctx.lineTo(p.x +. nx *. tickHalf, p.y +. ny *. tickHalf)
}

// A 10×10 arrowhead with its tip at `tip`, pointing along −(ux, uy) — i.e.
// the triangle lies on the line, base 10 px in from the endpoint.
let arrowhead = (ctx: Canvas.Ctx.t, ~tip: Viewport.pt, ~ux: float, ~uy: float, ~nx: float, ~ny: float): unit => {
  let bx = tip.x +. ux *. arrow
  let by = tip.y +. uy *. arrow
  ctx->Canvas.Ctx.moveTo(tip.x, tip.y)
  ctx->Canvas.Ctx.lineTo(bx +. nx *. arrow /. 2.0, by +. ny *. arrow /. 2.0)
  ctx->Canvas.Ctx.lineTo(bx -. nx *. arrow /. 2.0, by -. ny *. arrow /. 2.0)
}

let roundedRect = (ctx: Canvas.Ctx.t, ~x: float, ~y: float, ~w: float, ~h: float, ~r: float): unit => {
  ctx->Canvas.Ctx.beginPath
  ctx->Canvas.Ctx.moveTo(x +. r, y)
  ctx->Canvas.Ctx.arcTo(x +. w, y, x +. w, y +. h, r)
  ctx->Canvas.Ctx.arcTo(x +. w, y +. h, x, y +. h, r)
  ctx->Canvas.Ctx.arcTo(x, y +. h, x, y, r)
  ctx->Canvas.Ctx.arcTo(x, y, x +. w, y, r)
  ctx->Canvas.Ctx.closePath
}

let pillFont = (style: style): string => style == Pending ? activeFont : savedFont

// The pill's box for `text`: measured width plus padding, and the style's
// height.
let pillSize = (ctx: Canvas.Ctx.t, text: string, ~style: style): (float, float) => {
  ctx->Canvas.Ctx.setFont(pillFont(style))
  (
    ctx->Canvas.Ctx.measureText(text)->Canvas.Ctx.textWidth +. 2.0 *. pillPadX,
    style == Pending ? pillHeight : savedPillHeight,
  )
}

// The value pill, centred on `at` (SPEC §8a A14b overlay table). Pending:
// `Overlay.ink` fill, 28 px, `Overlay.inkOn` label and 1 px border (17:1).
// Selected/Dimmed: `Overlay.scrim` fill, `Overlay.ink` label, mono 12 — a
// Dimmed pill is only ever passed to this function after `dimension`'s
// alpha group has been restored (see `dimension` below), so its label is
// never scaled by `Overlay.savedAlpha`.
let pill = (ctx: Canvas.Ctx.t, text: string, ~at: Viewport.pt, ~style: style): unit => {
  let (fill, ink) = switch style {
  | Pending => (Overlay.ink, Overlay.inkOn)
  | Selected | Dimmed => (Overlay.scrim, Overlay.ink)
  }
  let (w, h) = pillSize(ctx, text, ~style)
  ctx->Canvas.Ctx.setTextAlign("center")
  ctx->Canvas.Ctx.setTextBaseline("middle")
  roundedRect(ctx, ~x=at.x -. w /. 2.0, ~y=at.y -. h /. 2.0, ~w, ~h, ~r=h /. 2.0)
  ctx->Canvas.Ctx.setFillStyle(fill)
  ctx->Canvas.Ctx.fill
  if style == Pending {
    ctx->Canvas.Ctx.setLineDash([])
    ctx->Canvas.Ctx.setLineWidth(1.0)
    ctx->Canvas.Ctx.setStrokeStyle(Overlay.inkOn)
    ctx->Canvas.Ctx.stroke
  }
  ctx->Canvas.Ctx.setFillStyle(ink)
  ctx->Canvas.Ctx.fillText(text, at.x, at.y)
}

// The full dimension glyph: haloed line with arrowheads, dashed extension
// lines at both ends, the value pill on the line's upper (or right) side,
// and — unless dimmed — the endpoint handles. `a`/`b` are screen points.
let dimension = (
  ctx: Canvas.Ctx.t,
  ~a: Viewport.pt,
  ~b: Viewport.pt,
  ~text: option<string>,
  ~style: style,
): unit => {
  let colour = colourFor(style)
  ctx->Canvas.Ctx.save
  ctx->Canvas.Ctx.setGlobalAlpha(alphaFor(style))
  ctx->Canvas.Ctx.setLineCap("round")
  ctx->Canvas.Ctx.setLineJoin("round")

  stroked(ctx, ~width=lineWidth, ~colour, ~dash=[], () => {
    ctx->Canvas.Ctx.moveTo(a.x, a.y)
    ctx->Canvas.Ctx.lineTo(b.x, b.y)
  })

  // A Dimmed pill is queued here and drawn after `restore` below, at alpha
  // 1 (SPEC §8a A14b overlay table): inside the alpha group a 100 % label
  // on a 70 % `Overlay.scrim` pill is 3.9:1 on white. Pending and Selected
  // already run this alpha group at 1.0 (`alphaFor`), so drawing their
  // pill in place is equivalent — only Dimmed needs the deferral.
  let dimmedPill = ref(None)

  let len = Viewport.distance(a, b)
  if len > 0.0 {
    // Unit direction a→b and a unit normal, chosen to point up the screen
    // (or right, for a vertical line) so the pill sits above a horizontal
    // line and to the right of a vertical one.
    let ux = (b.x -. a.x) /. len
    let uy = (b.y -. a.y) /. len
    let (nx, ny) = ux > 0.0 || (ux == 0.0 && uy > 0.0) ? (uy, -.ux) : (-.uy, ux)
    stroked(ctx, ~width=extensionWidth, ~colour, ~dash=extensionDash, () => {
      extension(ctx, a, ~nx, ~ny)
      extension(ctx, b, ~nx, ~ny)
    })
    if len >= 3.0 *. arrow {
      filled(ctx, ~colour, () => arrowhead(ctx, ~tip=a, ~ux, ~uy, ~nx, ~ny))
      filled(ctx, ~colour, () => arrowhead(ctx, ~tip=b, ~ux=-.ux, ~uy=-.uy, ~nx, ~ny))
    }
    switch text {
    | Some(t) =>
      // 8 px clear of the line whatever its angle: offset by the pill's
      // half-extent along the normal (|nx|·w/2 + |ny|·h/2 for a box).
      let mid = Viewport.midpoint(a, b)
      let (w, h) = pillSize(ctx, t, ~style)
      let off =
        lineWidth /. 2.0 +. pillClearance +. Math.abs(nx) *. w /. 2.0 +. Math.abs(ny) *. h /. 2.0
      let at: Viewport.pt = {x: mid.x +. nx *. off, y: mid.y +. ny *. off}
      switch style {
      | Dimmed => dimmedPill := Some((t, at))
      | Selected | Pending => pill(ctx, t, ~at, ~style)
      }
    | None => ()
    }
  }
  ctx->Canvas.Ctx.restore

  switch dimmedPill.contents {
  | Some((t, at)) => pill(ctx, t, ~at, ~style)
  | None => ()
  }

  switch style {
  | Dimmed => ()
  | Selected | Pending =>
    handle(ctx, a, ~style)
    handle(ctx, b, ~style)
  }
}
