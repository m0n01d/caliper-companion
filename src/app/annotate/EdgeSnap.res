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
//
// -- A5 hardening (agent/a5-blur) -----------------------------------------
// Two classical upgrades on top of the raw-patch Sobel search below, plus
// two additive fixes from the wiring agent's real-photo testing. None of
// them change a public signature's name, arity or meaning:
//   1. Window-local Gaussian smoothing: `snapPoint`/`snapPair` search a
//      5×5-blurred copy of just their own search window (never the whole
//      patch, which the wiring agent passes as-is, up to 1024 px on the
//      long edge) — raw JPEG pixels amplify block artifacts and surface
//      texture, which Sobel then mistakes for edges. `gradientMagnitude` /
//      `medianGradient` keep their raw-patch semantics; the threshold is
//      still calibrated on them.
//   2. Non-max suppression: a candidate is kept only if it's a local
//      maximum — along its own gradient direction for `snapPoint`, along
//      the walk for `snapPair` — so a soft, several-pixel-wide edge snaps
//      to its centre instead of its first pixel above threshold.
//   3. Distance-weighted scoring (additive, both functions): a falloff on
//      distance from the tap/end so the strongest edge still wins over a
//      weaker nearer one (weak candidates are already excluded by
//      `cutoff`'s floor, so this is about disambiguating among real edge
//      pixels, not about protecting a "weak" one from a "strong" one), but
//      among near-equal candidates (e.g. noisy real photos, where
//      "near-equal" magnitude no longer means *exactly* equal) the nearest
//      one wins outright, rather than only on an exact tie. Coefficient is
//      1.0 (`magnitude × (1 − dist / radius)`), not the wiring agent's
//      illustrative 0.35 — see the coefficient's own comment below for why.
//   4. Optional `~median` (additive, both functions): lets a caller that
//      already has `medianGradient(patch)` pass it in instead of paying
//      for another patch-wide stride sample — the wiring agent searches
//      two radii per tap. Absent, behavior is unchanged.

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

// The Sobel gradient vector, parametrized over how a luma value is read at
// `(x, y)` — the shared kernel for both the raw-patch reader (`sobelVector`,
// below) and the smoothed-window reader (`sobelVectorSmoothed`, further
// down) so the two never drift apart.
let sobelVectorAt = (lumaFn: (int, int) => float, x: int, y: int): (float, float) => {
  let l = (dx, dy) => lumaFn(x + dx, y + dy)
  let gx = l(1, -1) +. 2.0 *. l(1, 0) +. l(1, 1) -. (l(-1, -1) +. 2.0 *. l(-1, 0) +. l(-1, 1))
  let gy = l(-1, 1) +. 2.0 *. l(0, 1) +. l(1, 1) -. (l(-1, -1) +. 2.0 *. l(0, -1) +. l(1, -1))
  (gx, gy)
}

// The Sobel gradient vector at `(x, y)` on the *raw* patch, edge-clamped.
// Private: exposed publicly only as `gradientMagnitude` (its length).
let sobelVector = (patch: patch, x: int, y: int): (float, float) =>
  sobelVectorAt((px_, py_) => lumaAt(patch, px_, py_), x, y)

let gradientMagnitude = (patch: patch, x: int, y: int): float => {
  let (gx, gy) = sobelVector(patch, x, y)
  Math.hypot(gx, gy)
}

// Cheap noise floor: every 4th pixel on both axes (SPEC bullet 1: "stride-
// sampled subset (every 4th px both axes)"), median of their gradient
// magnitudes. `(0, 0)` is always sampled, so even a 1×1 patch yields a
// defined (zero) median instead of an empty-array crash. Deliberately reads
// the *raw* patch, unaffected by the window-local smoothing below — it has
// to summarize the whole patch, which smoothing is explicitly not allowed
// to touch, and it's what `defaultThreshold` is calibrated against.
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

let cutoff = (threshold: threshold, ~median: float): float =>
  Math.max(threshold.relative *. median, threshold.absolute)

