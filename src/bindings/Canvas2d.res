// Canvas2d — the offscreen-render surface for the dimensioned PNG (SPEC §5
// canvas cap, M5 bullet 1). `OffscreenCanvas` with a fallback to a detached
// `<canvas>` (feature-detected the same way WebApi.ServiceWorker/Platform
// do: read the global as `Nullable.t`, never call it to find out); 2D
// context drawing + text metrics for the pill labels; `createImageBitmap`
// decoded `from-image` (SPEC §5's EXIF rule — applies here too, at export
// time, not just at capture); `toBlob`/`convertToBlob` wrapped as a promise.
//
// No `%raw`, no `Obj.magic`. `blob` is a plain alias for `PouchDb.blob` —
// both name the same runtime `Blob`, so a face image fetched via
// `Store.getFaceImage` and a PNG produced here are interchangeable without
// a cast, and `Bundle.res` can read either back with `PouchDb.blobArrayBuffer`.

type blob = PouchDb.blob

// -- image decode ------------------------------------------------------------

type imageBitmap
@get external bitmapWidth: imageBitmap => int = "width"
@get external bitmapHeight: imageBitmap => int = "height"

type imageBitmapOptions = {imageOrientation: string}

@val
external createImageBitmap: (blob, imageBitmapOptions) => promise<imageBitmap> = "createImageBitmap"

let decodeOriented = (b: blob): promise<imageBitmap> =>
  createImageBitmap(b, {imageOrientation: "from-image"})

// -- 2D context ---------------------------------------------------------------
//
// One opaque `ctx` type covers both `OffscreenCanvasRenderingContext2D` and
// `CanvasRenderingContext2D` — the drawing/text methods this app uses are
// the same surface on both (the shared `CanvasDrawPath`/`CanvasText`/etc.
// mixins in the DOM spec), so a single set of externals works for whichever
// canvas produced the context.

type ctx

@set external setFillStyle: (ctx, string) => unit = "fillStyle"
@set external setStrokeStyle: (ctx, string) => unit = "strokeStyle"
@set external setLineWidth: (ctx, float) => unit = "lineWidth"
@set external setFont: (ctx, string) => unit = "font"
@set external setTextAlign: (ctx, string) => unit = "textAlign"
@set external setTextBaseline: (ctx, string) => unit = "textBaseline"

@send external drawImage: (ctx, imageBitmap, float, float, float, float) => unit = "drawImage"
@send external fillRect: (ctx, float, float, float, float) => unit = "fillRect"
@send external beginPath: ctx => unit = "beginPath"
@send external closePath: ctx => unit = "closePath"
@send external moveTo: (ctx, float, float) => unit = "moveTo"
@send external lineTo: (ctx, float, float) => unit = "lineTo"
// `(x, y, radius, startAngle, endAngle)` — this app only ever draws full
// circles (`0` to `2π`, SPEC §8a A3's endpoint handles), so the DOM's
// trailing optional `anticlockwise` argument is never needed.
@send
external arc: (ctx, float, float, float, float, float) => unit = "arc"
@send external roundRect: (ctx, float, float, float, float, float) => unit = "roundRect"
@send external stroke: ctx => unit = "stroke"
@send external fill: ctx => unit = "fill"
@send external fillText: (ctx, string, float, float) => unit = "fillText"
// SPEC §8a A3: dashed extension ticks. `[]` (the default the drawing code
// always resets to after a dashed stroke) draws a solid line again.
@send external setLineDash: (ctx, array<float>) => unit = "setLineDash"

type textMetrics
@send external measureText: (ctx, string) => textMetrics = "measureText"
@get external metricsWidth: textMetrics => float = "width"

// -- render target: OffscreenCanvas, falling back to a detached <canvas> ---

type offscreenCanvas
@send external getOffscreenContext: (offscreenCanvas, string) => Nullable.t<ctx> = "getContext"
// `quality` is only meaningful for `image/jpeg`/`image/webp` (SPEC §8a A4's
// re-encode); omitted (`None`) for the PNG export path, where the browser
// ignores it anyway.
type blobOptions = {@as("type") type_: string, quality?: float}
@send
external convertToBlob: (offscreenCanvas, blobOptions) => promise<blob> = "convertToBlob"

// Presence check only — mirrors WebApi.ServiceWorker.container /
// WebApi.Platform.standaloneNavigator: read the global as `Nullable.t`,
// never invoke it to find out whether it exists.
type offscreenCtorPresence
@val @scope("window")
external offscreenCtorPresence: Nullable.t<offscreenCtorPresence> = "OffscreenCanvas"
@new external makeOffscreen: (int, int) => offscreenCanvas = "OffscreenCanvas"

type canvasElement
@val external document: Dom.document = "document"
@send external createElement: (Dom.document, string) => canvasElement = "createElement"
@set external setWidth: (canvasElement, int) => unit = "width"
@set external setHeight: (canvasElement, int) => unit = "height"
@send external getElementContext: (canvasElement, string) => Nullable.t<ctx> = "getContext"
@send
external toBlobRaw: (canvasElement, Nullable.t<blob> => unit, string) => unit = "toBlob"
@send
external toBlobRawQuality: (canvasElement, Nullable.t<blob> => unit, string, float) => unit =
  "toBlob"

type target = OffscreenTarget(offscreenCanvas) | ElementTarget(canvasElement)

let hasOffscreenCanvas = (): bool =>
  offscreenCtorPresence->Nullable.toOption->Option.isSome

let makeTarget = (~width: int, ~height: int): target =>
  if hasOffscreenCanvas() {
    OffscreenTarget(makeOffscreen(width, height))
  } else {
    let el = createElement(document, "canvas")
    setWidth(el, width)
    setHeight(el, height)
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

exception ToBlobFailed(string)

let pngMimeType = "image/png"

// `~quality` (0.0–1.0) is SPEC §8a A4's JPEG re-encode knob; left out for
// the (default) PNG export path, where it has no effect.
let toBlob = (target: target, ~mimeType: string=pngMimeType, ~quality: option<float>=None): promise<blob> =>
  switch target {
  | OffscreenTarget(oc) =>
    let opts: blobOptions = switch quality {
    | Some(q) => {type_: mimeType, quality: q}
    | None => {type_: mimeType}
    }
    convertToBlob(oc, opts)
  | ElementTarget(el) =>
    Promise.make((resolve, reject) => {
      let onResult = nb =>
        switch nb->Nullable.toOption {
        | Some(b) => resolve(b)
        | None => reject(ToBlobFailed("canvas toBlob() returned null"))
        }
      switch quality {
      | Some(q) => toBlobRawQuality(el, onResult, mimeType, q)
      | None => toBlobRaw(el, onResult, mimeType)
      }
    })
  }
