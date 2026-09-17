// EdgeSnap — pure edge-snapping math for the annotate canvas (SPEC §8a A5).
//
// The tap is still a sketch mark, never a measurement (SPEC §1: "the photo
// is never measured"); this module only nudges a drawn point onto the
// nearest visible edge so the arrow *looks* right. No DOM, no React, no
// bindings — plain data in, plain data out. `ImageData.res` produces the
// `patch` this module consumes; the (later) wiring agent owns the toggle,
// the ring feedback and wiring taps to `snapPoint`/`snapPair`.
//
// Coordinate space: everything here is in *patch pixels* (the downscaled
// grayscale copy SPEC §8a A5 bullet 2 describes, long edge ≤ 1024). Patch
// pixels are not normalized `Types.point`s — `toPatch`/`toNormalized`
// convert at the boundary so callers don't reinvent that math (mirrors
// `Viewport.res`'s `toImage`/`toNormalized` split for the same reason).

type patch = {width: int, height: int, luma: Uint8Array.t} // 8-bit grayscale, row-major, length = width*height
type px = {x: float, y: float} // patch pixel coordinates (float; sub-pixel allowed)
type result = {point: px, strength: float} // strength = gradient magnitude at the snapped pixel

// `relative` × `medianGradient` OR `absolute`, whichever is larger, is the
// floor a candidate edge must clear (SPEC bullet 1: "≥ 3× the patch's
// median gradient magnitude, and an absolute floor"). Both are needed: a
// flat, low-contrast photo has a tiny median, so the relative term alone
// would snap to noise; a hard-edged photo has a big median, so the
// absolute term alone would snap to secondary edges.
type threshold = {relative: float, absolute: float}

let defaultThreshold: threshold = {relative: 3.0, absolute: 24.0}

// -- patch pixel access -------------------------------------------------

let clampInt = (v: int, ~lo: int, ~hi: int): int => Math.Int.max(lo, Math.Int.min(v, hi))

// Edge-clamped sample: a coordinate outside the patch reads the nearest
// border pixel instead of wrapping or throwing, which is what lets the
// Sobel kernel run right up to `(0, 0)` / `(width-1, height-1)` without a
// special-cased border loop ("Sobel … edges clamped" — SPEC bullet 1's
// public signature comment).
let lumaAt = (patch: patch, x: int, y: int): float => {
  let xc = clampInt(x, ~lo=0, ~hi=patch.width - 1)
  let yc = clampInt(y, ~lo=0, ~hi=patch.height - 1)
  switch patch.luma->TypedArray.get(yc * patch.width + xc) {
  | Some(v) => Int.toFloat(v)
  | None => 0.0
  }
}

// The Sobel gradient vector at `(x, y)`, edge-clamped. Private: exposed
// publicly only as `gradientMagnitude` (its length), but `snapPair` below
// also needs the vector itself to score edges by *direction*.
let sobelVector = (patch: patch, x: int, y: int): (float, float) => {
  let l = (dx, dy) => lumaAt(patch, x + dx, y + dy)
  let gx = l(1, -1) +. 2.0 *. l(1, 0) +. l(1, 1) -. (l(-1, -1) +. 2.0 *. l(-1, 0) +. l(-1, 1))
  let gy = l(-1, 1) +. 2.0 *. l(0, 1) +. l(1, 1) -. (l(-1, -1) +. 2.0 *. l(0, -1) +. l(1, -1))
  (gx, gy)
}

let gradientMagnitude = (patch: patch, x: int, y: int): float => {
  let (gx, gy) = sobelVector(patch, x, y)
  Math.hypot(gx, gy)
}

// Cheap noise floor: every 4th pixel on both axes (SPEC bullet 1: "stride-
// sampled subset (every 4th px both axes)"), median of their gradient
// magnitudes. `(0, 0)` is always sampled, so even a 1×1 patch yields a
// defined (zero) median instead of an empty-array crash.
let medianGradient = (patch: patch): float => {
  let samples = []
  let y = ref(0)
  while y.contents < patch.height {
    let x = ref(0)
    while x.contents < patch.width {
      samples->Array.push(gradientMagnitude(patch, x.contents, y.contents))
      x := x.contents + 4
    }
    y := y.contents + 4
  }
  switch samples->Array.length {
  | 0 => 0.0
  | n =>
    let sorted = samples->Array.toSorted(Float.compare)
    let at = i => sorted->Array.get(i)->Option.getOr(0.0)
    if Int.mod(n, 2) == 1 {
      at(n / 2)
    } else {
      (at(n / 2 - 1) +. at(n / 2)) /. 2.0
    }
  }
}

let cutoff = (patch: patch, threshold: threshold): float =>
  Math.max(threshold.relative *. medianGradient(patch), threshold.absolute)

// -- snapPoint ------------------------------------------------------------

