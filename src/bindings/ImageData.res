// ImageData — turns an already-decoded ImageBitmap into a downscaled
// grayscale EdgeSnap.patch (SPEC §8a A5 bullet 2: "the annotate page keeps
// a downscaled grayscale copy of the oriented image (long edge 1024 px,
// built once from the bitmap via a canvas getImageData); snapping runs in
// that space"). This file only draws + reads back a bitmap the caller
// already has — it never calls `createImageBitmap` itself (SPEC bullet 2's
// "built once from the bitmap": decoding happens exactly once, elsewhere).
//
// -- Bitmap-type note (flagged for the wiring agent, and in the hand-off
// report) --------------------------------------------------------------
// `Canvas.res` and `Canvas2d.res` each already declare their OWN opaque
// `imageBitmap` type rather than sharing one — `ImageDecode.res` bridges
// two of them with a single justified same-representation `%identity`
// cast (see its header comment). This file was told not to add a third
// such cast, so it declares its own `ImageData.imageBitmap` below instead
// of importing either sibling's. All three name the same runtime
// `ImageBitmap` object. Whoever wires taps to `EdgeSnap` holds a
// `Canvas.imageBitmap` (the annotate page's own oriented decode) and is
// the one who calls `lumaPatchOf` with it — *they* own converting it to
// `ImageData.imageBitmap`, one line, the same technique and justification
// as `ImageDecode.res`'s `asCanvasBitmap`. This file intentionally does
// not perform that cast itself.
//
// -- Render-target plumbing -----------------------------------------------
// Feature-detects `OffscreenCanvas` the same way `Canvas2d.res` does (read
// the global as `Nullable.t`, never call it to find out whether it
// exists), falling back to a detached `<canvas>`. That plumbing can't
// simply be *called* from `Canvas2d.res` because its `drawImage` is bound
// to *its* `imageBitmap` type, not this file's — so it's mirrored here
// (same shape, on purpose, so the two stay trivially easy to diff) rather
// than duplicated-and-drifting.
//
// No `%raw`, no `Obj.magic`.

type imageBitmap
@get external bitmapWidth: imageBitmap => int = "width"
@get external bitmapHeight: imageBitmap => int = "height"

// -- 2D context: just enough to draw the bitmap and read pixels back ----

type ctx
@send external drawImage: (ctx, imageBitmap, float, float, float, float) => unit = "drawImage"

type imageDataT
@send
external getImageDataRaw: (ctx, float, float, float, float) => imageDataT = "getImageData"
@get external imageDataData: imageDataT => Uint8ClampedArray.t = "data"

// -- render target: OffscreenCanvas, falling back to a detached <canvas> --

type offscreenCanvas
@send external getOffscreenContext: (offscreenCanvas, string) => Nullable.t<ctx> = "getContext"
@new external makeOffscreen: (int, int) => offscreenCanvas = "OffscreenCanvas"

// Presence check only — mirrors Canvas2d.res's `offscreenCtorPresence`.
type offscreenCtorPresence
@val @scope("window")
external offscreenCtorPresence: Nullable.t<offscreenCtorPresence> = "OffscreenCanvas"

type canvasElement
@val external document: Dom.document = "document"
@send external createElement: (Dom.document, string) => canvasElement = "createElement"
@set external setCanvasWidth: (canvasElement, int) => unit = "width"
@set external setCanvasHeight: (canvasElement, int) => unit = "height"
@send external getElementContext: (canvasElement, string) => Nullable.t<ctx> = "getContext"

type target = OffscreenTarget(offscreenCanvas) | ElementTarget(canvasElement)

let hasOffscreenCanvas = (): bool => offscreenCtorPresence->Nullable.toOption->Option.isSome

let makeTarget = (~width: int, ~height: int): target =>
  if hasOffscreenCanvas() {
    OffscreenTarget(makeOffscreen(width, height))
  } else {
    let el = createElement(document, "canvas")
    setCanvasWidth(el, width)
    setCanvasHeight(el, height)
    ElementTarget(el)
  }

