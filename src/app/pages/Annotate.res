// Annotate — the core screen (SPEC M4). Tap two edges on the face photo,
// type the caliper reading, name the feature. The photo is never measured
// (SPEC §1): every tap becomes a normalized point on the *oriented* image
// via Viewport.res, and the reading comes only from the field.
//
// TEA (CLAUDE.md "Architecture"): every piece of page state — the viewport
// transform, live pointers, the gesture in progress, pending points, the
// selected dimension, field texts — lives in `model`; pointer and keyboard
// handlers only `dispatch`; Store calls and `focus()` are `Tea.cmd`s. The
// one sanctioned DOM-ref spot is `CanvasView`, which owns the <canvas> and
// redraws in an effect as a pure function of the model slice it's given.
//
// The keyboard-wedge seam (SPEC §9, M4 bullet 6) is the focus order:
// p2 placed → `reading` focused; Enter in `reading` → `name`; Enter in
// `name` → Save → canvas. A dongle typing `42.18⏎` lands a reading and
// advances with zero app code.

// ── Model ──────────────────────────────────────────────────────────────

type size = {w: float, h: float}

type handle = P1 | P2

// The endpoints being placed or edited. While a saved dimension is selected
// these ARE its endpoints (see `select`), so the sheet's Update writes them.
type pending = {p1: option<Types.point>, p2: option<Types.point>}

// Whose endpoints a hit or a drag refers to (SPEC §8a A1): the pending pair,
// or a saved dimension other than the selected one.
type target = Pending | Existing(string)

type hit =
  | HitNothing
  | HitHandle(target, handle) // within handleHitRadius of an endpoint
  | HitBody(target) // within lineHitRadius of the segment, off its handles

type activePointer = {id: int, start: Viewport.pt, pos: Viewport.pt, hit: hit}

type dragKind = Handle(handle) | Body

// A drag in progress: what it moves, and the endpoints as they were before
// it started — so a second finger (→ pinch) or a cancel reverts exactly, and
// every move is `before + total pointer travel` (no drift, no grab jump).
type drag = {target: target, kind: dragKind, before: pending}

// What the pointers currently mean. Positions live in `pointers`; this is
// the interpretation. One pointer is a press until it moves past the slop,
// then a pan (or a drag if it went down on a handle or a line body); two
// are a pinch and never a tap.
type gesture =
  | NoGesture
  | Press(int)
  | Pan(int)
  | Drag(int, drag)
  | Pinch(int, int)

// A focus the page owes the reading field but must not perform yet (SPEC
// §8a A2): iOS Safari opens the keyboard for `focus()` only inside a `click`
// (or `touchend`) handler, never from `pointerup`. So the p2 tap records the
// intent and the canvas's click — which follows every tap and never a drag
// or pinch — performs it.
type focusIntent = Reading

type loaded = {
  part: Types.part,
  face: Types.face,
  bitmap: Canvas.imageBitmap,
  imageW: float, // the bitmap's, i.e. oriented, size
  imageH: float,
  dims: array<Types.dimension>, // this face's, createdAt ascending
  suggestions: array<string>, // FeatureName.suggestions(~used = other faces' names)
  settings: Store.settings,
}

type status =
  | Loading
  | NotFound(string)
  | Ready(loaded)

type model = {
  partId: string,
  faceId: string,
  status: status,
  // canvas CSS size + devicePixelRatio, reported by CanvasView
  view: size,
  dpr: float,
  viewport: Viewport.t,
  fitScale: float,
  touched: bool, // user has zoomed/panned; a resize clamps instead of re-fitting
  pointers: array<activePointer>,
  gesture: gesture,
  pending: pending,
  selected: option<string>, // dimension id being edited
  focusIntent: option<focusIntent>, // performed by the next canvas click
  announcement: string, // the `aria-live` line after a save (DESIGN.md §9)
  reading: string,
  name: string,
  tolerance: string,
  kind: Types.dimensionKind,
  busy: bool, // a Save/Delete Store write is in flight
  moving: bool, // a drag's Store write is in flight (SPEC §8a A1)
  error: option<string>, // last Store failure, shown inline
}

type msg =
  | Loaded(result<loaded, string>)
  | ViewSized(size, float)
  | PointerDown(int, Viewport.pt)
  | PointerMove(int, Viewport.pt)
  | PointerUp(int)
  | PointerCancel(int)
  | CanvasClicked
  | ZoomIn
  | ZoomOut
  | ReadingChanged(string)
  | ReadingEnter
  | NameChanged(string)
  | NameEnter
  | ChipTapped(string)
  | KindChosen(Types.dimensionKind)
  | ToleranceChanged(string)
  | SaveClicked
  | Saved(result<(array<Types.dimension>, Store.settings, Types.dimension), string>)
  | DeleteClicked
  | Deleted(result<array<Types.dimension>, string>)
  | Moved(result<array<Types.dimension>, string>)
  | CancelClicked

let tapSlop = 8.0
let handleHitRadius = 22.0 // a 44 px target (DESIGN.md §2) on a 22 px handle
let lineHitRadius = 16.0
let zoomStep = 1.5
let maxZoomOverFit = 8.0

let noPending = {p1: None, p2: None}

// ── Effects ────────────────────────────────────────────────────────────

let exnMessage = (e: exn): string =>
  switch JsExn.fromException(e) {
  | Some(js) => JsExn.message(js)->Option.getOr("Unknown error")
  | None => "Unknown error"
  }

let focusTestId = (id: string, ~select: bool): Tea.cmd<msg> =>
  Tea.effect(_dispatch =>
    switch Canvas.byTestId(id) {
    | Some(el) =>
      el->Canvas.focus
      if select {
        el->Canvas.select
      }
    | None => ()
    }
  )

let faceKindLabel = (k: Types.faceKind): string =>
  switch k {
  | Top => "Top"
  | Side => "Side"
  | End => "End"
  | Detail => "Detail"
  }

