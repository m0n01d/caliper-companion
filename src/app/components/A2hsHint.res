// A2hsHint — the "Add to Home Screen" nudge (SPEC M6 first checkbox): shown
// once on iOS Safari when the app isn't already installed, dismissible,
// remembered in localStorage.
//
// Judgment call (see LOGBOOK.md): this is a plain React component with its
// own `useState`, not a TEA page under `pages/`. Its "model" is a single
// value — visible or not — computed once from platform checks that never
// change during the component's life (device type, install state at mount)
// plus one dismiss action; routing it through a full model/msg/update page
// would be ceremony with nothing left for `update` to do. It also must not
// depend on the Store (SPEC M2 owns that), which localStorage sidesteps.

let storageKey = "cc.a2hsHintShown"

let hasBeenShown = (): bool =>
  WebApi.LocalStorage.storage->WebApi.LocalStorage.getItem(storageKey)->Null.toOption->Option.isSome

let shouldOffer = (): bool =>
  WebApi.Platform.isIos() && !WebApi.Platform.isStandalone() && !hasBeenShown()

@react.component
let make = () => {
  let (visible, setVisible) = React.useState(() => shouldOffer())

  let dismiss = _event => {
    WebApi.LocalStorage.storage->WebApi.LocalStorage.setItem(storageKey, "1")
    setVisible(_ => false)
  }

  if !visible {
    React.null
  } else {
    <div className="a2hs-hint" role="note">
      <p className="a2hs-hint-text">
        {React.string(
          "Tap Share, then \"Add to Home Screen\" — Caliper Companion works offline once installed.",
        )}
      </p>
      <button type_="button" className="a2hs-hint-dismiss" ariaLabel="Dismiss" onClick={dismiss}>
        {React.string("×")}
      </button>
    </div>
  }
}
