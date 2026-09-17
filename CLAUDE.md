# Caliper Companion

Annotated-photo caliper capture for reverse engineering small parts. Photograph each face, tap two
edges, type the caliper reading, name the feature. Exports a dimensioned PNG per face and a
`features.json` for the Fusion 360 MCP. **The photo is never measured** — it is a labeled sketch;
the caliper is the only source of numbers.

## Shared conventions

Workspace-wide conventions (language choice, ReScript rules, `resq`, sub-agent orchestration, PR
rules) live in the private repo [`m0n01d/claude-conventions`](https://github.com/m0n01d/claude-conventions).
On the Mac they auto-load via `~/code/CLAUDE.md`; **a cloud sandbox does not see them** — fetch
before starting work:

```sh
gh repo clone m0n01d/claude-conventions /tmp/conventions 2>/dev/null || git clone https://github.com/m0n01d/claude-conventions /tmp/conventions
cat /tmp/conventions/CLAUDE.md
```

If the clone fails (sandbox credentials may be scoped to this repo only), continue with this file —
the critical rules for this project are inlined below.

## Instructions (SPEC.md §14)

```
Read SPEC.md fully before writing code. Build modules M1→M6 in order; tests first for M1, alongside for the rest.
ReScript + React + PouchDB, matching the Ternpike repo's versions and config exactly. Copy Ternpike's PouchDB bindings and PWA scaffold; do not reinvent them.
No dependencies beyond React, PouchDB (+ pouchdb-find), ReScript toolchain, and fflate. Ask before adding anything.
Apply EXIF orientation at decode; every stored coordinate is relative to the oriented image. This is the most common bug in this class of app — test it.
Do not build anything under Non-goals. No Bluetooth code. No AR code. Reserved fields stay reserved.
Do not change the features.json shape; if the schema must change, stop and ask.
One commit per acceptance-criteria group; the message names the module and criteria met.
Ambiguous criterion → simplest reading, note it in the commit body, keep going.
```

## Stack (locked)

- **ReScript 12.3 + @rescript/react 0.15 + React 19.** JSX v4 automatic. `warnings.error = "+a"`:
  every warning is a build error, so no unused bindings, no partial matches.
- **No `%raw`, no `%%raw`, no `Obj.magic`, no untyped `@val` shortcuts.** JS APIs get proper
  `external` bindings in `src/bindings/` (see `WebApi.res` for the house style: `@send` methods with
  the instance first, `Null.t`/`Nullable.t` at the boundary, one binding per API surface).
- **Vite 8** bundler, config copied from ternpike (`vite.config.js`: service-worker stamping plugin,
  `pouchdb` aliased to its browser bundle). Dev server on port 3000, strict.
- **PouchDB 9 + pouchdb-find** via `src/bindings/PouchDb.res`; all DB access goes through
  `src/store/Store.res`. No PouchDB calls anywhere else.
- **fflate** for the export zip. Nothing else without asking.
- **Tests:** `core/` unit tests in ReScript (`src/core/tests/*Test.res`) on top of the thin
  `Vitest.res` binding, run by vitest on the compiled `.res.mjs` (`npm test`,
  `npm run test:coverage`). App-level tests are Playwright (`npm run e2e`, config in `e2e/`).
- **Tools:** `npm run build` (ReScript + Vite), `npm run dev`, `npm test`, `npm run e2e`.

## Architecture: The Elm Architecture in ReScript

`src/app/Tea.res` is the runtime: `use(~init, ~update)` returns `{model, dispatch}`. Rules:

- **One model per page, one `msg` variant per page, `update: (model, msg) => (model, Tea.cmd<msg>)`.**
  `view` is a pure function of the model plus `dispatch`. No `useState` scattered in views; local
  UI state lives in the page model.
- **Side effects are `Tea.cmd` values**, never run inside `update` or `view`. `Tea.fromPromise` wraps
  a Store/DOM promise into a cmd that dispatches a msg on completion. `Tea.effect` for fire-and-forget.
- **Pages follow elm-spa:** `src/app/pages/<Page>.res` exports `type model`, `type msg`, `init`,
  `update`, `view`, plus the Shell slots `title`, `back`, `subtitle` (option) and `actions`
  (option, a trailing bar element). `src/app/Main.res` owns routing (`Route.res`, hash-based) and composes pages with
  `Tea.map`. Cross-page navigation is a `Route.push` cmd, never a direct call into another page.
- **`core/` is pure**: no DOM, no React, no PouchDB imports. Everything in it is unit-tested.

## Layout

```
src/core/       Types, Codec, FeatureName, Slug, Reconcile, NumberParse, FeaturesDocument (+ tests/)
src/bindings/   PouchDb, WebApi (DOM/canvas/file/share/orientation), Fflate
src/store/      Store — the only module that touches PouchDB
src/app/        Tea (runtime), Route, Main, Index (entry), pages/, components/
public/         manifest.json, sw.js, icons (PWA scaffold from ternpike)
fixtures/       hinge_pin/ — three JPEGs (one EXIF-rotated) + golden features.json
e2e/            Playwright config + specs (390×844 portrait)
docs/           screenshots and design notes
```

## Use `resq` when authoring ReScript

`resq` reads and edits `.res`/`.resi` structurally. Prefer it over reading whole files and
hand-splicing text. `resq guide` prints the agent-facing docs. Address declarations by dot-path;
writes fail closed and leave the file untouched on any error.

```sh
resq list src/app/Main.res            # module summary
resq get src/core/Reconcile.res reconcile
resq grep 'pattern' src/
resq refs src/core/Types.res dimension
resq set decl F.res --name x --content 'let x = 1'
resq patch F.res update --old 'a' --new 'b'
```

### Bootstrapping resq in a fresh environment

**This section exists because a cloud sandbox starts with nothing installed.** The SessionStart hook
in `.claude/hooks/session-start.sh` runs `npm install`, builds the ReScript, and installs resq
(remote-only; no-op on the Mac). If hooks didn't run:

```sh
curl -fsSL https://raw.githubusercontent.com/m0n01d/resq/main/scripts/install.sh | sh
export PATH="$HOME/.cargo/bin:$PATH"
```

[`m0n01d/resq`](https://github.com/m0n01d/resq) is public, so this needs no credentials. The script
is idempotent and installs rustup itself if `cargo` is missing. If resq cannot be installed, nothing
here breaks — edit the `.res` files directly.

## iOS Safari rules that bite (from SPEC §5 — encode as tests where possible)

- Camera via `<input type="file" accept="image/jpeg,image/png" capture="environment">`. Never
  `getUserMedia` for stills.
- Decode with `createImageBitmap(file, {imageOrientation: "from-image"})`. Every stored point is
  relative to the **oriented** image.
- Canvas at source size up to 4096 on the long edge; above that, downscale and record `renderScale`.
- Layout with `100dvh` and `env(safe-area-inset-*)`; no `position: fixed` toolbars over the canvas;
  `visualViewport` for the reading-input sheet.
- Numeric entry: `<input type="text" inputmode="decimal" enterkeyhint="next">`, never `type="number"`.
- Export via `navigator.share({files})`, with a download-anchor fallback.

## Logbook

`LOGBOOK.md` holds decisions, judgment calls, and hand-off state. Append an entry when you make a
call the spec left open; keep it short.