let load = async (~partId: string, ~faceId: string): result<loaded, string> => {
  let store = Store.shared()
  let part = await Store.getPart(store, partId)
  let face = await Store.getFace(store, faceId)
  switch (part, face) {
  | (Some(part), Some(face)) =>
    switch await Store.getFaceImage(store, faceId) {
    | None => Error("This face has no image.")
    | Some(blob) =>
      // EXIF rotation is applied here, at decode (SPEC §5). The bitmap IS
      // the oriented image; every coordinate below is relative to it.
      let bitmap = await Canvas.createImageBitmap(blob, {imageOrientation: "from-image"})
      let imageW = Canvas.bitmapWidth(bitmap)
      let imageH = Canvas.bitmapHeight(bitmap)
      if imageW != face.pixelWidth || imageH != face.pixelHeight {
        Console.warn(
          `Annotate: face ${face.id} stores ${Int.toString(face.pixelWidth)}×${Int.toString(
              face.pixelHeight,
            )} but the oriented bitmap is ${Int.toString(imageW)}×${Int.toString(
              imageH,
            )}; trusting the bitmap`,
        )
      }
      let dims = await Store.dimensionsOfFace(store, ~faceId)
      let all = await Store.dimensionsOf(store, ~partId)
      let used = all->Array.filter(d => d.faceId != faceId)->Array.map(d => d.name)
      let settings = await Store.getSettings(store)
      Ok({
        part,
        face,
        bitmap,
        imageW: Int.toFloat(imageW),
        imageH: Int.toFloat(imageH),
        dims,
        suggestions: FeatureName.suggestions(~used),
        settings,
      })
    }
  | (None, _) => Error("Part not found.")
  | (_, None) => Error("Face not found.")
  }
}

let loadCmd = (~partId, ~faceId): Tea.cmd<msg> =>
  Tea.fromPromise(() => load(~partId, ~faceId), r => Loaded(r), e => Loaded(Error(exnMessage(e))))

let saveCmd = (
  ~partId: string,
  ~faceId: string,
  ~units: Types.units,
  ~settings: Store.settings,
  dim: Types.dimension,
): Tea.cmd<msg> =>
  Tea.fromPromise(
    async () => {
      let store = Store.shared()
      let _ = await Store.putDimension(store, ~partId, dim)
      // The tolerance just used becomes the part-units default (M4 bullet 5).
      let next: Store.settings = switch units {
      | Mm => {...settings, lastToleranceMm: dim.tolerance}
      | Inch => {...settings, lastToleranceIn: dim.tolerance}
      }
      await Store.putSettings(store, next)
      let dims = await Store.dimensionsOfFace(store, ~faceId)
      (dims, next, dim)
    },
    r => Saved(Ok(r)),
    e => Saved(Error(exnMessage(e))),
  )

let deleteCmd = (~faceId: string, id: string): Tea.cmd<msg> =>
  Tea.fromPromise(
    async () => {
      let store = Store.shared()
      await Store.deleteDimension(store, id)
      await Store.dimensionsOfFace(store, ~faceId)
    },
    dims => Deleted(Ok(dims)),
    e => Deleted(Error(exnMessage(e))),
  )

// A drag on a saved dimension persists on release — same id, no Save tap
// (SPEC §8a A1) — and the face's dimensions are reloaded so the model shows
// what the store holds.
let moveCmd = (~partId: string, ~faceId: string, dim: Types.dimension): Tea.cmd<msg> =>
  Tea.fromPromise(
    async () => {
      let store = Store.shared()
      let _ = await Store.putDimension(store, ~partId, dim)
      await Store.dimensionsOfFace(store, ~faceId)
    },
    dims => Moved(Ok(dims)),
    e => Moved(Error(exnMessage(e))),
  )

// ── Init ───────────────────────────────────────────────────────────────

let init = (~partId: string, ~faceId: string): (model, Tea.cmd<msg>) => (
  {
    partId,
    faceId,
    status: Loading,
    view: {w: 0.0, h: 0.0},
    dpr: 1.0,
    viewport: Viewport.identity,
    fitScale: 1.0,
    touched: false,
    pointers: [],
    gesture: NoGesture,
    pending: noPending,
    selected: None,
    focusIntent: None,
    announcement: "",
    reading: "",
    name: "",
    tolerance: "",
    kind: Length,
    busy: false,
    moving: false,
    error: None,
  },
  loadCmd(~partId, ~faceId),
)

// ── Pure helpers over the model ────────────────────────────────────────

let clampViewport = (m: model, l: loaded, vp: Viewport.t): Viewport.t =>
  Viewport.clamp(
    vp,
    ~minScale=m.fitScale,
    ~maxScale=maxZoomOverFit *. m.fitScale,
    ~imageW=l.imageW,
    ~imageH=l.imageH,
    ~viewW=m.view.w,
    ~viewH=m.view.h,
  )

// Recompute fit for the current view; re-fit unless the user has already
// zoomed or panned, in which case just keep the transform legal.
let refit = (m: model, l: loaded): model => {
  let fitted = Viewport.fit(~imageW=l.imageW, ~imageH=l.imageH, ~viewW=m.view.w, ~viewH=m.view.h)
  let m = {...m, fitScale: fitted.scale}
  {...m, viewport: m.touched ? clampViewport(m, l, m.viewport) : fitted}
}

let toScreen = (m: model, l: loaded, n: Types.point): Viewport.pt =>
  Viewport.fromNormalized(m.viewport, ~imageW=l.imageW, ~imageH=l.imageH, n)

let clamp01 = (v: float): float => Math.min(Math.max(v, 0.0), 1.0)

let toNormalized = (m: model, l: loaded, s: Viewport.pt): Types.point => {
  let n = Viewport.toNormalized(m.viewport, ~imageW=l.imageW, ~imageH=l.imageH, s)
  {x: clamp01(n.x), y: clamp01(n.y)}
}

