// Canvas — bindings for the annotate screen's DOM slice (SPEC M4): the
// <canvas> element and its 2D context, `createImageBitmap` with EXIF
// orientation applied at decode (SPEC §5), devicePixelRatio, element
// geometry/focus/attributes, the pointer-event fields the stock
// `JsxEvent.Pointer` binding leaves out, a ResizeObserver, and a typed
// `react/jsx-runtime` entry for `<input>` that carries the attributes
// `JsxDOM.domProps` lacks (`enterkeyhint`, `autocorrect` — the keyboard-
// wedge seam, SPEC §9).
//
// House style follows WebApi.res: real `external`s over the standard
// library's `Dom` types, instance-first `@send` methods, `option` at the
// boundary via `@return(nullable)`. No `%raw`, no `Obj.magic`, no
// `%identity` casts — the canvas element is handled as the `Dom.element`
// React's ref hands us, and the canvas-only members (`getContext`,
// `width`/`height`) are bound on that type with the caller responsible for
// only pointing them at a <canvas>.

// ── ImageBitmap ─────────────────────────────────────────────────────────
type imageBitmap

// `imageOrientation: "from-image"` applies the JPEG's EXIF rotation during
// decode, so the bitmap's width/height ARE the oriented dimensions and every
// coordinate computed from it is relative to the oriented image (SPEC §5).
type bitmapOptions = {imageOrientation: string}

@val external createImageBitmap: (PouchDb.blob, bitmapOptions) => promise<imageBitmap> = "createImageBitmap"
@get external bitmapWidth: imageBitmap => int = "width"
@get external bitmapHeight: imageBitmap => int = "height"

// ── window ─────────────────────────────────────────────────────────────
@val @scope("window") external devicePixelRatio: float = "devicePixelRatio"

// ── Element geometry, focus, attributes ────────────────────────────────
@send external getBoundingClientRect: Dom.element => Dom.domRect = "getBoundingClientRect"
@get external rectLeft: Dom.domRect => float = "left"
@get external rectTop: Dom.domRect => float = "top"
@get external rectWidth: Dom.domRect => float = "width"
@get external rectHeight: Dom.domRect => float = "height"

@send external focus: Dom.element => unit = "focus"
// HTMLInputElement
@send external select: Dom.element => unit = "select"
@get external value: Dom.element => string = "value"

@send external setAttribute: (Dom.element, string, string) => unit = "setAttribute"

@send external setPointerCapture: (Dom.element, int) => unit = "setPointerCapture"

// `document.querySelector`, as ReactDOM binds it, plus the testid helper the
// focus cmds use (CLAUDE.md/docs/testids.md: ids are the stable contract).
@val @return(nullable) external querySelector: string => option<Dom.element> = "document.querySelector"

let byTestId = (id: string): option<Dom.element> => querySelector(`[data-testid="${id}"]`)

// ── <canvas> backing store ─────────────────────────────────────────────
@get external width: Dom.element => int = "width"
@get external height: Dom.element => int = "height"
@set external setWidth: (Dom.element, int) => unit = "width"
@set external setHeight: (Dom.element, int) => unit = "height"

type context2d
@send @return(nullable) external getContext: (Dom.element, string) => option<context2d> = "getContext"

// ── CanvasRenderingContext2D ───────────────────────────────────────────
module Ctx = {
  type t = context2d

  @send external setTransform: (t, float, float, float, float, float, float) => unit = "setTransform"
  @send external clearRect: (t, float, float, float, float) => unit = "clearRect"
  @send external fillRect: (t, float, float, float, float) => unit = "fillRect"
  @send external drawImage: (t, imageBitmap, float, float, float, float) => unit = "drawImage"

  @send external beginPath: t => unit = "beginPath"
  @send external closePath: t => unit = "closePath"
  @send external moveTo: (t, float, float) => unit = "moveTo"
  @send external lineTo: (t, float, float) => unit = "lineTo"
  @send external arc: (t, float, float, float, float, float) => unit = "arc"
  @send external arcTo: (t, float, float, float, float, float) => unit = "arcTo"
  @send external stroke: t => unit = "stroke"
  @send external fill: t => unit = "fill"
  @send external save: t => unit = "save"
  @send external restore: t => unit = "restore"

  @set external setStrokeStyle: (t, string) => unit = "strokeStyle"
  @set external setFillStyle: (t, string) => unit = "fillStyle"
  @set external setLineWidth: (t, float) => unit = "lineWidth"
  @set external setLineCap: (t, string) => unit = "lineCap"
  @set external setLineJoin: (t, string) => unit = "lineJoin"
  @send external setLineDash: (t, array<float>) => unit = "setLineDash"
  @set external setGlobalAlpha: (t, float) => unit = "globalAlpha"
  @set external setImageSmoothingEnabled: (t, bool) => unit = "imageSmoothingEnabled"

  @set external setFont: (t, string) => unit = "font"
  @set external setTextAlign: (t, string) => unit = "textAlign"
  @set external setTextBaseline: (t, string) => unit = "textBaseline"
  @send external fillText: (t, string, float, float) => unit = "fillText"

  type textMetrics
  @send external measureText: (t, string) => textMetrics = "measureText"
  @get external textWidth: textMetrics => float = "width"
}

// ── Pointer events: fields JsxEvent.Pointer doesn't expose ─────────────
// `clientX/Y` are bound as float here (JsxEvent has them as int); modern
// engines report fractional CSS pixels and the normalized-coordinate math
// wants them.
module Pointer = {
  @get external pointerId: JsxEvent.Pointer.t => int = "pointerId"
  @get external clientX: JsxEvent.Pointer.t => float = "clientX"
  @get external clientY: JsxEvent.Pointer.t => float = "clientY"
  @get external currentTarget: JsxEvent.Pointer.t => Dom.element = "currentTarget"
}

// ── Form events: a typed `target` instead of JsxEvent's `{..}` ─────────
module Form = {
  @get external target: JsxEvent.Form.t => Dom.element = "target"
}

// ── ResizeObserver — the canvas re-fits when the sheet grows/shrinks ───
module ResizeObserver = {
  type t
  type entry
  @new external make: (array<entry> => unit) => t = "ResizeObserver"
  @send external observe: (t, Dom.element) => unit = "observe"
  @send external disconnect: t => unit = "disconnect"
}

// ── <input> with the wedge-seam attributes ─────────────────────────────
// `JsxDOM.domProps` has no `enterKeyHint`/`autoCorrect` field and ReScript
// JSX rejects hyphenated attribute names, so the sheet's inputs are created
// through the same `react/jsx-runtime` call `ReactDOM.jsx` uses, with a
// props record that carries exactly the attributes SPEC §5/M4 require.
// React maps `enterKeyHint` → `enterkeyhint` and `autoCorrect` →
// `autocorrect` itself.
module Input = {
  type props = {
    @as("data-testid") dataTestId: string,
    id?: string,
    @as("type") type_: string,
    className?: string,
    inputMode?: string,
    enterKeyHint?: string,
    autoCapitalize?: string,
    autoCorrect?: string,
    autoComplete?: string,
    spellCheck?: bool,
    placeholder?: string,
    @as("aria-invalid") ariaInvalid?: bool,
    @as("aria-label") ariaLabel?: string,
    value: string,
    onChange: JsxEvent.Form.t => unit,
    onKeyDown?: JsxEvent.Keyboard.t => unit,
  }

  @module("react/jsx-runtime") external jsx: (string, props) => React.element = "jsx"

  let make = (props: props): React.element => jsx("input", props)
}
