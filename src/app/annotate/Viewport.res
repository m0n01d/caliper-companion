// Viewport — the tap → normalized-coordinate math for the annotate canvas
// (SPEC M4 bullet 1: "taps convert to normalized image coordinates
// regardless of zoom"). Pure: no DOM, no React, unit-tested in
// tests/ViewportTest.res.
//
// Three coordinate spaces:
//   normalized  `Types.point`  0..1 of the *oriented* image — what's stored
//   image       `pt`           oriented-image pixels
//   screen      `pt`           canvas CSS pixels, origin at the canvas's
//                              top-left (devicePixelRatio is the canvas's
//                              own business, never this module's)
//
// `t` maps image pixels → screen pixels: `screen = img *. scale +. (tx, ty)`.
// Everything else is derived from that one equation, which is why every
// gesture (zoom about a point, pinch, pan) is expressed as a change to `t`
// and never touches a stored point.

type pt = {x: float, y: float}

type t = {scale: float, tx: float, ty: float}

let pt = (x: float, y: float): pt => {x, y}

let identity: t = {scale: 1.0, tx: 0.0, ty: 0.0}

// Contain + centre: the largest scale at which the whole image fits, with
// the slack on the longer view axis split evenly. Degenerate sizes (nothing
// measured yet) fall back to identity rather than producing NaN/Infinity.
let fit = (~imageW: float, ~imageH: float, ~viewW: float, ~viewH: float): t =>
  if imageW <= 0.0 || imageH <= 0.0 || viewW <= 0.0 || viewH <= 0.0 {
    identity
  } else {
    let scale = Math.min(viewW /. imageW, viewH /. imageH)
    {scale, tx: (viewW -. imageW *. scale) /. 2.0, ty: (viewH -. imageH *. scale) /. 2.0}
  }

let toScreen = (t: t, p: pt): pt => {x: p.x *. t.scale +. t.tx, y: p.y *. t.scale +. t.ty}

let toImage = (t: t, s: pt): pt => {x: (s.x -. t.tx) /. t.scale, y: (s.y -. t.ty) /. t.scale}

let toNormalized = (t: t, ~imageW: float, ~imageH: float, s: pt): Types.point => {
  let i = toImage(t, s)
  {x: i.x /. imageW, y: i.y /. imageH}
}

let fromNormalized = (t: t, ~imageW: float, ~imageH: float, n: Types.point): pt =>
  toScreen(t, {x: n.x *. imageW, y: n.y *. imageH})

// Scale by `factor` while the image point under `screenAnchor` stays under it.
let zoomAbout = (t: t, ~factor: float, ~screenAnchor: pt): t => {
  scale: t.scale *. factor,
  tx: screenAnchor.x -. (screenAnchor.x -. t.tx) *. factor,
  ty: screenAnchor.y -. (screenAnchor.y -. t.ty) *. factor,
}

let pan = (t: t, ~dx: float, ~dy: float): t => {...t, tx: t.tx +. dx, ty: t.ty +. dy}

let distance = (a: pt, b: pt): float => Math.hypot(b.x -. a.x, b.y -. a.y)

let midpoint = (a: pt, b: pt): pt => {x: (a.x +. b.x) /. 2.0, y: (a.y +. b.y) /. 2.0}

// Two-finger step: scale by the ratio of finger distances about the previous
// midpoint, then translate by the midpoint's movement. Fingers that keep
// their distance produce a pure pan (factor 1).
let pinch = (t: t, ~prev: (pt, pt), ~next: (pt, pt)): t => {
  let (p1, p2) = prev
  let (n1, n2) = next
  let dPrev = distance(p1, p2)
  let factor = dPrev > 0.0 ? distance(n1, n2) /. dPrev : 1.0
  let mPrev = midpoint(p1, p2)
  let mNext = midpoint(n1, n2)
  zoomAbout(t, ~factor, ~screenAnchor=mPrev)->pan(~dx=mNext.x -. mPrev.x, ~dy=mNext.y -. mPrev.y)
}

// One axis of the translation clamp. An image smaller than the view on this
// axis is centred; a larger one may be panned until its edge reaches the
// view's centre line, so any pixel can be brought to the middle of the
// screen (edges of a part are exactly where taps land) but the image never
// leaves the screen.
let clampOffset = (~offset: float, ~extent: float, ~view: float): float =>
  if extent <= view {
    (view -. extent) /. 2.0
  } else {
    Math.min(Math.max(offset, view /. 2.0 -. extent), view /. 2.0)
  }

// Keep the scale within [minScale, maxScale] — re-zooming about the view
// centre so a clamped pinch doesn't jump — then keep the image on screen.
let clamp = (
  t: t,
  ~minScale: float,
  ~maxScale: float,
  ~imageW: float,
  ~imageH: float,
  ~viewW: float,
  ~viewH: float,
): t => {
  let target = Math.min(Math.max(t.scale, minScale), maxScale)
  let scaled = if target == t.scale || t.scale <= 0.0 {
    t
  } else {
    zoomAbout(t, ~factor=target /. t.scale, ~screenAnchor={x: viewW /. 2.0, y: viewH /. 2.0})
  }
  {
    scale: scaled.scale,
    tx: clampOffset(~offset=scaled.tx, ~extent=imageW *. scaled.scale, ~view=viewW),
    ty: clampOffset(~offset=scaled.ty, ~extent=imageH *. scaled.scale, ~view=viewH),
  }
}