// Nearest of `xs` by `dist`, if any is within `r`.
let nearestWithin = (xs: array<'a>, ~dist: 'a => float, ~r: float): option<'a> =>
  xs
  ->Array.reduce(None, (acc, x) => {
    let d = dist(x)
    switch acc {
    | Some((_, best)) if best <= d => acc
    | _ => d <= r ? Some((x, d)) : acc
    }
  })
  ->Option.map(((x, _)) => x)

// Hit priority handle > line body > nothing (a pan), nearest wins within a
// class (SPEC §8a A1). Candidates are the pending pair — which, while a saved
// dimension is selected, is that dimension's pair — and every other saved
// dimension on the face.
let hitTest = (m: model, l: loaded, s: Viewport.pt): hit => {
  let saved = l.dims->Array.filter(d => m.selected != Some(d.id))
  let pendingHandles =
    [(P1, m.pending.p1), (P2, m.pending.p2)]->Array.filterMap(((h, p)) =>
      p->Option.map(p => (Pending, h, toScreen(m, l, p)))
    )
  let savedHandles =
    saved->Array.flatMap(d => [
      (Existing(d.id), P1, toScreen(m, l, d.p1)),
      (Existing(d.id), P2, toScreen(m, l, d.p2)),
    ])
  let handles = Array.concat(pendingHandles, savedHandles)
  switch nearestWithin(handles, ~dist=((_, _, p)) => Viewport.distance(s, p), ~r=handleHitRadius) {
  | Some((t, h, _)) => HitHandle(t, h)
  | None =>
    let pendingBody = switch (m.pending.p1, m.pending.p2) {
    | (Some(a), Some(b)) => [(Pending, toScreen(m, l, a), toScreen(m, l, b))]
    | _ => []
    }
    let savedBodies = saved->Array.map(d => (Existing(d.id), toScreen(m, l, d.p1), toScreen(m, l, d.p2)))
    let bodies = Array.concat(pendingBody, savedBodies)
    switch nearestWithin(bodies, ~dist=((_, a, b)) => Viewport.distanceToSegment(s, ~a, ~b), ~r=lineHitRadius) {
    | Some((t, _, _)) => HitBody(t)
    | None => HitNothing
    }
  }
}

let readingResult = (m: model, l: loaded) => NumberParse.parse(m.reading, l.part.units)
let nameResult = (m: model) => FeatureName.validate(m.name)
let toleranceResult = (m: model, l: loaded) => NumberParse.parse(m.tolerance, l.part.units)

// Save is enabled only when p1, p2, a valid reading, a valid name and a
// valid tolerance all exist (M4 bullets 3–4). Editing reuses the selected
// dimension's id and createdAt.
let buildDimension = (m: model, l: loaded): option<Types.dimension> =>
  switch (m.pending.p1, m.pending.p2, readingResult(m, l), nameResult(m), toleranceResult(m, l)) {
  | (Some(p1), Some(p2), Ok(value), Ok(name), Ok(tolerance)) if !m.busy =>
    let existing = switch m.selected {
    | Some(id) => l.dims->Array.find(d => d.id == id)
    | None => None
    }
    Some({
      id: existing->Option.mapOr(Ids.dimension(), d => d.id),
      faceId: m.faceId,
      name,
      kind: m.kind,
      value,
      tolerance,
      p1,
      p2,
      source: l.settings.wedge ? Wedge : Typed,
      createdAt: existing->Option.mapOr(Clock.nowIso(), d => d.createdAt),
    })
  | _ => None
  }

let canSave = (m: model, l: loaded): bool => buildDimension(m, l)->Option.isSome

let defaultTolerance = (l: loaded): string =>
  switch l.part.units {
  | Mm => Float.toString(l.settings.lastToleranceMm)
  | Inch => Float.toString(l.settings.lastToleranceIn)
  }

// Drop the entry in progress; kind and tolerance stay (M4 bullet 7).
let clearEntry = (m: model): model => {
  ...m,
  pending: noPending,
  selected: None,
  reading: "",
  name: "",
  error: None,
}

// Existing dimension → the sheet shows its values for edit (M4 bullet 8);
// its endpoints become the draggable pending handles.
let select = (m: model, l: loaded, id: string): model =>
  switch l.dims->Array.find(d => d.id == id) {
  | Some(d) => {
      ...m,
      selected: Some(id),
      pending: {p1: Some(d.p1), p2: Some(d.p2)},
      reading: Float.toString(d.value),
      name: d.name,
      kind: d.kind,
      tolerance: Float.toString(d.tolerance),
      error: None,
    }
  | None => m
  }

let tap = (m: model, l: loaded, s: Viewport.pt, hit: hit): (model, Tea.cmd<msg>) => {
  let n = toNormalized(m, l, s)
  switch (m.pending.p1, m.pending.p2, hit) {
  // Second tap of a two-tap dimension: place p2 (wherever it lands, even on
  // a handle — p2 stays draggable). The reading gets focus from the click
  // that follows this tap (SPEC §8a A2), not from here.
  | (Some(_), None, _) => (
      {...m, pending: {...m.pending, p2: Some(n)}, focusIntent: Some(Reading)},
      Tea.none,
    )
  // A tap (no movement) on a saved dimension still selects it (SPEC §8a A1).
  | (_, _, HitHandle(Existing(id), _)) | (_, _, HitBody(Existing(id))) => (select(m, l, id), Tea.none)
  // The pending pair is already the one being edited: a tap on it is a no-op.
  | (_, _, HitHandle(Pending, _)) | (_, _, HitBody(Pending)) => (m, Tea.none)
  | (_, _, HitNothing) =>
    switch m.selected {
    | Some(_) => (clearEntry(m), Tea.none)
    | None => ({...m, pending: {p1: Some(n), p2: None}, announcement: ""}, Tea.none)
    }
  }
}

// The endpoints a drag starts from: the pending pair, or the saved
// dimension's own.
let beforeOf = (m: model, l: loaded, target: target): pending =>
  switch target {
  | Pending => m.pending
  | Existing(id) =>
    switch l.dims->Array.find(d => d.id == id) {
    | Some(d) => {p1: Some(d.p1), p2: Some(d.p2)}
    | None => noPending
    }
  }