// Resolves the median gradient magnitude to feed `cutoff`: the caller's
// cached value when given (upgrade 4 — the wiring agent searches two radii
// per tap and would otherwise pay for `medianGradient`'s patch-wide stride
// sample twice), else computed fresh exactly as before. The `max(relative ×
// median, absolute)` formula itself lives only in `cutoff`, so there's one
// place that ever does that arithmetic regardless of where the median came
// from.
let resolveMedian = (patch: patch, median: option<float>): float =>
  switch median {
  | Some(m) => m
  | None => medianGradient(patch)
  }

// -- window-local Gaussian smoothing (upgrade 1) --------------------------
//
// A 5×5 Gaussian, σ ≈ 1.0 — the standard integer kernel `[1 4 6 4 1]`
// outer-product / 256 — applied as two separable 1-D passes (horizontal
// then vertical, each dividing by 16, so the composed weight is the 5×5
// kernel / 256). `smoothWindow` blurs only `[minX,maxX] × [minY,maxY]`
// (a call's search window) padded 3 px on every side (clamped to the
// patch) into a fresh scratch buffer — it never touches the whole patch,
// which can be up to 1024 px on the long edge. The 3-px pad is more than
// either consumer needs (Sobel's own ±1 px, plus non-max suppression's
// ±1 px neighbour sample = 2 px beyond the window), so every read either
// consumer does lands on real smoothed data instead of the buffer's own
// edge-clamp.
type smoothedWindow = {ox: int, oy: int, width: int, height: int, data: Float64Array.t}

// Edge-clamped read into the smoothed window — mirrors `lumaAt`'s
// edge-clamping, just scoped to the window's own rectangle instead of the
// whole patch (a read past the window's edge repeats its border, same
// policy as the raw patch).
let smoothedLumaAt = (w: smoothedWindow, x: int, y: int): float => {
  let xc = clampInt(x - w.ox, ~lo=0, ~hi=w.width - 1)
  let yc = clampInt(y - w.oy, ~lo=0, ~hi=w.height - 1)
  switch w.data->TypedArray.get(yc * w.width + xc) {
  | Some(v) => v
  | None => 0.0
  }
}

// One 1-D `[1 4 6 4 1]` tap; callers divide the result by 16.
let gaussTap = (a: float, b: float, c: float, d: float, e: float): float =>
  a +. 4.0 *. b +. 6.0 *. c +. 4.0 *. d +. e

let smoothWindow = (patch: patch, ~minX: int, ~maxX: int, ~minY: int, ~maxY: int): smoothedWindow => {
  let ox = clampInt(minX - 3, ~lo=0, ~hi=patch.width - 1)
  let oy = clampInt(minY - 3, ~lo=0, ~hi=patch.height - 1)
  let ex = clampInt(maxX + 3, ~lo=0, ~hi=patch.width - 1)
  let ey = clampInt(maxY + 3, ~lo=0, ~hi=patch.height - 1)
  let width = ex - ox + 1
  let height = ey - oy + 1

  // Horizontal pass first, reading the *raw* patch (edge-clamped via
  // `lumaAt`, so a window flush against the patch border is still
  // well-defined). Two extra rows top and bottom so the vertical pass
  // always has a full 5-tap neighbourhood to read.
  let hh = height + 4
  let horiz = Float64Array.fromLength(width * hh)
  for row in 0 to hh - 1 {
    let y = oy - 2 + row
    for col in 0 to width - 1 {
      let x = ox + col
      let v =
        gaussTap(
          lumaAt(patch, x - 2, y),
          lumaAt(patch, x - 1, y),
          lumaAt(patch, x, y),
          lumaAt(patch, x + 1, y),
          lumaAt(patch, x + 2, y),
        ) /. 16.0
      horiz->TypedArray.set(row * width + col, v)
    }
  }

  let data = Float64Array.fromLength(width * height)
  for row in 0 to height - 1 {
    for col in 0 to width - 1 {
      let tap = r => horiz->TypedArray.get((row + r) * width + col)->Option.getOr(0.0)
      let v = gaussTap(tap(0), tap(1), tap(2), tap(3), tap(4)) /. 16.0
      data->TypedArray.set(row * width + col, v)
    }
  }
  {ox, oy, width, height, data}
}

