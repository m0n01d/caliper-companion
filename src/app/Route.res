// Route — hash-based routing (SPEC §8 M6, CLAUDE.md "Architecture"). `t` is
// the single source of truth for every navigable screen; `Main.res` matches
// it to a page and later agents extend pages without ever touching this
// file's shape.

type t =
  | Parts
  | Part(string)
  | Capture(string)
  | Annotate(string, string)
  | Settings
  | Debug

let toHash = (route: t): string =>
  switch route {
  | Parts => "#/"
  | Part(id) => "#/parts/" ++ id
  | Capture(id) => "#/parts/" ++ id ++ "/capture"
  | Annotate(id, faceId) => "#/parts/" ++ id ++ "/faces/" ++ faceId
  | Settings => "#/settings"
  | Debug => "#/debug"
  }

// Identical to `toHash` today; named separately so call sites read like
// markup (`<a href={Route.href(r)}>`) rather than exposing a routing detail.
let href = (route: t): string => toHash(route)

// `location.hash` includes the leading "#" when present and is "" when
// absent. Strip it, split on "/", and drop empty segments — this handles
// "", "#", "#/", and "#/parts/abc/capture" uniformly.
let segments = (hash: string): array<string> => {
  let stripped = hash->String.startsWith("#") ? hash->String.slice(~start=1) : hash
  stripped->String.split("/")->Array.filter(s => s !== "")
}

// Unknown or malformed paths fall back to the parts list rather than error —
// there is no 404 page in v0.
let parse = (hash: string): t =>
  switch segments(hash) {
  | [] => Parts
  | ["parts", id] => Part(id)
  | ["parts", id, "capture"] => Capture(id)
  | ["parts", id, "faces", faceId] => Annotate(id, faceId)
  | ["settings"] => Settings
  | ["debug"] => Debug
  | _ => Parts
  }

let current = (): t => WebApi.Location.location->WebApi.Location.hash->parse

// Fire-and-forget: sets `location.hash`, which in turn fires `hashchange` —
// `subscribe` below is what turns that into a `msg`. Polymorphic in 'msg
// because the effect never calls `dispatch`.
let push = (route: t): Tea.cmd<'msg> =>
  Tea.effect(_dispatch => WebApi.Location.location->WebApi.Location.setHash(toHash(route)))

// Registers a single `hashchange` listener (the effect runs once, at
// `Main.init`) that dispatches on every change thereafter — `Tea.effect`'s
// callback may call `dispatch` many times over the component's lifetime.
let subscribe = (toMsg: t => 'msg): Tea.cmd<'msg> =>
  Tea.effect(dispatch => {
    WebApi.Window.window->WebApi.Window.addEventListener("hashchange", () => dispatch(toMsg(current())))
  })
