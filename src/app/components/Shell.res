// Shell — the persistent page chrome (CLAUDE.md "Layout", DESIGN.md §11.1
// "Layout"/"Materials"): the one glass navigation bar (sticky inside `.shell`,
// the scroll container — never `fixed`), with a chevron back button, a
// centred Headline title (or, on the root screen, a static Large Title in
// the content flow), an optional Footnote subtitle, a trailing actions slot,
// and the content area, plus a leading slot that root screens (no back
// button) use for a navigation control, and a footer slot (SPEC §8a A12b,
// review B1): a sibling *after* `<main>` directly inside `.shell`, so a
// page's bottom toolbar can be `position: sticky; bottom: 0` against the
// scroll container — `main` is `flex: 1 1 auto`, so a short page still
// pushes it to the bottom edge. It is the second glass surface (DESIGN.md
// §11.1 "Materials"), styled by `.shell-footer` in global.css; the page
// supplies only the contents. `Main.res` wraps every page's view in one.

// SPEC §8a A16 (review S3): `Main` renders one `<Shell>`, so `.shell` — the
// scroll container — and its `scrollTop` persist across pages; a push from
// a scrolled list would snapshot the new screen scrolled. Every cross-page
// `RouteChanged` and `PartsList.FolderChanged` batches this. It runs inside
// `dispatch`, before the commit, which is fine because the element
// persists; the new screen is therefore snapshotted at the top. A
// constructor applied to a lambda, not `Tea.effect(...)`, so the value
// generalises over 'msg (the value restriction) and every page can use it.
let scrollToTop: Tea.cmd<'msg> = Tea.Effect(
  _dispatch =>
    switch Canvas.querySelector(".shell") {
    | Some(el) => Canvas.setScrollTop(el, 0)
    | None => ()
    },
)

// SPEC §8a A17 (review S2): the reading column is the Shell's, not the
// page's — `.shell-content` is one element here that a page cannot reach,
// and the pages want three widths. `Main.view` maps each page to one of
// these beside `largeTitle`; global.css §16 reads it as `data-column` on
// `.shell` and sets `--col` from it (720 / 560 / 1120-at-expanded / 100%).
// Nothing at compact: every column rule sits under a `min-width` query.
type column = Column | Narrow | Wide | Bleed

let columnName = (column: column): string =>
  switch column {
  | Column => "column"
  | Narrow => "narrow"
  | Wide => "wide"
  | Bleed => "bleed"
  }

// `.shell` carries `data-column`, which `JsxDOM.domProps` cannot express —
// so the root goes through the jsx-runtime call with exactly the
// attributes it needs, the `PathDiv` route (PartsList.res, `Ui.Segmented`).
module Root = {
  type props = {
    className: string,
    @as("data-column") dataColumn: string,
    children: React.element,
  }

  @module("react/jsx-runtime") external jsx: (string, props) => React.element = "jsx"

  let make = (props: props): React.element => jsx("div", props)
}

@react.component
let make = (
  ~title: string,
  ~back: option<Route.t>,
  ~column: column=Column,
  ~actions: option<React.element>=?,
  ~largeTitle: bool=false,
  ~subtitle: option<string>=?,
  ~leading: option<React.element>=?,
  ~footer: option<React.element>=?,
  ~children: React.element,
) => {
  let subtitleEl = switch subtitle {
  | Some(text) => <p className="shell-subtitle"> {React.string(text)} </p>
  | None => React.null
  }
  Root.make({
    className: "shell",
    dataColumn: columnName(column),
    children: <>
      <header className="shell-topbar">
        <div className="shell-topbar-leading">
          {switch (back, leading) {
          | (Some(route), _) =>
            <button
              type_="button"
              className="btn btn-icon shell-back"
              ariaLabel="Back"
              onClick={_ => Tea.run(Route.push(route), _msg => ())}>
              <Icon name=ChevronLeft />
            </button>
          // Root screens have nowhere to go back to, so the leading slot is
          // free for one navigation control (HIG: a bar button on the root).
          | (None, Some(el)) => el
          | (None, None) => React.null
          }}
        </div>
        <div className="shell-topbar-center">
          {largeTitle
            ? React.null
            : <>
                <h1 className="shell-title"> {React.string(title)} </h1>
                subtitleEl
              </>}
        </div>
        <div className="shell-topbar-actions">
          {switch actions {
          | Some(el) => el
          | None => React.null
          }}
        </div>
      </header>
      {largeTitle
        ? <div className="shell-large-title">
            <h1 className="shell-title shell-title-large"> {React.string(title)} </h1>
            subtitleEl
          </div>
        : React.null}
      <main className="shell-content"> children </main>
      {switch footer {
      | Some(el) => <div className="shell-footer"> el </div>
      | None => React.null
      }}
    </>,
  })
}
