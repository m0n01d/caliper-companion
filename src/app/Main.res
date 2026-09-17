// Main — TEA composition root (CLAUDE.md "Architecture"). Owns the
// route↔page mapping and composes pages with `Tea.map`; the page modules
// under `pages/` are what later agents fill in without ever touching this
// file.

type page =
  | PartsList(PartsList.model)
  | Part(Part.model)
  | Capture(Capture.model)
  | Annotate(Annotate.model)
  | Settings(Settings.model)
  | Debug(Debug.model)

type msg =
  | RouteChanged(Route.t)
  | PartsListMsg(PartsList.msg)
  | PartMsg(Part.msg)
  | CaptureMsg(Capture.msg)
  | AnnotateMsg(Annotate.msg)
  | SettingsMsg(Settings.msg)
  | DebugMsg(Debug.msg)

type model = {
  route: Route.t,
  page: page,
}

// Builds the page + cmd for a route, lifting the page's own msg into `msg`.
let pageForRoute = (route: Route.t): (page, Tea.cmd<msg>) =>
  switch route {
  | Route.Parts =>
    let (pageModel, cmd) = PartsList.init()
    (PartsList(pageModel), Tea.map(cmd, m => PartsListMsg(m)))
  | Route.Part(partId) =>
    let (pageModel, cmd) = Part.init(~partId)
    (Part(pageModel), Tea.map(cmd, m => PartMsg(m)))
  | Route.Capture(partId) =>
    let (pageModel, cmd) = Capture.init(~partId)
    (Capture(pageModel), Tea.map(cmd, m => CaptureMsg(m)))
  | Route.Annotate(partId, faceId) =>
    let (pageModel, cmd) = Annotate.init(~partId, ~faceId)
    (Annotate(pageModel), Tea.map(cmd, m => AnnotateMsg(m)))
  | Route.Settings =>
    let (pageModel, cmd) = Settings.init()
    (Settings(pageModel), Tea.map(cmd, m => SettingsMsg(m)))
  | Route.Debug =>
    let (pageModel, cmd) = Debug.init()
    (Debug(pageModel), Tea.map(cmd, m => DebugMsg(m)))
  }

let init = (): (model, Tea.cmd<msg>) => {
  let route = Route.current()
  let (page, pageCmd) = pageForRoute(route)
  ({route, page}, Tea.batch([pageCmd, Route.subscribe(r => RouteChanged(r))]))
}

let update = (model: model, msg: msg): (model, Tea.cmd<msg>) =>
  switch msg {
  | RouteChanged(route) =>
    // Cross-page navigation is always a route change, never a direct call
    // into another page (CLAUDE.md "Architecture") — re-init discards the
    // outgoing page's model and runs the incoming page's own init cmd.
    let (page, cmd) = pageForRoute(route)
    ({route, page}, cmd)
  | PartsListMsg(pageMsg) =>
    switch model.page {
    | PartsList(pageModel) =>
      let (nextPage, cmd) = PartsList.update(pageModel, pageMsg)
      ({...model, page: PartsList(nextPage)}, Tea.map(cmd, m => PartsListMsg(m)))
    | _ => (model, Tea.none)
    }
  | PartMsg(pageMsg) =>
    switch model.page {
    | Part(pageModel) =>
      let (nextPage, cmd) = Part.update(pageModel, pageMsg)
      ({...model, page: Part(nextPage)}, Tea.map(cmd, m => PartMsg(m)))
    | _ => (model, Tea.none)
    }
  | CaptureMsg(pageMsg) =>
    switch model.page {
    | Capture(pageModel) =>
      let (nextPage, cmd) = Capture.update(pageModel, pageMsg)
      ({...model, page: Capture(nextPage)}, Tea.map(cmd, m => CaptureMsg(m)))
    | _ => (model, Tea.none)
    }
  | AnnotateMsg(pageMsg) =>
    switch model.page {
    | Annotate(pageModel) =>
      let (nextPage, cmd) = Annotate.update(pageModel, pageMsg)
      ({...model, page: Annotate(nextPage)}, Tea.map(cmd, m => AnnotateMsg(m)))
    | _ => (model, Tea.none)
    }
  | SettingsMsg(pageMsg) =>
    switch model.page {
    | Settings(pageModel) =>
      let (nextPage, cmd) = Settings.update(pageModel, pageMsg)
      ({...model, page: Settings(nextPage)}, Tea.map(cmd, m => SettingsMsg(m)))
    | _ => (model, Tea.none)
    }
  | DebugMsg(pageMsg) =>
    switch model.page {
    | Debug(pageModel) =>
      let (nextPage, cmd) = Debug.update(pageModel, pageMsg)
      ({...model, page: Debug(nextPage)}, Tea.map(cmd, m => DebugMsg(m)))
    | _ => (model, Tea.none)
    }
  }

