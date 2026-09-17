// Ui — small typed components over global.css's shared classes (DESIGN.md
// §4/§6/§11), so pages don't hand-write class strings. Every component is
// dumb: props in, JSX out. `testId` lands on the element as `data-testid`
// (the e2e contract in docs/testids.md). Icons come from `Icon`.

// Capsule buttons (§11.1 "Shape"). `disabled` renders `aria-disabled` rather
// than the native attribute so the button stays focusable and its reason can
// be read (§6); the click is swallowed here. Playwright's `toBeDisabled()`
// honours `aria-disabled` on buttons.
module Button = {
  // `Small` stays as a deprecated alias for the old combined variant+size
  // (renders exactly "btn btn-small", unchanged) — pages this track doesn't
  // own (`Annotate.res`, `A2hsHint.res`) still pass it. New call sites
  // should use a colour variant with `~size=Small` instead, which composes
  // the compact metrics with any variant's colours via `.btn-compact`
  // rather than baking a colour into the size.
  type variant = Primary | Secondary | Danger | Plain | Small | Icon
  type size = Regular | Small

  let baseClassName = (variant: variant, ~size: size, ~block: bool): string => {
    let variantClass = switch variant {
    | Primary => "btn btn-primary"
    | Secondary => "btn btn-secondary"
    | Danger => "btn btn-danger"
    | Plain => "btn btn-plain"
    | Small => "btn btn-small"
    | Icon => "btn btn-icon"
    }
    let sizedClass = switch (size, variant) {
    // Icon and the deprecated Small variant already carry their own
    // compact sizing; don't double it up.
    | (Small, Icon) | (Small, Small) => variantClass
    | (Small, _) => variantClass ++ " btn-compact"
    | (Regular, _) => variantClass
    }
    block ? sizedClass ++ " btn-block" : sizedClass
  }