// Where a drag has taken its endpoints: the pre-drag pair moved by the
// pointer's total travel — a handle drag moves that point, a body drag
// moves both together (Viewport keeps them inside the image).
let dragged = (m: model, l: loaded, d: drag, ~from: Viewport.pt, ~to: Viewport.pt): pending => {
  let delta = Viewport.deltaToNormalized(
    m.viewport,
    ~imageW=l.imageW,
    ~imageH=l.imageH,
    ~dx=to.x -. from.x,
    ~dy=to.y -. from.y,
  )
  switch d.kind {
  | Handle(P1) => {...d.before, p1: d.before.p1->Option.map(p => Viewport.translatePoint(p, delta))}
  | Handle(P2) => {...d.before, p2: d.before.p2->Option.map(p => Viewport.translatePoint(p, delta))}
  | Body =>
    switch (d.before.p1, d.before.p2) {
    | (Some(a), Some(b)) =>
      let (a, b) = Viewport.translatePair(a, b, delta)
      {p1: Some(a), p2: Some(b)}
    | _ => d.before
    }
  }
}

// Put a drag's endpoints where they belong: the pending pair, or the saved
// dimension in the loaded face (drawn live; persisted on release).
let setPoints = (m: model, l: loaded, target: target, pts: pending): model =>
  switch target {
  | Pending => {...m, pending: pts}
  | Existing(id) =>
    let dims = l.dims->Array.map(d =>
      d.id == id ? {...d, p1: pts.p1->Option.getOr(d.p1), p2: pts.p2->Option.getOr(d.p2)} : d
    )
    {...m, status: Ready({...l, dims})}
  }

let panBy = (m: model, l: loaded, ~from: Viewport.pt, ~to: Viewport.pt): model => {
  ...m,
  touched: true,
  viewport: clampViewport(m, l, Viewport.pan(m.viewport, ~dx=to.x -. from.x, ~dy=to.y -. from.y)),
}

let zoomBy = (m: model, l: loaded, factor: float): model => {
  ...m,
  touched: true,
  viewport: clampViewport(
    m,
    l,
    Viewport.zoomAbout(m.viewport, ~factor, ~screenAnchor={x: m.view.w /. 2.0, y: m.view.h /. 2.0}),
  ),
}

let pointerById = (m: model, id: int): option<activePointer> => m.pointers->Array.find(p => p.id == id)

// ── Update ─────────────────────────────────────────────────────────────

let pointerDown = (m: model, l: loaded, id: int, s: Viewport.pt): model => {
  let hit = hitTest(m, l, s)
  let pointers = m.pointers->Array.filter(p => p.id != id)->Array.concat([{id, start: s, pos: s, hit}])
  // An intent the last tap's click never collected (a pointer type that
  // produced none) must not fire on a later, unrelated click.
  let m = {...m, pointers, focusIntent: None}
  switch m.gesture {
  | NoGesture => {...m, gesture: Press(id)}
  | Press(other) | Pan(other) if other != id => {...m, gesture: Pinch(other, id)}
  // A second finger during a drag cancels it: the points revert and the two
  // fingers are a pinch (SPEC §8a A1).
  | Drag(other, d) if other != id => {...setPoints(m, l, d.target, d.before), gesture: Pinch(other, id)}
  | _ => m // a third finger is ignored; the pinch keeps its two
  }
}

let pointerMove = (m: model, l: loaded, id: int, s: Viewport.pt): model =>
  switch pointerById(m, id) {
  | None => m
  | Some(before) =>
    let pointers = m.pointers->Array.map(p => p.id == id ? {...p, pos: s} : p)
    let m = {...m, pointers}
    let drag = (d: drag): model => {
      ...setPoints(m, l, d.target, dragged(m, l, d, ~from=before.start, ~to=s)),
      gesture: Drag(id, d),
    }
    switch m.gesture {
    | Press(pid) if pid == id =>
      if Viewport.distance(before.start, s) > tapSlop {
        switch before.hit {
        | HitHandle(target, h) => drag({target, kind: Handle(h), before: beforeOf(m, l, target)})
        | HitBody(target) => drag({target, kind: Body, before: beforeOf(m, l, target)})
        | HitNothing => {...panBy(m, l, ~from=before.pos, ~to=s), gesture: Pan(id)}
        }
      } else {
        m
      }
    | Pan(pid) if pid == id => panBy(m, l, ~from=before.pos, ~to=s)
    | Drag(pid, d) if pid == id => drag(d)
    | Pinch(a, b) if id == a || id == b =>
      switch (pointerById(m, a), pointerById(m, b)) {
      | (Some(pa), Some(pb)) =>
        let prevA = a == id ? before.pos : pa.pos
        let prevB = b == id ? before.pos : pb.pos
        {
          ...m,
          touched: true,
          viewport: clampViewport(
            m,
            l,
            Viewport.pinch(m.viewport, ~prev=(prevA, prevB), ~next=(pa.pos, pb.pos)),
          ),
        }
      | _ => m
      }
    | _ => m
    }
  }