let sobelVectorSmoothed = (w: smoothedWindow, x: int, y: int): (float, float) =>
  sobelVectorAt((px_, py_) => smoothedLumaAt(w, px_, py_), x, y)

let magnitudeSmoothed = (w: smoothedWindow, x: int, y: int): float => {
  let (gx, gy) = sobelVectorSmoothed(w, x, y)
  Math.hypot(gx, gy)
}

// Bilinearly samples the smoothed gradient magnitude at a fractional
// position — non-max suppression's ±1 px neighbours along a gradient or
// walk direction rarely land on integer pixels.
let sampleMagnitude = (w: smoothedWindow, fx: float, fy: float): float => {
  let x0 = Float.toInt(Math.floor(fx))
  let y0 = Float.toInt(Math.floor(fy))
  let tx = fx -. Int.toFloat(x0)
  let ty = fy -. Int.toFloat(y0)
  let m00 = magnitudeSmoothed(w, x0, y0)
  let m10 = magnitudeSmoothed(w, x0 + 1, y0)
  let m01 = magnitudeSmoothed(w, x0, y0 + 1)
  let m11 = magnitudeSmoothed(w, x0 + 1, y0 + 1)
  let top = m00 *. (1.0 -. tx) +. m10 *. tx
  let bottom = m01 *. (1.0 -. tx) +. m11 *. tx
  top *. (1.0 -. ty) +. bottom *. ty
}

// -- non-max suppression, `snapPoint` half (upgrade 2) --------------------
//
// A candidate at `(x, y)` with gradient vector `(gx, gy)` / magnitude
// `mag` is kept only if it's a local maximum along its own gradient
// direction — compared against the two neighbours ±1 px along the unit
// vector `(gx, gy) / mag`. `>=` on both sides, not `>`: a flat-topped
// plateau (a soft, multi-pixel-wide ramp — see the "soft ramp" test) would
// otherwise have *no* pixel strictly above its neighbours and the whole
// ramp would wrongly report `None`. Allowing ties keeps every plateau
// pixel eligible; `snapPoint`'s own nearest-to-tap / distance-weighted
// tie-break (below) then picks the plateau's centre-most pixel instead of
// its first.
let isDirectionalMax = (w: smoothedWindow, x: int, y: int, gx: float, gy: float, mag: float): bool =>
  if mag <= 0.0 {
    false
  } else {
    let ux = gx /. mag
    let uy = gy /. mag
    let before = sampleMagnitude(w, Int.toFloat(x) -. ux, Int.toFloat(y) -. uy)
    let after = sampleMagnitude(w, Int.toFloat(x) +. ux, Int.toFloat(y) +. uy)
    mag >= before && mag >= after
  }

// -- snapPoint ------------------------------------------------------------