// Distance in screen pixels from `s` to the segment a–b (both screen points).
// Used by the hit test for "tap within ~16 px of a dimension's line".
let distanceToSegment = (s: pt, ~a: pt, ~b: pt): float => {
  let vx = b.x -. a.x
  let vy = b.y -. a.y
  let len2 = vx *. vx +. vy *. vy
  if len2 == 0.0 {
    distance(s, a)
  } else {
    let u = ((s.x -. a.x) *. vx +. (s.y -. a.y) *. vy) /. len2
    let u = Math.min(Math.max(u, 0.0), 1.0)
    distance(s, {x: a.x +. u *. vx, y: a.y +. u *. vy})
  }
}

// Stored points never leave the oriented image (SPEC §6: 0..1).
let clamp01 = (v: float): float => Math.min(Math.max(v, 0.0), 1.0)

// What a drag of (dx, dy) screen pixels means for a stored point under `t`:
// the same movement in normalized units (SPEC §8a A1 — "moved by the
// matching normalized delta").
let deltaToNormalized = (t: t, ~imageW: float, ~imageH: float, ~dx: float, ~dy: float): Types.point => {
  x: dx /. (imageW *. t.scale),
  y: dy /. (imageH *. t.scale),
}

// A handle drag: move one endpoint by a normalized delta, kept inside the
// image.
let translatePoint = (n: Types.point, d: Types.point): Types.point => {
  x: clamp01(n.x +. d.x),
  y: clamp01(n.y +. d.y),
}

// A body drag: move both endpoints by the same delta. The delta is
// shortened, per axis, so that neither endpoint leaves the image — the line
// keeps its length and angle instead of folding at the edge.
let translatePair = (a: Types.point, b: Types.point, d: Types.point): (Types.point, Types.point) => {
  let clampDelta = (d: float, p: float, q: float): float =>
    Math.min(Math.max(d, -.Math.min(p, q)), 1.0 -. Math.max(p, q))
  let dx = clampDelta(d.x, a.x, b.x)
  let dy = clampDelta(d.y, a.y, b.y)
  ({x: a.x +. dx, y: a.y +. dy}, {x: b.x +. dx, y: b.y +. dy})
}

// ── SPEC §8a A6: fit the view to a segment ──────────────────────────────

// The transform that shows the segment p1–p2 (normalized) as large as the
// view allows. Its bounding box in image px — never thinner than `minBox`
// of the image on either axis, so two nearly coincident taps still zoom to
// something sensible — is grown by `padding` of its own size on each side
// and fitted to the view; the scale is clamped to [fitScale, maxScale] (a
// dimension across the whole part just re-centres at the fit scale); the
// result is centred on the segment's midpoint and clamped with the same
// pan rules as every gesture. Degenerate sizes fall back to `fit`.
let fitToSegment = (
  ~p1: Types.point,
  ~p2: Types.point,
  ~imageW: float,
  ~imageH: float,
  ~viewW: float,
  ~viewH: float,
  ~padding: float=0.15,
  ~minBox: float=0.1,
  ~fitScale: float,
  ~maxScale: float,
): t =>
  if imageW <= 0.0 || imageH <= 0.0 || viewW <= 0.0 || viewH <= 0.0 || fitScale <= 0.0 {
    fit(~imageW, ~imageH, ~viewW, ~viewH)
  } else {
    let ax = p1.x *. imageW
    let ay = p1.y *. imageH
    let bx = p2.x *. imageW
    let by = p2.y *. imageH
    let boxW = Math.max(Math.abs(bx -. ax), minBox *. imageW) *. (1.0 +. 2.0 *. padding)
    let boxH = Math.max(Math.abs(by -. ay), minBox *. imageH) *. (1.0 +. 2.0 *. padding)
    let scale = Math.min(viewW /. boxW, viewH /. boxH)
    let scale = Math.min(Math.max(scale, fitScale), maxScale)
    let mx = (ax +. bx) /. 2.0
    let my = (ay +. by) /. 2.0
    clamp(
      {scale, tx: viewW /. 2.0 -. mx *. scale, ty: viewH /. 2.0 -. my *. scale},
      ~minScale=fitScale,
      ~maxScale,
      ~imageW,
      ~imageH,
      ~viewW,
      ~viewH,
    )
  }

// One frame of a viewport animation: `k` = 0 is `a`, 1 is `b`. Scale and
// offsets interpolate linearly; over 160 ms the difference from a true
// zoom-about-a-point is invisible, and the endpoints are exact.
let lerp = (a: t, b: t, k: float): t => {
  scale: a.scale +. (b.scale -. a.scale) *. k,
  tx: a.tx +. (b.tx -. a.tx) *. k,
  ty: a.ty +. (b.ty -. a.ty) *. k,
}

// y of the CSS `cubic-bezier(x1, y1, x2, y2)` timing curve at time
// fraction `x`: the x-polynomial is inverted by bisection (it is monotonic
// for CSS-legal control points), then y is read off at that parameter.
let cubicBezier = (~x1: float, ~y1: float, ~x2: float, ~y2: float, x: float): float => {
  let at = (c1: float, c2: float, t: float): float => {
    let u = 1.0 -. t
    3.0 *. u *. u *. t *. c1 +. 3.0 *. u *. t *. t *. c2 +. t *. t *. t
  }
  if x <= 0.0 {
    0.0
  } else if x >= 1.0 {
    1.0
  } else {
    let lo = ref(0.0)
    let hi = ref(1.0)
    for _ in 1 to 24 {
      let mid = (lo.contents +. hi.contents) /. 2.0
      if at(x1, x2, mid) < x {
        lo := mid
      } else {
        hi := mid
      }
    }
    at(y1, y2, (lo.contents +. hi.contents) /. 2.0)
  }
}

// `--cc-ease` from theme.css (DESIGN.md §11.1 "Interaction feel"), so the
// viewport tween and the CSS transitions share one feel.
let ease = (progress: float): float => cubicBezier(~x1=0.2, ~y1=0.8, ~x2=0.2, ~y2=1.0, progress)
