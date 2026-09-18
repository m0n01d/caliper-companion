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
  | Route.Parts(folder) =>
    let (pageModel, cmd) = PartsList.init(~folder)
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
  // A13 (SPEC §8a, review S5): a folder-to-folder move is the *same* page
  // re-targeted, not a re-init — the parts and images stay loaded and the
  // page's `FolderChanged` decides what else is kept. It is a direct call
  // into the mounted page's `update`, never a cmd (a cmd would render one
  // frame at the old folder first). `hashchange` is the only source of
  // `RouteChanged`, so `Route.push`, a folder row's link and the browser's
  // own Back/Forward all take this branch.
  | RouteChanged(Route.Parts(folder) as route) =>
    switch model.page {
    | PartsList(pageModel) =>
      let (nextPage, cmd) = PartsList.update(pageModel, PartsList.FolderChanged(folder))
      ({route, page: PartsList(nextPage)}, Tea.map(cmd, m => PartsListMsg(m)))
    | _ =>
      let (page, cmd) = pageForRoute(route)
      ({route, page}, Tea.batch([cmd, Shell.scrollToTop]))
    }
  | RouteChanged(route) =>
    // Cross-page navigation is always a route change, never a direct call
    // into another page (CLAUDE.md "Architecture") — re-init discards the
    // outgoing page's model and runs the incoming page's own init cmd. A16
    // (review S3): `.shell` persists across pages, so the new screen starts
    // at the top — pushes and pops alike (the returning list re-inits).
    let (page, cmd) = pageForRoute(route)
    ({route, page}, Tea.batch([cmd, Shell.scrollToTop]))
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

  // The Parts list owns both of these (SPEC §8a A12a, A13): its static Large
  // Title is root-only — a folder screen and the picker use the centred bar
  // title — and its leading slot is the Settings gear (the only way in from
  // an installed app) or the picker's Cancel; in a folder the page has a
  // Back button instead and Shell drops the slot. Every other page has a
  // Back button and a centred Headline.
  let largeTitle = switch model.page {
  | PartsList(pageModel) => PartsList.largeTitle(pageModel)
  | _ => false
  }
  let leading = switch model.page {
  | PartsList(pageModel) => PartsList.leading(pageModel, ~dispatch=m => dispatch(PartsListMsg(m)))
  | _ => None
  }
  // The Shell's footer slot (SPEC §8a A12b): the Parts root's Edit-mode
  // selection toolbar, sticky at the bottom of the scroll container.
  let footer = switch model.page {
  | PartsList(pageModel) => PartsList.footer(pageModel, ~dispatch=m => dispatch(PartsListMsg(m)))
  | _ => None
  }

  <div className="app-frame">
    <Shell title back ?subtitle ?actions largeTitle ?leading ?footer> {body} </Shell>
    <A2hsHint />
  </div>
}

@react.component
let make = () => {
  let {model, dispatch} = Tea.use(~init, ~update)
  view(model, ~dispatch)
}