exception Context2dUnavailable(string)

let context2d = (target: target): ctx =>
  switch target {
  | OffscreenTarget(oc) =>
    switch getOffscreenContext(oc, "2d")->Nullable.toOption {
    | Some(c) => c
    | None => throw(Context2dUnavailable("OffscreenCanvas 2D context unavailable"))
    }
  | ElementTarget(el) =>
    switch getElementContext(el, "2d")->Nullable.toOption {
    | Some(c) => c
    | None => throw(Context2dUnavailable("canvas 2D context unavailable"))
    }
  }

// -- target size: caps the long edge, never upscales ----------------------
//
// SPEC bullet 2: "long edge 1024 px". A bitmap already at or below
// `maxLongEdge` is drawn at its own size (this only ever shrinks).
let targetSize = (~bitmapWidth: int, ~bitmapHeight: int, ~maxLongEdge: int): (int, int) => {
  let longEdge = Math.Int.max(bitmapWidth, bitmapHeight)
  if longEdge <= maxLongEdge || longEdge <= 0 {
    (bitmapWidth, bitmapHeight)
  } else {
    let scale = Int.toFloat(maxLongEdge) /. Int.toFloat(longEdge)
    let w = Math.max(1.0, Math.round(Int.toFloat(bitmapWidth) *. scale))
    let h = Math.max(1.0, Math.round(Int.toFloat(bitmapHeight) *. scale))
    (Float.toInt(w), Float.toInt(h))
  }
}

// -- pure RGBA → luma conversion (Rec. 601) --------------------------------
//
// Kept as a plain function of a `Uint8ClampedArray.t` + explicit size
// (rather than folded into `lumaPatchOf`) so the conversion itself is a
// pure, directly testable step even though this whole file is exercised by
// Playwright, not unit tests (SPEC bullet 5 assigns unit tests to
// `EdgeSnap.res` only; this binding has no DOM-free unit-testable surface
// beyond `targetSize`/`toLuma`, which is why both are plain top-level
// functions instead of being inlined).
let toLuma = (rgba: Uint8ClampedArray.t, ~width: int, ~height: int): EdgeSnap.patch => {
  let n = width * height
  let luma = Uint8Array.fromLength(n)
  for i in 0 to n - 1 {
    let o = i * 4
    let r = rgba->TypedArray.get(o)->Option.getOr(0)
    let g = rgba->TypedArray.get(o + 1)->Option.getOr(0)
    let b = rgba->TypedArray.get(o + 2)->Option.getOr(0)
    let y = 0.299 *. Int.toFloat(r) +. 0.587 *. Int.toFloat(g) +. 0.114 *. Int.toFloat(b)
    luma->TypedArray.set(i, Float.toInt(Math.round(y)))
  }
  {EdgeSnap.width, height, luma}
}

// The one entry point the wiring agent calls: draw `bitmap` downscaled
// onto an offscreen (or fallback) canvas, read it back, convert to luma.
// A `promise` per the SPEC signature — every step here is synchronous
// today, but this keeps the door open for a future `createImageBitmap`
// `resizeWidth`/`resizeHeight` decode path (which is async) without a
// signature change.
let lumaPatchOf = (bitmap: imageBitmap, ~maxLongEdge: int): promise<EdgeSnap.patch> => {
  let (w, h) = targetSize(
    ~bitmapWidth=bitmapWidth(bitmap),
    ~bitmapHeight=bitmapHeight(bitmap),
    ~maxLongEdge,
  )
  let target = makeTarget(~width=w, ~height=h)
  let ctx = context2d(target)
  drawImage(ctx, bitmap, 0.0, 0.0, Int.toFloat(w), Int.toFloat(h))
  let data = getImageDataRaw(ctx, 0.0, 0.0, Int.toFloat(w), Int.toFloat(h))->imageDataData
  Promise.resolve(toLuma(data, ~width=w, ~height=h))
}