let pointerEnd = (m: model, l: loaded, id: int, ~cancelled: bool): (model, Tea.cmd<msg>) =>
  switch pointerById(m, id) {
  | None => (m, Tea.none)
  | Some(p) =>
    let m = {...m, pointers: m.pointers->Array.filter(q => q.id != id)}
    switch m.gesture {
    | Press(pid) if pid == id =>
      let m = {...m, gesture: NoGesture}
      cancelled ? (m, Tea.none) : tap(m, l, p.pos, p.hit)
    | Pan(pid) if pid == id => ({...m, gesture: NoGesture}, Tea.none)
    | Drag(pid, d) if pid == id =>
      let m = {...m, gesture: NoGesture}
      switch (cancelled, d.target) {
      // The browser took the pointer away mid-drag: nothing half-moved stays.
      | (true, _) => (setPoints(m, l, d.target, d.before), Tea.none)
      | (false, Pending) => (m, Tea.none)
      // Releasing a saved dimension's drag writes it at once (SPEC §8a A1).
      | (false, Existing(sid)) =>
        switch l.dims->Array.find(x => x.id == sid) {
        | Some(dim) => ({...m, moving: true}, moveCmd(~partId=m.partId, ~faceId=m.faceId, dim))
        | None => (m, Tea.none)
        }
      }
    | Pinch(a, b) if id == a || id == b =>
      // The finger left behind continues as a pan; never a tap.
      let rest = id == a ? b : a
      ({...m, gesture: pointerById(m, rest)->Option.isSome ? Pan(rest) : NoGesture}, Tea.none)
    | _ => (m, Tea.none)
    }
  }

let trySave = (m: model, l: loaded): (model, Tea.cmd<msg>) =>
  switch buildDimension(m, l) {
  | Some(dim) => (
      {...m, busy: true, error: None},
      saveCmd(~partId=m.partId, ~faceId=m.faceId, ~units=l.part.units, ~settings=l.settings, dim),
    )
  | None => (m, Tea.none)
  }

