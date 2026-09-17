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