// Every integer pixel within `radius` of `at` is a candidate; the winner is
// the strongest Sobel magnitude, ties broken by nearest to `at` (SPEC
// bullet 1: "candidate = highest Sobel magnitude; tie-break by nearest to
// `at`"). `None` when nothing clears `cutoff` — the caller leaves the tap
// where it was.
let snapPoint = (patch: patch, ~at: px, ~radius: float, ~threshold: threshold): option<result> => {
  let floor = cutoff(patch, threshold)
  let minX = clampInt(Float.toInt(Math.floor(at.x -. radius)), ~lo=0, ~hi=patch.width - 1)
  let maxX = clampInt(Float.toInt(Math.ceil(at.x +. radius)), ~lo=0, ~hi=patch.width - 1)
  let minY = clampInt(Float.toInt(Math.floor(at.y -. radius)), ~lo=0, ~hi=patch.height - 1)
  let maxY = clampInt(Float.toInt(Math.ceil(at.y +. radius)), ~lo=0, ~hi=patch.height - 1)

  let best = ref(None) // (x, y, magnitude, distanceToAt)
  for y in minY to maxY {
    for x in minX to maxX {
      let dx = Int.toFloat(x) -. at.x
      let dy = Int.toFloat(y) -. at.y
      let dist = Math.sqrt(dx *. dx +. dy *. dy)
      if dist <= radius {
        let mag = gradientMagnitude(patch, x, y)
        if mag >= floor {
          let isBetter = switch best.contents {
          | None => true
          | Some((_, _, bestMag, bestDist)) => mag > bestMag || (mag == bestMag && dist < bestDist)
          }
          if isBetter {
            best := Some((x, y, mag, dist))
          }
        }
      }
    }
  }
  best.contents->Option.map(((x, y, mag, _)) => {
    point: {x: Int.toFloat(x), y: Int.toFloat(y)},
    strength: mag,
  })
}

// -- snapPair ---------------------------------------------------------------

// One end of a rough dimension tap. Walks the segment line through `endPt`
// (SPEC bullet 2: "from `end − radius·d` to `end + radius·d` in 0.5 px
// steps", `±1 px across the line to be robust to thin lines"), scoring
// each sampled pixel by the *directional* component of its gradient (the
// dot product with `d`, so an edge perpendicular to the segment scores
// high and one parallel to it scores ~0 — SPEC: "edges perpendicular to
// the segment win and edges parallel to it are ignored"). `strength` on
// the result is still the plain gradient magnitude at the winning pixel,
// matching every other `result` — the directional dot product is only the
// *selection* score, not what's reported back.
let snapEnd = (patch: patch, ~endPt: px, ~d: px, ~radius: float, ~floor: float): option<result> => {
  let n: px = {x: -.d.y, y: d.x} // unit normal to the segment
  let best = ref(None) // (px, score, magnitude, distanceToEnd)
  let t = ref(-.radius)
  while t.contents <= radius +. 0.001 {
    let base: px = {x: endPt.x +. t.contents *. d.x, y: endPt.y +. t.contents *. d.y}
    for k in -1 to 1 {
      let kf = Int.toFloat(k)
      let sample: px = {x: base.x +. kf *. n.x, y: base.y +. kf *. n.y}
      let px_ = clampInt(Float.toInt(Math.round(sample.x)), ~lo=0, ~hi=patch.width - 1)
      let py_ = clampInt(Float.toInt(Math.round(sample.y)), ~lo=0, ~hi=patch.height - 1)
      let (gx, gy) = sobelVector(patch, px_, py_)
      let score = Math.abs(gx *. d.x +. gy *. d.y)
      if score >= floor {
        let dx = Int.toFloat(px_) -. endPt.x
        let dy = Int.toFloat(py_) -. endPt.y
        let dist = Math.sqrt(dx *. dx +. dy *. dy)
        let isBetter = switch best.contents {
        | None => true
        | Some((_, bestScore, _, bestDist)) =>
          score > bestScore || (score == bestScore && dist < bestDist)
        }
        if isBetter {
          best := Some(({x: Int.toFloat(px_), y: Int.toFloat(py_)}, score, Math.hypot(gx, gy), dist))
        }
      }
    }
    t := t.contents +. 0.5
  }
  best.contents->Option.map(((point, _, mag, _)) => {point, strength: mag})
}

// Snaps `p1` and `p2` independently along their shared segment direction
// (SPEC bullet 1: "searches along the p1→p2 segment"). Degenerate case —
// `p1 == p2`, no direction — snaps neither end rather than dividing by
// zero; the caller's two rough taps always differ in practice.
let snapPair = (
  patch: patch,
  ~p1: px,
  ~p2: px,
  ~radius: float,
  ~threshold: threshold,
): (option<result>, option<result>) => {
  let dx = p2.x -. p1.x
  let dy = p2.y -. p1.y
  let len = Math.sqrt(dx *. dx +. dy *. dy)
  if len == 0.0 {
    (None, None)
  } else {
    let d: px = {x: dx /. len, y: dy /. len}
    let floor = cutoff(patch, threshold)
    (snapEnd(patch, ~endPt=p1, ~d, ~radius, ~floor), snapEnd(patch, ~endPt=p2, ~d, ~radius, ~floor))
  }
}

// -- coordinate helpers (SPEC bullet 1: "so the wiring agent doesn't
// reinvent them" — mirrors Viewport.res's normalized ⇄ image-pixel pair) --

let toPatch = (n: Types.point, ~width: int, ~height: int): px => {
  x: n.x *. Int.toFloat(width),
  y: n.y *. Int.toFloat(height),
}

let clamp01 = (v: float): float => Math.min(Math.max(v, 0.0), 1.0)

let toNormalized = (p: px, ~width: int, ~height: int): Types.point => {
  x: clamp01(p.x /. Int.toFloat(width)),
  y: clamp01(p.y /. Int.toFloat(height)),
}
