// A2hsHint — the "Add to Home Screen" nudge (SPEC M6 first checkbox): shown
// once on iOS Safari when the app isn't already installed, dismissible,
// remembered in localStorage. Rendered as an opaque card docked under the
// shell (DESIGN.md §11: no `fixed`, no glass outside the nav bar).
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
      <span className="a2hs-hint-icon"> <Icon name=Share size=20 /> </span>
      <p className="a2hs-hint-text">
        {React.string(
          "Tap Share, then \"Add to Home Screen\" — Caliper Companion works offline once installed.",
        )}
      </p>
      <Ui.Button variant=Small onClick={dismiss} testId="a2hs-later">
        <span className="a2hs-hint-dismiss"> {React.string("Later")} </span>
      </Ui.Button>
    </div>
  }
}