// Every integer pixel within `radius` of `at` is a candidate; the winner is
// the strongest Sobel magnitude (read off a window-local Gaussian-smoothed
// copy of the patch, upgrade 1), filtered to local maxima along the
// gradient direction (upgrade 2), and among those the highest
// distance-weighted score (upgrade 3: `magnitude × (1 − dist / radius)` —
// see the coefficient note just below `weight`). `~median`, when given,
// skips the patch-wide median-gradient pass (upgrade 4). `None` when
// nothing clears `cutoff` — the caller leaves the tap where it was.
let snapPoint = (
  patch: patch,
  ~at: px,
  ~radius: float,
  ~threshold: threshold,
  ~median: option<float>=?,
): option<result> => {
  let floor = cutoff(threshold, ~median=resolveMedian(patch, median))
  let minX = clampInt(Float.toInt(Math.floor(at.x -. radius)), ~lo=0, ~hi=patch.width - 1)
  let maxX = clampInt(Float.toInt(Math.ceil(at.x +. radius)), ~lo=0, ~hi=patch.width - 1)
  let minY = clampInt(Float.toInt(Math.floor(at.y -. radius)), ~lo=0, ~hi=patch.height - 1)
  let maxY = clampInt(Float.toInt(Math.ceil(at.y +. radius)), ~lo=0, ~hi=patch.height - 1)
  let win = smoothWindow(patch, ~minX, ~maxX, ~minY, ~maxY)

  let best = ref(None) // (x, y, magnitude, distanceToAt, weightedScore)
  for y in minY to maxY {
    for x in minX to maxX {
      let dx = Int.toFloat(x) -. at.x
      let dy = Int.toFloat(y) -. at.y
      let dist = Math.sqrt(dx *. dx +. dy *. dy)
      if dist <= radius {
        let (gx, gy) = sobelVectorSmoothed(win, x, y)
        let mag = Math.hypot(gx, gy)
        if mag >= floor && isDirectionalMax(win, x, y, gx, gy, mag) {
          // Coefficient 1.0, not the wiring agent's illustrative 0.35: at
          // 0.35 the weight only varies ±17.5% across the whole disk, which
          // ±20 noise (post-smoothing) comfortably overwhelms for two
          // candidates a couple of pixels apart — exactly the "slides along
          // the edge" bug this upgrade exists to fix. 1.0 (weight reaches
          // 0 at the disk's edge) still leaves `cutoff`'s floor as the
          // only thing deciding whether a *weak* candidate is in the
          // running at all, so "the strongest edge still wins over a weak
          // nearer one" is unaffected — this only sharpens the tie-break
          // among real edge pixels. See the "distance weighting" test.
          let weight = radius > 0.0 ? 1.0 -. dist /. radius : 1.0
          let weighted = mag *. weight
          let isBetter = switch best.contents {
          | None => true
          | Some((_, _, _, bestDist, bestWeighted)) =>
            weighted > bestWeighted || (weighted == bestWeighted && dist < bestDist)
          }
          if isBetter {
            best := Some((x, y, mag, dist, weighted))
          }
        }
      }
    }
  }
  best.contents->Option.map(((x, y, mag, _, _)) => {
    point: {x: Int.toFloat(x), y: Int.toFloat(y)},
    strength: mag,
  })
}

// -- snapPair ---------------------------------------------------------------

type walkSample = {point: px, score: float, mag: float, dist: float}

