// Route — hash-based routing (SPEC §8 M6, CLAUDE.md "Architecture"). `t` is
// the single source of truth for every navigable screen; `Main.res` matches
// it to a page and later agents extend pages without ever touching this
// file's shape.
//
// A13 (SPEC §8a): the parts list is a folder browser, so `Parts` carries the
// folder path (`""` = root). Root is `#/`; a folder is `#/f/<seg>/<seg>`
// with each segment percent-encoded on its own (`#/f/Miata%20(NB)`) — `/`
// is not a valid segment character (`Folder.segmentRe`), so a segment never
// needs a `%2F`.

type t =
  | Parts(string)
  | Part(string)
  | Capture(string)
  | Annotate(string, string)
  | Settings
  | Debug

let toHash = (route: t): string =>
  switch route {
  | Parts("") => "#/"
  | Parts(path) =>
    "#/f/" ++ Folder.segments(path)->Array.map(WebApi.Uri.encodeComponent)->Array.join("/")
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

// `decodeURIComponent` throws a `URIError` on a malformed escape (`%E0`),
// and `parse` runs inside the `hashchange` listener — an uncaught throw
// there would kill routing for the session. `None` is the malformed case.
let decodeAll = (segs: array<string>): option<array<string>> =>
  try {
    Some(segs->Array.map(WebApi.Uri.decodeComponent))
  } catch {
  | JsExn(_) => None
  }

// Unknown or malformed paths fall back to the parts list rather than error —
// there is no 404 page in v0. A folder hash is decoded segment by segment
// and normalised (`#/f`, `#/f/` and `#/f/Miata/` are the root, the root and
// `Miata`); it is never *validated* here — a path that names no folder is
// the parts list's own "This folder doesn't exist." view (A13). Array
// spread is not a pattern in ReScript, so the `f` prefix is indexed and the
// rest sliced.
let parse = (hash: string): t => {
  let segs = segments(hash)
  switch segs[0] {
  | Some("f") =>
    switch decodeAll(segs->Array.slice(~start=1)) {
    | Some(decoded) => Parts(Folder.normalize(decoded->Array.join("/")))
    | None => Parts("")
    }
  | Some(_) | None =>
    switch segs {
    | [] => Parts("")
    | ["parts", id] => Part(id)
    | ["parts", id, "capture"] => Capture(id)
    | ["parts", id, "faces", faceId] => Annotate(id, faceId)
    | ["settings"] => Settings
    | ["debug"] => Debug
    | _ => Parts("")
    }
  }
}

let current = (): t => WebApi.Location.location->WebApi.Location.hash->parse

// Fire-and-forget: sets `location.hash`, which in turn fires `hashchange` —
// `subscribe` below is what turns that into a `msg`. Polymorphic in 'msg
// because the effect never calls `dispatch`.
let push = (route: t): Tea.cmd<'msg> =>
  Tea.effect(_dispatch => WebApi.Location.location->WebApi.Location.setHash(toHash(route)))

// SPEC §8a A16: how far into the app a route sits, so a route change knows
// which way it moves. `Parts(folder)` is 1 + the folder's depth; Settings
// is only reachable from the root's leading slot and Debug only from
// Settings; a part is deeper than any folder; capture sits over the part;
// Annotate is 12, not 11 — capture → annotate is the most-travelled forward
// step (`Capture.res` pushes it after every capture) and at equal depth it
// would fade.
let depth = (route: t): int =>
  switch route {
  | Parts(folder) => 1 + Folder.depth(folder)
  | Settings => 2
  | Debug => 3
  | Part(_) => 10
  | Capture(_) => 11
  | Annotate(_, _) => 12
  }

// Deeper → push (the new screen slides in from the right), shallower → pop
// (the old screen slides out to the right), equal → fade (same-depth
// sibling folders reached from search, both ways).
type direction = Push | Pop | Fade

let direction = (from: t, to: t): direction => {
  let (a, b) = (depth(from), depth(to))
  if b > a {
    Push
  } else if b < a {
    Pop
  } else {
    Fade
  }
}

// The `html[data-nav]` value the CSS is keyed on.
let directionAttr = (d: direction): string =>
  switch d {
  | Push => "push"
  | Pop => "pop"
  | Fade => "fade"
  }

// Registers a single `hashchange` listener (the effect runs once, at
// `Main.init`) that dispatches on every change thereafter — `Tea.effect`'s
// callback may call `dispatch` many times over the component's lifetime.
// A16: the listener keeps the previous route so it can tell push from pop,
// and dispatches through `Motion.transition`, which animates the swap where
// the View Transitions API exists and is the plain dispatch elsewhere. The
// Back chevron, folder rows, `Route.push` and the browser's own
// back/forward all arrive here, so they all animate.
let subscribe = (toMsg: t => 'msg): Tea.cmd<'msg> =>
  Tea.effect(dispatch => {
    let prev = ref(current())
    WebApi.Window.window->WebApi.Window.addEventListener("hashchange", () => {
      let next = current()
      let nav = direction(prev.contents, next)
      prev := next
      Motion.transition(~nav=directionAttr(nav), dispatch, toMsg(next))
    })
  })
