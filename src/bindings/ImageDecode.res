// ImageDecode — bindings for the camera/library `<input type="file">` flow
// and EXIF-aware image decoding (SPEC §5, CLAUDE.md "iOS Safari rules that
// bite"). House style matches WebApi.res: `@send` methods take the
// instance first, `Nullable.t` at every boundary that can be `undefined`,
// no `%raw`/`Obj.magic`/untyped `@val` shortcuts.
//
// `file` models a DOM `File`. A `File` *is* a `Blob` at the platform level
// (MDN: "The File interface is based on Blob"), so `asBlob` below is a
// same-representation upcast — the exact technique @rescript/react's own
// `ReactEvent.resi` uses internally (`toSyntheticEvent`, `"%identity"`) to
// narrow one checked type into another without changing the runtime value.
// That's different from `Obj.magic`, which would let two runtime-
// incompatible types compile together with no such guarantee.

// -- File / FileList ---------------------------------------------------

type file
type fileList

@get external fileType: file => string = "type"
@get external fileSize: file => int = "size"

// Never inline base64 / re-encode a selected file (SPEC §6.1) — it goes to
// `Store.putFace`'s `~image` exactly as picked.
external asBlob: file => PouchDb.blob = "%identity"

@get external fileListLength: fileList => int = "length"
@send external fileListItem: (fileList, int) => Nullable.t<file> = "item"

let firstFile = (list: fileList): option<file> =>
  fileListLength(list) > 0 ? fileListItem(list, 0)->Nullable.toOption : None

// A React `<input type="file">` change event's `target` comes back through
// `ReactEvent.Form.t` as `{..}` — an intentionally open, unconstrained
// object type (React doesn't statically know which element dispatched the
// event; see `ReactEvent.resi`). Narrowing it to the one property this app
// reads (`.files`) is the same kind of same-representation coercion as
// `asBlob` above: the object really is the `<input>` element at runtime,
// and `%identity` asserts that to the compiler instead of bypassing it.
type inputTarget
external asInputTarget: {..} => inputTarget = "%identity"
@get external filesOfInputTarget: inputTarget => Nullable.t<fileList> = "files"

// The chosen file, if any — `None` covers both "the user cancelled the
// native picker" (an empty `FileList`) and the (impossible in practice,
// but typed honestly) case of a `files` property that's `undefined`.
let fileFromChangeEvent = (event: ReactEvent.Form.t): option<file> =>
  event
  ->ReactEvent.Form.target
  ->asInputTarget
  ->filesOfInputTarget
  ->Nullable.toOption
  ->Option.flatMap(firstFile)

// -- createImageBitmap (SPEC §5: decode with `imageOrientation:
// "from-image"` so EXIF rotation is applied before any coordinate is
// computed) ---------------------------------------------------------------

type imageBitmap
type imageBitmapOptions = {imageOrientation: string}

@val
external createImageBitmapFromFile: (file, imageBitmapOptions) => promise<imageBitmap> =
  "createImageBitmap"

@get external bitmapWidth: imageBitmap => int = "width"
@get external bitmapHeight: imageBitmap => int = "height"
@send external closeBitmap: imageBitmap => unit = "close"

// Oriented dimensions are read off the bitmap by the caller *before*
// `closeBitmap` frees it — this only performs the decode.
let decodeOriented = (f: file): promise<imageBitmap> =>
  createImageBitmapFromFile(f, {imageOrientation: "from-image"})

// -- downscale + re-encode (SPEC §8a A4: cap stored photos at 2048px) -----
//
// Redraws an oversized bitmap onto a canvas at the capped size and
// re-encodes it as JPEG. Reuses `Canvas2d`'s render-target / drawImage /
// toBlob machinery (OffscreenCanvas, falling back to a detached
// `<canvas>` — same fallback Render.res's export path already relies on)
// instead of duplicating that machinery here. `asCanvasBitmap` is a
// same-representation cast, exactly like `asBlob` above: this file's own
// `imageBitmap` and `Canvas2d`'s are both just a DOM `ImageBitmap` at
// runtime, decoded by the identical `createImageBitmap(…, {imageOrientation:
// "from-image"})` call (Canvas2d.res's own header comment notes it applies
// the same rule "again here — the app never trusts a stored width/height
// over a fresh decode"; capture time is the one place that redraw also has
// to actually *store* the result).
external asCanvasBitmap: imageBitmap => Canvas2d.imageBitmap = "%identity"

let resizedJpegMimeType = "image/jpeg"
let resizedJpegQuality = 0.85

// The bitmap is the caller's to close, same as `decodeOriented` above —
// this only draws and encodes.
let resizeToJpeg = (bitmap: imageBitmap, ~width: int, ~height: int): promise<PouchDb.blob> => {
  let target = Canvas2d.makeTarget(~width, ~height)
  let ctx = Canvas2d.context2d(target)
  Canvas2d.drawImage(ctx, asCanvasBitmap(bitmap), 0.0, 0.0, Int.toFloat(width), Int.toFloat(height))
  Canvas2d.toBlob(target, ~mimeType=resizedJpegMimeType, ~quality=Some(resizedJpegQuality))
}

// -- camera permission (SPEC M3 "camera denied") ---------------------------
//
// A file input can't detect OS-level camera denial by itself — there's no
// event for it, just a picker that silently offers no camera option. Where
// the Permissions API exists and knows about "camera" (Chrome; Safari has
// neither), a `denied` state lets Capture.res make the standing
// capture-note more prominent instead of only showing it unconditionally.
module CameraPermission = {
  type api
  type status

  // `undefined` on Safari (no `navigator.permissions` support at all for
  // "camera") and on any browser where the API itself is absent.
  @val @scope("navigator") external instance: Nullable.t<api> = "permissions"

  type descriptor = {name: string}
  @send external query: (api, descriptor) => promise<status> = "query"
  @get external state: status => string = "state"

  // Resolves `true` only for a confirmed `"denied"`. Every other outcome —
  // API absent, the browser doesn't recognize "camera" as a queryable
  // permission name (rejects), "granted", "prompt" — resolves `false`:
  // Capture.res's unconditional `capture-note` already covers those, this
  // only upgrades it to "prominent".
  let isDenied = (): promise<bool> =>
    switch instance->Nullable.toOption {
    | None => Promise.resolve(false)
    | Some(api) =>
      query(api, {name: "camera"})
      ->Promise.then(s => Promise.resolve(state(s) == "denied"))
      ->Promise.catch(_ => Promise.resolve(false))
    }
}
