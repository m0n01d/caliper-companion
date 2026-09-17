// Index — browser entry point. Mounts the TEA program (Main) into #root.
// Scaffold placeholder: Main lands with the app-shell module.

switch ReactDOM.querySelector("#root") {
| Some(root) => ReactDOM.Client.createRoot(root)->ReactDOM.Client.Root.render(<Main />)
| None => Console.error("Caliper Companion: #root not found")
}
