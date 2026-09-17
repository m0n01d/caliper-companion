// Download — Blob + object-URL helpers (SPEC M6: Debug's CSV export via a
// download anchor; also used by Part.res to turn a face image attachment
// into an `<img src>` object URL). Two `external`s bind the same
// `URL.createObjectURL` global over two different (opaque, nominal) blob
// types — one for text we build here, one for `PouchDb.blob` handed back by
// `Store.getFaceImage` — rather than reaching for `Obj.magic` to reconcile
// them; both are really DOM `Blob`s at runtime, JS doesn't care.
//
// No `%raw`, no `Obj.magic`. Real `external`s only.

type blob

type blobOptions = {@as("type") mime: string}

@new external makeBlob: (array<string>, blobOptions) => blob = "Blob"

@val @scope("URL") external createObjectUrl: blob => string = "createObjectURL"
@val @scope("URL")
external createObjectUrlFromPouchBlob: PouchDb.blob => string = "createObjectURL"
@val @scope("URL") external revokeObjectUrl: string => unit = "revokeObjectURL"

module Anchor = {
  type t

  @val @scope("document") external createElement: string => t = "createElement"
  @set external setHref: (t, string) => unit = "href"
  @set external setDownload: (t, string) => unit = "download"
  @send external click: t => unit = "click"

  @val @scope("document") external body: Dom.element = "body"
  @send external appendChild: (Dom.element, t) => unit = "appendChild"
  @send external removeChild: (Dom.element, t) => unit = "removeChild"
}

// Builds a Blob from `text`, clicks a throwaway anchor with a `download`
// attribute, then revokes the URL. Appends the anchor to `document.body`
// only for the duration of the click — some engines (historically Safari)
// refuse to fire a `download` on a detached anchor.
let save = (~name: string, ~mime: string, ~text: string): unit => {
  let blob = makeBlob([text], {mime: mime})
  let url = createObjectUrl(blob)
  let a = Anchor.createElement("a")
  a->Anchor.setHref(url)
  a->Anchor.setDownload(name)
  Anchor.body->Anchor.appendChild(a)
  a->Anchor.click
  Anchor.body->Anchor.removeChild(a)
  revokeObjectUrl(url)
}

// Object URL for a face-image blob (Part.res's face thumbnails). Revoking
// it when the page model is replaced isn't required in v0 (SPEC scope for
// this module) — noted in LOGBOOK.md.
let objectUrlOfImage = (b: PouchDb.blob): string => createObjectUrlFromPouchBlob(b)