let update = (m: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch (msg, m.status) {
  | (Loaded(Ok(l)), _) =>
    let m = {...m, status: Ready(l), tolerance: defaultTolerance(l), touched: false}
    (refit(m, l), Tea.none)
  | (Loaded(Error(why)), _) => ({...m, status: NotFound(why)}, Tea.none)

  | (ViewSized(view, dpr), status) =>
    if view == m.view && dpr == m.dpr {
      (m, Tea.none)
    } else {
      let m = {...m, view, dpr}
      switch status {
      | Ready(l) => (refit(m, l), Tea.none)
      | _ => (m, Tea.none)
      }
    }

  | (PointerDown(id, s), Ready(l)) => (pointerDown(m, l, id, s), Tea.none)
  | (PointerMove(id, s), Ready(l)) => (pointerMove(m, l, id, s), Tea.none)
  | (PointerUp(id), Ready(l)) => pointerEnd(m, l, id, ~cancelled=false)
  | (PointerCancel(id), Ready(l)) => pointerEnd(m, l, id, ~cancelled=true)
  // The wedge seam's first hop (M4 bullet 6): p2 placed → `reading`. Runs
  // inside the click dispatch so iOS opens the keyboard (SPEC §8a A2).
  | (CanvasClicked, _) =>
    switch m.focusIntent {
    | Some(Reading) => ({...m, focusIntent: None}, focusTestId("reading", ~select=true))
    | None => (m, Tea.none)
    }

  | (ZoomIn, Ready(l)) => (zoomBy(m, l, zoomStep), Tea.none)
  | (ZoomOut, Ready(l)) => (zoomBy(m, l, 1.0 /. zoomStep), Tea.none)

  | (ReadingChanged(text), _) => ({...m, reading: text}, Tea.none)
  // The wedge seam: Enter in the reading moves to the name (M4 bullet 6).
  | (ReadingEnter, _) => (m, focusTestId("name", ~select=true))
  | (NameChanged(text), _) => ({...m, name: text}, Tea.none)
  | (ChipTapped(text), _) => ({...m, name: text}, Tea.none)
  | (NameEnter, Ready(l)) => trySave(m, l)
  | (KindChosen(kind), _) => ({...m, kind}, Tea.none)
  | (ToleranceChanged(text), _) => ({...m, tolerance: text}, Tea.none)

  | (SaveClicked, Ready(l)) => trySave(m, l)
  // Save clears reading + name + points, keeps kind and tolerance, and
  // returns focus to the canvas for the next tap (M4 bullet 7).
  | (Saved(Ok((dims, settings, dim))), Ready(l)) =>
    let announcement =
      "Dimension saved: " ++
      dim.name ++
      " " ++
      NumberParse.format(dim.value, l.part.units) ++
      " " ++
      NumberParse.unitsLabel(l.part.units)
    (
      {...clearEntry(m), status: Ready({...l, dims, settings}), busy: false, announcement},
      focusTestId("annotate-canvas", ~select=false),
    )
  | (Saved(Error(why)), _) => ({...m, busy: false, error: Some(why)}, Tea.none)

  | (DeleteClicked, Ready(_)) =>
    switch m.selected {
    | Some(id) if !m.busy => ({...m, busy: true, error: None}, deleteCmd(~faceId=m.faceId, id))
    | _ => (m, Tea.none)
    }
  | (Deleted(Ok(dims)), Ready(l)) => (
      {...clearEntry(m), status: Ready({...l, dims}), busy: false},
      focusTestId("annotate-canvas", ~select=false),
    )
  | (Deleted(Error(why)), _) => ({...m, busy: false, error: Some(why)}, Tea.none)

  | (Moved(Ok(dims)), Ready(l)) => (
      {...m, status: Ready({...l, dims}), moving: false, error: None},
      Tea.none,
    )
  | (Moved(Error(why)), _) => ({...m, moving: false, error: Some(why)}, Tea.none)

  | (CancelClicked, _) => (clearEntry(m), focusTestId("annotate-canvas", ~select=false))

  // Messages that need a loaded face, arriving before/after one.
  | (
      PointerDown(_, _)
      | PointerMove(_, _)
      | PointerUp(_)
      | PointerCancel(_)
      | ZoomIn
      | ZoomOut
      | NameEnter
      | SaveClicked
      | Saved(Ok(_))
      | DeleteClicked
      | Deleted(Ok(_))
      | Moved(Ok(_)),
      _,
    ) => (m, Tea.none)
  }

// ── Page contract ──────────────────────────────────────────────────────

let title = (m: model): string =>
  switch m.status {
  | Ready(l) => faceKindLabel(l.face.kind) ++ " · " ++ l.part.name
  | _ => "Annotate"
  }

let back = (m: model): option<Route.t> => Some(Route.Part(m.partId))

// ── CanvasView — the one DOM-ref spot ──────────────────────────────────
//
// Owns the <canvas>, reports its CSS size + DPR, forwards pointer events
// as msgs (canvas-local CSS px), and redraws in an effect whenever the
// `scene` slice changes. It never holds state of its own.

type scene = {
  bitmap: option<Canvas.imageBitmap>,
  imageW: float,
  imageH: float,
  viewport: Viewport.t,
  dims: array<Types.dimension>,
  selected: option<string>,
  pending: pending,
  pendingLabel: option<string>,
  view: size,
  dpr: float,
}

// Pill text (DESIGN.md §5): `name value`, prefixed ⌀ for a diameter and ↓
// for a depth. Either part may still be empty while an entry is typed; no
// pill at all when both are.
let formatLabel = (~name: string, ~value: string, ~kind: Types.dimensionKind): option<string> => {
  let body = [String.trim(name), String.trim(value)]->Array.filter(s => s != "")->Array.join(" ")
  if body == "" {
    None
  } else {
    Some(
      switch kind {
      | Diameter => "⌀ " ++ body
      | Depth => "↓ " ++ body
      | Length => body
      },
    )
  }
}

let drawScene = (el: Dom.element, scene: scene): unit => {
  let wPx = Float.toInt(Math.round(scene.view.w *. scene.dpr))
  let hPx = Float.toInt(Math.round(scene.view.h *. scene.dpr))
  if Canvas.width(el) != wPx {
    el->Canvas.setWidth(wPx)
  }
  if Canvas.height(el) != hPx {
    el->Canvas.setHeight(hPx)
  }
  switch el->Canvas.getContext("2d") {
  | None => ()
  | Some(ctx) =>
    // Backing store is DPR-scaled; everything below draws in CSS px.
    ctx->Canvas.Ctx.setTransform(scene.dpr, 0.0, 0.0, scene.dpr, 0.0, 0.0)
    ctx->Canvas.Ctx.clearRect(0.0, 0.0, scene.view.w, scene.view.h)
    let vp = scene.viewport
    let toS = (n: Types.point) => Viewport.fromNormalized(vp, ~imageW=scene.imageW, ~imageH=scene.imageH, n)
    switch scene.bitmap {
    | Some(bitmap) => Draw.image(ctx, bitmap, vp, ~imageW=scene.imageW, ~imageH=scene.imageH)
    | None => ()
    }
    // Saved dimensions, dimmed (a drag on one shows live because it moves
    // the loaded copy); the selected one is drawn from the pending points
    // below, in the selected style.
    scene.dims->Array.forEach(d =>
      if scene.selected != Some(d.id) {
        Draw.dimension(
          ctx,
          ~a=toS(d.p1),
          ~b=toS(d.p2),
          ~text=formatLabel(~name=d.name, ~value=Float.toString(d.value), ~kind=d.kind),
          ~style=Dimmed,
        )
      }
    )
    let style: Draw.style = scene.selected->Option.isSome ? Selected : Pending
    switch (scene.pending.p1, scene.pending.p2) {
    | (Some(p1), Some(p2)) =>
      Draw.dimension(ctx, ~a=toS(p1), ~b=toS(p2), ~text=scene.pendingLabel, ~style)
    | (Some(p1), None) => Draw.handle(ctx, toS(p1), ~style)
    | _ => ()
    }
  }
  // Test hooks (docs/testids.md "Annotate"): the live transform and the
  // oriented image size, so a spec can compute where a normalized point is.
  el->Canvas.setAttribute(
    "data-transform",
    Float.toString(scene.viewport.scale) ++
    "," ++
    Float.toString(scene.viewport.tx) ++
    "," ++
    Float.toString(scene.viewport.ty),
  )
  el->Canvas.setAttribute(
    "data-image-size",
    Float.toString(scene.imageW) ++ "x" ++ Float.toString(scene.imageH),
  )
}

let localPoint = (e: JsxEvent.Pointer.t): Viewport.pt => {
  let rect = e->Canvas.Pointer.currentTarget->Canvas.getBoundingClientRect
  {
    x: Canvas.Pointer.clientX(e) -. Canvas.rectLeft(rect),
    y: Canvas.Pointer.clientY(e) -. Canvas.rectTop(rect),
  }
}

module CanvasView = {
  @react.component
  let make = (~scene: scene, ~dispatch: msg => unit) => {
    let canvasRef = React.useRef(Nullable.null)

    // Size reporting: once on mount and whenever the stage resizes (the
    // keyboard changing `--vv-height`, the panel growing for an error).
    React.useEffect(() =>
      switch canvasRef.current->Nullable.toOption {
      | Some(el) =>
        let report = () => {
          let r = el->Canvas.getBoundingClientRect
          dispatch(ViewSized({w: Canvas.rectWidth(r), h: Canvas.rectHeight(r)}, Canvas.devicePixelRatio))
        }
        report()
        let observer = Canvas.ResizeObserver.make(_ => report())
        observer->Canvas.ResizeObserver.observe(el)
        Some(() => observer->Canvas.ResizeObserver.disconnect)
      | None => None
      }
    , [])

    // Redraw as a pure function of the scene. Deps are the scene's fields
    // (record identity is stable across unrelated model updates).
    React.useEffect(() => {
      switch canvasRef.current->Nullable.toOption {
      | Some(el) => drawScene(el, scene)
      | None => ()
      }
      None
    }, (
      scene.bitmap,
      scene.viewport,
      scene.dims,
      scene.selected,
      scene.pending,
      scene.pendingLabel,
      scene.view,
      scene.dpr,
    ))

    <canvas
      ref={ReactDOM.Ref.domRef(canvasRef)}
      className="annotate-canvas"
      dataTestId="annotate-canvas"
      tabIndex=0
      ariaLabel="Face photo; tap two edges to place a dimension"
      onPointerDown={e => {
        // Capture so moves/ups arrive here even when the finger leaves the
        // canvas — plumbing, not state.
        let id = Canvas.Pointer.pointerId(e)
        e->Canvas.Pointer.currentTarget->Canvas.setPointerCapture(id)
        dispatch(PointerDown(id, localPoint(e)))
      }}
      onPointerMove={e => dispatch(PointerMove(Canvas.Pointer.pointerId(e), localPoint(e)))}
      onPointerUp={e => dispatch(PointerUp(Canvas.Pointer.pointerId(e)))}
      onPointerCancel={e => dispatch(PointerCancel(Canvas.Pointer.pointerId(e)))}
      onClick={_ => dispatch(CanvasClicked)}
    />
  }
}

// ── View ───────────────────────────────────────────────────────────────

let onEnter = (e: JsxEvent.Keyboard.t, then: unit => unit): unit =>
  if JsxEvent.Keyboard.key(e) == "Enter" {
    e->JsxEvent.Keyboard.preventDefault
    then()
  }

let inputValue = (e: JsxEvent.Form.t): string => e->Canvas.Form.target->Canvas.value

let fmt4 = (v: float): string => Float.toFixed(v, ~digits=4)

let pendingPointsText = (p: pending): string =>
  switch (p.p1, p.p2) {
  | (Some(a), Some(b)) => fmt4(a.x) ++ "," ++ fmt4(a.y) ++ ";" ++ fmt4(b.x) ++ "," ++ fmt4(b.y)
  | (Some(a), None) => fmt4(a.x) ++ "," ++ fmt4(a.y)
  | _ => ""
  }

// Test hook (docs/testids.md): every saved dimension's endpoints,
// `id:x1,y1;x2,y2|…` at 4 dp. Ids contain a colon, so split at the last one.
let dimensionPointsText = (dims: array<Types.dimension>): string =>
  dims
  ->Array.map(d =>
    d.id ++ ":" ++ fmt4(d.p1.x) ++ "," ++ fmt4(d.p1.y) ++ ";" ++ fmt4(d.p2.x) ++ "," ++ fmt4(d.p2.y)
  )
  ->Array.join("|")

let errorLine = (testId: string, text: option<string>) =>
  switch text {
  | Some(t) => <p className="field-error" dataTestId=testId> {React.string(t)} </p>
  | None => React.null
  }

// DESIGN.md §5 placement hint, plus the name while a saved dimension is
// being edited (its points are the pending pair, so "Read the caliper"
// would mislead).
let hintText = (m: model, l: loaded): string =>
  switch (m.selected, m.pending.p1, m.pending.p2) {
  | (Some(id), _, _) =>
    switch l.dims->Array.find(d => d.id == id) {
    | Some(d) => "Editing " ++ d.name
    | None => "Read the caliper"
    }
  | (None, None, _) => "Tap the first edge"
  | (None, Some(_), None) => "Tap the second edge"
  | (None, Some(_), Some(_)) => "Read the caliper"
  }

let kindOptions: array<(string, string)> = [("length", "Length"), ("diameter", "Diameter"), ("depth", "Depth")]

// The stage (DESIGN.md §11.2): the canvas on the photo mat, the flat scrim
// toolbar top-right (count, zoom out, zoom readout, zoom in), the placement
// hint top-left, and the hidden test readouts. The canvas wrapper is the
// `role="img"` group of §9's focus order; the toolbar sits outside it so
// its buttons stay real controls.
let stage = (m: model, l: loaded, ~dispatch: msg => unit): React.element => {
  let scene = {
    bitmap: Some(l.bitmap),
    imageW: l.imageW,
    imageH: l.imageH,
    viewport: m.viewport,
    dims: l.dims,
    selected: m.selected,
    pending: m.pending,
    pendingLabel: formatLabel(~name=m.name, ~value=m.reading, ~kind=m.kind),
    view: m.view,
    dpr: m.dpr,
  }
  let count = Array.length(l.dims)
  let zoom = m.fitScale > 0.0 ? m.viewport.scale /. m.fitScale : 1.0
  let groupLabel =
    faceKindLabel(l.face.kind) ++
    " face, " ++
    Int.toString(count) ++ (count == 1 ? " dimension" : " dimensions")
  <div className="annotate-stage">
    <div className="annotate-photo" role="img" ariaLabel=groupLabel>
      <CanvasView scene dispatch />
    </div>
    <div className="annotate-overlay">
      <div className="annotate-tools">
        <Ui.Pill testId="dimension-count"> {React.string(Int.toString(count))} </Ui.Pill>
        <Ui.Button
          variant=Ui.Button.Icon testId="zoom-out" ariaLabel="Zoom out" onClick={_ => dispatch(ZoomOut)}>
          <Icon name=ZoomOut />
        </Ui.Button>
        <Ui.Pill mono=true testId="zoom"> {React.string(Float.toFixed(zoom, ~digits=2))} </Ui.Pill>
        <Ui.Button
          variant=Ui.Button.Icon testId="zoom-in" ariaLabel="Zoom in" onClick={_ => dispatch(ZoomIn)}>
          <Icon name=ZoomIn />
        </Ui.Button>
      </div>
      <div className="annotate-hint"> <Ui.Pill> {React.string(hintText(m, l))} </Ui.Pill> </div>
    </div>
    <span hidden=true dataTestId="pending-points"> {React.string(pendingPointsText(m.pending))} </span>
    <span hidden=true dataTestId="dimension-points" ariaBusy=m.moving>
      {React.string(dimensionPointsText(l.dims))}
    </span>
  </div>
}

// The control area (DESIGN.md §11.1 "Sheets", §11.2): an opaque, in-flow
// `.panel` — reading, name + chips, kind + tolerance, Save, Clear/Delete.
let panel = (m: model, l: loaded, ~dispatch: msg => unit): React.element => {
  let units = NumberParse.unitsLabel(l.part.units)
  let readingError = switch (m.reading, readingResult(m, l)) {
  | ("", _) | (_, Ok(_)) => None
  | (_, Error(e)) => Some(NumberParse.errorMessage(e))
  }
  let nameError = switch (m.name, nameResult(m)) {
  | ("", _) | (_, Ok(_)) => None
  | (_, Error(e)) => Some(FeatureName.errorMessage(e))
  }
  let toleranceError = switch (m.tolerance, toleranceResult(m, l)) {
  | ("", _) | (_, Ok(_)) => None
  | (_, Error(e)) => Some(NumberParse.errorMessage(e))
  }
  let editing = m.selected->Option.isSome
  let nothingToClear = !editing && m.pending.p1->Option.isNone && m.reading == "" && m.name == ""

  <div className="panel annotate-panel">
    <Ui.Field label="Reading" htmlFor="annotate-reading" mono=true error=?readingError errorTestId="reading-error">
      <div className="annotate-reading">
        {Canvas.Input.make({
          dataTestId: "reading",
          id: "annotate-reading",
          type_: "text",
          inputMode: "decimal",
          enterKeyHint: "next",
          autoComplete: "off",
          placeholder: switch l.part.units {
          | Mm => "0.00"
          | Inch => "0.000"
          },
          ariaInvalid: readingError->Option.isSome,
          value: m.reading,
          onChange: e => dispatch(ReadingChanged(inputValue(e))),
          onKeyDown: e => onEnter(e, () => dispatch(ReadingEnter)),
        })}
        <span className="annotate-unit" dataTestId="reading-units"> {React.string(units)} </span>
      </div>
    </Ui.Field>
    <div className="annotate-name">
      <Ui.Field label="Name" htmlFor="annotate-name" mono=true error=?nameError errorTestId="name-error">
        {Canvas.Input.make({
          dataTestId: "name",
          id: "annotate-name",
          type_: "text",
          autoCapitalize: "none",
          autoCorrect: "off",
          autoComplete: "off",
          spellCheck: false,
          enterKeyHint: "done",
          placeholder: "feature_name",
          ariaInvalid: nameError->Option.isSome,
          value: m.name,
          onChange: e => dispatch(NameChanged(inputValue(e))),
          onKeyDown: e => onEnter(e, () => dispatch(NameEnter)),
        })}
      </Ui.Field>
      <Ui.ChipRow>
        {l.suggestions
        ->Array.map(s =>
          <Ui.Chip key=s selected={m.name == s} testId="name-chip" onClick={_ => dispatch(ChipTapped(s))}>
            {React.string(s)}
          </Ui.Chip>
        )
        ->React.array}
      </Ui.ChipRow>
    </div>
    <div className="annotate-kind-row">
      <div className="field annotate-kind">
        <span className="field-label" ariaHidden=true> {React.string("Kind")} </span>
        <Ui.Segmented
          options=kindOptions
          selected={Enums.dimensionKindToString(m.kind)}
          onSelect={key =>
            switch Enums.dimensionKindFromString(key) {
            | Some(kind) => dispatch(KindChosen(kind))
            | None => ()
            }}
          testIdPrefix="kind-"
          ariaLabel="Kind"
        />
      </div>
      <Ui.Field label="Tolerance" htmlFor="annotate-tolerance" mono=true>
        <div className="annotate-tolerance">
          <span className="annotate-unit" ariaHidden=true> {React.string("±")} </span>
          {Canvas.Input.make({
            dataTestId: "tolerance",
            id: "annotate-tolerance",
            type_: "text",
            inputMode: "decimal",
            autoComplete: "off",
            ariaLabel: "Tolerance, ± " ++ units,
            ariaInvalid: toleranceError->Option.isSome,
            value: m.tolerance,
            onChange: e => dispatch(ToleranceChanged(inputValue(e))),
          })}
          <span className="annotate-unit"> {React.string(units)} </span>
        </div>
      </Ui.Field>
    </div>
    // The tolerance message sits under the whole row: its column is too
    // narrow for a sentence.
    {errorLine("tolerance-error", toleranceError)}
    {errorLine("annotate-error", m.error)}
    <div className="annotate-actions">
      <Ui.Button
        variant=Ui.Button.Primary
        block=true
        testId="save"
        disabled={!canSave(m, l)}
        onClick={_ => dispatch(SaveClicked)}>
        {React.string(editing ? "Update" : "Save dimension")}
      </Ui.Button>
      <div className="annotate-actions-row">
        <Ui.Button
          variant=Ui.Button.Small
          testId="cancel"
          disabled=nothingToClear
          onClick={_ => dispatch(CancelClicked)}>
          {React.string("Clear")}
        </Ui.Button>
        {editing
          ? <Ui.Button
              variant=Ui.Button.Danger testId="delete" disabled=m.busy onClick={_ => dispatch(DeleteClicked)}>
              {React.string("Delete")}
            </Ui.Button>
          : React.null}
      </div>
    </div>
    // DESIGN.md §9: "Dimension saved: name value" after a save. Always in
    // the tree so assistive tech is already listening when the text lands.
    <p className="visually-hidden" ariaLive=#polite dataTestId="annotate-live">
      {React.string(m.announcement)}
    </p>
  </div>
}

let view = (m: model, ~dispatch: msg => unit): React.element =>
  switch m.status {
  // DESIGN.md §7: the only real load is the image decode — the photo mat
  // with a centred pill, no spinner.
  | Loading =>
    <div className="annotate">
      <div className="annotate-stage annotate-stage-empty">
        <Ui.Pill> {React.string("Decoding…")} </Ui.Pill>
      </div>
    </div>
  | NotFound(why) =>
    <div className="stack annotate-missing">
      <p className="help-text" dataTestId="annotate-missing"> {React.string(why)} </p>
      <a className="btn btn-secondary" href={Route.href(Route.Part(m.partId))}>
        {React.string("Back to part")}
      </a>
    </div>
  | Ready(l) =>
    <div className="annotate">
      {stage(m, l, ~dispatch)}
      {panel(m, l, ~dispatch)}
    </div>
  }