  @react.component
  let make = (
    ~variant: variant=Secondary,
    ~size: size=Regular,
    ~block: bool=false,
    ~disabled: bool=false,
    ~onClick: option<JsxEvent.Mouse.t => unit>=?,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~type_: string="button",
    ~className: option<string>=?,
    ~children: React.element,
  ) => {
    let base = baseClassName(variant, ~size, ~block)
    let full = switch className {
    | Some(extra) => base ++ " " ++ extra
    | None => base
    }
    <button
      type_
      className=full
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
// Full width by default (a segmented bar reads as a tiny content-hugging
// blob otherwise inside any flex row — see the report); pass `~inline` to
// size it to its content instead.
module Segmented = {
  @react.component
  let make = (
    ~options: array<(string, string)>,
    ~selected: string,
    ~onSelect: string => unit,
    ~inline: bool=false,
    ~testIdPrefix: option<string>=?,
    ~ariaLabel: option<string>=?,
  ) =>
    <div
      className={inline ? "segmented segmented-inline" : "segmented"} role="group" ariaLabel=?ariaLabel>
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
// uppercase header and footnote footer. `~asList` (DESIGN.md §9 "Semantics":
// "lists are <ul>/<li> or role=list") marks the container `role="list"` —
// true for a container of *repeating same-kind items* (parts, faces,
// timers); left `false` (default) when `ListGroup` is instead grouping form
// fields or wrapping a `<table>` (Part.res's features section), where a
// list role would misdescribe the content. `Ui.ListRow` below always
// carries `role="listitem"` since that component's whole purpose is "one
// row of a list" — safe even where the enclosing container isn't marked
// `asList` (an orphaned `listitem` is tolerated, never wrong).
module ListGroup = {
  @react.component
  let make = (
    ~header: option<string>=?,
    ~footer: option<string>=?,
    ~asList: bool=false,
    ~testId: option<string>=?,
    ~children: React.element,
  ) =>
    <section className="list-group-section">
      {switch header {
      | Some(text) => <h2 className="list-group-header"> {React.string(text)} </h2>
      | None => React.null
      }}
      <div className="list-group" role=?{asList ? Some("list") : None} dataTestId=?testId>
        children
      </div>
      {switch footer {
      | Some(text) => <p className="list-group-footer"> {React.string(text)} </p>
      | None => React.null
      }}
    </section>
}

// One row. With `onClick` it is a real <button> (pressed highlight, 44 px);
// with `href` the body (+ chevron) is a real <a>, `leading`/`trailing` sit
// outside it as plain siblings so nothing nests a <button> inside an <a> —
// invalid HTML, and it's how a row gets sibling actions (e.g. Rename/Delete)
// next to a navigable title without wrapping the whole row in a button (see
// the report). With neither, a plain <div>. `leading` is the 52 px
// thumbnail slot, `trailing` one or more actions/a value; `chevron` marks a
// navigable row. Children are the body: use `ListRow.Title` / `ListRow.Meta`
// for the two standard lines.
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
    ~href: option<string>=?,
    ~chevron: bool=false,
    ~testId: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~leading: option<React.element>=?,
    ~trailing: option<React.element>=?,
    ~children: React.element,
  ) => {
    let leadingEl = switch leading {
    | Some(el) => el
    | None => React.null
    }
    let chevronEl =
      chevron
        ? <span className="list-row-chevron"> <Icon name=ChevronRight size=20 /> </span>
        : React.null
    let trailingEl = switch trailing {
    | Some(el) => <span className="list-row-trailing"> el </span>
    | None => React.null
    }
    switch href {
    | Some(url) =>
      // The anchor is its own flex ROW (`.list-row-link`, in global.css next
      // to `.list-row-body`) holding the text stack + chevron side by side —
      // NOT `.list-row-body` itself, which is a flex COLUMN (Title over
      // Meta). Nesting the chevron straight into a column would stack it
      // under the meta line as a third line instead of sitting beside the
      // text.
      <div className="list-row" role="listitem" dataTestId=?testId ariaLabel=?ariaLabel>
        leadingEl
        <a className="list-row-link" href=url>
          <span className="list-row-body"> children </span>
          chevronEl
        </a>
        trailingEl
      </div>
    | None =>
      let body =
        <>
          leadingEl
          <span className="list-row-body"> children </span>
          trailingEl
          chevronEl
        </>
      switch onClick {
      | Some(handler) =>
        <button
          type_="button"
          className="list-row"
          role="listitem"
          onClick=handler
          dataTestId=?testId
          ariaLabel=?ariaLabel>
          body
        </button>
      | None =>
        <div className="list-row" role="listitem" dataTestId=?testId ariaLabel=?ariaLabel> body </div>
      }
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
    ~after: option<React.element>=?,
    ~children: React.element,
  ) => {
    let className =
      "field" ++ (mono ? " field-mono" : "") ++ (error->Option.isSome ? " field-invalid" : "")
    <div className>
      <label className="field-label" htmlFor=?htmlFor> {React.string(label)} </label>
      children
      {switch after {
      | Some(el) => el
      | None => React.null
      }}
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
        className="toggle-input"
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
  let make = (
    ~mono: bool=false,
    ~testId: option<string>=?,
    ~className: option<string>=?,
    ~ariaLabel: option<string>=?,
    ~children: React.element,
  ) => {
    let base = mono ? "pill pill-mono" : "pill"
    let full = switch className {
    | Some(extra) => base ++ " " ++ extra
    | None => base
    }
    <span className=full dataTestId=?testId ariaLabel=?ariaLabel> children </span>
  }
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

// Visually hidden `aria-live="polite"` status line (DESIGN.md §9): mount it
// once per page (unconditionally — never behind an `option`/`switch`) and
// pass the current announcement as `~text`. A screen reader announces a
// live region's *content changes*, not its initial mount, so a region that
// only appears once there's something to say never gets heard; `""` is the
// silent/idle state, not "don't render". Modelled on Annotate.res's own
// `annotate-live` (design wave 2), pulled up into `Ui.res` here since every
// page this track owns needs its own copy of the same pattern.
module Live = {
  @react.component
  let make = (~text: string, ~testId: option<string>=?) =>
    <p className="visually-hidden" role="status" ariaLive=#polite dataTestId=?testId>
      {React.string(text)}
    </p>
}
