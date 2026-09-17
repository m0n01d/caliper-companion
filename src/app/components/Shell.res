// Shell — the persistent page chrome (CLAUDE.md "Layout", DESIGN.md §11.1
// "Layout"/"Materials"): the one glass navigation bar (sticky inside `.shell`,
// the scroll container — never `fixed`), with a chevron back button, a
// centred Headline title (or, on the root screen, a static Large Title in
// the content flow), an optional Footnote subtitle, a trailing actions slot,
// and the content area. `Main.res` wraps every page's view in one.

@react.component
let make = (
  ~title: string,
  ~back: option<Route.t>,
  ~actions: option<React.element>=?,
  ~largeTitle: bool=false,
  ~subtitle: option<string>=?,
  ~children: React.element,
) => {
  let subtitleEl = switch subtitle {
  | Some(text) => <p className="shell-subtitle"> {React.string(text)} </p>
  | None => React.null
  }
  <div className="shell">
    <header className="shell-topbar">
      <div className="shell-topbar-leading">
        {switch back {
        | Some(route) =>
          <button
            type_="button"
            className="btn btn-icon shell-back"
            ariaLabel="Back"
            onClick={_ => Tea.run(Route.push(route), _msg => ())}>
            <Icon name=ChevronLeft />
          </button>
        | None => React.null
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
  </div>
}
