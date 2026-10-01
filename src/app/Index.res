// Index — browser entry point. Mounts the TEA program (Main) into #root,
// registers the service worker (feature-detected), and keeps the
// `--vv-height` CSS var in step with `visualViewport` for the annotate-sheet
// layout (SPEC §5: `visualViewport` for the reading-input sheet).

switch ReactDOM.querySelector("#root") {
| Some(root) => ReactDOM.Client.createRoot(root)->ReactDOM.Client.Root.render(<Main />)
| None => Console.error("Snapkin: #root not found")
}

// `WebApi.ServiceWorker.container` is `undefined` (Nullable → None) in any
// browser without support — that's the feature-detection guard.
//
// `./sw.js` is relative to the page. Routing is hash-based, so the document is
// always the app root, and the worker loads from the folder the app is served
// from (`/` or `/caliper-companion/`); its default scope is that same folder.
// No build-time base is needed (vite.config.js: relative base).
switch WebApi.ServiceWorker.container->Nullable.toOption {
| Some(container) =>
  container
  ->WebApi.ServiceWorker.register("./sw.js")
  ->Promise.then(_registration => Promise.resolve())
  ->Promise.catch(err => {
    Console.error2("Snapkin: service worker registration failed", err)
    Promise.resolve()
  })
  ->ignore
| None => ()
}

let updateVvHeight = () =>
  switch WebApi.VisualViewport.instance->Nullable.toOption {
  | Some(vv) =>
    WebApi.Style.setDocumentVar("--vv-height", Float.toString(vv->WebApi.VisualViewport.height) ++ "px")
  | None => ()
  }

updateVvHeight()

switch WebApi.VisualViewport.instance->Nullable.toOption {
| Some(vv) => vv->WebApi.VisualViewport.addEventListener("resize", updateVvHeight)
| None => ()
}
