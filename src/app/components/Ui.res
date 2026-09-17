// Ui — small typed components over global.css's shared classes (DESIGN.md
// §4/§6/§11), so pages don't hand-write class strings. Every component is
// dumb: props in, JSX out. `testId` lands on the element as `data-testid`
// (the e2e contract in docs/testids.md). Icons come from `Icon`.

// Capsule buttons (§11.1 "Shape"). `disabled` renders `aria-disabled` rather
// than the native attribute so the button stays focusable and its reason can
// be read (§6); the click is swallowed here. Playwright's `toBeDisabled()`
// honours `aria-disabled` on buttons.
module Button = {
  type variant = Primary | Secondary | Danger | Small | Icon

  let className = (variant: variant, ~block: bool): string => {
    let base = switch variant {
    | Primary => "btn btn-primary"
    | Secondary => "btn btn-secondary"
    | Danger => "btn btn-danger"
    | Small => "btn btn-small"
    | Icon => "btn btn-icon"
    }
    block ? base ++ " btn-block" : base
  }

  @react.component
  let make = (
    ~variant: variant=Secondary,
    ~block: bool=false,
    ~disabled: bool=false,
    ~onClick: option<JsxEvent.Mouse.t => unit>=?,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~type_: string="button",
    ~children: React.element,
  ) =>
    <button
      type_
      className={className(variant, ~block)}
      ariaDisabled=?{disabled ? Some(true) : None}
      dataTestId=?testId
      ariaLabel=?ariaLabel
      onClick={evt =>
        if !disabled {
          switch onClick {
          | Some(handler) => handler(evt)
          | None => ()
          }
        }}>
      children
    </button>
}

// Selectable capsule chip (§4): 36 px for name suggestions, `large` = 44 px
// for the face picker. Selection is `aria-pressed`, which the CSS reads.
module Chip = {
  @react.component
  let make = (
    ~selected: bool=false,
    ~large: bool=false,
    ~onClick: option<JsxEvent.Mouse.t => unit>=?,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~children: React.element,
  ) =>
    <button
      type_="button"
      className={large ? "chip chip-lg" : "chip"}
      ariaPressed={selected ? #"true" : #"false"}
      dataTestId=?testId
      ariaLabel=?ariaLabel
      onClick=?onClick>
      children
    </button>
}

// Horizontal chip strip (scrolls) or wrapping strip (`wrap`).
module ChipRow = {
  @react.component
  let make = (~wrap: bool=false, ~testId: option<string>=?, ~children: React.element) =>
    <div className={wrap ? "chip-row chip-row-wrap" : "chip-row"} dataTestId=?testId> children </div>
}

// Segmented control (§4, §11.1): `options` are (key, label); `testIdPrefix`
// gives each option `data-testid={prefix ++ key}` (e.g. "kind-" → "kind-length").
module Segmented = {
  @react.component
  let make = (
    ~options: array<(string, string)>,
    ~selected: string,
    ~onSelect: string => unit,
    ~testIdPrefix: option<string>=?,
    ~ariaLabel: option<string>=?,
  ) =>
    <div className="segmented" role="group" ariaLabel=?ariaLabel>
      {options
      ->Array.map(((key, label)) =>
        <button
          key
          type_="button"
          className="segmented-option"
          ariaPressed={key == selected ? #"true" : #"false"}
          dataTestId=?{testIdPrefix->Option.map(prefix => prefix ++ key)}
          onClick={_ => onSelect(key)}>
          {React.string(label)}
        </button>
      )
      ->React.array}
    </div>
}

// Inset grouped list container (§11.1 "Layout"), with the optional iOS-style
// uppercase header and footnote footer.
module ListGroup = {
  @react.component
  let make = (
    ~header: option<string>=?,
    ~footer: option<string>=?,
    ~testId: option<string>=?,
    ~children: React.element,
  ) =>
    <section className="list-group-section">
      {switch header {
      | Some(text) => <h2 className="list-group-header"> {React.string(text)} </h2>
      | None => React.null
      }}
      <div className="list-group" dataTestId=?testId> children </div>
      {switch footer {
      | Some(text) => <p className="list-group-footer"> {React.string(text)} </p>
      | None => React.null
      }}
    </section>
}

// One row. With `onClick` it is a real <button> (pressed highlight, 44 px);
// without, a plain <div>. `leading` is the 52 px thumbnail slot, `trailing`
// a toggle/value; `chevron` marks a navigable row. Children are the body:
// use `ListRow.Title` / `ListRow.Meta` for the two standard lines.
module ListRow = {
  module Title = {
    @react.component
    let make = (~children: React.element) => <span className="list-row-title"> children </span>
  }

