// Tea — a minimal Elm-architecture runtime over React.
//
// One model, one `msg` variant, `update: (model, msg) => (model, cmd<msg>)`,
// and a pure `view`. Side effects never run inside `update` or `view`: `update`
// *describes* them as a `cmd`, and the runtime executes them after the model
// has been advanced, handing each effect a `dispatch` to feed results back in.
//
// Why not `React.useReducer` directly: reducers must be pure, so commands
// would have to be smuggled out through state and drained in an effect.
// Holding the model in a ref and advancing it synchronously inside `dispatch`
// keeps ordering deterministic (a cmd always sees the model that produced it)
// and needs no drain step. `dispatch` is stable for the component's lifetime.

type rec cmd<'msg> =
  | NoCmd
  | Batch(array<cmd<'msg>>)
  /// Run an arbitrary effect; call the supplied dispatch zero or more times.
  | Effect(('msg => unit) => unit)

let none: cmd<'msg> = NoCmd

let batch = (cmds: array<cmd<'msg>>): cmd<'msg> => Batch(cmds)

let effect = (run: ('msg => unit) => unit): cmd<'msg> => Effect(run)

/// A promise that resolves to a msg. Rejections go to `onError`.
let fromPromise = (p: unit => promise<'a>, onOk: 'a => 'msg, onError: exn => 'msg): cmd<'msg> =>
  Effect(
    dispatch => {
      p()
      ->Promise.then(a => {
        dispatch(onOk(a))
        Promise.resolve()
      })
      ->Promise.catch(e => {
        dispatch(onError(e))
        Promise.resolve()
      })
      ->ignore
    },
  )

/// Dispatch a msg on the next turn (after the current update has committed).
let msg = (m: 'msg): cmd<'msg> => Effect(dispatch => dispatch(m))

let rec map = (c: cmd<'a>, f: 'a => 'b): cmd<'b> =>
  switch c {
  | NoCmd => NoCmd
  | Batch(cs) => Batch(cs->Array.map(x => map(x, f)))
  | Effect(run) => Effect(dispatch => run(a => dispatch(f(a))))
  }

let rec run = (c: cmd<'msg>, dispatch: 'msg => unit): unit =>
  switch c {
  | NoCmd => ()
  | Batch(cs) => cs->Array.forEach(x => run(x, dispatch))
  | Effect(go) => go(dispatch)
  }

type runtime<'model, 'msg> = {
  model: 'model,
  dispatch: 'msg => unit,
}

/// Mount a TEA program. `init` runs once; its cmd runs after first render.
let use = (
  ~init: unit => ('model, cmd<'msg>),
  ~update: ('model, 'msg) => ('model, cmd<'msg>),
): runtime<'model, 'msg> => {
  let initial = React.useMemo(() => init(), [])
  let (initModel, initCmd) = initial
  let modelRef = React.useRef(initModel)
  let (model, setModel) = React.useState(() => initModel)
  let updateRef = React.useRef(update)
  updateRef.current = update
  let dispatch = React.useMemo(() => {
    let rec dispatch = (m: 'msg) => {
      let (next, cmd) = updateRef.current(modelRef.current, m)
      modelRef.current = next
      setModel(_ => next)
      run(cmd, dispatch)
    }
    dispatch
  }, [])
  React.useEffect(() => {
    run(initCmd, dispatch)
    None
  }, [])
  {model, dispatch}
}