// One end of a rough dimension tap. Walks the segment line through `endPt`
// (SPEC bullet 2: "from `end − radius·d` to `end + radius·d` in 0.5 px
// steps", "±1 px across the line to be robust to thin lines"), scoring
// each sampled pixel — read off a window-local Gaussian-smoothed copy of
// the patch (upgrade 1) — by the *directional* component of its gradient
// (the dot product with `d`, so an edge perpendicular to the segment
// scores high and one parallel to it scores ~0). `result.strength` is
// still the plain gradient magnitude at the winning pixel, matching every
// other `result` — the directional dot product is only the *selection*
// score, not what's reported back.
//
// Non-max suppression (upgrade 2): for each of the 3 parallel scan lines
// (`k` = -1/0/1 across the segment), a step is a candidate only if its
// score is a local maximum *along the walk* — strictly greater than the
// step already visited, and at least as great as the one still to come
// (the "first" element of a flat-topped run — the walk's equivalent of
// `isDirectionalMax`'s plateau handling above). Among candidates that
// clear `floor`, the winner is the highest distance-weighted score
// (upgrade 3, `score × (1 − dist / radius)`, `dist` = distance to `endPt`
// — coefficient 1.0, same reasoning as `snapPoint`'s tie-break, above).
let snapEnd = (patch: patch, ~endPt: px, ~d: px, ~radius: float, ~floor: float): option<result> => {
  let n: px = {x: -.d.y, y: d.x} // unit normal to the segment
  // Any sampled point is within `radius` along `d` plus 1 px along `n` of
  // `endPt`, so a Euclidean pad of `radius + 1` bounds the whole walk —
  // looser than the exact rotated footprint, still bounded by `radius`,
  // never by the patch.
  let pad = radius +. 1.0
  let minX = clampInt(Float.toInt(Math.floor(endPt.x -. pad)), ~lo=0, ~hi=patch.width - 1)
  let maxX = clampInt(Float.toInt(Math.ceil(endPt.x +. pad)), ~lo=0, ~hi=patch.width - 1)
  let minY = clampInt(Float.toInt(Math.floor(endPt.y -. pad)), ~lo=0, ~hi=patch.height - 1)
  let maxY = clampInt(Float.toInt(Math.ceil(endPt.y +. pad)), ~lo=0, ~hi=patch.height - 1)
  let win = smoothWindow(patch, ~minX, ~maxX, ~minY, ~maxY)

  let sampleAt = (px_: int, py_: int): walkSample => {
    let (gx, gy) = sobelVectorSmoothed(win, px_, py_)
    let ddx = Int.toFloat(px_) -. endPt.x
    let ddy = Int.toFloat(py_) -. endPt.y
    {
      point: {x: Int.toFloat(px_), y: Int.toFloat(py_)},
      score: Math.abs(gx *. d.x +. gy *. d.y),
      mag: Math.hypot(gx, gy),
      dist: Math.sqrt(ddx *. ddx +. ddy *. ddy),
    }
  }

  let walkK = (k: int): array<walkSample> => {
    let kf = Int.toFloat(k)
    let samples = []
    let t = ref(-.radius)
    while t.contents <= radius +. 0.001 {
      let bx = endPt.x +. t.contents *. d.x +. kf *. n.x
      let by = endPt.y +. t.contents *. d.y +. kf *. n.y
      let px_ = clampInt(Float.toInt(Math.round(bx)), ~lo=0, ~hi=patch.width - 1)
      let py_ = clampInt(Float.toInt(Math.round(by)), ~lo=0, ~hi=patch.height - 1)
      samples->Array.push(sampleAt(px_, py_))
      t := t.contents +. 0.5
    }
    samples
  }

  let scoreOf = (samples: array<walkSample>, i: int): float =>
    samples->Array.get(i)->Option.mapOr(0.0, s => s.score)

  let best = ref(None) // (sample, weightedScore)
  [-1, 0, 1]->Array.forEach(k => {
    let samples = walkK(k)
    let len = samples->Array.length
    for i in 0 to len - 1 {
      let cur = scoreOf(samples, i)
      let leftOk = i == 0 || cur > scoreOf(samples, i - 1)
      let rightOk = i == len - 1 || cur >= scoreOf(samples, i + 1)
      if leftOk && rightOk && cur >= floor {
        switch samples->Array.get(i) {
        | None => ()
        | Some(s) =>
          // Coefficient 1.0 — see `snapPoint`'s matching comment for why.
          let weight = radius > 0.0 ? 1.0 -. s.dist /. radius : 1.0
          let weighted = s.score *. weight
          let isBetter = switch best.contents {
          | None => true
          | Some((bestSample, bestWeighted)) =>
            weighted > bestWeighted || (weighted == bestWeighted && s.dist < bestSample.dist)
          }
          if isBetter {
            best := Some((s, weighted))
          }
        }
      }
    }
  })
  best.contents->Option.map(((s, _)) => {point: s.point, strength: s.mag})
}

// Snaps `p1` and `p2` independently along their shared segment direction
// (SPEC bullet 1: "searches along the p1→p2 segment"). Degenerate case —
// `p1 == p2`, no direction — snaps neither end rather than dividing by
// zero; the caller's two rough taps always differ in practice. `~median`,
// when given, skips the patch-wide median-gradient pass (upgrade 4) —
// shared by both ends, computed once.
let snapPair = (
  patch: patch,
  ~p1: px,
  ~p2: px,
  ~radius: float,
  ~threshold: threshold,
  ~median: option<float>=?,
): (option<result>, option<result>) => {
  let dx = p2.x -. p1.x
  let dy = p2.y -. p1.y
  let len = Math.sqrt(dx *. dx +. dy *. dy)
  if len == 0.0 {
    (None, None)
  } else {
    let d: px = {x: dx /. len, y: dy /. len}
    let floor = cutoff(threshold, ~median=resolveMedian(patch, median))
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