let view = (model: model, ~dispatch: msg => unit): React.element => {
  let (title, back, subtitle, actions, body) = switch model.page {
  | PartsList(pageModel) => (
      PartsList.title(pageModel),
      PartsList.back(pageModel),
      PartsList.subtitle(pageModel),
      PartsList.actions(pageModel, ~dispatch=m => dispatch(PartsListMsg(m))),
      PartsList.view(pageModel, ~dispatch=m => dispatch(PartsListMsg(m))),
    )
  | Part(pageModel) => (
      Part.title(pageModel),
      Part.back(pageModel),
      Part.subtitle(pageModel),
      Part.actions(pageModel, ~dispatch=m => dispatch(PartMsg(m))),
      Part.view(pageModel, ~dispatch=m => dispatch(PartMsg(m))),
    )
  | Capture(pageModel) => (
      Capture.title(pageModel),
      Capture.back(pageModel),
      Capture.subtitle(pageModel),
      Capture.actions(pageModel, ~dispatch=m => dispatch(CaptureMsg(m))),
      Capture.view(pageModel, ~dispatch=m => dispatch(CaptureMsg(m))),
    )
  | Annotate(pageModel) => (
      Annotate.title(pageModel),
      Annotate.back(pageModel),
      Annotate.subtitle(pageModel),
      Annotate.actions(pageModel, ~dispatch=m => dispatch(AnnotateMsg(m))),
      Annotate.view(pageModel, ~dispatch=m => dispatch(AnnotateMsg(m))),
    )
  | Settings(pageModel) => (
      Settings.title(pageModel),
      Settings.back(pageModel),
      Settings.subtitle(pageModel),
      Settings.actions(pageModel, ~dispatch=m => dispatch(SettingsMsg(m))),
      Settings.view(pageModel, ~dispatch=m => dispatch(SettingsMsg(m))),
    )
  | Debug(pageModel) => (
      Debug.title(pageModel),
      Debug.back(pageModel),
      Debug.subtitle(pageModel),
      Debug.actions(pageModel, ~dispatch=m => dispatch(DebugMsg(m))),
      Debug.view(pageModel, ~dispatch=m => dispatch(DebugMsg(m))),
    )
  }

  let largeTitle = switch model.page {
  | PartsList(_) => true
  | _ => false
  }
  // Settings and Debug have no other way in from an installed app (no URL
  // bar), so the Parts root carries a gear in the bar's leading slot;
  // Settings then links on to Debug.
  let leading = switch model.page {
  | PartsList(_) =>
    Some(
      <a
        className="btn btn-icon"
        href={Route.href(Route.Settings)}
        ariaLabel="Settings"
        dataTestId="settings-link">
        <Icon name=Settings size=22 />
      </a>,
    )
  | _ => None
  }

  <div className="app-frame">
    <Shell title back ?subtitle ?actions largeTitle ?leading> {body} </Shell>
    <A2hsHint />
  </div>
}

@react.component
let make = () => {
  let {model, dispatch} = Tea.use(~init, ~update)
  view(model, ~dispatch)
}