  module Meta = {
    @react.component
    let make = (~live: bool=false, ~children: React.element) =>
      <span className={live ? "list-row-meta list-row-meta-live" : "list-row-meta"}> children </span>
  }

  @react.component
  let make = (
    ~onClick: option<JsxEvent.Mouse.t => unit>=?,
    ~chevron: bool=false,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~leading: option<React.element>=?,
    ~trailing: option<React.element>=?,
    ~children: React.element,
  ) => {
    let body =
      <>
        {switch leading {
        | Some(el) => el
        | None => React.null
        }}
        <span className="list-row-body"> children </span>
        {switch trailing {
        | Some(el) => <span className="list-row-trailing"> el </span>
        | None => React.null
        }}
        {chevron
          ? <span className="list-row-chevron"> <Icon name=ChevronRight size=20 /> </span>
          : React.null}
      </>
    switch onClick {
    | Some(handler) =>
      <button
        type_="button" className="list-row" onClick=handler dataTestId=?testId ariaLabel=?ariaLabel>
        body
      </button>
    | None => <div className="list-row" dataTestId=?testId ariaLabel=?ariaLabel> body </div>
    }
  }
}

// 52 px thumbnail for a list row's leading slot; `src` None = placeholder.
module ListThumb = {
  @react.component
  let make = (~src: option<string>, ~alt: string="") =>
    switch src {
    | Some(url) => <img className="list-thumb" src=url alt />
    | None => <span className="list-thumb" ariaHidden=true />
    }
}

// Labelled field wrapper (§4 text input): Caption 1 label above, the input as
// children, Footnote error / help below. `mono` switches the input to the
// mono stack (readings, feature names). Give the input the `id` in `htmlFor`.
module Field = {
  @react.component
  let make = (
    ~label: string,
    ~htmlFor: option<string>=?,
    ~error: option<string>=?,
    ~help: option<string>=?,
    ~mono: bool=false,
    ~errorTestId: option<string>=?,
    ~children: React.element,
  ) => {
    let className =
      "field" ++ (mono ? " field-mono" : "") ++ (error->Option.isSome ? " field-invalid" : "")
    <div className>
      <label className="field-label" htmlFor=?htmlFor> {React.string(label)} </label>
      children
      {switch error {
      | Some(text) => <p className="field-error" dataTestId=?errorTestId> {React.string(text)} </p>
      | None => React.null
      }}
      {switch help {
      | Some(text) => <p className="help-text"> {React.string(text)} </p>
      | None => React.null
      }}
    </div>
  }
}

// System-style switch (§11.2 Settings): a real, visually hidden checkbox
// drives the 52×32 track. `onChange` receives the new value.
module Toggle = {
  @react.component
  let make = (
    ~checked: bool,
    ~onChange: bool => unit,
    ~disabled: bool=false,
    ~id: option<string>=?,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
  ) =>
    <label className="toggle">
      <input
        type_="checkbox"
        className="visually-hidden"
        checked
        disabled
        id=?id
        dataTestId=?testId
        ariaLabel=?ariaLabel
        onChange={_ => onChange(!checked)}
      />
      <span className="toggle-track" ariaHidden=true> <span className="toggle-knob" /> </span>
    </label>
}

// Flat scrim pill over the photo (§4): hints, or `mono` for the teal
// readout. Never glass — it sits on the live canvas.
module Pill = {
  @react.component
  let make = (~mono: bool=false, ~testId: option<string>=?, ~children: React.element) =>
    <span className={mono ? "pill pill-mono" : "pill"} dataTestId=?testId> children </span>
}

// Warning row (§4): Teal = reconciliation note (check icon), Error = kind
// conflict (alert icon). With `onClick` it is a button (§6: tap scrolls the
// table to the flagged rows).
module WarningRow = {
  type tone = Teal | Error

  @react.component
  let make = (
    ~tone: tone=Teal,
    ~onClick: option<JsxEvent.Mouse.t => unit>=?,
    ~testId: option<string>=?,
    ~children: React.element,
  ) => {
    let (className, icon) = switch tone {
    | Teal => ("warning-row", <Icon name=CircleCheck size=20 />)
    | Error => ("warning-row warning-row-error", <Icon name=TriangleAlert size=20 />)
    }
    let body =
      <>
        <span className="warning-row-icon"> icon </span>
        <span className="warning-row-text"> children </span>
      </>
    switch onClick {
    | Some(handler) =>
      <button type_="button" className onClick=handler dataTestId=?testId> body </button>
    | None => <div className dataTestId=?testId> body </div>
    }
  }
}
