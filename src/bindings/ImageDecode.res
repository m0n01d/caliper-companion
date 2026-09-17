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
