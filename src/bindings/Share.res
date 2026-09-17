// Share — `navigator.share`/`canShare`, the `File` constructor, and the
// Blob→object-URL→anchor download fallback (SPEC §5 `navigator.share`
// note, M5 bullet 2). No `%raw`: every feature check reads a property as
// `Nullable.t` and only calls the real method once that read proves it's
// there — the same pattern as `WebApi.ServiceWorker.container` and
// `WebApi.Platform.standaloneNavigator`.

// -- File ---------------------------------------------------------------

type file

type fileOptions = {@as("type") type_: string}

@new external makeFile: (array<Uint8Array.t>, string, fileOptions) => file = "File"

let zipMimeType = "application/zip"

let makeZipFile = (bytes: Uint8Array.t, ~fileName: string): file =>
  makeFile([bytes], fileName, {type_: zipMimeType})

// -- navigator.share / navigator.canShare --------------------------------

type navigator
@val external navigator: navigator = "navigator"

type shareData = {files?: array<file>, title?: string}

// Presence checks only (see module doc) — `share`/`canShare` are absent
// (`undefined`), not merely throwing, on browsers without the Web Share
// API, e.g. this repo's own Playwright chromium project (SPEC §10/M5:
// "chromium has no navigator.share").
type shareMethodPresence
@get external shareProp: navigator => Nullable.t<shareMethodPresence> = "share"
@get external canShareProp: navigator => Nullable.t<shareMethodPresence> = "canShare"

let hasShare = (): bool => shareProp(navigator)->Nullable.toOption->Option.isSome
let hasCanShare = (): bool => canShareProp(navigator)->Nullable.toOption->Option.isSome

@send external shareCall: (navigator, shareData) => promise<unit> = "share"
@send external canShareCall: (navigator, shareData) => bool = "canShare"

// SPEC M5: "If navigator.canShare exists and canShare({files: [zip]}) is
// true". Both halves are required — `canShare` can exist and still say no
// (e.g. a browser that shares text/urls but not files).
let canShareFile = (file: file): bool =>
  hasCanShare() && canShareCall(navigator, {files: [file]})

let share = (file: file, ~title: string): promise<unit> =>
  shareCall(navigator, {files: [file], title})

// A user cancelling the native share sheet rejects with a DOMException
// named "AbortError" — SPEC M5: that maps to `Failed("Share cancelled")`,
// not a hard failure.
@get external errorName: JsExn.t => Nullable.t<string> = "name"
let isAbortError = (exn: exn): bool =>
  switch exn {
  | JsExn(err) => errorName(err)->Nullable.toOption == Some("AbortError")
  | _ => false
  }

// -- download fallback (object URL + a clicked, invisible anchor) --------

@val external document: Dom.document = "document"
@get external body: Dom.document => Dom.element = "body"

type anchor
@send external createAnchor: (Dom.document, string) => anchor = "createElement"
@set external setHref: (anchor, string) => unit = "href"
@set external setDownload: (anchor, string) => unit = "download"
@send external click: anchor => unit = "click"
@send external appendAnchor: (Dom.element, anchor) => unit = "appendChild"
@send external removeAnchor: (Dom.element, anchor) => unit = "removeChild"

@scope("URL") @val external createObjectURL: file => string = "createObjectURL"
@scope("URL") @val external revokeObjectURL: string => unit = "revokeObjectURL"

// Appending the anchor to the DOM before `click()` and removing it right
// after is the well-worn cross-browser way to make a synthetic download
// click reliable (some engines ignore `click()` on a detached element);
// the anchor is never visible — it's added and removed synchronously.
let downloadFile = (file: file, ~fileName: string): unit => {
  let url = createObjectURL(file)
  let a = createAnchor(document, "a")
  setHref(a, url)
  setDownload(a, fileName)
  let parent = body(document)
  appendAnchor(parent, a)
  click(a)
  removeAnchor(parent, a)
  revokeObjectURL(url)
}
