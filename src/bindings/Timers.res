// Timers — `setInterval` binding (SPEC M6: the Part page ticks its
// hands-on-timer display once per second while the timer is running).
//
// No `%raw`, no `Obj.magic`. Real `external`s only.

type intervalId

@val external setInterval: (unit => unit, int) => intervalId = "setInterval"
@val external clearInterval: intervalId => unit = "clearInterval"

// A `Tea.cmd` that dispatches `msg` once a second, forever. `Part.res`
// starts this unconditionally from `init` — see LOGBOOK.md ("fine to leave
// the interval running"): `Main.res`'s catch-all `| _ => (model, Tea.none)`
// branch makes a stray tick harmless once the user navigates to another
// page, so there is no matching `clearInterval` call in v0.
let everySecond = (msg: 'msg): Tea.cmd<'msg> =>
  Tea.effect(dispatch => {
    let _id = setInterval(() => dispatch(msg), 1000)
    ()
  })
