// Motion — the one animated dispatch (SPEC §8a A16, review B2). `Tea.res`
// stays DOM-free; `Route.subscribe` is the only caller: every `hashchange`
// (the Back chevron, folder rows, `Route.push`, the browser's own
// back/forward) dispatches through `transition`, which wraps the dispatch in
// `document.startViewTransition` so the CSS keyed on `html[data-nav]` can
// slide the old and new root snapshots. Unsupported → the plain dispatch, no
// attribute, no animation.
//
// The update callback is *asynchronous*: it runs at the next rendering
// opportunity, after microtasks, `setTimeout(0)` and rAF (measured 3–38 ms),
// so the model lags the URL by about one frame. Two hash changes in flight
// (a Back double-tap): the first transition's `ready` rejects `AbortError`,
// its callback still runs, its `finished` fulfils, and only then does the
// second callback run — a cleanup keyed on "my `finished`" would strip the
// second transition's `data-nav` before its animations exist (measured: the
// pseudos fall back to the UA 250 ms crossfade). Hence the generation
// counter: clear only if no newer transition has started. `finished` also
// rejects when the callback throws (`dispatch` → `update`), so `clear` runs
// on both branches.
//
// `Tea.use` runs cmds synchronously inside `dispatch`, before the commit —
// the same order as today, so nothing regresses; a cmd that calls
// `Route.push` from inside the callback starts a second transition that
// skips this one (its callback still runs) — acceptable.

let gen = ref(0)

let transition = (~nav: string, dispatch: 'msg => unit, msg: 'msg): unit =>
  if !WebApi.ViewTransition.supported() {
    dispatch(msg)
  } else {
    gen := gen.contents + 1
    let mine = gen.contents
    WebApi.Document.setDataNav(nav) // before `start`: the old capture and the CSS must see it
    let clear = _ => {
      if gen.contents == mine {
        WebApi.Document.removeDataNav()
      }
      Promise.resolve()
    }
    WebApi.ViewTransition.start(WebApi.ViewTransition.document, () =>
      WebApi.flushSync(() => dispatch(msg))
    )
    ->WebApi.ViewTransition.finished
    ->Promise.then(clear)
    ->Promise.catch(clear)
    ->ignore
  }
