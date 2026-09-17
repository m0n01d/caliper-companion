// WebApi — hand-written bindings to the slice of the DOM the app shell
// touches: service-worker registration, hash routing, localStorage, viewport
// layout, and the iOS platform checks behind the Add-to-Home-Screen hint.
// Real `external`s over the abstract types in the standard library's `Dom`
// module; no `%raw`, no `Obj.magic`, no untyped `@val` shortcuts.
//
// House style (ported from ternpike/src/bindings/WebApi.res): methods bind
// as functions taking the instance as the first argument
// (`el->WebApi.Foo.method(...)`); `Null.t`/`Nullable.t` at the boundary —
// `Null.t` where the API returns JS `null` (e.g. `localStorage.getItem`),
// `Nullable.t` where the property can also be `undefined` (unsupported API,
// absent on this platform).

// ── Service worker ──────────────────────────────────────────────────────
module ServiceWorker = {
  type container
  type registration

  // `undefined` in browsers without service-worker support — this is the
  // feature-detection guard `Index.res` switches on before registering.
  @val @scope("navigator")
  external container: Nullable.t<container> = "serviceWorker"

  @send external register: (container, string) => promise<registration> = "register"
}

// ── localStorage (A2HS hint dismissal) ──────────────────────────────────
module LocalStorage = {
  type t

  @val external storage: t = "localStorage"

  // Returns JS `null` (not `undefined`) when the key is absent.
  @send external getItem: (t, string) => Null.t<string> = "getItem"
  @send external setItem: (t, string, string) => unit = "setItem"
}

// ── Hash routing (Route.res) ────────────────────────────────────────────
module Location = {
  type t

  @val external location: t = "location"
  @get external hash: t => string = "hash"
  @set external setHash: (t, string) => unit = "hash"
}

module Window = {
  type t

  @val external window: t = "window"

  // Typed loosely on purpose: every listener this app registers
  // (`hashchange`, `visualViewport`'s `resize`) ignores the event payload,
  // so the callback takes no arguments. JS tolerates the arity mismatch —
  // the extra argument the browser passes to the callback is simply dropped.
  @send external addEventListener: (t, string, unit => unit) => unit = "addEventListener"
}

// ── visualViewport — keyboard-aware sheet height (SPEC §5) ──────────────
// `Index.res` mirrors this into the `--vv-height` CSS custom property that
// `.sheet` in global.css reads, since CSS alone can't see `visualViewport`.
module VisualViewport = {
  type t

  // `undefined` on browsers without the API.
  @val @scope("window")
  external instance: Nullable.t<t> = "visualViewport"

  @get external height: t => float = "height"
  @send external addEventListener: (t, string, unit => unit) => unit = "addEventListener"
}

// ── document.documentElement.style — for setting CSS custom properties ──
module Style = {
  type t

  @val external document: Dom.document = "document"
  @get external documentElement: Dom.document => Dom.element = "documentElement"
  @get external style: Dom.element => t = "style"
  @send external setProperty: (t, string, string) => unit = "setProperty"

  let setDocumentVar = (name: string, value: string): unit =>
    document->documentElement->style->setProperty(name, value)
}

// ── Platform detection — the A2HS hint (SPEC §5 iOS rules) ──────────────
module Platform = {
  // `navigator.standalone` is a non-standard iOS Safari boolean; `undefined`
  // everywhere else, which doubles as the "is this an iOS browser" signal.
  @val @scope("navigator")
  external standaloneNavigator: Nullable.t<bool> = "standalone"

  @val @scope("navigator") external userAgent: string = "userAgent"

  // `window.MSStream` exists only on legacy Windows Phone IE, which
  // otherwise spoofs an iPad user agent. Its presence rules a device *out*
  // of the iOS branch — ported from ternpike's `onIosDevice` check verbatim.
  // The value itself is never used, only whether it's present, so its shape
  // stays an opaque abstract type.
  type msStreamValue
  @val @scope("window") external msStream: Nullable.t<msStreamValue> = "MSStream"

  type mediaQueryList
  @val external matchMedia: string => mediaQueryList = "matchMedia"
  @get external matches: mediaQueryList => bool = "matches"

  let isStandalone = (): bool =>
    standaloneNavigator->Nullable.toOption == Some(true) ||
      matchMedia("(display-mode: standalone)")->matches

  let isIos = (): bool => {
    let uaLooksIos = ["iPhone", "iPad", "iPod"]->Array.some(needle => userAgent->String.includes(needle))
    let msStreamPresent = msStream->Nullable.toOption->Option.isSome
    standaloneNavigator->Nullable.toOption->Option.isSome || (uaLooksIos && !msStreamPresent)
  }
}
