// Shell — the persistent page chrome (CLAUDE.md "Layout"): a top bar with an
// optional back button and title, an optional action slot, and a scrollable
// content area. `Main.res` wraps every page's view in one.

@react.component
let make = (
  ~title: string,
  ~back: option<Route.t>,
  ~actions: option<React.element>=?,
  ~children: React.element,
) =>
  <div className="shell">
    <header className="shell-topbar">
      <div className="shell-topbar-leading">
        {switch back {
        | Some(route) =>
          <button
            type_="button"
            className="shell-back"
            ariaLabel="Back"
            onClick={_ => Tea.run(Route.push(route), _msg => ())}>
            {React.string("‹")}
          </button>
        | None => React.null
        }}
      </div>
      <h1 className="shell-title"> {React.string(title)} </h1>
      <div className="shell-topbar-actions">
        {switch actions {
        | Some(el) => el
        | None => React.null
        }}
      </div>
    </header>
    <main className="shell-content"> children </main>
  </div>
