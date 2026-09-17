// Orientation — `DeviceOrientationEvent` permission + listener bindings for
// the on-screen level indicator (SPEC M3 bullet 3). House style matches
// WebApi.res: `Nullable.t` at every boundary that can be `undefined`.
//
// iOS 13+ gates `deviceorientation` behind an explicit, promise-returning
// `DeviceOrientationEvent.requestPermission()` static method that must be
// called from inside a user-gesture handler. That method exists on no
// other platform, so it can't be called unguarded (`@val` straight to a
// name that's `undefined` elsewhere would throw at the call site) — it's
// read as a `Nullable.t<...>` property off the constructor and only
// invoked when present, exactly as CLAUDE.md's iOS-rules section asks.

// -- requestPermission (iOS 13+ only) --------------------------------------

type permissionState = Granted | Denied

let permissionStateFromString = (s: string): option<permissionState> =>
  switch s {
  | "granted" => Some(Granted)
  | "denied" => Some(Denied)
  | _ => None
  }

type eventCtor

// `undefined` in server-side/non-DOM contexts; always present as a
// constructor in a browser, but the `requestPermission` property on it
// (read below) is the real feature-detection signal.
@val external eventCtor: Nullable.t<eventCtor> = "DeviceOrientationEvent"

@get
external requestPermissionFn: eventCtor => Nullable.t<unit => promise<string>> = "requestPermission"

let isRequestPermissionAvailable = (): bool =>
  switch eventCtor->Nullable.toOption {
  | None => false
  | Some(ctor) => requestPermissionFn(ctor)->Nullable.toOption->Option.isSome
  }

// Callers must check `isRequestPermissionAvailable` first (this app calls
// it only from a user-gesture handler, per the iOS requirement) — calling
// this where the function is absent resolves `None` rather than throwing.
let requestPermission = (): promise<option<permissionState>> =>
  switch eventCtor->Nullable.toOption {
  | None => Promise.resolve(None)
  | Some(ctor) =>
    switch requestPermissionFn(ctor)->Nullable.toOption {
    | None => Promise.resolve(None)
    | Some(fn) => fn()->Promise.then(s => Promise.resolve(permissionStateFromString(s)))
    }
  }

// -- deviceorientation listener ---------------------------------------------

type event

@val @scope("window") external addEventListener: (string, event => unit) => unit = "addEventListener"
@val @scope("window")
external removeEventListener: (string, event => unit) => unit = "removeEventListener"

// Both nullable per the DOM spec: unsupported axes (rare) or a sensor that
// hasn't reported yet on a given event.
@get external beta: event => Nullable.t<float> = "beta"
@get external gamma: event => Nullable.t<float> = "gamma"

// Adds a `deviceorientation` listener that calls `onSample` with each raw
// (beta, gamma) reading; returns an unsubscribe function. No throttling
// here — the DOM fires this event as fast as the sensor updates (can be
// 30–60/s), so the caller throttles before turning a sample into a `Tea`
// dispatch (SPEC M3: "~4/s").
let subscribe = (onSample: (option<float>, option<float>) => unit): (unit => unit) => {
  let handler = (e: event) => onSample(beta(e)->Nullable.toOption, gamma(e)->Nullable.toOption)
  addEventListener("deviceorientation", handler)
  () => removeEventListener("deviceorientation", handler)
}
