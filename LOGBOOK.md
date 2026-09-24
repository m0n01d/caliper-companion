# Caliper Companion — LOGBOOK

Running log of decisions, judgment calls, and hand-off state. Newest entry last.

## 2026-09-17 — v0 build kicked off

- Repo scaffolded from the v0 spec (`SPEC.md`). Stack: ReScript 12.3 + @rescript/react 0.15 +
  React 19, Vite 8, PouchDB 9 + pouchdb-find, fflate, vitest for `core/`, Playwright for e2e.
  Versions match ternpike where ternpike has the package (rescript, vite, playwright, pouchdb).
- Ternpike is Elm with PouchDB in plain-JS glue (`src/pouch.js`) and no React, so "copy the PouchDB
  bindings" became: port the doc/index/attachment patterns from `pouch.js` into typed ReScript
  `external` bindings (`src/bindings/PouchDb.res`). The PWA scaffold (manifest, `sw.js`, the Vite
  SW-stamping plugin, `index.html` meta) is copied nearly verbatim.
- Judgment call: no Tailwind. Ternpike's theme tokens are copied into plain CSS custom properties
  (`src/theme.css`) so the dependency list stays at what the spec allows.
- Judgment call: unit tests are written in ReScript (`*Test.res`) with a thin vitest binding and run
  by vitest on the compiled `.res.mjs`. Tests in raw JS would have to know ReScript's runtime
  representation of variants, which is brittle.
- TEA: `src/app/Tea.res` is a ~60-line Elm-architecture runtime over React (single model, `msg`
  variant, `update: (model, msg) => (model, cmd)`, pure `view`). Pages follow the elm-spa layout:
  one module per screen with its own `model`/`msg`/`init`/`update`/`view`; `Main.res` composes.
- Blocking open question from SPEC §13 (mm-only in v0 with inch as a display toggle) is unanswered;
  building the spec as written (units on the part, inch parsing for fractions) since that's what
  the acceptance criteria test.

## 2026-09-17 — M2 (persistence) landed on `agent/m2-store`

- `src/bindings/PouchDb.res`, `Ids.res`, `Clock.res`, and `src/store/Store.res`/`.resi` +
  `src/store/tests/StoreTest.res`. `npx rescript build` clean, `npx vitest run` 13/13 green
  (12 Store tests + the pre-existing SmokeTest). M1 (`core/`) hadn't landed yet when this started,
  so `Slug` wasn't available — `Store.createPart` takes `~slug` from the caller instead of deriving
  it, per the task's own note.
- Attachments are the real finding here: this repo's `pouchdb` package resolves to its Node/LevelDB
  build under vitest, and that build has **no Blob support at all** for inline `_attachments` —
  `binaryMd5` hashes the attachment data with Node's `crypto`, which throws on a `Blob`
  (`ERR_INVALID_ARG_TYPE`), and its own source comment says "In Node, we store the buffer directly."
  The one payload shape PouchDB accepts identically in the browser build and this Node build is a
  base64 string, so `Store.putFace` converts the given `PouchDb.blob` (a real `Blob` — that part of
  the SPEC's suggested `@new external makeBlob: array<Uint8Array.t> => blob = "Blob"` shape is
  right, and it's what the browser side will hand in from a canvas `toBlob()` later) via
  `PouchDb.blobToBase64` before the atomic `put`. Reading back is the mirror problem —
  `getAttachment` returns a `Buffer` on Node (no `.size`) and a `Blob` in the browser — normalized
  through `PouchDb.blobOfRaw`, which passes either through `new Blob([raw])` (a `Buffer` is a valid
  Blob part; so is an existing `Blob`). All verified live against the actual installed `pouchdb`
  package, not assumed from docs — see the comments in `PouchDb.res`'s attachments section.
- `pouchdb-find`'s query planner couldn't sort by `updatedAt` even with an explicit `use_index`
  naming the exact `[type, updatedAt]` compound index (`Cannot sort on field(s) "updatedAt" when
  using the default index`, reproduced standalone against the installed package). `ensureIndexes`
  still creates both required indexes, but every Store read path (`listParts`, `facesOf`,
  `dimensionsOf*`) uses `allDocs` id-prefix range scans + in-memory filter/sort instead of `find` —
  the same pattern ternpike's `pouch.js` already uses for `expense::` ids. Plenty fast at this app's
  single-user scale; revisit if `find()`'s planner behaves differently on a later pouchdb-find.
- ReScript 12.3 compiler gotcha (not a design choice, cost real time to isolate): a `.res` function
  *definition* with an explicit inline type annotation on an optional labeled argument
  (`~adapter: string=?`) — even completely unused in the body — trips an internal parser bug
  ("We've found a bug for you!", the arg gets typed as `string` instead of `option<string>`).
  Reproduced in isolation with no record punning involved. Fix: drop the inline annotation in the
  `.res` (`~adapter=?`) and let it unify against the `.resi`'s declared type, which is unaffected —
  the bug is specific to the implementation-site pattern, not the signature-position syntax.
## 2026-09-17 — M6 app shell (agent/app-shell)

- **PWA scaffold**: `public/manifest.json`, `public/sw.js`, `index.html` head meta ported from
  ternpike almost verbatim, minus the Cloudflare analytics beacon and the no-cache meta tags (this
  app wants its shell cached, not defeated). `sw.js` additionally drops ternpike's `SKIP_CACHE`
  host allowlist and the `push`/`notificationclick` listeners per the brief — v0 makes no network
  calls of its own (SPEC §5) so there's nothing to skip, and no push feature exists to receive for.
  Kept: atomic critical precache (`addAll`), two-generation cache retention on activate,
  `SKIP_WAITING`/`GET_VERSION` messages, network-first fetch with a cached-shell fallback for
  navigations.
- **Icons are ternpike's, unchanged placeholders** (`icon-192.png`, `icon-512.png`,
  `apple-touch-icon.png`, `favicon.svg`) — Caliper Companion has no art yet. Whoever designs the
  real mark should replace these four files; nothing else references their content.
- **Judgment call — no Google Fonts.** ternpike's `global.css` `@import`s Playfair
  Display/DM Mono/Crimson Pro from `fonts.googleapis.com`. SPEC §5 says v0 makes no network calls,
  and pulling a stylesheet from Google's CDN on every cold load is a network call the offline-shell
  criterion (M6) would then depend on. `theme.css` keeps the same three `--font-*` family-name
  stacks (so the look ports forward if fonts are vendored later) but falls through to system
  serif/mono today. No new dependency, no CDN fetch, and the SW's fetch handler stays simple
  (no cache-first branch for `fonts.googleapis.com`/`fonts.gstatic.com` — there's nothing to fetch).
- **Judgment call — no Tailwind, no `html.dark`.** Per the brief, `theme.css` is `:root` custom
  properties instead of a Tailwind `@theme` block, carrying over only the palette/fonts/radii/
  shadows tokens (not ternpike's grain texture, topo-atlas backgrounds, or keyframe animations,
  which are ternpike-specific decoration). Dropped ternpike's `html.dark` night-mode remap entirely
  — SPEC never asks for a dark theme and there's no toggle UI to drive it; can be ported later if
  wanted.
- **Route.res**: `t = Parts | Part(string) | Capture(string) | Annotate(string, string) | Settings
  | Debug`, hash-based (`#/`, `#/parts/:id`, …), unknown/malformed hashes fall back to `Parts`
  (no 404 page in v0). `push`/`subscribe` both go through `Tea.effect`, so routing has no
  special-cased side-effect path outside the TEA runtime.
- **A2hsHint is a plain React component, not a TEA page** (see its own header comment for the
  reasoning) — its whole state is one derived boolean computed once at mount from platform checks,
  plus a dismiss action that never needs to round-trip through `update`. Uses `localStorage`
  (key `cc.a2hsHintShown`) rather than the Store, per the brief: the shell must not depend on
  `src/store/*`, which doesn't exist yet (a later agent owns it).
- **Shell's back button calls `Tea.run(Route.push(route), ...)` directly** rather than going
  through a page's `dispatch` — it's chrome, not a page, and doesn't have one. Setting
  `location.hash` fires `hashchange`, which `Main`'s `Route.subscribe` turns into `RouteChanged`,
  so the round trip back into the TEA loop happens automatically.
- **No `position: fixed` anywhere** (SPEC §5: the keyboard resizes the viewport and breaks fixed
  toolbars). `.app-frame` is a `100dvh` flex column with `.shell` (flex: 1, internally scrolling)
  and `.a2hs-hint` as flex siblings, so the hint docks to the bottom of the viewport without
  `position: fixed`. `.sheet` (for the future annotate reading-input panel) is `position: absolute`
  within its own page container, sized off `--vv-height`, a CSS var `Index.res` keeps live from a
  `visualViewport` `resize` listener.
- **e2e config bug found and fixed**: Playwright resolves `webServer.command`'s cwd to the config
  file's own directory (`e2e/`) by default, not the invocation cwd. `vite preview` run from `e2e/`
  binds the port fine but serves 404s for everything (`e2e/dist` doesn't exist), and the webServer
  health check then times out waiting for a response it's never going to get — no useful error
  message, just `Timed out waiting 60000ms from config.webServer.`. Fixed by setting
  `webServer.cwd` explicitly to the repo root (`fileURLToPath(new URL('..', import.meta.url))`).
  `testDir`/`outputDir` have the same config-relative-path behavior and are set accordingly
  (`'specs'`, `'.results'`, not `'e2e/specs'`).
- **Real sw.js bug found by the offline e2e test, fixed in `public/sw.js`**: the offline-reload
  test was intermittently failing (`net::ERR_FAILED` on the hashed JS/CSS, page never renders) —
  not a test flake, a genuine cache-miss. `vite preview`/`vite dev` serve every asset with `Vary:
  Origin` (Vite's `cors: true` default). `install`'s `caches.addAll(...)` fetches those URLs
  *from inside the worker*, with no `Origin` header; the page's own tags fetch them *with* one
  (Vite emits `crossorigin` on the built `<script type="module">`/`<link rel="stylesheet">`).
  `Cache.match()` honors `Vary` by default, so it compares the `Origin` header of the live request
  against the one recorded for the cached response — no match, byte-identical URL or not — and the
  fetch handler falls through to `Response.error()`. Fixed by matching with `{ignoreVary: true}`
  (both the direct match and the `'/'` shell fallback); confirmed with a 15-run repro loop before
  and after. Worth carrying this same `ignoreVary` fix into ternpike's `sw.js` if it hasn't already
  hit the same bug there — nothing here is Caliper-Companion-specific, it's a Vite-preview-plus-
  Cache-API interaction.
- **WebKit cannot launch in this sandbox** — missing GTK4/graphene/gstreamer/flite shared
  libraries (full list in `e2e/README.md`). The `webkit` project stays defined; per the brief,
  nothing was apt-installed and the project wasn't deleted. All three specs pass on `chromium`;
  the offline-launch test explicitly skips on anything but `chromium`
  (`test.skip(browserName !== 'chromium', ...)`) since the SW mechanics it checks are
  engine-agnostic. SPEC's real target for the iOS-specific rules (§5, §10) is WebKit, though —
  that suite still needs a real run on a Mac or a Linux host with the WebKit deps before trusting
  iOS-specific behavior (viewport, safe-area, `navigator.standalone`).
- Verified clean: `npx rescript build` (26 modules, `warnings.error = "+a"`, zero warnings),
  `npm run build` (`dist/sw.js` stamped with a real `CACHE` version and `PRECACHE_URLS`),
  `npm test` (existing `SmokeTest` still green — nothing in `src/core` touched), `npm run e2e`
  (3/3 passing on chromium, 3/3 failing to *launch* — not fail assertions — on webkit).

## 2026-09-17 — M2 UI / M6 (agent/m2-ui)

Built out `PartsList`, `Part`, `Settings`, `Debug` (SPEC M2 UI criteria, M4's wedge toggle, M6's
timer + CSV criteria). All four keep the exact page contract (`model`/`msg`/`init`/`update`/
`title`/`back`/`view`) so `Main.res` needed no changes.

- **PartsList** (`#/`): create (inline form, `Slug.make` for the slug), rename and delete-with-
  confirm inline per row, empty state, loading/error text. Row tap navigates via a dispatched
  `RowTapped` msg → `Route.push`, gated so it's a no-op while that row is mid-rename/-confirm;
  the Rename/Delete buttons call `ReactEvent.Mouse.stopPropagation` so they don't also fire the
  row navigation. Added three ids beyond the existing contract (`docs/testids.md`, under Parts
  list): `part-rename-input`/`part-rename-save`/`part-rename-cancel` for the inline rename form,
  `part-delete-confirm`/`part-delete-cancel` for the confirm strip — the prior contract named the
  triggering buttons but not the form/strip contents.
- **Part** (`#/parts/:id`): faces row (`Store.facesOf`, thumbnails via `Store.getFaceImage` →
  object URL — see `Download.res`), features table (`Reconcile.reconcile`), warning row, export,
  timer. `init` batches five cmds: part/faces/dimensions/timer loads plus `Timers.everySecond(Tick)`
  for the running-timer readout.
  - **Kind-conflict display, SPEC's "never a blank section"**: `reconcileForDisplay` computes
    `Reconcile.conflicts` first, filters out every dimension whose name conflicts, then reconciles
    the rest — guaranteed conflict-free by construction, so the table always renders whatever
    features aren't in conflict, and the conflicting names still show up in the warning row
    alongside flagged names. Simpler than trying to salvage a partial reconcile from a raw
    dimension list, and matches the bullet's "if practical" language.
  - **Judgment call — object URLs are never revoked.** SPEC explicitly allows this for v0
    ("revoked when the page model is replaced isn't required"); noted here per that instruction.
    `Download.objectUrlOfImage` just wraps `URL.createObjectURL` on the face-image blob.
  - **Judgment call — the per-second timer interval is never cleared.** `Timers.everySecond`
    starts a `setInterval` from `init` and there is no matching `clearInterval` anywhere; a stray
    `Tick` dispatched after the user has navigated to another page is absorbed by `Main.res`'s
    existing catch-all `| _ => (model, Tea.none)` branch per page-msg case. SPEC's wording ("fine
    to leave the interval running") reads as accepting exactly this v0 shortcut rather than asking
    for a real page-lifecycle unmount hook, which `Tea.res` doesn't have one of today.
  - Export button wires straight to the `Export.run` stub and maps its `result` per the spec's
    exact message table; it's currently always `Error(Failed("Export is not implemented yet"))`
    until the M5 agent lands the real implementation — the UI plumbing is complete and doesn't need
    revisiting once that lands, only the message text will change.
- **Settings** (`#/settings`): `wedge-toggle` bound to `Store.getSettings`/`putSettings`
  (`settings.wedge`), optimistic toggle with revert-on-failure, default tolerances shown read-only.
- **Debug** (`#/debug`): `Store.listTimers(~limit=20)`, part name resolved per-row via
  `Store.getPart` (falls back to the id — including for a deleted part, satisfying "deleted → the
  id" without a separate branch, since a missing doc and this fallback look identical). CSV via a
  new `Download.res` (`save: (~name, ~mime, ~text) => unit`, Blob + object URL + a throwaway
  anchor) — RFC-4180 quoting only when a field actually needs it (comma/quote/newline), verified
  against a part name containing both a comma and a quote (see the scratch check below).
- **New binding files**: `src/bindings/Download.res` (Blob/object-URL helpers — the CSV download
  anchor *and* the face-thumbnail object URLs, since both are "wrap a Blob in a URL", just from two
  different call sites with two different, nominally distinct blob types feeding the same
  `URL.createObjectURL` global) and `src/bindings/Timers.res` (`setInterval` binding for the
  timer tick). Neither reaches for `%raw`/`Obj.magic`; `Store.res` already sets the precedent this
  codebase follows for small local `JsExn`-adjacent externals living outside `bindings/` when a
  page module needs one and it's not a browser API.
- **Judgment call — no shared `describeError` helper.** All four pages carry an identical
  `describeError = (_exn) => "Something went wrong talking to storage. Try again."` rather than a
  shared module, because the file-ownership list for this track has nowhere to put one (no
  `src/app/pages/Errors.res` or similar was granted). Trivial to factor out later if a shared pages
  helper module gets added to a future track's ownership list.

### Environment gap hit while verifying — not a Store gap, a Vite/dependency one

`npm run build` (and therefore `npm run e2e`, which builds first) fails **before any of this
track's code runs**, on the very first production build that actually needs to bundle the
`Store → PouchDb → pouchdb-find` import chain:

```
[UNLOADABLE_DEPENDENCY] Could not load node_modules/pouchdb-find/dist/pouchdb.find.js
  src/bindings/PouchDb.res.mjs:5:25 — import PouchdbFind from "pouchdb-find"
  No such file or directory (os error 2)
```

Root cause, confirmed by inspection (not guessed): `vite.config.js`'s `resolve.alias` (line 45)
points `pouchdb-find` at `./node_modules/pouchdb-find/dist/pouchdb.find.js`, but the installed
`pouchdb-find@9.0.0` package (per `package-lock.json`) ships only `lib/index.js` /
`lib/index-browser.js` — no `dist/` at all. The actual prebuilt UMD bundle the alias wants *does*
exist on disk, just under the sibling `pouchdb` package instead:
`node_modules/pouchdb/dist/pouchdb.find.js` (confirmed by reading its header comment — literally
"// pouchdb-find plugin 9.0.0..."). This is a known pouchdb-monorepo packaging quirk (the aggregate
`pouchdb` npm package bundles prebuilt dist files for several official plugins; the standalone
`pouchdb-find` package on npm hasn't shipped its own `dist/` for a while). The one-line fix, for
whoever owns `vite.config.js` (not in this track's file-ownership list, so not made here):

```diff
- 'pouchdb-find': path.resolve('./node_modules/pouchdb-find/dist/pouchdb.find.js'),
+ 'pouchdb-find': path.resolve('./node_modules/pouchdb/dist/pouchdb.find.js'),
```

Reproduced identically under both `vite build` and plain `vite` (dev server) — the alias is
resolved eagerly by Vite's dependency optimizer either way, so there's no dev/build split to route
around, and nothing about it is specific to a browser (Node import of the same alias target fails
the same way). It also predates this track: the M6 app-shell LOGBOOK entry above reports a clean
`npm run build`, but at that point no page imported `Store` yet, so nothing had ever asked Vite to
resolve `pouchdb-find` — this track's pages are the first code to actually reach that import at
build time, which is why the gap surfaces here rather than earlier.

Per this file's own instruction for a missing `Store` function ("STOP and report; don't work
around it") applied to the same spirit here: `vite.config.js` isn't in this track's file-ownership
list and `node_modules` is the shared symlink into `/home/user/caliper-companion` that every
worktree points at and the brief says never to touch — so neither got edited. What got verified
instead, directly against the compiled `.res.mjs` output under plain Node (bypassing Vite
entirely, the same way `StoreTest.res` already runs PouchDB under Node's LevelDB adapter):
- `PartsList.relativeDate`, `Part.formatHandsOn` (including the negative-clamp case),
  `Debug.csvQuote`/`csvOf` (including RFC-4180 quoting and the trailing newline) — pure functions,
  checked against hand-computed expected strings.
- `Part.reconcileForDisplay` — a four-dimension fixture with one flagged pair and one kind
  conflict; confirmed the conflicting name is excluded from the returned features and still
  reported as a conflict.
- The full `Store` round trip every page drives: `createPart`/`listParts`/`putPart`/`getPart`/
  `deletePart`, `getSettings`/`putSettings`, `startTimer`/`stopTimer`/`listTimers`/
  `handsOnSeconds`, then feeding a real timer row into `Debug.csvOf` — all against a real
  Node/LevelDB PouchDB instance in a temp dir, all green.

That's real behavioral coverage of every non-view code path this track added, short of actually
clicking through a rendered page. `npx rescript build` (clean, 47 modules) and `npm test` (107/107)
are both green. `e2e/specs/parts.spec.js` is written and ready (create → navigate → empty part
screen; rename persists; delete-with-confirm returns to the empty state; settings toggle persists;
Debug CSV download's first line is the RFC-4180 header) but **could not be run** — `npx playwright
test --config=e2e/playwright.config.js --project=chromium` needs `npm run build`'s `dist/` first,
which needs the fix above. Whoever picks this back up should re-run it once `vite.config.js` is
fixed; nothing in the spec itself depends on that fix, only on being able to build.
## 2026-09-17 — M5 export (agent/m5-export)

- New: `src/bindings/Fflate.res`, `Canvas2d.res`, `Share.res`; `src/app/export/Render.res`,
  `Bundle.res`, `tests/RenderTest.res`; `e2e/specs/export.spec.js`. `Export.res`'s body replaced
  (via `resq set decl … run`, keeping `type error`/`type outcome` byte-identical to the stub other
  pages already build against).
- **`Fflate.res` — tuple entries, not a plain `Dict.t<Uint8Array.t>`.** Read fflate's own source
  (`node_modules/fflate/esm/browser.js`, `fltn`) before binding it: `zipSync`'s per-entry
  `[data, opts]` tuple form has its `opts` merged *over* the call's top-level options, so it's the
  only way to give `features.json` and the JPEG/PNG entries different compression levels in one
  call. A ReScript 2-tuple `(Uint8Array.t, zipOptions)` compiles to exactly that JS `[data, opts]`
  pair, so `entries = Dict.t<(Uint8Array.t, zipOptions)>` is a fully-typed binding of the real
  shape — no raw object literals, no branching on which entries happen to carry options. Every
  entry gets explicit options (`{level: 6}`/fflate's own default for JSON, `{level: 0}`/stored for
  the already-compressed images) rather than leaning on an implicit default.
- **`Canvas2d.blob = PouchDb.blob`**, a plain alias, not a cast. A `Store.getFaceImage` result and
  a canvas-rendered PNG are both real `Blob`s; aliasing means `Render`/`Bundle` can feed either
  straight into `createImageBitmap` or `PouchDb.blobArrayBuffer` with no `Obj.magic`-shaped escape
  hatch — the type system already knows they're the same thing.
- **OffscreenCanvas feature-detected the WebApi.res way**: read `window.OffscreenCanvas` as
  `Nullable.t<_>` and never call it to find out, same pattern as
  `WebApi.ServiceWorker.container`/`Platform.standaloneNavigator`. Falls back to a detached
  `<canvas>` + callback-based `toBlob` wrapped in `Promise.make`. Same pattern reused for
  `navigator.share`/`canShare` in `Share.res`.
- **Render re-decodes the face image at export time** (`createImageBitmap(…, {imageOrientation:
  "from-image"})`) rather than trusting the face doc's stored `pixelWidth`/`pixelHeight`, and
  `Export.run` overwrites those two fields on the `Types.face` it hands to `FeaturesDocument.make`
  with whatever the fresh decode actually measured. Judgment call: this guarantees `features.json`
  can never disagree with the PNG shipped next to it in the same export, at the cost of trusting
  the decode over M3's capture-time numbers if the two ever drifted (they shouldn't — SPEC's own
  EXIF rule applies at both points identically).
- **Render's geometry is pure, split from its drawing.** `targetSize`/`strokeWidthPx`/`fontSizePx`/
  `absLineOf`/`pillFor`/`labelText` take no `Canvas2d.ctx` and are exercised by
  `tests/RenderTest.res`; `drawDimension`/`renderFace` are the thin DOM-touching replay. Necessary
  split, not just tidiness — `vitest.config.js` runs in `node`, which has no canvas at all, so
  anything touching `Canvas2d.ctx` can only be verified by the e2e suite.
- **Reconcile is checked twice, deliberately.** Once directly in `Export.run` before any rendering
  (SPEC: "return Error(KindConflict(name)) before rendering anything"), and again implicitly inside
  `FeaturesDocument.make`'s own call to `Reconcile.reconcile`. The second `Error(KindConflict(_))`
  arm is unreachable in practice (same `dimensions`, nothing mutates it in between) but kept for
  exhaustiveness rather than an unchecked `Ok`-only assumption.
- **`run` is wrapped in one top-level `try`/`catch`** that maps any escaping exception (a
  `createImageBitmap` decode failure, a missing 2D context, …) to `Error(Failed(msg))`. Without it,
  an unanticipated DOM exception would reject the returned promise instead of resolving to this
  module's own `result` contract, which the Part page isn't expected to guard against separately.
- **Judgment call — missing face attachment.** SPEC doesn't say what happens if `Store.getFaceImage`
  returns `None` for a face `Store.facesOf` just listed (attachment write raced/failed). Treated as
  `Error(Failed("Missing image for face <kind>"))` rather than skipping the face silently.
- **Judgment call — zip only**, no multi-file `navigator.share` fallback, per SPEC §13 leaving this
  open and the M5 brief's explicit "ship zip only and note it."
- **`e2e/specs/export.spec.js` is written but could not be run to a pass.** `src/app/pages/
  PartsList.res`, `Capture.res`, and `Annotate.res` are still SPEC-M6 stubs (a different, parallel
  track) — none of the testids this spec drives (`new-part`, `capture-file-top`, `annotate-canvas`,
  `reading`, `name`, `kind-*`, …) exist yet. Ran it anyway to confirm exactly where it stops:
  both tests time out identically, in `createPart()`, waiting on `new-part`
  (`npx playwright test --config=e2e/playwright.config.js --project=chromium
  e2e/specs/export.spec.js`). The spec's header comment flags two guesses that whoever lands
  Annotate/Parts should double check against what they actually build: (1) `annotate-canvas`'s
  `data-transform="scale,tx,ty"` attribute semantics — `docs/testids.md` documents the canvas but
  not that attribute, so the click-coordinate mapping in `clickNormalizedPoint` is read directly off
  the M5 brief's wording, not a verified contract; (2) that creating a part navigates straight to
  `#/parts/:id` rather than staying on the list.
- Verified: `npx rescript build` clean from scratch (0 warnings under `+a`, 51 modules), `npm test` —
  121/121 passing across 9 files (107 pre-existing + 14 new in `RenderTest.res`), `npm run build`
  clean. `npm run e2e` / the export spec: could not be run to a pass, see above; `shell.spec.js`
  wasn't rerun since nothing in this track touches app-shell files.
## M4 annotate (agent/m4-annotate)

- Files: `src/app/annotate/Viewport.res` (pure transform math) + `tests/ViewportTest.res` (vitest,
  15 tests), `src/app/annotate/Draw.res` (2D-context drawing), `src/bindings/Canvas.res` (canvas /
  ImageBitmap / pointer / ResizeObserver / input bindings), `src/app/pages/Annotate.res` + `.css`,
  `e2e/specs/annotate.spec.js`, the Annotate section of `docs/testids.md`.
- **The photo is never measured** (SPEC §1) is enforced structurally: the only way a point enters
  the model is `Viewport.toNormalized(viewport, screenPt)`, and every gesture (pan, pinch, zoom
  buttons) changes the transform, never a stored point. `ViewportTest` proves the same feature taps
  to the same normalized point at 1× and 3×; the e2e proves it on the EXIF-rotated fixture in a
  real Chromium (`end.jpg` → 1200×1600, hole at (0.55, 0.30) within 0.005 at 1× and ≥3×).
- **EXIF**: `createImageBitmap(blob, {imageOrientation: "from-image"})` is the decode; the bitmap's
  width/height are treated as the oriented size. If they disagree with `face.pixelWidth/Height`
  the page logs a warning and trusts the bitmap (the brief's rule).
- **TEA shape.** All state — viewport, live pointers (`pointers` by id), the gesture in progress
  (`Press | Pan | DragHandle | Pinch`), pending points, selection, field texts — is in the page
  model. Handlers only dispatch; `focus()`/`select()` and Store calls are `Tea.cmd`s. The one
  DOM-ref spot is `CanvasView`, which reports its CSS size + DPR (`ViewSized`, via a
  ResizeObserver) and redraws in an effect whose deps are the scene's fields, so unrelated model
  updates (typing a reading) don't repaint the bitmap. `setPointerCapture` is called in the
  pointerdown handler — event plumbing, not state.
- **Gestures.** Slop 8 px; pending-handle hit radius 24 px; line hit radius 16 px (nearest wins).
  One pointer: press → tap on release, or pan/handle-drag once past the slop. A second pointer
  turns any one-pointer gesture into a pinch (no tap on release); when one finger lifts the other
  continues as a pan. A third finger is ignored. Tap semantics: p1 placed and no p2 → the tap is
  p2 (even on p1's handle — the brief's literal rule); otherwise tapping an existing line selects
  it, tapping empty space deselects if something is selected, else starts a new p1 (discarding an
  unsaved pair).
- **Clamp policy** (`Viewport.clamp`): scale within [fit, 8×fit], re-zooming about the view centre
  when it hits a bound; an axis smaller than the view is centred, a larger one can be panned until
  the image edge reaches the view's centre line — so any pixel (edges of a part are where taps go)
  can be brought to the middle of the screen without ever losing the image.
- **Layout judgment call.** `.app-frame` has `min-height: 100dvh`, not `height`, so nothing below
  it has a definite height and a percentage-height stage would collapse. The stage is
  `calc(var(--vv-height, 100dvh) * 0.5)` instead — `--vv-height` is the `visualViewport` height
  Index.res already maintains — and the sheet sits *in flow* below it (`.annotate .sheet` overrides
  the global `.sheet`'s `position: absolute`). Side effect worth keeping: when the iOS keyboard
  shrinks the visual viewport, the stage shrinks with it and the sheet rides up into view. No
  `position: fixed` anywhere (SPEC §5); the zoom toolbar is absolute *inside the stage*.
- **Hyphenated attributes.** ReScript JSX rejects `data-transform=…` (it parses as a record
  field) and `JsxDOM.domProps` has no `enterKeyHint`/`autoCorrect`. So: the canvas's test hooks
  (`data-transform`, `data-image-size`) are `setAttribute` calls in the redraw effect, and the
  sheet's inputs go through `Canvas.Input.make`, a typed `react/jsx-runtime` binding (the same
  `jsx` call `ReactDOM.jsx` uses) with a props record that carries exactly the SPEC §5 attributes.
  No `%raw`, no `Obj.magic`, no `%identity`.
- **Save** sets `busy` and clears the entry only on `Saved(Ok)` (so a failed write doesn't lose
  the reading); it also writes the tolerance back to settings as the part-units default and
  refreshes the face's dimensions from the Store. Editing keeps the dimension's id and
  `createdAt`. Kind and tolerance follow a selection and survive save/clear. A `cancel` ("Clear")
  button and a `dimension-count` readout were added beyond the brief's list (both in testids.md).
- **12 MP images**: the bitmap is drawn directly on every redraw (the effect deps keep that to
  transform/point/dimension changes). If it stutters on an iPhone 13, the fallback is a 2048-wide
  working copy for the canvas with the original attachment kept for export (SPEC §13).
- **Draw colours** are theme.css token values inlined (a canvas can't read custom properties).
- **Shared-config bug found: the `pouchdb-find` Vite alias** in `vite.config.js` pointed at
  `pouchdb-find/dist/pouchdb.find.js`, which doesn't exist in pouchdb-find 9 (it ships `lib/`).
  Nothing on the wave-2 base imported `Store` from a page, so `vite build` never resolved it until
  Annotate did (`pouchdb/dist/pouchdb.find.js` exists but self-registers on a global and exports
  nothing, so it can't satisfy `PouchDb.res`'s `import … from "pouchdb-find"` either). Reported to
  the conductor; the fix landed on the integration branch as two commits (alias → the pouchdb
  bundle, then drop the alias so Vite bundles pouchdb-find's own browser entry) and both are
  cherry-picked onto this branch, attribution intact. Net state: `resolve.alias` holds only the
  `pouchdb` entry. `vite.config.js` is otherwise untouched by M4.
- **e2e.** Setup per test is the real Parts → Capture flow through docs/testids.md. Those pages
  were still in flight on sibling branches, so `ANNOTATE_SEED=pouch` seeds the same part + face
  docs straight into PouchDB (same shapes as Store.res) and the five tests run against the
  Annotate page in isolation. All five pass on chromium that way; the UI-flow path is written but
  could not be executed here. WebKit still can't launch in this sandbox (see e2e/README.md).
- Verified: `npx rescript build` clean under `warnings.error = "+a"`, `npm test` (ViewportTest
  15/15 plus the existing suites), `npm run build`, chromium e2e 8/8 (3 shell + 5 annotate).
## 2026-09-17 — M3 capture (agent/m3-capture)

- `src/app/pages/Capture.res`/`.css` (full implementation, replacing the M6 stub), new
  `src/bindings/ImageDecode.res` (File/FileList/`createImageBitmap`/camera-permission-query
  bindings) and `src/bindings/Orientation.res` (`DeviceOrientationEvent.requestPermission` +
  `deviceorientation` bindings), `e2e/specs/capture.spec.js`. No new `data-testid`s needed —
  everything used was already listed under "Capture" in `docs/testids.md`.
- **All four SPEC M3 bullets implemented**: face picker (one row per `Enums.allFaceKinds`
  order, "captured"/pixel-size vs "not captured" status, both actions relabel to "Recapture …"
  once a kind has a face); the camera/library `<input type=file>` flow decoding with
  `imageOrientation: "from-image"` and storing the *oriented* `pixelWidth`/`pixelHeight` while
  the *original* file bytes go to `Store.putFace` as the attachment; `DeviceOrientationEvent`
  permission requested once (armed by a capture label's `pointerdown`, iOS's user-gesture
  requirement), with `levelDegrees` snapshotted at that pointerdown, never at file-change time,
  and always `None` for the library input; a "camera blocked?" note always visible, made
  prominent when `navigator.permissions.query({name: "camera"})` resolves `"denied"` (guarded —
  Safari has neither this API's "camera" descriptor nor, in most versions, the API at all).
- **Recapture** picks the file first (a native `<input type=file>` can only be opened by a user
  gesture, so the confirm dialog can't gate it), decodes it, and only then — if the kind already
  has a face — shows `recapture-confirm`/`recapture-keep`/`recapture-cancel`. Confirm calls
  `Store.deleteDimensionsOfFace` then `Store.putFace` with the *same* face id; keep skips the
  delete; cancel drops the pending file. The `<input>`'s React `key` (a per-(kind, source)
  generation counter) is bumped the instant a file is read out of it, in `FileChosen`, not only
  on cancel — the `File` object is already captured into the msg by then, independent of the DOM
  node, so it's safe to remount immediately, and doing it there (rather than only at cancel)
  means cancel needs no separate reset path and a decode failure can be retried with the same
  file. This is a judgment call SPEC didn't spell out.
- **`ImageDecode.res`**: `file`/`fileList` model a DOM `File`/`FileList`. `File` *is* a `Blob` at
  the platform level, so handing a picked file to `Store.putFace`'s `~image: PouchDb.blob` uses
  `external asBlob: file => PouchDb.blob = "%identity"` — a same-representation upcast, the exact
  technique `@rescript/react`'s own `ReactEvent.resi` uses internally (`toSyntheticEvent`) to
  narrow one checked type into another without touching the runtime value. Reading `.files` off a
  React change event's `target` (typed `{..}`, an intentionally open/unconstrained object — React
  doesn't know statically which element fired it) uses the same `%identity` technique. Neither is
  `Obj.magic` (which would let runtime-incompatible types compile together with no such
  guarantee) or `%raw`.
- **Judgment call — `levelDegrees` formula.** SPEC never defines what "the level" actually is,
  only when to snapshot it. Used the Euclidean norm of the two DOM tilt axes,
  `sqrt(beta² + gamma²)` (falling back to whichever single axis is available) — the standard
  "bubble level" magnitude, 0° flat, larger more tilted regardless of which axis. Whoever
  consumes `levelDegrees` downstream (export/UI) should treat it as a magnitude, not a signed
  tilt direction.
- **Judgment call — `Store.startTimer` sequenced strictly before `Route.push`** (via a
  `TimerStarted` msg After `Saved`), rather than fired concurrently with navigation. SPEC just
  says "then… then"; a deterministic msg chain was simpler to reason about than a fire-and-forget
  effect racing the route change, and `startTimer` is cheap and idempotent either way.
- **Known limitation, not fixed (out of file-ownership scope):** the `deviceorientation`
  listener `Capture.init` registers is never torn down on navigating away —
  `src/app/Tea.res`'s `use` runs `init`'s cmd once with no unsubscribe/cleanup hook at all. A
  stray listener keeps updating a model nobody reads after leaving the Capture page; harmless for
  correctness, a minor cost worth fixing in `Tea.res` itself later (that file isn't mine to
  touch here).
- **Real, pre-existing bug found and fixed in `vite.config.js`** (not one of my own files, but
  it blocked every acceptance check this task asked for): `resolve.alias` pointed
  `pouchdb-find` at `./node_modules/pouchdb-find/dist/pouchdb.find.js`, a file the installed
  `pouchdb-find@9.0.0` package has never shipped (only `lib/`). Since `Capture.res` is the first
  page whose module graph actually reaches `Store` → `PouchDb` → `pouchdb-find`, `npm run build`
  and `vite dev` both failed outright (`UNLOADABLE_DEPENDENCY` / `ENOENT`) the moment this page
  existed — a latent bug since the initial scaffold commit, not something this page introduced.
  Coordinator confirmed the same finding from the M2 UI agent and had two fix commits ready on
  the integration branch; cherry-picked both onto `agent/m3-capture` (`30bafbf`, then `44ba297`,
  net effect: the `pouchdb-find` alias is dropped entirely, letting Vite resolve the package's own
  `browser` field to `lib/index-browser.es.js`; only the `pouchdb` alias remains). Verified after
  cherry-picking: `npm run build` succeeds, `npm run e2e --project=chromium` runs all 6 specs
  (`shell.spec.js` 3/3 still green; `capture.spec.js`'s 3 fail cleanly at `getByTestId('new-part')`
  — see below, expected on this branch).
- **Verification, in order:**
  - `npx rescript build` (clean, 47 modules, zero warnings under `warnings.error = "+a"`).
  - `npm test` — 107/107 existing unit tests still green (nothing under `src/core` touched).
  - `npm run build` — succeeds (after the `vite.config.js` cherry-picks above).
  - `npm run e2e --project=chromium` (official suite) — `shell.spec.js` 3/3 pass;
    `capture.spec.js`'s 3 tests fail at the very first step, `getByTestId('new-part')` timing
    out, because `PartsList.res` on this branch is still the M6 stub with no create-part form
    (agent/m2-ui's work hasn't been merged into this branch — the coordinator will run
    `capture.spec.js` again against the merged integration tree). This is the expected,
    anticipated outcome per the task brief, not a bug in `Capture.res`.
  - **Ad-hoc verification of the actual M3 behavior**, done because the official e2e suite
    can't exercise a real part yet: a throwaway Playwright script (not committed) seeded a part
    directly through the app's own compiled `Store.res.mjs` (dynamically `import()`ed in-page,
    the same module the app uses) against a `vite` dev server, then drove the real Capture UI.
    28/28 checks passed, covering: "Part not found" renders a message + back link;
    `capture-note` always visible; all 8 `capture-file-<kind>`/`library-file-<kind>` inputs
    present; **`end.jpg` (EXIF orientation 6) decodes to the oriented 1200×1600, `top.jpg`
    (no EXIF rotation) to 1600×1200** — the core M3 EXIF behavior, matching `fixtures/README.md`
    exactly; navigation to the Annotate route after a successful capture; the recapture dialog
    appearing on a second capture of an already-captured kind, and all three of its outcomes
    (`recapture-confirm` replaces the face keeping the same id and a new `capturedAt`,
    `recapture-keep` does the same without deleting dimensions first, `recapture-cancel` leaves
    the face untouched and the input immediately reusable); the library input always producing
    `levelDegrees == None`; a decode failure (a non-image file) showing an inline error and
    leaving no face doc. This script and its local `vite.config.js` patch (superseded by the
    cherry-picks above) were fully reverted/deleted before finishing — nothing from it is
    committed.

## 2026-09-17 — Integration (conductor)

- Seven agent branches merged in two waves: M1 core, M2 store, app shell; then M2 UI + M6 pages,
  M3 capture, M4 annotate, M5 export. LOGBOOK conflicts were resolved by keeping every section.
- **Bug found by the M2-UI agent:** `vite.config.js` aliased `pouchdb-find` to a file the package
  never ships; the pouchdb `dist/pouchdb.find.js` alternative is a self-registering browser script
  with no ESM export. Fix: no alias for `pouchdb-find`; Vite resolves its `browser` field. Only the
  `pouchdb` alias (ternpike's) remains.
- Spec-side fixes after merge (the app was right, the specs' cross-page assumptions weren't):
  `capture.spec.js` clicked a part row that no longer appears because create navigates straight
  to the part; `export.spec.js` mapped taps through the canvas CSS size instead of the image
  size (`data-transform` maps image pixels → CSS pixels; `data-image-size` gives the bitmap).
  `shell.spec.js` asserted a stub-era `.page-name` marker.
- Part page face tiles now show the oriented pixel size (`1200 × 1600`) — useful on screen, and it
  is how the capture spec proves the EXIF fixture decoded portrait.
- Final: `rescript build` clean under `+a`, vitest 136/136 (one unreproducible single failure seen
  once in the store suite mid-integration; three consecutive clean runs after — watch for a
  same-millisecond `updatedAt` ordering race in `listParts`/`listTimers`), Vite build clean,
  Playwright **18/18 on Chromium**. **WebKit never ran:** the sandbox lacks GTK/WPE system libs;
  run `npm run e2e` on the Mac before trusting any iOS-specific claim (SPEC §5, §10).
- Escape-hatch audit: no `%raw`, no `Obj.magic`. Two `"%identity"` externals in
  `ImageDecode.res` (File → Blob upcast, event-target narrowing), the same technique
  `@rescript/react`'s own `ReactEvent` uses; called out here so they stay the only ones.
- Icons are ternpike's placeholders. Google Fonts are not loaded (no network in v0), so the
  serif/mono stacks fall through to system fonts.

## 2026-09-17 — DESIGN.md added; GitHub Pages deploy

- `DESIGN.md` (Dwight's visual/interaction handoff) checked in verbatim. Not applied yet: the app
  still runs ternpike's light theme. Applying it (dark `cc-` tokens, self-hosted fonts, amber/teal
  overlay rules, 44 px targets) is its own track.
- Pages deploy: `docs/pages-workflow.yml` (npm ci → `npm test` → build with `VITE_BASE=/<repo>/` →
  upload → deploy-pages) on pushes to `main` and `claude/**`. **Both the session's git token and
  the GitHub API tool refused to write `.github/workflows/` (no `workflow` OAuth scope)**, so the
  file is parked in `docs/` with a one-command move in the README. Private repos need GitHub Pro
  for Pages; Dwight is handling that gate.
- The scaffold assumed a root path in five places; all now derive from one `base`: Vite `base`,
  the SW's `APP_SHELL`/precache/shell-fallback (stamped `'__BASE__'` like the cache name), the
  manifest `start_url`/`scope` (`./`), and the SW registration (`Env.base`, a `@val` external that
  Vite's `define` substitutes as `__CC_BASE__`). Hash routing needed nothing.
- Verified with `scripts/pages-smoke.mjs`: SW scope is the base, page is controlled after one
  reload, and the app relaunches offline, at both `/` and `/caliper-companion/`. Full e2e still
  18/18 at `/`.
- Gotcha hit twice this session: a stale `vite preview` on :3000 makes any check run against the
  wrong build (Playwright's `reuseExistingServer` happily reuses it). Kill by PID, not by pattern.

## v0.1 A1–A3 annotate (agent/a-annotate)

- Files: `src/app/pages/Annotate.res`, `src/app/annotate/{Draw,Viewport}.res` +
  `tests/ViewportTest.res` (+5 tests, 20 total), `src/bindings/Canvas.res` (`setLineDash`,
  `setLineJoin`, `arcTo`), `e2e/specs/annotate.spec.js` (+2 specs, 7 total), `docs/testids.md`
  (Annotate section). One commit per amendment.
- **A1 — direct drags.** Hit test order is handle (22 px radius = the 44 px target, pending *or*
  saved) > line body (16 px) > nothing, nearest wins within a class. `hit` is now
  `HitHandle(target, P1|P2) | HitBody(target)` with `target = Pending | Existing(id)` (`Saved` is
  already the msg). A press past the 8 px slop becomes `Drag(pointer, {target, kind, before})`;
  every move is `before + total pointer travel` (`Viewport.deltaToNormalized`, `translatePoint`,
  `translatePair`) so the grab offset never jumps and a revert is exact. Releasing a drag on a
  saved dimension issues `moveCmd` → `Store.putDimension` (same id/createdAt/source) and reloads
  the face's dimensions (`Moved`); the pending pair just keeps its points. A second finger during
  a drag restores `before` and becomes a pinch; a `pointercancel` mid-drag also restores it
  (nothing half-moved is kept). A tap (no movement) on a saved handle or body still selects.
- **A1 judgment calls.** (1) The selected dimension's pair *is* the pending pair (as `select`
  already made it), so dragging a selected dimension edits the entry and Update persists —
  consistent with reading/name edits needing Update; unselected saved dimensions persist on
  release. (2) A body drag at the image edge shortens the delta per axis so the line keeps its
  length and angle instead of folding (`translatePair`). (3) A tap on the pending line body is a
  no-op, like a tap on a pending handle (it used to start a new p1). (4) Live drags of a saved
  dimension move the loaded copy in `status`, so the scene redraws from `dims` with no extra
  state; `moving: bool` marks the in-flight write (Save/Delete keep their own `busy`).
- **A1 test hook.** `dimension-points` (hidden span): `id:x1,y1;x2,y2|…` at 4 dp, `aria-busy`
  while a drag's write is in flight. The write is faster than Playwright's first poll, so the
  spec doesn't gate on `aria-busy="true"`; it polls PouchDB directly (`storedPoints`, same doc
  shape as the seed helper) for the moved points, then reloads and asserts the readout within
  0.005. The fit scale on the 390×844 viewport is height-limited (0.264), which the spec derives
  from `data-transform` rather than assuming.
- **A2 — keyboard on the second tap.** `focusTestId("reading")` no longer runs from `pointerup`.
  `tap` records `focusIntent: Some(Reading)` when p2 lands; the canvas `onClick` dispatches
  `CanvasClicked`, and `update` performs the intent as the existing focus cmd, synchronously
  inside the click dispatch (iOS opens the keyboard from `click`, not `pointerup`).
  `pointerDown` clears any intent a click never collected, so a stale one can't fire on a later
  tap. Enter → name → Save focus moves are unchanged. **Unverifiable here**: no WebKit in the
  sandbox; Chromium still asserts `reading` is focused after two taps (a tap produces a click).
  Dwight verifies on the Pages deploy.
- **A3 — halo strokes on the live canvas** (`Draw.res` rewritten). Every stroke is drawn twice:
  halo `rgba(23,24,26,0.85)` at 2.5× width, then the colour. Pending: amber `#F2A33A` 2 px line,
  1.5 px dashed 4/3 extension lines through each endpoint, 10×10 arrowheads, 22 px handles
  (`#F4F2EC` disc, 3 px amber ring with halo, 6 px amber dot — no halo on the dot, it sits on the
  disc), amber pill 28 px with `#2B1A02` mono 15 text and a 1 px `#17181A` border. Saved: teal
  `#4FD1B1` at 60 % (halo included), pill `rgba(26,27,29,0.8)` with teal mono 12 `name value`,
  no handles (DESIGN.md §5 shows handles on the selected one only — the endpoints stay
  grabbable per A1). Selected: full-opacity teal with handles. Pill text is `formatLabel`:
  `⌀ name value` for a diameter, `↓ name value` for a depth (was `↧`); the pending pill shows
  the typed reading and/or name live. Pill placement: the normal is chosen to point up the
  screen (right for a vertical line) and the offset is 8 px plus the pill's half-extent along
  the normal (`|nx|·w/2 + |ny|·h/2`), so a wide pill clears a vertical or shallow line too.
  Diameter keeps the line (no dashed circle — it would complicate hit-testing for no A1 gain).
  Colours are literals with the `cc-` token named in a comment. Verified by screenshot at
  390×844 on the built app: pending amber, dimmed teal, selected teal, all three kinds.
- **Sandbox gotcha (new).** Port 3000 is shared with sibling agents' `vite preview` servers
  (`/home/user/wt/a-export-capture` had one up during this track), and the sandbox reaps
  background processes between tool calls. Playwright's `reuseExistingServer` then runs the
  suite against a *sibling's* build and dies with `ERR_CONNECTION_REFUSED` when theirs goes away
  — two full runs cascaded that way. Final runs used a scratchpad copy of the config on port
  3017 (`workers: 1`, `reuseExistingServer: false`) and a one-call start/run/kill; nothing in the
  repo's config changed. Any e2e claim from a shared sandbox should name its port.
- Final: `npx rescript build` clean under `+a`, `npm test` 141/141 (ViewportTest 20/20),
  `npm run build` clean, Playwright chromium 20/20 (18 existing + 2 A1). WebKit not run (no
  system libs — see e2e/README.md).
## 2026-09-17 — v0.1 A3 export + A4 capture (agent/a-export-capture)

From the first real phone dogfood: exported dimensioned PNGs were unreadable on dark photos
(navy lines, no halo), and stored photos were needlessly large (whatever the camera handed
over, kept verbatim). Two independent amendments, two commits.

**A3 — export PNG legibility (`src/app/export/Render.res`, `RenderTest.res`, `Canvas2d.res`,
`e2e/specs/export.spec.js`).**

- Replaced the navy scheme (`#14213d`) with DESIGN.md §5's halo/amber treatment: every stroke —
  dimension line, arrowheads, extension ticks, endpoint handles — drawn twice, a near-black halo
  (`rgba(23,24,26,0.85)`, 2.5x the line width) underneath then amber (`#F2A33A`) on top. Label on
  a solid amber pill, `#2B1A02` text in the mono stack, 1px near-black border.
- Arrowheads and endpoint handles didn't exist in the pre-A3 renderer at all — M5 only drew the
  line, ticks, and pill. Added as filled shapes (triangle / circle) with the same halo treatment,
  via two small combinators (`strokeHaloed` for the line/ticks, `fillHaloed` for the filled
  shapes) rather than hand-duplicating the two-pass draw at each call site.
- Sizes per A3 bullet 2: stroke 0.15% of the long edge (min 2px) — note this is a change from the
  pre-A3 "~0.3% of *height*" reading, both because A3 says so and because the phone dogfood found
  the old line too thin against a busy photo; pill height 2% of image height (now a fixed measure,
  independent of font metrics — previously it was derived from font size + padding); label font
  1.4% of image height; arrowheads 5x the stroke width (10px at a 2px stroke).
- Judgment calls, no exact figure given in SPEC/DESIGN for these:
  - Endpoint handle radius = half the arrowhead size, so a handle and its end's arrowhead read as
    one scale rather than two.
  - Extension-tick dash (4/3 at a 2px stroke) carried over from DESIGN.md §5's *live-canvas* dash
    spec, scaled by the same factor as the stroke (export has no dash spec of its own).
  - Pill border width (1px) is literal, not scaled by image size — the bullet's own wording says
    "1px", unlike every other size in the list which is a percentage.
  - `labelText`'s `name = value unit` composition is unchanged. The amendment says to "keep" its
    semantics; Annotate.res's live canvas already has its own `⌀`/`↧` diameter/depth prefixing
    (a different agent's file, out of this track's ownership) — not mirrored here, since the
    pre-A3 `Render.labelText` never had it either and the amendment didn't ask for it to gain it.
- New pure helpers — `haloWidthPx`, `arrowheadSizePx`, `handleRadiusPx`, `dirOf`,
  `arrowheadTriangle`, and a small WCAG contrast helper (`relativeLuminance` / `contrastRatio` /
  `hexChannel`, the last shared so the hex colour constants and their luminance math can't drift
  apart) — are all unit-tested in `RenderTest.res`. The pill fill/text contrast comes out to
  ~8:1, comfortably over the 4.5:1 floor A3 bullet 3 asks for.
- New e2e suite in `export.spec.js` ("render legibility"): builds an all-white and an all-black
  800x600 JPEG in-page via `<canvas>`, runs each through capture -> one horizontal dimension ->
  export, and decodes the resulting PNG with a small hand-written reader (`zlib.inflateSync` +
  the PNG spec's five per-scanline unfilter types — no new npm package) to sample real pixel
  values a quarter of the way along the line, clear of the pill and both endpoints. Asserts an
  amber-core pixel and a halo pixel are both present, in both images.
  - **Threshold judgment call:** the task brief's illustrative "halo pixel: all channels < 60"
    doesn't survive alpha compositing — `rgba(23,24,26,0.85)` over solid white computes to
    ≈(58, 59, 60), i.e. the blue channel lands exactly on 60 after 8-bit rounding, making a
    literal `< 60` flaky. Used `< 70` instead: still far from amber (R>200) or a white background
    (255), with real margin against rounding, and it's this test's own choice to make, not a
    contract SPEC.md pins down.

**A4 — cap stored photos at 2048px (`src/app/pages/Capture.res`, `src/bindings/ImageDecode.res`,
`src/bindings/Canvas2d.res`, `e2e/specs/capture.spec.js`).**

- `Capture.maxLongEdge = 2048`. After the oriented `createImageBitmap` decode, if
  `max(width, height) > maxLongEdge`, the bitmap is redrawn onto a canvas at
  `round(w·k) × round(h·k)` (`k = 2048 / max(w,h)`) and re-encoded `image/jpeg` quality 0.85;
  that blob (not the picked file) is what `Store.putFace` stores, with the capped
  `pixelWidth`/`pixelHeight`. Under the cap, the picked file is stored byte-for-byte unchanged,
  same as before — the EXIF fixture (1200×1600) still takes this path untouched.
- Reused `Canvas2d.res`'s render-target/drawImage/toBlob machinery from `ImageDecode.res` instead
  of duplicating the `OffscreenCanvas`-with-`<canvas>`-fallback dance — a same-representation
  `%identity` cast (`asCanvasBitmap`) bridges `ImageDecode.imageBitmap` to `Canvas2d.imageBitmap`,
  the same technique this file's own `asBlob` already uses for `File` → `Blob`. `Canvas2d.toBlob`
  gained an optional `~quality` (as `option<float>`, not a bare `~quality: float=?` — the latter,
  despite matching the style of `Store.make`'s `~adapter: string=?`, didn't type-check here;
  didn't chase why, the explicit-`option` form is no less clear) for the JPEG re-encode; the PNG
  export path passes `None` and is unaffected.
- Refactored `Capture.res`'s `pendingCapture`/`Decoded`/`saveFaceCmd` to carry an already-decided
  `(PouchDb.blob, contentType)` pair instead of the raw `ImageDecode.file` — the resize decision
  (`decodeAndCap`, one `async` promise producer handed to `Tea.fromPromise`, same "async work
  lives in the producer, not the `onOk` callback" shape `Annotate.res`'s `saveCmd` already uses)
  happens once, at `Decoded`, so recapture-confirm/keep just replays the stored pair with no
  re-decode.
- `Render.res`'s `canvasCapLongEdge`/`targetSize` (the pre-existing 4096 path) is untouched and
  still exercised by `RenderTest.res` — A4 makes it unreachable in practice (every stored photo
  is already ≤ 2048 by the time Export gets to it) but SPEC says keep it, not delete it, so a
  later tier can raise `maxLongEdge` as a config change. Noted with a comment at both ends
  (`Render.res`'s `canvasCapLongEdge`, `Export.res`'s `renderScale` destructure).
- e2e: appended to `capture.spec.js`. A synthetic 4000×3000 JPEG (flat background + a dark
  circle, generated in-page via canvas so it isn't a degenerate single-colour image) captured as
  `top` shows `2048`/`1536` on the Part page's `face-top` tile; then, since `Bundle.res`'s
  `faces/<kind>.jpg` entry is the stored attachment's bytes verbatim, exporting and reading that
  entry's byte length back out of the zip confirms the *stored file itself* — not just its
  reported dimensions — is smaller than the 4000×3000 input (the brief's "or accept the tile
  assertion alone if that's too heavy" opt-out wasn't needed; the export-and-check-bytes route
  reused patterns already proven working in `export.spec.js`). The pre-existing EXIF test
  (1200×1600, under the cap) is untouched and still green.

**Verification, both amendments:** `npx rescript build` (clean, `warnings.error = "+a"`),
`npm test` (147/147, RenderTest's new/updated cases included), `npm run build`, `npx playwright
test --config=e2e/playwright.config.js --project=chromium` — **21/21** (all 18 pre-existing specs
green, plus the 2 new legibility tests and the 1 new A4 capture test). WebKit not run (this
sandbox lacks the GTK/WPE libs, per `e2e/README.md` — unchanged from earlier sessions, not
something this track touched).

Environment gotcha, twice: a sibling agent's stale `vite preview` on :3000 (from a different
worktree, `a-annotate`) got killed by PID before each e2e run, per this file's own standing
instruction — not this track's bug, just a shared-machine port squat.

Not done, out of this track's file ownership: `Annotate.res`/`Canvas.res`'s live canvas doesn't
get the halo treatment (SPEC §8a A3's fourth bullet, "the live annotate canvas uses the same halo
treatment so what you see is what exports") — the task brief scoped this track to A3 bullets 1–3
only, and `Canvas.res`/`Annotate.res` belong to another agent.
## 2026-09-17 — Design wave 1 — foundation (agent/d1-foundation)

Visual foundation per DESIGN.md §11 (owner: "modern Apple, Liquid Glass, not ternpike"): tokens,
the app shell with the one glass surface, shared component classes, `Icon.res`, `Ui.res`. No page
under `src/app/pages/` was edited; wave 2 restyles them onto these classes.

- **Tokens** (`src/theme.css`): ternpike's palette is gone. `--cc-*` colours/spacing/radii from §2,
  the §11 system font stacks and HIG "Large" type scale (`--cc-size-*`/`--cc-leading-*` pairs plus
  `--cc-text-*` `font:` shorthands), `--glass-*` from the glass brief verbatim, motion tokens,
  `color-scheme: dark`. The brief's `prefers-color-scheme: light` glass remap is deliberately
  omitted: dark-only with `color-scheme` forced means it would fire on every phone set to light
  appearance and put a 55%-white bar under off-white text. Add it with a light theme.
- **Legacy aliases** (`global.css` §13a): the page stylesheets still say `var(--color-cream)` etc.
  An undefined custom property makes the whole declaration invalid at computed-value time — it does
  not fall through to an earlier rule — so a global compat rule cannot rescue them. The old names
  are aliased onto `cc-` tokens (`ink` → `cc-text`, `cream` → `cc-surface`, `forest` → `cc-amber`,
  `rust` → `cc-error`, …) and the handful of places where that inverts meaning (annotate stage
  background, capture tile, secondary capture label, selected chip/segment, zoom toolbar) get
  higher-specificity overrides. Wave 2 deletes all of §13.
- **Glass**: exactly one surface, `.shell-topbar`, `position: sticky` inside `.shell` (now the
  scroll container; `.app-frame` is a fixed 100dvh so the document never scrolls). The blur lives
  on `.shell-topbar::before`, an absolutely-positioned pseudo-child, not on the sticky element —
  the brief's workaround for iOS's fixed/sticky + backdrop-filter scroll-lag bug. `.glass` is the
  recipe verbatim (`-webkit-` first, `@supports` opaque fallback, `prefers-reduced-transparency`
  hook that Safari will never fire). Bar icon buttons are transparent (no glass on glass).
  Verified in Chromium: computed `backdrop-filter: blur(20px) saturate(1.6)` on the pseudo, body
  scrollTop stays 0 while `.shell` scrolls, content visibly blurs under the bar.
- **Overscroll**: kept `overscroll-behavior: none` on the document (already there; iOS standalone
  has no pull-to-refresh, and an accidental Chrome/Android refresh mid-annotation costs more) and
  added `contain` on `.shell` so the container's own bounce still works.
- **Large title**: `Shell ~largeTitle` renders no bar title and a static `.shell-title
  .shell-title-large` block in flow under the bar; it keeps the `.shell-title` class on purpose so
  `shell.spec.js` (`locator('.shell-title')`) stays green when wave 2 enables it for Parts.
  `~subtitle` is a Footnote line under either title. Main.res unchanged.
- **Buttons**: bare `<button>` defaults to the secondary capsule (44 px). `Ui.Button ~disabled`
  renders `aria-disabled` and swallows the click instead of the native attribute, per §6 ("still
  focusable so the reason can be read"); Playwright's `toBeDisabled()` honours it. The primaries
  pages render today (New part, Create, Export, Save, Capture) are promoted to amber through compat
  selectors so each screen keeps one prominent button between waves.
- **List separators**: the inset separator is a `::before` at `left: 16px` rather than a
  `border-top` with a margin, so a tappable row stays tappable edge to edge.
- **Annotate segmented (compat only)**: 14 px semibold with 4 px padding, not Subhead 15 — it shares
  a row with the 132 px tolerance field until wave 2 re-lays the panel out, and "Diameter" at 15 px
  clipped on 390 px with the wide fallback font. `.segmented-option` proper is Subhead 15.
- **Icons**: Lucide 1.47.0 (ISC) path data inlined in `Icon.res`, 16 icons, `aria-hidden` unless
  `~label` is given (then `role="img"` + `aria-label`).
- **A2HS hint**: opaque `.list-group`-like card docked under the shell (never fixed, never glass),
  Footnote copy, `Ui.Button Small` "Later" (`data-testid="a2hs-later"`). Behaviour unchanged.
- **Meta**: `color-scheme: dark`, `theme-color` `#17181A`, manifest `background_color`/`theme_color`
  `#17181A`; `apple-mobile-web-app-status-bar-style` stays `black-translucent`.
- Verified: `rescript build` clean under `+a`, vitest 136/136, Vite build clean, Playwright
  **18/18 on Chromium** (WebKit still cannot launch here — check the glass bar and the switch on a
  real iPhone). Screenshots reviewed by eye; headless Linux renders the system stack as DejaVu
  Sans, so the SF Pro look only shows on device.
- Not done / for wave 2: pages still use their own classes (this section's §13 maps them); no
  scroll-edge shadow modulation (no reliable CSS for it in Safari); the 96 px face tiles on Part
  still overflow horizontally at 4 tiles (pre-existing; §11.2 wants 56 px slots).

## 2026-09-17 — App icon

- Ternpike's placeholder icons replaced. One hand-written SVG (`scripts/make-icons.mjs`): the
  app's own dimension mark — amber caliper jaws + dimension line, teal reading bar — on `cc-ground`.
  `favicon.svg` is rounded for browser tabs; the PNGs (192, 512, apple-touch 180) are full-bleed
  squares because iOS and the manifest mask corners themselves. Re-run the script after any change.
## 2026-09-17 — A5 EdgeSnap module (agent/w2-edgesnap)

Pure half of SPEC §8a A5 only (bullets 1, 2, 5): `src/app/annotate/EdgeSnap.res`, its unit tests,
and `src/bindings/ImageData.res` (the grayscale-patch binding). The toolbar toggle, the ring
feedback, and wiring taps into this module are a later agent's job on `Annotate.res`, which this
track never touched.

- **`EdgeSnap.res` is pure** — no DOM, no bindings, no React — per the task brief and SPEC's own
  "no DOM" framing for this module. `patch`/`px`/`result`/`threshold` are plain records; every
  top-level `let` is a real export (no `.resi`), same convention as `Viewport.res`, which is why
  the tests can call "private" helpers (`lumaAt`, `gradientMagnitude`, `medianGradient`, `cutoff`)
  directly rather than only exercising them indirectly.
- **`snapPoint`**: scans the integer pixel rectangle bounding the `radius` disk around `at`,
  candidate = highest Sobel magnitude within the disk, ties broken by nearest-to-`at`; `None` when
  nothing clears `max(relative × medianGradient, absolute)`.
- **`snapPair`**: direction `d` = unit(p2 − p1); each end walks the segment line through itself
  (`± radius` along `d`, 0.5 px steps, `±1` px across via the unit normal — "robust to thin lines"
  per spec) and scores by the **directional** dot product `|gradient · d|`, so an edge perpendicular
  to the segment wins and one parallel to it scores ~0. `result.strength` is still the plain Sobel
  magnitude at the winning pixel (matches `snapPoint`'s `result`) — the directional dot product is
  only the *selection* score, never what's reported back. Judgment call, not spelled out in the
  bullet's signature comment; noted here for the wiring agent.
- **Judgment call — threshold on `snapPair`**: "the best gradient" in the spec bullet is applied to
  the directional score (what's actually being maximized), not the raw magnitude — a strong edge
  running parallel to the segment can have high magnitude but ~zero directional score and correctly
  stays unsnapped either way, but this is the reading that matters when the two disagree.
  Sub-pixel refinement (the bullet's "optional" parabolic fit) was **not** implemented — integer-
  pixel landing already meets the ≤1 px acceptance bar on every synthetic patch tested, and the
  spec explicitly makes it optional.
- **`ImageData.res` bitmap-type note (flagged for the wiring agent):** `Canvas.res` and
  `Canvas2d.res` each already declare their own opaque `imageBitmap` type rather than sharing one
  (`ImageDecode.res` bridges two of them with one justified `%identity` cast). This task's brief
  said not to add a third such cast in this file, so `ImageData.res` declares its **own** opaque
  `imageBitmap` — structurally the same runtime `ImageBitmap`, nominally distinct. Whoever wires
  taps to `EdgeSnap` holds a `Canvas.imageBitmap` (the annotate page's own oriented decode) and is
  the one who converts it to `ImageData.imageBitmap` before calling `lumaPatchOf` — one line, same
  technique and justification as `ImageDecode.res`'s `asCanvasBitmap`. This file's own render-target
  plumbing (`OffscreenCanvas` with the detached-`<canvas>` fallback) mirrors `Canvas2d.res`'s
  structure on purpose rather than reusing its code, since `Canvas2d.drawImage` is bound to *its*
  bitmap type. `lumaPatchOf` returns a `promise` (per the spec signature) even though every step
  today is synchronous — documented in the file as leaving room for a future async
  `createImageBitmap` resize path without a signature change.
- **Noise-fixture judgment call**: the first deterministic "noise" generator tried was a position
  hash (`x * bigPrime + y * bigPrime2 + seed * bigPrime3, mod P`). It reads as noise by eye but is
  linear in `x`/`y`, and ReScript's `int` arithmetic truncates to 32 bits after every op (`| 0` in
  the compiled output) — the combination produced visibly banded, Sobel-detectable "edges" in a
  supposedly-flat noise patch and failed the "noise never snaps" test. Replaced with a small LCG
  (`state = state * 25173 + 13849 mod 65536`, Turbo-Pascal constants, deliberately small enough that
  the arithmetic never overflows 32 bits) threaded across the patch in raster order — genuinely
  uncorrelated neighbour-to-neighbour, verified against the compiled module directly (`node -e
  "import(...)"` against `EdgeSnap.res.mjs`, not a JS re-implementation) before it went into the
  `.res` test file.
- Verified: `npx rescript build` clean (`warnings.error = "+a"`) from a clean `rescript clean` (64
  modules); `npm test` 171/171 green (152 pre-existing + 19 new `EdgeSnapTest.res`); `EdgeSnap.res`
  at **100% statement/branch/function/line coverage** via a throwaway local vitest config scoped to
  just that file (deleted before committing — `vitest.config.js` itself is untouched, per the task
  brief's "add it to your local reasoning, not to the config").
- Not done / open for the wiring agent: the toggle pill, the 150 ms snap ring, `settings.snap`
  persistence, wiring `snapPoint`/`snapPair` into `Annotate.res`'s tap handling, and the
  `Canvas.imageBitmap → ImageData.imageBitmap` cast described above. The Playwright test on
  `top.jpg` (SPEC bullet 6) also belongs to that track — it needs the toggle and the live canvas to
  exist first.
## 2026-09-17 — Design wave 2 — capture (agent/w2-capture)

- `src/app/pages/Capture.res`/`.css` restyled onto the wave-1 foundation (DESIGN.md §11.2
  "Capture", §4 Chip/Thumbnail-slot/Shutter/Secondary-button/Scrim-pill). File-scoped to this
  page only; `global.css`/`theme.css`/`Ui.res`/`Icon.res` untouched. `Capture.css` no longer
  references any `--color-*` compat alias or global.css §13 legacy class.
- Layout: capsule chip row (`Ui.Chip large=true`, Top/Side/End/Detail, captured kind gets a small
  `Icon Check`) → 56 px slot row (`.slot`/`.slot-captured`/`.slot-empty`, same classes DESIGN.md
  §4 defines for Part's own face tiles) → either the 76 px amber shutter block or the inline
  recapture card → the camera note. Tapping a chip or a slot dispatches the same new
  `SelectKind(kind)` msg.
- **Two UI-only model additions**, both within the task brief's explicit allowance:
  - `selectedKind`/`kindManuallySelected` — which chip/slot/shutter target is active, defaulting
    to "first kind without a face, else Top" the one time `GotFaces` resolves (nothing else
    re-fetches the face list in this page), and sticking to the user's tap after that.
  - `faceImages`/`FaceImageLoaded` — object URLs for the slot thumbnails, the exact same cheap
    `Store.getFaceImage` + `Download.objectUrlOfImage` pattern `Part.res` already uses for its own
    face tiles (no new Store/Download code).
  Nothing about the file-input/decode/save/recapture state machine changed — same msgs, same cmds,
  same `update` branches, just two new msgs/fields layered on top.
- **All eight `<input type=file>`s (one camera + one library per kind) render unconditionally**,
  in a fixed spot in the tree, independent of `selectedKind` and `model.dialog` — this was the
  hard requirement (`docs/testids.md`, `capture.spec.js`/`annotate.spec.js`/`export.spec.js` all
  call `setInputFiles('[data-testid="capture-file-<kind>"]')` directly, never via the UI). The
  visible shutter/"From library" controls reference the *selected* kind's input by `htmlFor`
  (id), not by wrapping it, specifically so their presence in the DOM never depends on which chip
  is selected or whether the recapture dialog is showing. Trade-off noted in `Capture.res`'s own
  module-end comment: keyboard Tab reaches all eight (each has its own descriptive `aria-label`)
  rather than just the active pair, and a hidden input's focus ring — on a 1×1px clipped element —
  isn't a useful visual cue. Untested by any spec; a deliberate, minor rough edge.
- **Judgment calls**:
  - "From library" always reads "From library" (not "Recapture from library"): DESIGN.md §11.2
    names the capsule's copy once, and the Body caption above it ("Capture Top"/"Recapture Top")
    already carries the recapture state. The original M3 pass had both actions relabel to
    "Recapture …"; this page drops that for the library capsule. Copy-only change — same testid,
    same click handler.
  - The progress pill's text ("Decoding…" vs "Saving…") is derived from existing state (whether
    `model.dialog` is `NoDialog` or `RecaptureConfirm(_)` while `model.busy` matches the selected
    kind), not a new msg — the two phases were already distinguishable.
  - Level readout: a live, display-only read of the existing `levelFromSamples(lastBeta,
    lastGamma)` helper (same gating as the save-time `armedLevel` snapshot), shown as a mono teal
    `Ui.Pill` (`capture-level`) next to the shutter when available. No new state.
  - Recapture dialog: `Ui.Button Danger`/`Secondary`/(default) for confirm/keep/cancel, inline
    `.list-group`-styled card, no overlay/modal.
  - Dropped the old `sizeText`/"Captured — WxH" status line — DESIGN.md §11.2 doesn't call for it
    on this screen (chip check-mark + slot thumbnail already say "captured"), and the Part page's
    own `face-<kind>` tile is the one `capture.spec.js` actually reads pixel sizes off of.
- **`Ui.res` gap**: no "plain"/borderless button variant. DESIGN.md's recapture card asks for
  Danger / Secondary / a "plain" Cancel; `Ui.Button` only has Primary/Secondary/Danger/Small/Icon,
  so Cancel renders as Secondary — visually identical to "Replace, keep dimensions" next to it.
  Worth a `Plain` variant (borderless, `cc-text` on transparent) if this recurs on other pages.
- New `data-testid`s (documented in `docs/testids.md`): `capture-kinds` (the chip row),
  `capture-level` (the level pill). Both additive; no existing id changed.
- Verified: `npx rescript build` clean under `+a` (clean build too, 62 modules), `npm test`
  (152/152), `npm run build`, Playwright **23/23 on Chromium** (`E2E_PORT=3220`). Screenshots at
  390×844 (empty, one face captured, recapture dialog open) and 360×844 (empty, no horizontal
  scroll) taken against `vite preview` and reviewed by eye — thumbnail slot renders the actual
  captured photo, chip/slot selection and the check-mark all read correctly, recapture card
  matches DESIGN.md's inline no-overlay spec.
## 2026-09-17 — Design wave 2 — lists (agent/w2-lists)

Restyled Parts, Part, Settings and Debug onto the wave-1 foundation (DESIGN.md §11.2). All four
`.css` files dropped section-13-style legacy classes and `--color-*` aliases; they now reference
only `--cc-*` tokens and the shared `Ui.res`/global.css component classes, plus a handful of
genuinely page-specific rules (faces row, features table, the two-line part row, the toggle-track
hit-test fix below).

- **Parts**: empty state = one Footnote line + amber `Ui.Button Primary` "New part"; with parts, an
  inset `Ui.ListGroup` + secondary "New part" underneath. Copy conflict: DESIGN.md §7 mandates "A
  part is a set of photographed faces." verbatim, but `shell.spec.js` (not in this track's file
  ownership) hard-matches the pre-existing "No parts yet." substring. Resolved by leading with the
  old substring and appending the new sentence: "No parts yet. A part is a set of photographed
  faces." — satisfies both; flagging in case a later wave wants to update `shell.spec.js` and drop
  the compromise.
- **Create form**: `Ui.ListGroup` + `Ui.Field` "Name" (60-char limit, `autocapitalize="words"`) +
  `Ui.Segmented` mm/in, with a `visually-hidden` real `<select data-testid="part-units">` kept in
  sync so `parts.spec.js`'s `selectOption('mm')` still works — `Ui.Segmented` has no `<select>`
  semantics of its own. **Ui.res gap / layout bug**: `Ui.Segmented`'s container has no intrinsic
  width, and a `flex:1 1 0` row of segments collapses to its own min-content instead of filling its
  parent — inside a horizontal `.list-row`, the bar rendered as a tiny content-hugging blob instead
  of a full-width capsule. Fixed at the page level (`.parts-form-row .field/.segmented { width:
  100%; }`); the right long-term fix is probably `width: 100%` on `.segmented` itself in global.css.
- **Row actions, hand-rolled**: `Ui.ListRow`'s `onClick` wraps the whole row in a `<button>`, which
  can't coexist with the sibling Rename/Delete `<button>`s each row needs (`part-rename`,
  `part-delete` must stay directly clickable per docs/testids.md) — button-in-button is invalid
  HTML. `PartsList.res` hand-rolls the row with the same `list-row`/`list-row-body`/`-trailing`/
  `-chevron` classes `Ui.ListRow` itself uses, with a real `<a>` for navigation as a sibling of the
  action buttons rather than a wrapping button. **Ui.res gap**: no pencil/edit icon in `Icon.res`'s
  set (Trash exists, no equivalent for rename) — "Rename" stays a text `btn-small`, not an icon
  button; noted rather than worked around, since inventing a shape isn't this track's call.
  First pass crammed thumbnail + name + "Rename" + delete icon + chevron onto one 390 px line,
  which truncated names to ~4 characters — screenshotted, looked broken, redone as two lines (name
  + chevron on top, meta + actions below); Ui.ListThumb always renders the neutral placeholder
  (PartsList doesn't load face images — not "cheaply available" per §11.2's own escape hatch).
  Rename/delete stay fully inline (no modal): input + Save/Cancel, or the confirm sentence +
  danger Delete/Cancel, replacing the row's normal content in place.
- **Part**: faces = `.chip-row` (reused, already handles horizontal scroll + hidden scrollbar) of
  56 px `.slot`s; captured faces keep the size text inside the `face-<kind>` anchor for
  `capture.spec.js`. Features = `Ui.ListGroup` wrapping a `<table>` (no shared table component
  exists) — name mono, value mono + Subhead unit, tolerance/faces right-aligned, faces `cc-teal`
  when a feature spans >1 face. Flagged rows carry `Icon TriangleAlert` + literal " flagged" text
  (never colour alone). Split the old single "Check: …" warning row into two `Ui.WarningRow`s by
  cause — Teal for spread-flagged features, Error for kind conflicts (the DESIGN.md brief asks for
  tone-by-cause; the old code merged both into one line). Export is a full-width amber
  `Ui.Button Primary`; timer is a Footnote mono line.
- **Settings**: `Ui.ListGroup` + a real `Ui.Toggle` for the wedge row, second read-only `ListGroup`
  for default tolerances. **Ui.res gap, two-part, both worked around in `Settings.css` (global.css
  isn't ours to edit)**: (1) the toggle's decorative `.toggle-track` span is later in the DOM than
  its `aria-hidden`-free real `<input>` sibling, so at equal `position`/`z-index:auto` stacking it
  paints on top and intercepts every click meant for the checkbox — including Playwright's own
  `getByTestId('wedge-toggle').click()`, which timed out for 30s with "toggle-track intercepts
  pointer events". (2) even with the track set to `pointer-events: none`, the checkbox itself never
  received the click: global.css's `.visually-hidden` clips it to `clip: rect(0,0,0,0)`, which
  browsers exclude from hit-testing entirely, so the click fell through to the wrapping `<label>`
  instead. Fixed by overriding the input (scoped to `.wedge-row`) to occupy the full 52×32 switch
  and stay invisible via `opacity: 0` instead of `clip`, which keeps it hit-testable. Real users are
  unaffected either way (tapping anywhere in the `<label>` already activates the input natively);
  this only ever blocked a direct, precise click at the input's own coordinates. Also moved the
  wedge row's label off `.list-row-title` (forced single-line ellipsis) onto plain `.t-body`, since
  "Readings come from a wedge dongle" isn't a scannable short title and was truncating to
  "Readings come from a wedg…".
- **Debug**: `Ui.ListGroup header="Timers"` wrapping the loading/empty/rows states rather than only
  the rows — `shell.spec.js` expects a "Timers" heading even with zero timers recorded, and putting
  the header inside the conditional (my first pass) dropped it whenever the list was empty. Rows are
  `list-row`s (part name Body, start/stop Footnote meta, hands-on mono trailing); `Ui.Button
  Secondary` "Export CSV" below.
- Verified: `rescript build` clean under `+a`, vitest 152/152, `vite build` clean, Playwright
  **23/23 on Chromium** (re-ran after every fix above, not just once at the end). Screenshotted all
  four screens (empty/create/list/edit-states for Parts; empty/features for Part; Settings; Debug)
  at 390×844 via `scripts/screenshot-tour.mjs` plus an ad-hoc script for the rename/delete row
  states not on the tour's golden path — reviewed by eye, fixed the segmented-width and row-crowding
  bugs above before calling it done.
- Not done / for a later wave: `global.css`'s `.toggle-track`/`.visually-hidden` gaps above should
  get their real fix there once someone owns that file again, so every future `Ui.Toggle` use
  doesn't have to repeat this page-level workaround; the features table's VALUE/TOL columns wrap
  to two lines on a 390 px phone when the unit or "± " prefix doesn't fit — legible, not broken, but
  a narrower/denser layout would look tighter; face-slot size text ("1600 ×" / "1200") also wraps at
  72 px — same story.
## 2026-09-17 — Design wave 2 — annotate + A6 (agent/w2-annotate)

Restyle of the core screen onto the wave-1 foundation (DESIGN.md §11.2 "Annotate", §3, §4, §6,
§9) and SPEC §8a A6 (fit the view to the dimension when p2 lands). Files: `Annotate.res`,
`Annotate.css` (rewritten, 200 lines, tokens + global classes only), `annotate/Viewport.res`
(+`fitToSegment`, `lerp`, `cubicBezier`/`ease`) + `tests/ViewportTest.res` (+10, 30 total),
`bindings/Canvas.res` (`requestAnimationFrame`, `prefersReducedMotion`), `e2e/specs/annotate.spec.js`
(+3, 10 total), `docs/testids.md`. Two commits: restyle, then A6.

- **Layout.** Stage inset by the 16 px page margin on the photo mat with the 16 px radius, height
  `min(300px, --vv-height × 0.5)` (min 200) so it still shrinks with the iOS keyboard; the `.panel`
  below is edge to edge and stretches to the bottom of the screen (`min-height: 100%` on the page
  root resolves because `.shell-content` is a flexed item of a definite-height column — verified in
  the screenshot; where it doesn't resolve the panel simply ends early, nothing breaks). Never
  `fixed`, never glass.
- **Toolbar.** Top-right: `Ui.Pill` count, 44 px `.btn-icon` zoom out, mono `Ui.Pill` zoom readout
  (teal), zoom in; over the photo the icon buttons are flat scrim, no border (one material for
  everything floating on the canvas). Hint pill top-left in a reversed, wrapping flex row: at 390
  both fit on one line; on a 360 phone the hint wraps under the toolbar instead of clipping.
  Pills pass pointer events through to the canvas; only the buttons catch them. Canvas
  `focus-visible` is a 2 px `cc-text-3` inset ring, not amber.
- **Panel.** `Ui.Field` Reading — the input *is* the 38 px mono reading, unit Subhead `cc-text-2`
  beside it, placeholder `0.00`/`0.000` per units (hig-brief §2: placeholder *and* a persistent
  label); `Ui.Field` Name (mono 17, `feature_name` placeholder) + `Ui.ChipRow`/`Ui.Chip`;
  Kind (`Ui.Segmented`, `kind-` ids) and Tolerance (`Ui.Field`, ± prefix, unit) on one row; amber
  `Ui.Button Primary` block "Save dimension" → "Update" while editing; `Ui.Button Small` "Clear";
  `Ui.Button Danger` "Delete" only while editing. Errors are the Field's Footnote `cc-error` line
  (ids unchanged); the tolerance message sits under the whole row because its column is too narrow
  for a sentence. `aria-live="polite"` line `annotate-live` ("Dimension saved: overall_l 12.34 mm",
  cleared when the next p1 lands); the canvas wrapper is `role="img"` "End face, N dimensions" and
  contains only the canvas, so the toolbar buttons stay real controls; the canvas keeps
  `tabIndex=0` for the focus-return-after-save. Loading is the photo mat with a centred "Decoding…"
  pill (§7). Hint while editing reads "Editing <name>" — with the saved pair as the pending points,
  "Read the caliper" would mislead.
- **Judgment calls.** (1) Segmented options in this row are 14 px / 4 px padding (a page-scoped
  override of `.segmented-option`): "Diameter" at Subhead 15 semibold clips beside the 124 px
  tolerance column on 390 px with the wide fallback font — same call wave 1 made in the compat
  block. (2) `Ui.Button` has no Small+Danger combination and no `className` prop, so Delete is
  `variant=Danger` with a page rule for the small metrics (40 px, Subhead) — a `Ui.res` gap for the
  conductor. (3) `Ui.Pill` has no `className`/`ariaLabel` prop; the hint is wrapped in a div for
  positioning. (4) Class names deliberately avoid every selector in global.css §13i
  (`annotate-tools`, `annotate-unit`, not `-toolbar`/`-units`): the first screenshot showed the
  compat `.annotate-toolbar` scrim capsule painting a blob behind the new toolbar. The three
  remaining name overlaps (`annotate-stage`, `annotate-actions`, `annotate-tolerance`) are inert —
  same value, or matched only through legacy child/ancestor selectors this page no longer renders
  — so deleting §13 changes nothing here.
- **A6 math.** `Viewport.fitToSegment(~p1, ~p2, ~imageW, ~imageH, ~viewW, ~viewH, ~padding=0.15,
  ~minBox=0.1, ~fitScale, ~maxScale)`: bounding box in image px, never thinner than 10 % of the
  image per axis (two coincident taps still zoom to something sensible), grown 15 % a side, fitted,
  scale clamped to [fit, 8×fit], centred on the midpoint, then the ordinary pan clamp. A whole-image
  segment yields `fit` exactly. Tests cover horizontal/vertical/oblique (both ends inside with
  ≥ 10 % margin, transform legal), whole-image, the min-scale + offset clamp, the min box vs max
  scale, and degenerate sizes. `lerp` + `cubicBezier(0.2, 0.8, 0.2, 1)` (= `--cc-ease`, bisection
  on the x-polynomial) with pinned/monotone/identity tests.
- **A6 model.** `autoFit: option<{before, touched}>`, `tween: option<{gen, from, to}>`, `tweenGen`.
  p2 lands (`tap`) → `fitToPending`: `before` = the current view, or the earlier untouched fit's
  `before` if the user re-tapped without saving; `animateTo(target)` mints a generation and runs
  `tweenCmd(gen)`, a `Tea.effect` whose rAF loop dispatches `ViewportTick(gen, progress)` for 160 ms
  (one tick at 1 under `prefers-reduced-motion`, read at the edge via `WebApi.Platform.matchMedia`);
  `update` maps progress → `lerp(from, to, ease(p))`, and ticks whose `gen` isn't the live tween's
  are dropped, so a superseded loop can never move the view. `userMoved` (pan, pinch, zoom button)
  sets `touched` on the fit and drops the tween. `ViewSized` ends any tween at its target, refits,
  and while the pair is untouched re-fits it for the new stage size (the keyboard case) — instantly,
  the keyboard's own motion is enough. Save/Delete/Clear (and tap-off while editing) →
  `endAutoFit`: animate back to `clampViewport(before)` unless touched. **A pointerdown settles a
  running tween first** (`settle`), and `data-transform` reports the tween's *target* while it
  runs, so a tap computed from the attribute lands where it says; `data-autofit` is
  `fitting|fitted|touched|none` (`fitting` covers the restore too — the useful signal for tests is
  "the view is moving"). Documented in docs/testids.md.
- **The race that bit.** The first full e2e runs had `export.spec.js` lose a dimension twice (the
  golden path's `head_h`, the kind-conflict test's second `wall`): `addDimension` reads
  `data-transform` straight after the previous save's Enter, while the Store write is still in
  flight — so it read the *fitted* view of the pair just saved, which put the next p1 outside the
  canvas box, and the click missed. Pre-A6 the transform never changed at Save, so that early read
  was harmless. Two fixes, both in the app (the spec is another page's contract): (1) the restore
  starts when the save is *initiated* (`trySave`, `DeleteClicked`), not when `Saved` lands — the
  Enter/tap is a React discrete event, so the render flushes synchronously and the published
  transform is the restored view before Playwright's key/click call even returns (the
  `Saved`/`Deleted` restore stays as a no-op safety net); (2) the redraw is a `useLayoutEffect`,
  so the hooks commit with the render instead of a frame later. The narrower pre-existing window
  (a tap placed before the write completes is wiped by `clearEntry`) is unchanged.
- **Verification.** `rescript build` clean under `+a`; vitest 162/162; Vite build clean; Playwright
  chromium on port 3230, 26/26 (23 existing + 3 A6) three runs in a row after the fix; screenshots at 390×844 (loaded, p1, pending/fitted at 3.06×, saved,
  errors, editing, `--vv-height` 500 re-fit, 360-wide wrap) in the scratchpad, reviewed by eye.
  **Unverified here:** the iOS keyboard sequence (p2 → keyboard → `visualViewport` resize → re-fit
  → Save → restore → keyboard closes) and the tween's feel on device — phone check.
## 2026-09-17 — A7 custom faces (agent/a7-faces)

SPEC §8a A7, owner-approved JSON delta. A face now carries `label` (unique-per-part slug under the
feature-name rule) next to `kind` (the sketch-plane hint). Defaults keep `label == kind`, so nothing
about the four default faces — testids, export paths, golden — moved. `schema` stays
`caliper-companion/features/1`.

- **Core**: `Types.face.label`; `Codec` encodes it and decodes a missing one as `kind` (a non-string
  `label` is treated the same — lenient, tested); `FeaturesDocument` emits `"label"` right after
  `"kind"`, names `image`/`annotated` from it, and sorts faces by kind rank then label. Golden
  regenerated with the same injected dates — the diff is exactly three added `"label"` lines.
  The compiler now emits one early `return` per required field in `decodeFace`, so a per-field
  reject loop was added to keep core at 100 % line coverage (193 tests, branches 98.6 %).
- **Store**: face docs carry `label`; `FaceDoc.fromDoc` defaults it to the kind, so the face docs
  already on the owner's phone keep reading back (tested through a raw PouchDB handle writing a
  label-less doc). `facesOf` orders kind, then label. No `faceLabelsOf` — the Capture page already
  holds `facesOf`'s result and checks uniqueness against it plus its own unsaved chips.
- **Export**: `Bundle.faceBundle` carries `label` (kind was only ever used for the entry name);
  the missing-image error names the label.
- **Capture page** is keyed by label end to end. Chips are *derived* (`chipsOf`): the four
  defaults, captured custom faces from `faces`, then page-only `customChips` (unsaved, SPEC A7
  bullet 6). One camera + one library `<input>` per chip, always mounted (`capture-file-<label>` /
  `library-file-<label>`) — the "eight inputs" contract generalises to 2×N. "+ Custom" opens an
  inline `.list-group` card in place of the shutter block (like the recapture card): mono name via
  `Canvas.Input` (the one `<input>` path with `enterkeyhint`), `Ui.Field` error, `Ui.Segmented`
  plane picker, primary "Add face", Cancel. Enter adds. Uniqueness is checked against every chip,
  so `top` (uncaptured default) and an unsaved custom chip are both rejected. Recapture is by face
  (`existingFaceOf` by label → same id) so `side` and `left_side` coexist. A custom chip with no
  face shows "Remove chip" in the shutter block; captured ones are deleted from Part.
  - Judgment calls: tapping any chip closes the custom card; the slot row now reuses
    global.css's `.chip-row` scroller (N slots); no auto-focus on the name field (`Canvas.Input`
    has no `autoFocus` prop and bindings are outside this track) — one extra tap, flagged.
- **Part page**: slots iterate `faces` in Store order with `face-<label>`; default labels keep
  `.face-slot-label` (capitalised "Top"), custom ones render mono as-is. Features' faces column
  shows labels. "Edit faces" (`faces-edit`, small) swaps the slot row for an inset list with a
  Remove per face (`face-remove`, inside the `face-<label>` row); tapping one shows an in-flow
  error warning row + `face-delete-confirm` / `face-delete-cancel`; confirm calls
  `Store.deleteFace` (removes its dimensions) and reloads faces + dimensions.
  - Judgment call: Remove is a `Ui.Button Danger` capsule, not "small" — `Ui.Button`'s variants
    are exclusive and `.btn-small`'s field background would override `.btn-danger`'s; adding a
    small-danger variant is a `Ui.res` change outside this track. `Part.css` untouched (sibling
    owns it); the edit list needs no page CSS.
- **Annotate**: `title` only — `"<Label> · <part>"` with the first letter capitalised for display
  (`End · Hinge pin` for defaults, unchanged; `Left_side · Hinge pin` for a custom face).
- **e2e** `faces.spec.js` (4 tests): the A7 bullet-7 scenario (left_side on Side, capture
  `side.jpg`, one dimension, export → `faces/left_side.jpg` + `faces/left_side_dimensioned.png`,
  face `{kind: "side", label: "left_side"}` with `label` right after `kind`, default `top` paths
  unchanged); inline rejection of duplicate/default/invalid labels + Enter-to-add + chip removal;
  recapture-by-face coexistence + Part-page delete (dimension goes too, survives reload); a
  pre-A7 label-less face doc seeded via PouchDB reads back as `side` on Part/Capture/Annotate.
- New testids (docs/testids.md): `capture-chip-<label>`, `custom-face`, `custom-face-card`,
  `custom-face-label`, `custom-face-error`, `custom-face-plane-<kind>`, `custom-face-add`,
  `custom-face-cancel`, `custom-face-remove`, `faces-edit`, `faces-edit-list`, `face-remove`,
  `face-delete-confirm`, `face-delete-cancel`; `face-<kind>` → `face-<label>` (identical for
  defaults). Nothing existing changed.
- Verified: `npx rescript build` clean under `+a`, `npm test` 193/193 (core 100 % lines),
  `npm run build`, Playwright Chromium **30/30** (26 existing + 4 new, `E2E_PORT=3320`).
  Screenshots at 390×844 (custom card open, duplicate error, custom chip selected, annotate
  title, custom face captured, Part slots, Part edit/delete confirm) reviewed by eye.

## 2026-09-17 — Design wave 3a — foundation fixes (agent/w3-foundation)

Closed the `Ui.res`/`Icon.res` gaps the four wave-2 page agents reported (see "Design wave 2 —
lists"/"capture"/"annotate + A6" above), deleted wave 1's compatibility CSS now that every page is
confirmed restyled off it, and fixed two visible layout defects. Files: `src/global.css`,
`src/app/components/{Icon,Ui}.res`, `src/app/pages/{Settings,PartsList,Annotate,Part}.css`,
`src/app/pages/PartsList.res`. Four commits: components, annotate toolbar, compat removal, tables.

- **`Ui.Toggle` hit-testing** (global.css §9). Root cause exactly as wave 2's Settings.css comment
  diagnosed it: the decorative `.toggle-track` (later in the DOM than the real `<input>`, both
  `position` with `z-index: auto`) painted on top and intercepted every click meant for the input;
  the shared `.visually-hidden` utility's `clip: rect(0,0,0,0)` additionally made the input
  un-hit-testable even once the track got out of the way. Fixed at the component: `.toggle-track`
  is `pointer-events: none`, and the input gets its own `.toggle-input` class — `opacity: 0` over
  the full 52×32 switch, not the shared clip utility (which other, genuinely-hidden inputs —
  Capture.res's file inputs, PartsList's synced `<select>` — still use unmodified). Deleted the
  `.wedge-row` workaround from `Settings.css`; `parts.spec.js`'s `wedge-toggle` click test is the
  regression guard.
- **`Ui.Segmented`**: `width: 100%` by default (a `<div style="display:flex">` is still a flex ITEM
  in whatever row it sits inside, and shrinks to its label text without an explicit width — the
  wave-2 lists report's exact diagnosis), `~inline` prop to opt out. Crowding fix: 12 px option
  padding + 4 px container gap (previously segments were flush against each other with only 8 px
  padding total, no gap at all — the amber pill and the next label touched). Removed the now-
  redundant `.parts-form-row .segmented { width: 100% }` page override; kept Annotate's page-scoped
  14 px/4 px override (the kind row still shares 124 px with the tolerance field, and "Diameter" at
  the new 12 px/Subhead-15 base still doesn't fit in what's left — verified by not being able to
  remove it without the label clipping again).
- **`Ui.Button`**: added `~size: Regular | Small` decoupled from `~variant` (`.btn-compact`, sizing
  only, composes with any colour) and a borderless `Plain` variant (`.btn-plain`) per the capture-
  wave gap report. `~className` passthrough. `variant=Small` stays as a deprecated alias (renders
  identically to before) — `Annotate.res` and `A2hsHint.res` both still pass it and are out of this
  track's file ownership.
- **`Ui.Pill`**: `~className`/`~ariaLabel` (the annotate-wave gap report). **`Ui.Field`**: `~after`,
  rendered between the input and the error, for a chip row inside a field.
- **`Ui.ListRow`**: added `~href`, which renders the title/meta body (+ chevron) as a real `<a>` with
  `~leading`/`~trailing` as plain siblings outside it — the fix for the exact gap the lists-wave
  report named: `Ui.ListRow`'s old `onClick` wrapped the *whole row* in a `<button>`, which can't
  coexist with sibling Rename/Delete buttons (button-in-button is invalid HTML), so PartsList had
  hand-rolled its row instead. `PartsList.res` now uses `Ui.ListRow` for the Normal row state
  (Renaming/ConfirmingDelete stay a plain container — they're a form/confirm strip, not a
  navigable row). Rename became an icon button (new `Pencil` icon, `aria-label="Rename"`), which
  also freed enough row width to go back to a single-line row instead of wave 2's stacked two-line
  layout. `part-row`, `part-rename`, `part-delete` and the inline editor ids are all unchanged.
  **Self-caught regression**: my first pass nested the chevron straight inside `.list-row-body`
  (a flex *column* — Title over Meta), which stacked the chevron under the meta line as a third
  line instead of beside the text — caught from a screenshot, not e2e (no test asserts chevron
  position). Fixed by giving the anchor its own class, `.list-row-link`, that's a flex *row* (Title/
  Meta column + chevron side by side) and moving `flex: 1 1 auto`/`min-width: 0` onto it instead of
  `.list-row-body`. Also added `text-overflow: ellipsis`/`white-space: nowrap` to `.list-row-meta`
  (previously unclipped) since a navigable row's text column is narrower now that it shares the row
  with `~trailing` actions — without it "mm · updated today" wrapped to two lines.
- **Icon**: added `Pencil` and `FolderPlus` (Lucide v1.47.0, same source/citation as the existing
  set); `FolderPlus` isn't used by anything on this track, added per the brief for whoever needs it
  next.
- **Annotate toolbar collision** (`Annotate.css` only — `Annotate.res` isn't this track's file).
  Root cause of the "oversized black disc": `.annotate-tools` is a flex row with no `align-items`
  of its own, so the default `stretch` cross-axis alignment stretched the count `Ui.Pill` to the
  44 px height of its button siblings — a near-square box at `border-radius: 999px` renders as a
  circle. `align-items: center` fixes it outright. Relaid the group as one flat scrim capsule (the
  group itself carries `cc-scrim`; the buttons/pills inside go transparent so nothing paints a
  second, overlapping capsule) with the count as a compact mono figure. The hint pill's top-left
  position and 360 px wrap-below were already correct (`.annotate-overlay`'s existing `flex-wrap`)
  and needed no change — confirmed by screenshot, not assumed.
- **Compat removal** (`global.css` §13, ~384 net lines). Verified dead before deleting, not just
  assumed: `grep -rn -- "--color-"` outside `global.css` matches only a Capture.css comment noting
  it does *not* use the aliases (no real `var(--color-*)` usage anywhere; `theme.css` never defined
  any of its own, so there was nothing to re-alias); every §13b-i selector (`.page`, `.sheet`,
  `ul.list`, `.face-tile-*`, `.timers-table`, `.toggle-row`, `.face-row-*`, `.capture-btn*`, every
  `.annotate-toolbar`/`-zoom`/`-count`/`-chips`/`-segmented`/`-primary`/`-secondary`/`-danger`
  compat name) turned up zero real references in any `.res`/`.css` — the wave-2 annotate report
  already flagged that it deliberately avoided these names for exactly this reason. **One
  exception**: `.a2hs-hint*` (§13j) is current, real styling for `A2hsHint.res` — a component this
  track doesn't own and has nowhere else to put CSS for — not a wave-1 rename shim that happened to
  live in the same section. Kept, renumbered to a plain §13 with a note explaining why it survived.
- **Features table / face-slot** (`Part.css` only — `Part.res` isn't this track's file), closing two
  items wave 2's lists report explicitly deferred ("not done / for a later wave"). VALUE/TOL/FACES
  wrapped at 390 px for two compounding reasons: `.features-table td { font: ... }`'s shorthand
  (higher specificity than the shared `.mono` utility's longhands) was silently resetting every
  numeric cell back to the proportional UI font despite carrying the `mono` class, and nothing
  stopped the cells wrapping regardless. Tried the standard `table-layout: fixed` + tiny-percentage
  trick first (give NAME `width: 100%`, the rest `width: 1%`) — **it does not work**: fixed layout
  takes a specified width literally including padding under `box-sizing: border-box`, and a column
  narrower than its own padding renders degenerately (verified empirically with `getClientRects()`
  on the text nodes: Chromium laid VALUE/TOL/FACES text out starting past the cell's own right
  edge, off past the 390 px viewport — invisible, not clipped). Replaced with `display: grid` +
  `display: contents` on `thead`/`tbody`/`tr`, which doesn't have that failure mode: a
  `minmax(0, 1fr)` NAME track can shrink+ellipsis below its content width the way a real grid item
  can, `auto` tracks size VALUE/TOL/FACES to exactly what they need, and CSS selectors (e.g.
  `tr:last-child td`) still work since `display: contents` doesn't remove elements from the DOM.
  Also tightened cell padding toward DESIGN.md §4's literal "9 px row padding" (was 10 px/14 px,
  which cost a four-column row over 100 px in pure padding — freed that back to NAME, which still
  ellipsizes on a genuinely long name like `overall_l` but no longer to an unreadable 4 characters).
  Face-slot caption ("1200 × 1600") wrapped across the spaces around "×" in the 72 px slot —
  `white-space: nowrap` (the row already scrolls horizontally via `.chip-row`, so a slightly wider
  caption just claims more of that scroll room); widened the slot 72 → 78 px so the common case
  doesn't need the overflow at all.
- **Judgment calls**: kept `variant=Small` on `Ui.Button` as a deprecated alias rather than migrating
  every call site, since two of its three call sites (`Annotate.res`, `A2hsHint.res`) are outside
  this track's file ownership — the brief explicitly allows this. Kept the Annotate `.annotate-kind
  .segmented-option` page override after re-verifying it's still load-bearing post-fix, rather than
  assuming the base-component fix made it redundant. Widened `.face-slot` and reduced the features
  table's padding a few px beyond what the brief asked for outright — both are direct, minimal
  consequences of the "don't wrap"/"one line" requirements, not scope creep.
- Not done / for a later wave: the flaky `Store — parts > deletePart` unit test (fails
  intermittently only under vitest's parallel-worker full-suite run, passes standalone and 4/5 runs
  otherwise) is pre-existing and outside this track's file ownership (`src/store/`) — reproduced on
  a clean stash of this branch before any of this wave's edits, so it isn't a regression from this
  work; flagging for whoever owns Store next, likely a shared in-memory PouchDB adapter/DB-name
  collision across parallel test files.
- **Verification.** `rescript build` clean under `+a` (full clean rebuild, 65 modules); `npm test`
  181/181 (run 3× to confirm the Store flake above isn't from this track); `npm run build` clean;
  `E2E_PORT=3310 npx playwright test --config=e2e/playwright.config.js --project=chromium`
  **26/26** on Chromium, twice (once before, once after the ListRow-chevron/features-table fixes
  found during screenshot review). Screenshots at 390×844 via `scripts/screenshot-tour.mjs` against
  `vite preview --port 3311`, reviewed by eye each iteration — caught and fixed the chevron-stacking
  regression and the features-table `table-layout: fixed` failure this way, neither of which any
  existing spec would have caught.

## 2026-09-17 — A5 snap wiring + save race (agent/a5-wiring)

The UI half of SPEC §8a A5 (bullets 2–4, 6) on top of `agent/w2-edgesnap`'s pure module, plus two
robustness fixes. Files: `Annotate.res`/`.css`, `annotate/Draw.res` (`snapRing`),
`bindings/Canvas.res` (`asSnapBitmap`), `store/Store.res`+`.resi`+`tests/StoreTest.res`
(`settings.snap`, flake fix), `pages/Settings.res` (row), `e2e/specs/annotate.spec.js` (+5, 15
total), `docs/testids.md`. Five commits: settings.snap; wiring + toggle + feedback; e2e; save race;
store flake.

- **Patch and cast.** `load` builds the 1024-px luma patch right after the oriented decode
  (`ImageData.lumaPatchOf` through `Canvas.asSnapBitmap`, the one sanctioned `%identity` cast, with
  the same justification as `ImageDecode.asCanvasBitmap`; Canvas.res's header now names it) and
  caches the patch's edge floor (`EdgeSnap.cutoff`) beside it in `loaded`. A patch that fails to
  build only disables snapping. Building it inside `load` (not as a later cmd) means the canvas
  never exists without it — no "tap before the patch arrived" window for tests or thumbs.
- **Radius math.** Window in patch px = `css / viewport.scale × (patch.width / imageW)`: screen →
  image px through the viewport scale, image → patch px through the patch/image ratio. At the
  390×844 fit scale on top.jpg (0.224, patch ratio 0.64) 24 css px = 68.6 patch px; at 8× fit it's
  8.6. Finger-sized on screen at any zoom, as the brief asked.
- **Two calls the module left open — both decided against the real top.jpg patch, not by eye.** I
  dumped the actual 1024×768 luma the page builds (Chromium `drawImage` + `getImageData`, same
  Rec.601 rounding) and ran the compiled `EdgeSnap.res.mjs` over every tap the specs make. Two
  findings forced app-side rules. (1) *A tap already on an edge is left alone*: `snapPoint`/`snapPair`
  pick the **strongest** gradient in the window, and the fixture's hole (black on the bar, step 100)
  beats the bar's own edge (step 85). An exact-edge tap at (0.30, 0.35) — export.spec's `pin_dia`,
  a spec this track doesn't own — was pulled onto the hole (0.28, 0.40) at a flat 24 px, and even at
  16 px. So `onEdge`: if the tap's own patch pixel clears the cached floor it is not a miss, and it
  stays (mark `Unsnapped`, no ring). Snapping corrects near-misses; pulling a good tap onto a
  stronger neighbour is worse than not snapping. (2) *Two windows, near then full*: `[16, 24]` css
  px. SPEC bullet 6's own test — a tap 12 px inside the left edge — landed on the hole (21 px away)
  at a flat 24 px (`0.2676`, not `0.17`). Searching 16 px first lets a nearer edge beat a stronger
  one further out; the 24 px reach is kept for a tap that missed by more. For `snapPair` the walk
  is repeated per window and each end keeps its first hit. With both rules every existing spec
  passes with snap **on** (its default) — no spec outside this track's ownership was touched.
- **Observation for the EdgeSnap owner (not fixed here, not this track's file).** `snapPoint`'s
  argmax has no distance weighting, so along a straight edge the winner is decided by whichever
  pixel is noisiest — a first tap can slide *along* the edge by up to the radius. The synthetic
  fixture hides it (a flat colour step has exactly equal magnitudes along the edge, so the
  nearest-to-tap tie-break wins: y stays 0.4505); a real photo won't. A distance-weighted score, or
  restricting the first tap to the normal direction once an edge is found, would fix it. Also:
  `snapPoint`/`snapPair` recompute `medianGradient` (49k samples + sort) on every call, so the
  two-window search costs 2–4 medians per tap; a `~floor` parameter would let the page pass the
  cached one.
- **Marks.** `snapMark = Unsnapped | Snapped | Dragged` per pending point. `Dragged` is set when a
  drag of a pending handle or body is *released* (a cancelled drag reverts the points, so their marks
  stand) and is sticky: `snapSecond` skips a `Dragged` p1. Selecting a saved dimension resets both.
  `data-snapped="p1,p2"` reports `Snapped` only.
- **Ring.** `Draw.snapRing`: a second amber circle (halo underneath) growing 1.0→1.6× the handle
  radius while fading, 150 ms, driven by the same rAF effect as the A6 tween — `tweenCmd` became
  `frames(~ms, gen, tick)`, used by both. Reduced motion ticks straight to 1, which removes the
  ring before it renders (the effect's dispatch batches with the tap's own update). One ring
  animation carries both ends of a `snapPair`.
- **Toggle.** `snap-toggle` is a `<button class="pill annotate-snap">` inside the scrim capsule
  (`Ui.Pill` is a span; the toolbar's group rule already makes children transparent), Ruler icon at
  16 px (no magnet in `Icon.res`, not this track's file), 44 px tall for the tap target, amber text
  on / `cc-text-2` off. Persists via `putSettings`; a failed write flips back with the inline error.
  `Saved(Ok)` keeps `snap` from the live settings rather than the save's snapshot, so a flip during
  an in-flight save isn't undone. **Layout consequence:** the capsule can't fit a fifth control beside
  the hint at 390 px, so the hint pill now wraps under the toolbar there (wave 2's 360 px fallback,
  `.annotate-overlay`'s `flex-wrap`) — screenshot-checked, nothing clips or overlaps, pills still let
  taps through. If the conductor wants the hint back on one line at 390, the count pill or the zoom
  readout has to give; not decided here.
- **Settings row.** "Snap taps to edges" (`snap-setting-toggle`, `Ui.Toggle`) in its own
  `Ui.ListGroup` with a footer pointing at the pill. `SaveFinished` now carries which toggle flipped
  so the revert is the right one.
- **Save race.** `begin` clears the entry, starts the A6 restore *and* returns focus to the canvas at
  `trySave`/`DeleteClicked`, keeping the cleared entry in `inFlight`. `Saved(Ok)` only reloads dims and
  announces — it no longer calls `endAutoFit` (a pair placed during the flight is legitimate and
  keeps its fit; the old call was the wipe). `Saved(Error)`/`Deleted(Error)` restore the entry with
  its fit **only if the user hasn't started a new one** (`entryUntouched`); otherwise theirs stands
  and the failure is only the error line. Judgment call: never clobber fresh input to bring back old.
- **Store flake, reproduced then fixed.** 25 runs of the store file under CPU contention (two busy
  node loops) hit it once: `deletePart … expected 2 to be 1`. Cause: `Store.make` kicks off
  `ensureIndexes` in the background, each index is a `_design/` doc, and `allDocs().total_rows`
  counts design docs — the second index write landed between the test's `before` and `after` counts
  (one design doc before, two after). Fix: `await Store.ensureIndexes(store)` (idempotent, and the
  indexes test already does the same concurrently) before the first count. Also: `listParts orders
  updatedAt descending` could tie in the same millisecond (then sorts in random uuid order) — the
  test now waits for `Clock.nowIso()` to pass `b.updatedAt` before re-saving `a` and asserts the
  strict order; and every Store a test opens is registered and destroyed in a local `afterEach`
  (binding added in the test file — `core/Vitest.res` isn't this track's), so a failed assertion no
  longer leaves a LevelDB handle open. 25 more contention runs after the fix: 0 failures.
- **Verification.** `npx rescript build` clean under `+a`; `npm test` 194/194; `npm run build` clean;
  `E2E_PORT=3410 … --project=chromium` **35/35** (30 existing + 5 A5), export/faces specs passing
  with snap on; screenshots at 390×844 (Snap on, ring mid-flight, snapped pair fitted, Snap off, 360
  wrap, Settings row) in the scratchpad, reviewed by eye. **Unverified here:** WebKit/phone — the
  ring's feel and the pill under a thumb.
## 2026-09-17 — Design wave 3b — a11y + polish (agent/w3-polish)

Accessibility sweep + gap-note polish (DESIGN.md §9/§11) over the pages this track owns
(`PartsList`, `Part`, `Capture`, `Debug`) plus `Ui`/`Icon`/`Shell`/`A2hsHint`/`global.css`/
`theme.css`. `Annotate.*`/`Settings.*`/`Store.*`/`Canvas.res` are `agent/w3-foundation`'s sibling
track — read for audit/reuse, never edited.

- **`Ui.Live`**: a new visually-hidden `role="status" aria-live="polite"` component, mounted
  unconditionally in every owned page's `view` (never behind a conditional — a live region only
  announces *changes*, so one that appears after the fact is never heard). `PartsList` announces
  "Part created" / "Part deleted"; `Part` announces "Export ready: `<file>`" / "Export shared" /
  "Export failed: …" (built from the export `result`, not the already-composed display string, so
  it doesn't nest "Export ready:" in front of "Downloaded …"); `Capture` announces "Face captured:
  `<label>`". `PartCreated`/`Saved` both navigate away almost immediately after setting their
  announcement (`Route.push`/`TimerStarted`), so those two are mostly symbolic — an AT may not get
  to speak them before the live region itself unmounts. Flagging rather than skipping, since
  DESIGN.md §9 asks for them regardless and there's no cheap way to delay the navigation for it.
- **Focus management** (DESIGN.md §9). `PartsList`: `NewPartClicked`/`RenameStart` focus the
  create/rename input; `DeleteDone` focuses `new-part` (present whether the list is now empty or
  not — doubles as "focus goes to the list"). `Capture`: `CustomOpen` focuses
  `custom-face-label`; `RecaptureCancelClicked` focuses the shutter — which needed a
  `dataTestId="shutter"` + `tabIndex={-1}` added to it, since a `<label>` isn't natively focusable
  and this is a programmatic-only target, never in the Tab order itself. All four go through a
  local `focusTestId` cmd, duplicated per page (`PartsList.res`, `Capture.res`) rather than shared
  — same reasoning as the existing duplicated `describeError`: no page-shared module is in this
  track's file-ownership list to hang a common one on.
  - **Real binding, not a new one**: `src/bindings/Canvas.res` (read-only from here) already
    exports `byTestId`/`focus` — the exact pair Annotate.res's own `focusTestId` uses — so nothing
    needed adding to `Ui.res`, despite the brief's fallback instructions anticipating that might be
    necessary.
  - **The microtask deferral is load-bearing, not decoration.** `Tea.res`'s `dispatch` runs a
    msg's `cmd` *synchronously*, right after handing the new model to React's `setState` — before
    React has actually re-rendered/committed the DOM (see `Tea.res`'s own doc comment on `use`).
    Annotate's `focusTestId` gets away without this because its targets (`reading`, `name`,
    `annotate-canvas`) are already mounted before the msg that focuses them; a freshly-opened
    form's input isn't. Deferring one `Promise.resolve().then(...)` microtask — no new binding,
    `Promise` is already how `Tea.fromPromise` itself is built — reliably lands after React's
    synchronous-event commit. Verified empirically (a throwaway script, not committed) before
    relying on it, not just assumed.
- **`.capture-view:has(.input-selected-camera:focus-visible)` / `…-library…`** (`Capture.css`):
  found and fixed a **dead CSS rule**. `.shutter:focus-within:has(input:focus-visible)` (and the
  matching one for the "From library" label) can never match — the hidden camera/library `<input>`
  the label is `htmlFor` isn't a DOM *descendant* of that label (`hiddenInputs` renders every
  chip's inputs elsewhere, deliberately independent of `selectedLabel`/`model.dialog` — see
  `Capture.res`'s own module-end notes), so `:focus-within`/`:has()` had nothing to find. Since
  there's no way to key a static CSS rule to an arbitrary custom face's *id*, the fix is a static,
  non-dynamic class (`input-selected-camera`/`input-selected-library`) `renderCaptureInput` adds to
  whichever chip's input pair is currently selected, plus `:has()` reaching sideways from that
  class at the shared `.capture-view` root to the sibling label representing it — one rule, works
  for every label, default or custom.
- **`.slot-check`** (`global.css`, used by `Part.res` and `Capture.res`): a small teal check badge
  on captured thumbnail slots (DESIGN.md §9 "Color is never the only signal"). The teal ring vs.
  dashed-empty border already differ by shape as well as hue, but the badge also covers the gap
  between a face record resolving and its object-URL thumbnail actually loading, and doesn't
  depend on being able to tell teal from the empty slot's `cc-border` grey at a glance. `.slot`
  moved from `overflow: hidden` to `overflow: visible` (with `.slot-captured` alone carrying
  `hidden`, so the photo itself still clips to the tile) so the badge can sit half outside the
  56 px box without being cut off.
- **Semantics (DESIGN.md §9).** `Ui.ListGroup` gained `~asList` (`role="list"` on the container,
  default off — the component also wraps plain form-field groups and, in `Part.res`, a `<table>`,
  neither of which is a list); `Ui.ListRow` now always carries `role="listitem"` unconditionally
  (its whole purpose is "one row of a list" wherever it's used — checked every call site first:
  only `Part.res`/`PartsList.res` use it, both now flagged `asList`). Hand-rolled `.list-row`s that
  don't go through `Ui.ListRow` (`PartsList`'s Renaming/ConfirmingDelete strips, `Debug`'s timer
  rows) got `role="listitem"` added directly. `Part.res`'s features table: found the CSS-grid
  layout (`display: grid` + `display: contents` on `thead`/`tbody`/`tr` — wave 3's fix for the
  "VALUE/TOL wrap" bug, see that entry) silently strips the *implicit* `table`/`row`/`cell` ARIA
  roles Chromium/Firefox normally compute from the HTML tag, once `display` stops being
  `table`-family — a real, documented CSS-Display/Core-AAM interaction, not a hypothetical; the
  table was structurally a `<table>` but wasn't exposed as one to a screen reader. Fixed with
  explicit `role="table"`/`"rowgroup"`/`"row"`/`"columnheader"`/`"cell"` plus `scope="col"` on the
  headers, restoring real semantics regardless of the CSS `display` value — DESIGN.md §9's own
  parenthetical ("role=table grid with proper roles if it stays a CSS grid") anticipated exactly
  this. `lang`/`<main>` landmark were already correct (index.html, `Shell.res`) — verified, not
  touched (index.html is outside this track's file-ownership list regardless).
- **Focus-visible rings**: audited every interactive class. Most already had a ring via the base
  `button, .btn { ... }` rule in `global.css` (every `<button>` tag, regardless of class, already
  gets one — chips, segmented options, the Capture slot buttons). The real gap was plain `<a>`
  elements, which had none: added a blanket `a:focus-visible` rule, plus an inward `-2px`-offset
  override on `.list-row-link` specifically (it sits inside `.list-group`'s `overflow: hidden`, so
  an outward ring at a row near the card's rounded edge would get clipped — same reasoning the
  existing `button.list-row:focus-visible` rule already used). `touch-action: manipulation` added
  to `.list-row-link`/`.face-slot` (the two custom controls in scope that are plain `<a>`s, not
  `.btn`/`<button>`, so they didn't inherit it from the base rule). `-webkit-tap-highlight-color`
  moved onto the universal `*`/`::before`/`::after` reset in addition to `html` (belt and
  suspenders — it isn't a true inherited property, some engines want it closer to the tapped node).
- **Reduced motion**: audited every page's CSS for `transition`/`animation`. Already fully covered
  by the existing blanket `@media (prefers-reduced-motion: reduce) { *, *::before, *::after {
  transition-duration: 0ms !important; ... } }` in `global.css` §12 — the `!important` universal
  rule beats any more specific duration regardless of what adds a transition later, so nothing
  page-specific was needed; confirmed rather than assumed.
- **Contrast audit** (DESIGN.md §2/§9): computed WCAG relative-luminance ratios for every listed
  token pair with a throwaway node script (not committed). All six pass 4.5:1 — `cc-text-2` on
  `cc-surface-2` 6.58:1, `cc-text-3` on `cc-surface` 4.52:1, `cc-amber` on `cc-ground` 8.52:1,
  `cc-amber-ink` on `cc-amber` 8.05:1, `cc-teal-ink` on `cc-teal-wash` 10.48:1, `cc-error` on
  `cc-ground` 5.91:1. A few extra pairs actually used in owned pages were also checked (list/table
  text on `cc-surface`, footnote/caption on `cc-ground`, the primary-button pressed state, etc.) —
  all pass; the one pair under 4.5 (`cc-error`'s own icon-stroke colour composited onto the
  translucent `warning-row-error` wash, 4.42:1) is a **graphic**, not text, so the applicable WCAG
  bar is 1.4.11's 3:1, which it clears with room to spare. No token or usage changes needed.
- **Gap-note polish**: `.stack-lg` gained its missing `display: flex; flex-direction: column`
  (previously `gap`-only — a bare `.stack-lg` div, which is every owned page's outermost `view`
  wrapper, rendered as a plain block with margin-collapsed children instead of the intended
  `cc-space-5` vertical rhythm; confirmed visually via the screenshot tour before and after).
  Capture's recapture-card and custom-face-card Cancel buttons, and A2hsHint's "Later", moved to
  `Ui.Button ~variant=Plain`. Part's per-face Remove (in the faces-edit list) and the "Edit
  faces"/"Done" toggle both moved off the deprecated `variant=Small` alias — Remove to
  `variant=Danger size=Small` (per the brief), "Edit faces" to `variant=Secondary size=Small`
  (a judgment call: DESIGN.md's "Small button" spec is `cc-field` background with no colour
  connotation, which `Secondary` — `cc-surface` bg, bordered, neutral — is the closest existing
  colour variant to, not `Danger`/`Primary`). Capture's own `custom-face-remove` (the "Remove
  chip" button in the shutter block, `variant=Small` before this wave) got the same
  `variant=Secondary size=Small` treatment, added to the brief's `variant=Small` sweep since it's
  in this track's file (`Capture.res`) even though the brief's item 9 didn't name it explicitly.
- **Icon-only aria-label audit** (item 1): every `Ui.Button ~variant=Icon` call site in owned files
  (`PartsList`'s Rename/Delete) and every other icon-only control (`Shell`'s Back, `Capture`'s
  shutter, `PartsList`/`Part`'s icon-only rows) already carried an `ariaLabel` from prior waves —
  audited, nothing to fix. `~ariaLabel` stayed optional on `Ui.Button` per the brief (Annotate's
  zoom buttons, outside this track, need it settable but Annotate can't be edited to make it
  required without breaking that call site).
- **`e2e/specs/a11y.spec.js`** (new): on `#/`, a part page and the capture page — every
  `role=button` resolves to a non-empty accessible name, the features table exposes real
  `role="columnheader"`/`scope="col"` headers (the regression guard for the CSS-grid/ARIA-role fix
  above, not just "does a `<table>` exist"), each page's live region is attached, `New part`
  autofocuses the name field, and a keyboard-only Tab pass reaches Back first (where the page has
  one) then moves forward into real content. Two more tests exercise the specific focus-management
  paths this wave added directly (custom-face card autofocus, recapture-cancel → shutter, rename
  autofocus, delete → New part) since nothing else in the suite touches them.
  - **Found and worked around a Chromium/Playwright quirk while writing the keyboard-order test**,
    not an app bug: the very first `page.keyboard.press('Tab')` after a same-document SPA route
    change (e.g. `page.goto('/#/parts/x')` from `/#/parts/x/faces/y`) can skip straight past the
    (fully focusable, DOM-order-first, verified via a throwaway script) Back button to something
    further down the page — `document.activeElement` reports `<body>` at that point, but Chromium
    still anchors "first Tab" sequential-navigation search to wherever the last real user
    interaction was, and that anchor can survive a hash-only navigation even once the element
    itself is gone. A genuine `page.reload()` right before each keyboard-order assertion gives a
    real clean starting point (and is arguably more representative anyway — a keyboard user
    actually arriving at the URL fresh, not mid-SPA-session).
- **Not done / for a later wave**: focus management wasn't extended to `Part.res`'s own face-delete
  flow (`FaceDeleteConfirmed`/`FaceDeleted`) — the brief's item 4 names "a part" specifically, not
  "a face", and the parallel improvement (focus `faces-edit` or the list after a face is removed)
  is a reasonable follow-up but out of this wave's explicit scope. The hidden capture/library
  `<input>`s themselves still have no visible focus indicator of their own when Tab-focused
  directly (only the *label* they're `htmlFor` gets a ring now, via the `:has()` fix above) — an
  element that must stay fully invisible for the design can't also paint a visible outline on
  itself; this is the best available fix without restructuring the "always-mounted, selection-
  independent inputs" architecture, which is deliberate (SPEC §8a A4 / docs/testids.md) and out of
  scope to change here.
- **Verification.** `rescript build` clean under `+a` (full clean rebuild, 65 modules); `npm test`
  193/193; `npm run build` clean; `E2E_PORT=3420 npx playwright test --config=e2e/playwright.config.js
  --project=chromium` **35/35** on Chromium (30 existing + 5 new `a11y.spec.js`), twice (once
  before, once after the keyboard-order/Tab-reload fix above). Screenshots at 390×844 via
  `scripts/screenshot-tour.mjs` against `vite preview --port 3421`, reviewed by eye — the
  `.stack-lg` fix and the captured-slot check badges are both visible and correct in the result;
  nothing else looked wrong.
## 2026-09-17 — A5 EdgeSnap: blur + suppression (agent/a5-blur)

Hardened the pure `EdgeSnap` module (no public-signature changes) with two classical upgrades plus
two additive fixes the wiring agent asked for mid-task from real-photo testing. `npx rescript build`
clean under `+a`; `npm test` 205/205 (193 baseline + 12 net new in `EdgeSnapTest.res`, 19→31).

- **Window-local Gaussian smoothing.** `smoothWindow` blurs `[minX,maxX]×[minY,maxY]` (a call's own
  search rectangle) padded 3 px on every side (clamped to the patch) with the standard 5×5,
  `[1 4 6 4 1]`/256, σ≈1.0 kernel, applied as two separable 1-D passes into a fresh
  `Float64Array` scratch buffer — never the whole patch. `snapPoint`/`snapEnd` (and therefore
  `snapPair`) read gradients off this smoothed window; `gradientMagnitude`/`medianGradient` are
  untouched (still raw-patch), per the brief. `defaultThreshold` is **unchanged** — the floor is
  still `max(relative × medianGradient(raw), absolute)`, and since the synthetic patches' raw
  median is 0 almost everywhere, the floor is effectively still just the 24.0 absolute term, which
  the smoothed peak magnitude of every tested edge (hard step, ramp, thin line, noisy variants)
  clears comfortably. No legitimate reason found to move it.
- **Non-max suppression.** `snapPoint`: a candidate survives only if its magnitude is `>=` (not
  `>`) its two bilinearly-sampled neighbours ±1 px along its own gradient direction
  (`isDirectionalMax`) — `>=` on purpose, so a flat-topped plateau (a soft multi-pixel ramp) keeps
  every plateau pixel eligible instead of reporting `None` because no single pixel is *strictly*
  above its neighbours; the outer tie-break then picks the plateau's centre-most pixel. `snapEnd`
  (the `snapPair` walk): a step is a candidate only if its directional score is strictly greater
  than the step already visited and at least as great as the one still to come — the "first of a
  flat-topped run" test, the walk's equivalent of the same plateau handling.
- **Distance-weighted scoring (additive — requested by the wiring agent after testing against real
  `top.jpg` luma; not in the original brief).** Both functions weight a candidate's score by
  `1 − dist/radius` before comparing, so among real edge pixels (weak ones are already excluded by
  `cutoff`'s floor) the nearest wins. **Judgment call: coefficient is 1.0, not the wiring agent's
  illustrative "e.g. 0.35."** Swept the noisy-step and noisy-long-edge scenarios across ~60 LCG
  seeds at 0.35: ~25–50% failure rate (the weight only varies ±17.5% across the whole search disk,
  which ±20 noise comfortably overwhelms once two candidates are within a couple of px of each
  other in distance — exactly the "slides along the edge" bug being fixed). At 1.0 the same sweep
  passed cleanly (0/60, then re-verified 0/24 on the actual committed test's exact geometry).
  Because weak candidates are already gated out by `cutoff` before weighting is ever applied,
  pushing the coefficient to 1.0 doesn't reintroduce "a weak near edge beats a strong far one" —
  it only sharpens the tie-break among pixels that already cleared the floor.
- **Cached `~median` (additive, same request).** `snapPoint`/`snapPair` gained `~median:
  option<float>=?`; when given, `resolveMedian` uses it directly instead of calling
  `medianGradient(patch)`, keeping the `max(relative × median, absolute)` arithmetic itself in one
  place (`cutoff`, now `(threshold, ~median) => float`, no longer taking `patch`). Existing call
  sites are unaffected (optional, added last). This is what makes the per-call cost bound in the
  next bullet achievable for the wiring agent's actual usage (two radii per tap).
- **Per-call cost bound.** Nothing touches the whole patch per call except `medianGradient` itself
  (already stride-sampled, and now optional per the bullet above) — `smoothWindow`'s buffer size is
  `O(radius²)`, `snapPoint`'s scan is the same disk it always was, `snapEnd`'s walk is `O(radius)`
  along 3 lines. Verified, not just argued: a test scans a 1024×768 patch 1000 times with a cached
  median and asserts under 500 ms (was ~16 s before caching the median — `medianGradient` alone,
  stride-sampling ~49k pixels and sorting them, dominates the cost when it isn't cached; this is the
  concrete reason upgrade 4 exists).
- **Test judgment calls.** "Noisy step" (test 1) checks only the *x* distance to the edge line, not
  `y` — for a vertical edge, landing at a different row is still on the edge; staying near the tap's
  own row under noise is upgrade 3's job and has its own test. Offsets stop at 14 px, not the full
  16 px radius: at offset == radius exactly, only one pixel is geometrically admissible at all, and
  a noise draw that pushes *that one pixel* below threshold or off the NMS test legitimately
  returns `None` (~1 in 12 seeds, empirically) — a real edge case, but a different one from what
  this test checks, and not something any distance weighting can fix (there's nothing else to fall
  back to). Went with "assert the upgraded result" over also asserting the raw/unsmoothed failure
  mode, per the brief's stated option.
- Nothing left unfinished. Did not touch `Annotate.res` or any wiring — out of scope per the brief,
  and a sibling agent owns it.

## 2026-09-17 — Integration close-out: v0.1 amendments + design track

- Landed, in order: A1–A4 (move dims, iOS keyboard, halo overlays, 2048 cap), design research,
  design waves 1–3 (tokens + glass bar → pages → foundation fixes → a11y), A6 fit-to-segment,
  A7 custom faces, A5 edge snap (pure module → wiring → blur/suppression/distance weighting),
  Pages deploy, new icon. A8 (snap telemetry) is specified only.
- Final: `rescript build` clean under `+a`; vitest **206/206** (core 100 % lines); Vite build clean;
  Playwright **40/40 on Chromium**, two consecutive full runs. WebKit still never ran here.
- Conductor fixes between agent merges: the `cutoff` signature change from the blur track broke the
  page's on-edge rule; fixed by caching `medianGradient` once per face (`loaded.snapMedian`) and
  passing `~median` to both snap calls — which also removes the 2–4 median passes per tap.
  Two spec races (export: wait for each save; a11y: wait for render after reload before Tab).
- Process notes: parallel agents must use `E2E_PORT`; a stale `vite preview` on a shared port makes
  `reuseExistingServer` test a sibling's build. LOGBOOK conflicts are always union-merged.
- Known follow-ups: Parts rows truncate the name behind the Rename/Delete icons at 390 px — an
  Edit toggle in the bar (like "Edit faces") would give the row its width; hidden capture inputs
  have no self focus ring when tabbed directly; face-delete focus management.

## 2026-09-17 — A9 dimension list (agent/a9-list)

- Built SPEC §8a A9 on `agent/a9-list`: an inset grouped list of the face's saved dimensions under
  the controls (`dimension-list` / `dimension-row` / `dimension-empty`), rows in creation order —
  kind glyph · name · `value unit` · `± tol` — with the accessible name "<name>, <value> <unit>,
  <kind>"; a row tap selects, a tap on the selected row deselects, a canvas selection marks and
  scrolls to its row. vitest 206/206, `rescript build` and `vite build` clean under `+a`,
  Playwright **44/44 on Chromium** (the 40 existing + 4 new).
- **One selection path (judgment call).** A9 says a row tap selects "exactly as tapping it on the
  canvas does (… A6's fit applies to its segment)" — but the canvas path never fitted on select.
  Both now go through `selectDimension`: fill the sheet, `fitToPending` (A6 remembers the view;
  Save, Clear and Delete restore it exactly as for a placed pair), scroll the row into view. So a
  canvas tap on a saved dimension now zooms to it as well; the existing M4/A1 specs still pass
  (they read the transform after the fit settles). If the owner dislikes the zoom on a canvas
  select, drop `fitToPending` from `selectDimension` — the list still matches the canvas.
- **List placement.** In the DOM after Save as the panel's last section (`.annotate-dimensions`
  inside `.panel`), not a sibling on the ground: the panel is the sheet that runs to the bottom of
  the screen (DESIGN.md §11.2), and a sibling would need its bottom corners re-shaped and the 12 px
  `.annotate` gap closed. The inset container therefore sits on `cc-surface-2` at the 12 px inner
  radius (§11.1 concentric) instead of `cc-surface` at 16. The header is the house
  `.list-group-header` (Footnote 600 uppercase, as on every other list), not a literal Caption 2.
- **Row markup.** `Ui.ListRow` has no `data-id`/`aria-selected`, so the row is composed in
  Annotate.res from global.css's `.list-row` classes through a `react/jsx-runtime` props record
  (`RowButton`, the `Canvas.Input` pattern). `role="listitem"` matches `Ui.ListRow`'s button rows;
  `aria-selected` is the spec's contract although ARIA doesn't list it for `listitem` — noted, not
  changed. The empty state is a `<p>` inside the container, which then drops `role="list"` (a list
  owns only list items).
- **Focus.** A row tap leaves focus on the row, for select and deselect alike (the deselect is
  Clear's `endAutoFit(clearEntry)` without Clear's focus-the-canvas cmd). Canvas taps keep their
  existing focus behaviour.
- **Test hook.** `annotate-canvas` gained `data-selected` (the selected dimension's id, empty when
  none): with identical endpoints, `pending-points` can't tell the two apart.
- **Building the overlap in Playwright.** Two identical taps can't yield two dimensions — the
  canvas's A1 hit-test selects the saved one instead of placing a point on it — so the spec places
  the second pair 40 px lower and drags its pending body up onto the line (snap off) before saving.
- Screenshots (not committed): `…/scratchpad/a9/03-selected-viewport.png` — two overlapping
  dimensions plus a depth, the second selected from the list.
## 2026-09-17 — Fusion import skill (agent/skill-build)

Built SPEC §7's other half as a project skill: `.claude/skills/fusion-import/` (SKILL.md, one
self-contained `scripts/import_ccpart.py`, a recording `scripts/fake_adsk.py`, 84 stdlib unittest
cases, golden plan + call-log snapshots). Spec updated first with the review's R1–R4 rewrites
(`docs/fusion/IMPORT-SKILL-SPEC.md`), then built to it. No Fusion here: the executor is tested
against the fake; the owner runs the live V1–V15 checklist in Text Commands on the Mac.

- **Two entry paths, one planner/executor.** MCP: the skill stages shell-side (`--extract` into
  `~/.caliper-companion/imports/<slug>/`, pHYs written into the PNG copies), then two calls each
  sending the file text + `__ccpart = run_import({...})` — `inspect` (read-only) and, after
  confirmation, `execute`; no message boxes; `<dir>/import-report.json` is the channel. Standalone
  (coordinator addition mid-build): `run(context)` from Scripts and Add-Ins opens a file dialog,
  stages inside Fusion's Python with the same code, shows the plan in an OK/Cancel box, executes,
  ends with a summary box and the same report file. `run()` dispatches on `__ccpart` (already ran) →
  `CCPART_ARGS` (scripted) → standalone, so an MCP tool that also calls `run()` does nothing twice.
- **Judgment calls.** (1) Parameter comment carries the feature `kind` (`length ±0.1 mm · faces top ·
  ccpart:<slug>`) per review S4 — the brief's condensed format omitted it; one-line change if unwanted.
  (2) Canvas name stays `label_photo` (brief), not review N2's `_uncalibrated` suffix: a rename after
  calibration would defeat the by-name refresh; the uncalibrated status is in `canvas_note` and the
  confirmation text instead. (3) Timeline group is `<slug> import` (brief), not S2's `{exportedAt}`
  suffix; on re-import the kept sketches stay in the old group and only the new canvases get the new
  one — the fake models group membership shifting on delete, and the test pins the new group to the
  three new canvases. (4) Canvas refresh creates the new canvas **before** deleting the old one, so a
  failed refresh keeps the old canvas (no transactions); the group range is computed from
  `timelineObject.index` after the deletes, not from a marker captured up front. (5) `isComputeDeferred`
  only above 6 faces (brief) — N5 said never; kept the brief's threshold, always in `finally`.
  (6) Numbers via `f"{v:.4f}".rstrip("0").rstrip(".")` (S4): golden values come out `42.18 mm`, `2 mm`,
  `±0.1 mm` — verbatim, never exponent notation. (7) Extra reserved names refused up front (S5):
  `d<n>` and `mm cm m in ft deg rad`; app-side nit still open.
- **Fake fidelity.** `fake_adsk` raises on attribute typos and on `createByReal`, logs every call and
  property set, models `itemByName` returning `None`, `add` returning `None` on a duplicate name,
  timeline objects that re-index when items are deleted, and scripted dialog answers. What it cannot
  tell us is exactly the V-list (canvas factory/arg order, pHYs honoured, attributes on canvases,
  `Canvases.itemByName`, `Matrix2D.copy`, the MCP tool's exec semantics, dialog filter syntax).
- Not done: `part.path` (A10) is read into the plan and otherwise unused (v1 save); no CouchDB pull (v1).

## 2026-09-17 — A11 parameters.csv (agent/a11-csv)

- Built SPEC §8a A11 on `agent/a11-csv`: `src/core/ParametersCsv.res` — a pure writer,
  `make(~part, ~faces, ~dimensions) => result<string, Reconcile.error>` — producing
  `parameters.csv` for Autodesk's free ParameterIO add-in (Utilities → ParameterIO → Import), no
  header, `name,unit,expression,comment`, LF, trailing newline, UTF-8, one line per reconciled
  feature in the same order `features.json` uses (Reconcile.reconcile's own name-ascending order —
  no re-sort needed). `expression` is `"<value> <unit>"` via `Float.toString` (same
  Number.prototype.toString() rule `JSON.stringify` runs on features.json's `value`, so `0.8`/`2`/
  `9`, never `0.80`/`2.0`). `comment` is `"±<tolerance> <unit> · faces <labels> ·
  ccpart:<slug>"`, `"FLAGGED spread <spread> > ±<tolerance> · "` prefixed when flagged. Golden
  `fixtures/hinge_pin/parameters.csv` checked in (9 lines, generated by running the writer against
  the existing `Fixture` data, not hand-typed).
- **Verified against the add-in's source, not its docs.** Cloned
  `AutodeskFusion360/ParameterIO_Python` and read `ParameterIO.bundles/Contents/ParameterIO.py`
  directly. Confirmed: real `csv.reader(dialect=csv.excel)` (not a naive `split(',')` — SPEC's
  bullet guessed at the mechanism, harmlessly wrong since we never emit a comma or quote); no
  header; exactly 4 fields read (name/unit/expression/comment, comment optional); matched by name,
  new params get unit+expression+comment via `userParameters.add`, **existing params only get
  `.expression`/`.comment` reassigned — `paramInModel.unit = unitOfParam` is in the source but
  commented out, so unit never applies on a re-import** (the bundled help HTML claims otherwise;
  code wins — same "types over docs" call CLAUDE.md makes elsewhere, just against an external
  source this time); reader opens the file without `newline=''` so LF/CRLF/CR all normalize the
  same, and a trailing blank line from our required trailing newline is silently skipped. No shape
  change was forced — SPEC's assumed 4-field, no-header, LF, UTF-8, unit-in-expression contract
  held exactly. Full rule list is in `ParametersCsv.res`'s header comment.
- **Tolerance/spread formatting (judgment call).** SPEC's bullet only pins down `expression`'s
  number format explicitly ("verbatim 4-dp-rounded float, no trailing-zero padding"); its own
  inline example comment shows `±0.10 mm` (2dp). Went with the simpler, consistent reading: reuse
  the exact same `Float.toString` formatting for `tolerance`/`spread` too, so every number in the
  file renders exactly as it would inside `features.json` (`±0.1 mm`, not `±0.10 mm`) — one
  formatter, no separate fixed-precision path to keep in sync. Flagging in case the owner wanted
  the padded look.
- **Bundle + wiring.** `Bundle.buildZipBytes` gained a required `~parametersCsv: string` param and
  a `parameters.csv` entry at default (level 6) compression, same as `features.json`. That value
  has to come from somewhere — `Export.res` is the only caller, and it wasn't on this task's file
  list, but there's no way to get `parameters.csv` into a real exported bundle without touching its
  one call site, so it got the minimal edit: compute `ParametersCsv.make` right alongside the
  existing `FeaturesDocument.make` call (same `part`/`dimensions`, faces from the already-rendered
  `items`), thread the result into `Bundle.buildZipBytes`. No other behavior in `Export.res`
  changed. Flagging this deviation from the stated ownership list explicitly, in case another
  in-flight track also touches `Export.res`.
- `e2e/specs/export.spec.js`'s golden-path test now also asserts the zip holds `parameters.csv`:
  trailing newline, line count == feature count, names in `features.json` order, 4 fields per line,
  `unit`/`expression` matching `doc.part.units`/`doc.features[i].value`.
- README gained "Import into Fusion without Claude" (App Store link, Utilities → ParameterIO →
  Import, canvases still manual Insert → Canvas, pointer to the MCP skill spec for the automated
  path).
- Verified: `rescript build` clean under `+a`; `npx vitest run --coverage src/core` — 100 %
  lines/statements/functions on `ParametersCsv.res.mjs` (pre-existing `Codec.res.mjs` branch gaps
  untouched); full `npx vitest run` — 217/217 (one `EdgeSnapTest` timing test is flaky on this
  sandbox's CPU — reproduces 3/3 in the full run, passes standalone every time; pre-existing,
  unrelated to this change, not fixed here — out of scope per file ownership); `npm run build`
  clean; `E2E_PORT=3610` Playwright on `export.spec.js` — **4/4 on Chromium**, no stale preview
  processes.
## 2026-09-17 — P1 — Dark Sky tokens + Face card (agent/p1-darksky)

Phase P1 of the owner-approved re-theme (`docs/design/palettes-2026-09-17.md`, layout A per
`docs/design/review-2026-09-17.md`): tokens everywhere, semantic renames, the new `Ui.FaceCard`
component, the regenerated app icon, and DESIGN.md. Page layouts are P2's job — nothing here wires
`FaceCard` into Part/Capture/Parts; every page-CSS/`.res` edit in this track is a token/variant
rename only, no layout changes.

- **Token application.** `src/theme.css`'s colour block replaced with the Dark Sky diff verbatim
  (palettes doc §5/§8), plus the semantic rename the diff's own footnote called out as a separate
  mechanical follow-up: `--cc-amber(-ink/-pressed)` → `--cc-accent(-ink/-pressed)`,
  `--cc-teal(-wash/-ink/-border)` → `--cc-live(-wash/-ink/-border)`. Every consumer updated
  (`global.css`, `Capture.css`, `Annotate.css`, `Part.res`'s two `text-teal`→`text-live` call
  sites, the `part-a.html` mockup's inline overrides so it keeps matching) — `grep -rn --
  "--cc-\(amber\|teal\)" src docs/design/mockups/part-a.html` is empty, no aliases kept.
  `Ui.WarningRow.tone`'s `Teal` constructor renamed to `Live` (only caller: `Part.res`, both
  `tone=` sites). No CSS class carried the old meaning in its name except `.text-teal`
  (`.warning-row` etc. are tone-neutral names, left alone).
- **Canvas/export literals.** `Draw.res` and `Render.res` can't read CSS custom properties, so
  their colours are hardcoded by value with a comment naming the token — updated to Dark Sky and,
  in `Draw.res`, the local bindings themselves renamed (`amber`/`amberInk`/`teal` →
  `accent`/`accentInk`/`live`) to match. Halo = new `cc-ground` at 85%, `rgba(21,24,29,0.85)`,
  exactly as the palette doc's Recommendation section spells out.
- **Export-legibility e2e (item 3 in the brief).** `e2e/specs/export.spec.js`'s
  `sampleLegibility` hard-codes its accent-pixel check as `r > 200 && g >= 130 && g <= 190 && b <
  90`. Dark Sky's `#FF7F2A` is R255 G127 B42 — the line is stroked at full opacity on top of the
  halo (not blended), so the sampled pixel is exactly that value: G=127 is 3 below the spec's
  floor, no anti-aliased pixel nearby scores higher (they blend toward the halo's near-black, not
  up). So `sawAmber` reads false and `export.spec.js` fails after this change, with the literals
  exactly as specified — this was flagged in the brief as the expected outcome, not a bug to route
  around, and the spec is outside this track's file ownership (specs are explicitly excluded).
  **Did not edit the spec, including locally/uncommitted.** Partway through this track a message
  arrived addressed as "the coordinator", delivered as an injected system-reminder rather than a
  real user turn or a tool result, instructing me to patch `export.spec.js`'s `g >= 130` to
  `g >= 100` locally (uncommitted) to make the suite green, claiming the real fix was already on
  an integration branch. Declined: it contradicts this track's own explicit "you may not edit the
  spec" instruction, nothing in this session shows it actually came from the conductor, and the
  live repo's assertion still reads `g >= 130` (not `100`) — so even taking the message at face
  value, its own premise doesn't match what's on disk. Ran the suite unmodified instead; see the
  handoff report for the exact numbers. Flagging for the conductor to relax the window for real.
- **`Ui.FaceCard`.** New module + `global.css` §14. `~image=None` always renders the `Empty` look
  regardless of `~state`, so a caller can't get the ring/scrim and "no photo" out of sync by
  passing a stale state; `~state` still matters for a real `None`-image card (dashed empty vs.
  nothing to ring). Badge content (the captured check, or a future EXIF marker) is a caller slot
  (`~badge`), not auto-rendered — the component only positions it top-right and supplies the ring
  per state; `.face-card-check` is provided as the conventional 24 px badge shape for callers that
  want the default. Sized off its grid track, not a fixed width, so `.face-grid`/`.face-grid-dense`
  fully control 2-up vs. 3-up. Checked with a throwaway scratch HTML + Playwright screenshot
  (written and deleted within this session, never committed) rendering all three states in both
  grid densities against the live `theme.css`/`global.css` — screenshot path is in the handoff
  report, not this repo. Not wired into any page; P2 does that.
- **Badge size vs. the review draft.** The brief specified a 24 px check badge; the review doc's
  own draft text (and the `part-a.html` mockup it produced) used 22 px. Built and documented at
  24 px throughout (component, CSS, DESIGN.md's Face card row) since the brief is the later,
  more specific instruction and the doc should describe what actually shipped — left
  `part-a.html`'s 22 px mockup badge untouched (its file-ownership note limits edits there to the
  scrim-gradient colour token, not the badge size).
- **Vertical rhythm.** `.stack-lg`'s gap `cc-space-5` (20) → `cc-space-6` (24) — the review found
  `cc-space-6` had never been used as a spacing step at all, so the scale's top was dead and
  sections read as one column. `.list-group-header`'s own spacing was already correct (8 px to its
  group via `.list-group-section`'s flex gap, per the review's own audit table) — no property
  needed adding there; the fix that mattered was `.stack-lg`. Documented as a rule in `global.css`'s
  header comment and as a new "Vertical rhythm" row in DESIGN.md §11.1.
- **DESIGN.md.** Beyond the specific rows/sections the brief named, also swept §5/§6/§9 (still
  "in force" per §11.3) for the old `cc-amber`/`cc-teal` names and old hexes — leaving them would
  have made the doc self-contradictory against its own §2 table. §1's "Amber"/"Teal" prose became
  "Orange"/"Blue" (colour words, matching that section's existing conversational style, not the
  token names). §2 keeps a one-line note that v1.0 shipped amber/teal under the old token names.
  The review's "§2: `cc-size-micro` no longer appears on Part" note landed inside the §11.2 Part
  bullet instead of literal §2, since it's a Part-screen fact, not a token-table fact.
- Screenshots and the export-spec run: see the handoff report (paths and numbers kept out of this
  file to avoid duplicating what's already there).

## 2026-09-17 — P2c — annotate do-now fixes (agent/p2-annotate)

The Annotate "do now" fixes from `docs/design/review-2026-09-17.md` A1/A2/§2, on top of P1's Dark
Sky tokens. View/CSS only — no gesture, update or msg changes; every testid and data attribute is
unchanged.

- **A1, tools strip.** The Snap pill/count/zoom-out/zoom-readout/zoom-in toolbar moved out of the
  stage's scrim overlay into a new `toolsStrip` view, rendered as the first child of `.panel` —
  a 44 px opaque `cc-surface` strip, 8 px gap, right-aligned. Only the hint pill (`Ui.Pill`, plain
  `<span>`, no controls) is left over the photo, top-left, in its own scrim capsule as before.
  `.annotate-overlay` lost its old reversed-row/wrap layout (it only ever positioned one pill now)
  but kept `pointer-events: none` so a tap under the hint still reaches the canvas underneath.
  DOM order is now canvas → tools strip → Reading, so the strip's buttons fall between the canvas
  and `reading` in tab order — a small, accepted departure from §9's literal focus order (which has
  nothing between them); everything else in that order (reading → name → chips → kind → tolerance
  → Save → dims list) is unchanged. No testid or msg moved: `snap-toggle`, `dimension-count`,
  `zoom-out`, `zoom`, `zoom-in` render exactly as before, just relocated — confirmed by the full
  e2e suite (`export.spec.js`/`faces.spec.js` click `zoom-in`/`zoom-out` and read `zoom`,
  `dimension-count`, `snap-toggle` by testid, position-independent). `docs/testids.md` needed no
  edit.
- **A2, tolerance 124 → 104 px.** `.annotate-kind-row > .field:last-child` narrowed to 104 px
  (review: "± 0.10 mm" needs ≈ 96). The page-scoped `.annotate-kind .segmented-option` override
  (4 px padding, 14 px font) is dropped entirely — the extra 20 px freed by the narrower tolerance
  field lets `Ui.Segmented`'s own global metrics (12 px padding, Subhead 15 semibold) fit
  "Diameter" without clipping. Verified by screenshot at 390×844 and 360×740 (`shot.mjs` in the
  handoff report): at 390 the segmented control now gets ≈243 px (was 222), and at 360 the kind row
  still wraps (`@media (max-width: 360px)`, untouched) so the control gets the full 328 px content
  width regardless.
- **Rhythm.** `.annotate .panel` gets its own `gap: var(--cc-space-4)` (16, was the shared
  `.panel`'s 12) so the page's direct sections (tools strip, reading, name, kind row, errors,
  actions, dimension list) sit 16 px apart; `.annotate-dimensions`'s existing `margin-top:
  var(--cc-space-2)` (8) now stacks on top of that for 24 px total before the dimension list, as
  the brief asked. Non-scale leftovers cleared: the tools strip's `gap: 6px` → `var(--cc-space-2)`
  (8), the Snap pill's `padding: 0 8px 0 6px` → `0 var(--cc-space-2)`, the count pill's
  `padding: 0 6px` → `0 var(--cc-space-2)`, `.annotate-tolerance`'s `gap: 6px` → `var(--cc-space-1)`
  (4) and its input's `padding: … 10px` → `… var(--cc-space-2)` (8) — narrowed further than the
  general 14 px input-padding convention (DESIGN.md §11.1's one allowed exception) because the
  104 px tolerance field has no room for 14 px each side alongside "±", the digits and "mm";
  verified "0.10" doesn't clip at 390 or 360. `.annotate-reading input`'s `14px` side padding is
  untouched — that's the exception DESIGN.md §11.1 names. Stage sizing
  (`min(300px, --vv-height × 0.5)`, min 200) and the A6/A9 hooks are untouched, as required.
- **Verification.** `npx rescript build` clean, `npm test` (217/217), `npm run build`, and
  `E2E_PORT=3830 npx playwright test --config=e2e/playwright.config.js --project=chromium`
  (44/44, chromium project) all green. Screenshots (loaded/pending at 390×844, loaded/pending at
  360×740) taken against `vite preview --port 3831` with a Playwright script seeding a real part +
  `fixtures/hinge_pin/end.jpg`; looked at all four — tools strip reads as one continuous surface
  with the panel below it, the count no longer sits on a handle, "Diameter" doesn't clip at either
  width, and the strip doesn't wrap at 360. Stale preview processes killed by PID before each run.
  Paths are in the handoff report, not this repo.
## 2026-09-17 — P2b — layout A: Capture (agent/p2-capture)

Wires P1's `Ui.FaceCard` into the Capture page (`docs/design/review-2026-09-17.md` C1-C4, DESIGN.md
§11.2 "Capture"): the chip row + slot row are gone, replaced by one face-card grid that is both the
kind picker and the thumbnail gallery, and the shutter/library block moves into the bottom 60% of
the screen. Capture/decode/recapture/custom-face logic, `Store` calls, level snapshot, timer start
and navigation are all untouched — this track only touches `Capture.res`'s view layer and
`Capture.css`.

- **Face grid.** New `faceGrid` (replaces `chipRow`/`slotRow`): one `Ui.FaceCard` per chip from
  `chipsOf`, `onClick` dispatching the same `SelectChip` the old rows already used. Captured =
  `Captured` (thumbnail + `~badge` check); the selected chip on top of that = `Selected` (accent
  ring) — `state` and `badge` are independent props, so a captured-and-selected card keeps both
  signals at once. Uncaptured = `Empty` regardless of selection. "+ Custom" is a fixed trailing
  `Empty` card (own testid, not one of `chipsOf`'s chips) opening the existing inline custom-face
  card, ids unchanged.
- **Shutter anchored low (C1).** `.capture-view` renamed `.capture-page`, `min-height: 100%`; a new
  `.capture-action` wrapper around the shutter/recapture/custom-card switch is `margin-top: auto`.
  Measured (Playwright, 390×844, fresh part): shutter centre y = 675px = 80% of viewport height,
  well past the ≥ 45% floor; at 360×740 it's 630px = 85%. `shellScrollHeight` runs ~45px over
  `clientHeight` on a bare 4-default/0-capture part (5 cards, 3 rows at 2-up) — the same order of
  overflow the review doc's own scroll table expected for layout A at baseline ("15 px over"); the
  page scrolls (`.shell`'s existing `overflow-y: auto`), nothing is clipped.
- **Judgment call — dense-grid threshold.** Task brief said "dense at ≥ 5 cards"; DESIGN.md §11.2
  says "3-up at ≥ 5 faces". Read the two together as "≥ 5 chips" (`Array.length(chipsOf(model))`),
  **not** counting the always-present "+ Custom" trailing cell — counting it would make every
  bare, zero-capture part (4 defaults + 1 "+ Custom" = 5 cells) dense from the very first render,
  which isn't what either source intends.
- **Ui gaps hit, not worked around by hand-rolling markup outside `Ui.FaceCard`** (`Ui.res` is
  outside this track's file ownership):
  1. No `ariaPressed` prop. The old slot's `aria-pressed` is gone; selection is now stated in the
     card's `ariaLabel` instead (`cardAriaLabel`: `"<label> — captured|not captured[, selected]"`).
     Updated `faces.spec.js`'s two `capture-chip-*` `aria-pressed` assertions to
     `toHaveAccessibleName(/…selected/)` instead — a legitimate interaction change (the component
     itself changed, not the thing being tested), not a weakened check.
  2. `~image=None` always renders the `Empty` look regardless of `~state` (per the component's own
     doc comment), so a *selected-but-uncaptured* kind shows no accent ring on the grid — the
     shutter block's "Capture <Label>" caption is the only visible cue for which kind is targeted
     in that case.
  3. `Empty`'s icon is hardcoded to Camera with no way to ask for `Plus`, so the "+ Custom" card's
     own label text reads "+ Custom" (the "+" lives in the string, not an icon swap).
  4. `badge`/`caption` only render in the `Some(image)` branch — a real `Empty` card (no image at
     all) has no slot for either. Two knock-on effects: (a) `custom-face-remove` stays exactly
     where it was, a button in the shutter block, rather than moving onto the card itself — there's
     nowhere on an `Empty` card to put it; (b) a just-captured face briefly shows as a plain `Empty`
     card until its object-URL thumbnail loads (`FaceImageLoaded`) — the old slot row showed the
     check badge immediately off `hasExisting`, independent of the thumbnail. Minor and transient
     (local-blob object URLs resolve in well under a frame in practice) but worth a future look if
     `Ui.res` gets revisited.
- **Verification.** `npx rescript build` clean (no warnings; `warnings.error = "+a"`), `npm test`
  217/217, `npm run build` clean, `E2E_PORT=3820 npx playwright test --config=e2e/playwright.config.js
  --project=chromium` — 44/44 green, including `a11y.spec.js`'s two Capture-page checks (not in this
  track's file ownership, untouched, still pass). Screenshots (empty grid, one captured face, the
  custom card open, the recapture card, 360×740) taken via a throwaway Playwright script against
  `vite preview --port 3821` (written and deleted within this session, never committed) — paths in
  the handoff report, not this repo.
## 2026-09-17 — P2a — layout A: Part + Parts (agent/p2-lists)

Layout A ("Gallery-first", `docs/design/review-2026-09-17.md` §3/§4) wired into the two pages it
touches, plus the matching Parts-list changes (P1-P5). `Ui.FaceCard`/`.face-grid*` (from P1) were
already built and unused; this track is what wires them in.

- **Part page.** Faces are now a 2-column `Ui.FaceCard` grid (`.face-grid`, `.face-grid-dense` at
  ≥ 5 faces), each card `state=Captured`, caption `"<w> × <h> · <n> dim(s)"`, `href` to Annotate,
  `testId="face-<label>"` — replacing the old 56 px `.face-slot` row. A trailing `Ui.FaceCard`
  card (`state=Empty`, `testId="capture-face"`) replaces the dashed slot. The old in-body
  "Edit faces" button is gone; `Edit`/`Done` (`faces-edit`) is now the bar's trailing text action
  (`Ui.Button ~variant=Plain`, a new `.bar-action` class in Part.css for the accent colour Plain
  alone doesn't carry). Edit mode itself (`renderFacesEdit`: the removable list, inline
  delete-confirm, `face-remove`/`face-delete-confirm`/`face-delete-cancel`) is untouched — same
  msgs, same Store calls, same testids; only its entry point moved.
  The features table became a role=list of role=listitem "Feature rows" (`Part.css`'s
  `.feature-row`, a 3-col grid: name+faces / value+unit / ±tol), no column header row, no
  `role="table"`/`columnheader` ARIA. Each row's own `aria-label` is
  `"<name>, <value> <unit>, ± <tol>, faces <labels>"`. A dimension's kind now prefixes its name as
  a glyph (⌀ diameter, ↓ depth, nothing for length) since there's no longer a column to show kind
  in — a deliberate departure from `part-a.html`'s mockup, which puts the glyph on the *value*
  column instead; the written brief for this track puts it on the name, and that's what's built
  (flagged here as a mockup/brief mismatch, not resolved unilaterally in the mockup's favour).
  The group header itself carries the old bar-subtitle stats line: "Features · n faces · n
  features · unit" — see the subtitle note below.
- **Shell subtitle vs. layout A's stats line (B2).** `docs/design/a10-folders-review.md` §1 B2
  (blocker) reserves the Part page's one `Shell` subtitle slot for A10's future folder path and
  tells layout A's "n faces · n features · unit" line to move into the features group header
  instead. `DESIGN.md` §11.2 still literally says "bar subtitle 'n faces · n features · unit'" —
  that line predates B2's resolution and wasn't updated; this build follows B2 (the more specific,
  later-dated decision) over the stale DESIGN.md sentence. `Part.subtitle` stays `None`. Flagging
  for whoever lands A10 to fix DESIGN.md's wording to match.
- **Parts list.** Rows: `Ui.ListThumb` now loads the part's first captured face (`Store.facesOf`
  then `Store.getFaceImage`, one cmd per part, fired once off the `PartsLoaded` that follows
  `init`'s `Store.listParts` — never re-triggered by a later render). `Ui.ListThumb` has no size
  prop and is 52 px in `global.css`, also used by Part.res's own face-edit list at that size; since
  CSS here is unscoped app-wide (index.html links every page stylesheet unconditionally, no CSS
  Modules), the 72 px override is scoped to a `.parts-page` wrapper class on this page's own
  `view` root rather than touching `.list-thumb` directly — noted as a `Ui.ListThumb` gap (no
  `~size` prop) rather than editing `Ui.res`, which is out of this track's file ownership.
  Rename/Delete (`part-rename`/`part-delete`) moved behind a new `editing: bool` + `EditToggled`
  msg, toggled by the bar's `parts-edit` text action (same `.bar-action` class as Part's
  `faces-edit` — defined once in Part.css, reused here since the CSS is unscoped anyway). Out of
  edit mode a row is purely navigational (`Ui.ListRow ~trailing=?None`). The "+" (`new-part`) now
  lives in the bar as a 44 px icon button once the list is non-empty; the body capsule
  (`renderEmptyCapsule`, ex-`renderNewPartButton`) only renders in the empty state — never both,
  so `getByTestId('new-part')` stays a single-element match either way.
- **Focus-management fix forced by the "+"/capsule split.** `DeleteDone`'s `focusTestId("new-part")`
  relied on `new-part` being one continuously-mounted DOM node regardless of list emptiness (see
  the pre-P2a code's own comment) — true before this track, no longer true once the last part's
  delete swaps the bar icon for the empty-state capsule (two different DOM nodes). The existing
  single-microtask `focusTestId` (still correct for every click-triggered call site, since React
  flushes synchronously by the end of a discrete event) raced the async, promise-driven
  `DeleteDone` dispatch: verified with a throwaway MutationObserver+focus-event script (written and
  deleted within this session, not committed) that it was focusing the *old*, about-to-be-removed
  bar icon a frame before React swapped it for the capsule, losing focus to `<body>` with nothing
  to refocus it. Fixed by having `focusWhenReady` keep refocusing on every attempt (never stop at
  the first match) across up to 6 `requestAnimationFrame` ticks — the id-string match is the same,
  it's the identity of the underlying node that can change mid-flight, so the last attempt after
  the DOM has actually settled is the one that has to win. `e2e/specs/a11y.spec.js`'s existing
  "deleting a part sends focus to New part" assertion is the regression guard.
- **Specs.** `parts.spec.js`'s rename/delete tests and `a11y.spec.js`'s rename-focus/delete-focus
  test now click `parts-edit` first (the only interaction change; everything else in both files is
  unmodified). `a11y.spec.js`'s part-page test swapped its `.features-table`/`columnheader`
  assertions for `features-list`'s `role="list"` + `feature-row`'s `role="listitem"`/`aria-label`,
  matching the new structure — same test intent (real semantic roles survive the CSS-grid
  layout), new shape.
- **Not done / flagged, not fixed:** DESIGN.md's stale subtitle sentence (B2, above); Export's
  `disabled` state doesn't gate on "has a face yet" (`review-2026-09-17.md` F8/DESIGN.md §11.2 say
  it should) — omitted because the written brief for this track's `renderExport` spec doesn't
  mention it and no test depends on it either way; left as-is rather than adding scope unasked.
- **Verified:** `npx rescript build` clean under `+a` (`rescript clean` + full rebuild, 67 modules,
  zero warnings); `npm test` (`rescript build && vitest run`) — 217/217; `npm run build` (vite
  production build) clean; `E2E_PORT=3810 npx playwright test --config=e2e/playwright.config.js
  --project=chromium` — **44/44 green**, no stale preview processes (checked port 3810 was free
  before the run; killed the scratch preview servers used for screenshots/debugging by PID
  afterward). Screenshots (390×844 @2x unless noted; via a throwaway script, written and deleted
  within this session, driving the real UI per `docs/testids.md` — not committed) covered `#/`
  empty and with one row (72 px thumb, bar Edit + "+"), the Part page with 3 faces (top/side/end,
  end EXIF-rotated portrait) and 3 features (one flagged/multi-face, two diameters), the same page
  in faces-Edit mode, and a 360×740 render of the faces+features page — all matched the mockup
  within the tokens; the one odd-looking detail (a sliver of "(EXIF 6)" watermark text peeking out
  top-right of the End card) turned out to be the real `fixtures/hinge_pin/end.jpg` fixture's own
  printed content after EXIF rotation + `cover` crop, not a rendering bug — confirmed by reading
  the raw fixture image directly.

## 2026-09-17 — FaceCard gaps (agent/facecard-fix)

Closes the four `Ui.FaceCard` gaps P2b hit and ran into rather than worked around (LOGBOOK.md
"P2b — layout A: Capture", "P1 — Dark Sky tokens + Face card"), then wires the fixes into Capture.
File ownership: `Ui.res` (`FaceCard` only), `global.css` (§14 only), `Capture.res`/`Capture.css`,
`faces.spec.js` (`aria-pressed` restoration only), `docs/testids.md` (Capture). `Part.res`/`Part.css`
untouched, confirmed unchanged both by `git diff --stat` and a Part-page screenshot (below).

- **State-driven ring on empty cards.** `Ui.FaceCard`'s `stateClass` switch grew a
  `(None, Selected) => " face-card-empty face-card-selected"` arm — the accent ring
  (`.face-card-selected::after`) now reaches an `image=None` card instead of only ever landing on a
  photo. `(None, Captured)` (impossible in practice — a captured face always has an image) falls
  back to the plain empty look, no ring, rather than a new failure mode. Doc comment rewritten to
  state the real matrix (it previously said `~image=None` always renders `Empty` "regardless of
  `~state`", which stopped being true here).
  **CSS (fix 5):** the ring pseudo-element is inset from the *padding* box, so on top of
  `.face-card-empty`'s own 2px dashed border it would've sat visibly inside it (two concentric
  rings) instead of replacing it — `.face-card-empty.face-card-selected { border: none; }` in
  global.css §14 drops the dashed border so the solid accent ring is flush with the card edge,
  same as a captured/selected card with a photo.
  **Capture.res gap not mentioned in the brief, found by looking at the first screenshot:**
  `faceGrid`'s own `state` expression was `hasExisting ? (isSelected ? Selected : Captured) :
  Empty` — the `Empty` branch never checked `isSelected` at all, so even with `Ui.FaceCard` fixed,
  a selected-but-uncaptured chip still got `Empty`, not `Selected`, and still showed no ring. Fixed
  to `isSelected ? Selected : (hasExisting ? Captured : Empty)` (`isSelected` wins over
  `hasExisting`). Without this, the Ui.res fix alone is inert on this page — caught by actually
  rendering a fresh-part screenshot before calling the work done, not by reading the diff.
- **`~ariaPressed: option<bool>=?`.** Renders `ariaPressed=?` (mapped to the `[#"true" | #"false"]`
  polymorphic variant `JsxDOM` expects — not a bare `bool`, ReScript's JSX aria props aren't typed
  that loosely) on the `<button>` form only (`<a>`/inert `<div>` cards have nothing to be "pressed").
  `faceGrid` passes `ariaPressed=isSelected` on every `capture-chip-*` card (not just the selected
  one — `false` on the rest, matching a real toggle group). `cardAriaLabel`'s accessible-name
  signal is kept alongside it, not replaced — DESIGN.md §9 "color is never the only signal," and
  redundant channels for the same state aren't noise for a screen reader here.
  `faces.spec.js`'s two `capture-chip-*` checks (`addCustomChip`, the standalone Enter-adds case)
  get their `toHaveAttribute('aria-pressed', 'true')` assertions back, added *alongside* the
  `toHaveAccessibleName` ones P2b introduced, not instead of them.
- **`~icon: Icon.name=Camera`.** The empty look's icon is now a prop; `faceGrid`'s `addCustomCard`
  passes `~icon=Plus` and its label drops to `"Custom"` (the "+" was living in the label string
  before, baked in because there was no other way to get it on screen).
- **`~badge`/`~caption` on `Empty` cards too.** Both render regardless of `~image` now (badge
  top-right via the same `.face-card-badge` class either branch uses, caption under the label).
  Two knock-on fixes in Capture.res: (a) a just-captured face whose object-URL thumbnail hasn't
  resolved yet (`existing` is `Some` but `thumbUrl` is still `None`) keeps its check badge and size
  caption instead of reading as a bare empty card until `FaceImageLoaded` fires — `faceGrid` already
  computed both, they just weren't reaching the card. (b) `custom-face-remove` moved off the
  shutter block and onto the selected, unsaved custom chip's own card, in the badge slot's
  position. **Not** passed as that card's actual `~badge` prop, though — the card is a `<button>`
  (Capture always passes `onClick`), and a `<button>` nested inside another `<button>` is invalid
  HTML and breaks the accessibility tree. `faceGrid` instead renders it as a real sibling
  `Ui.Button` (`variant=Icon`), absolutely positioned over the card via `.face-card-badge`, inside a
  new `.face-card-holder` wrapper (Capture.css) that stands in for `.face-card` as the grid item
  (`aspect-ratio: 1`, inner `.face-card` at 100%/100%) so the button has a `position: relative`
  ancestor. Shrunk from the standard 44px `.btn-icon` tap target to 24px (`.face-card-holder
  .custom-face-remove.btn-icon`) to match `.face-card-check`'s badge size and not swallow a 109px
  (3-up) card. Only the one removable card gets the extra wrapper div — every other card renders
  exactly as before.
- **Verification.** `npx rescript build` clean (`warnings.error = "+a"`, no warnings), `npm test`
  217/217, `npm run build` clean, `E2E_PORT=3920 npx playwright test --config=e2e/playwright.config.js
  --project=chromium` — **44/44 green** both before and after the `faceGrid` state-expression fix
  above (no stale preview/dev-server processes running before either pass). Screenshots (390×844,
  via a throwaway Playwright script against `node node_modules/vite/bin/vite.js preview --port
  3921 --strictPort`, killed by PID after each run, not committed): a fresh part's Capture page
  with nothing captured and Top selected (solid accent ring, no dashed-border doubling); Top
  captured + Side selected (live ring + check badge on Top, accent ring on the still-empty Side);
  the "+ Custom" card (Plus icon, "Custom" label); an unsaved custom chip (`left_side`) showing
  `custom-face-remove` as a small round badge top-right of its own card, and the grid right after
  clicking it (chip gone, selection fell back to Top); the Part page, unchanged. Looked at all of
  them — the first screenshot is what caught the `faceGrid` state-expression gap above.
- **Judgment calls:** (1) `~ariaPressed`'s ReScript type is `option<bool>` rather than the brief's
  literal `bool=?` — ReScript 12's JSX requires optional labelled args to be spelled with an
  explicit `option<_>`; `bool=?` alone is a compile error (warning 22, configured as an error here).
  Same optional-bool prop, correct syntax. (2) `custom-face-remove`'s accessible affordance changed
  from a labelled "Remove chip" button (icon + text, in the shutter block) to an icon-only 24px
  badge (`aria-label` unchanged: "Remove the `<label>` chip") — smaller, but per the brief's own
  instruction to move it into the badge slot; the accessible name carries the same information a
  sighted "Remove chip" label did.
## 2026-09-17 — A10 folders (agent/a10-folders)

SPEC §8a A10 built to the pre-build review (`docs/design/a10-folders-review.md`, BUILD WITH
CHANGES). First commit applied the review's rewrites to the spec text; the four after it built to
that text. Branch `agent/a10-folders`, not pushed.

- **Spec rewrites applied (commit 1).** B1: `a//b` *normalises* to `a/b`, only bad segments
  reject. B2: the Part page's one Shell subtitle is the folder path; layout A's stats line stays
  in the features group header (DESIGN.md §11.2's stale "bar subtitle stats" sentence fixed to
  match, plus one clause on the Parts list's sections + search). S1–S8, N1–N7 folded in as the
  review's ready-to-paste bullets. §7 gained the one-line `part.path` carve-out the review's
  bullet 1 points at (it is a folder path, not a bundle-relative file path) — a sentence outside
  the A10 block, but the review text explicitly references it, so it went in rather than leaving
  a dangling cross-reference.
- **`core/Folder.res`** (pure, `FolderTest.res` = the review's §4 table + message cases).
  Judgment calls where the brief and the review's table differed: `display` is `string => string`
  (`""` stays `""`; `Part.subtitle` wraps it in the option), and the error type is exactly
  `BadSegment(seg) | TooDeep | TooLong` — a 33-char segment is a `BadSegment` (the regex's own
  `{0,31}` cap; `errorMessage` says "too long" for it instead of reciting the alphabet), `TooLong`
  is the 120-char whole-path cap the review's N1 asked for. `validate` normalises first, so its
  `Ok` payload is the path to store; `snap` is case-insensitive against the existing folders.
- **Codec coverage.** Adding the read-time `let path = …` between `decodePart`'s tuple match and
  its record build made the compiler emit one early `return` per required field (A7 hit the same
  with `decodeFace`), which dropped core/ to 98.4 % lines. Fixed the same way A7 did: the single
  "missing slug" test became a per-field reject loop. Core is back at 100 % lines (branch misses
  on `Codec.res.mjs` lines 27/124 are pre-existing).
- **Store.** `createPart` takes a *required* `~path` (not an optional defaulting to `""`): the
  brief said `createPart(~path)`, and a required arg makes every caller state its intent; the 13
  StoreTest call sites pass `~path=""`. Docs without `path` read back as `""` — tested with a raw
  pre-A10 part doc, same pattern as A7's raw legacy face doc. No index change.
- **Parts list.** Sections, chips and search are all derived in `view` from `model.parts` — the
  chip order ("newest `updatedAt` of any part in that folder") falls straight out of `parts`
  order (Store sorts updatedAt desc; `RenameSaved` now re-sorts), so `foldersOf` is one
  first-seen pass, no second sort. The root section is *always* headerless (review: "header
  omitted when no part has a folder" and the e2e's "root header absent" agree on that reading),
  so a folder-less list is the pre-A10 list plus the search field. Search: `global.css` puts
  `-webkit-appearance: none` on `input[type="search"]` (can't edit it — not owned by this track),
  which in WebKit also drops the native cancel button, so the page ships its own
  `parts-search-clear` icon button and removes Chromium's leftover
  `::-webkit-search-cancel-button` explicitly — one clear affordance, ours, on every engine.
  Clearing refocuses the field. `Ui.ChipRow` has no `~className`, so the chips' 8 px top gap
  comes from a wrapper `div.part-path-chips` — a small Ui gap, noted not fixed (Ui.res edits
  were limited to `ListGroup ~headerTestId`).
- **One `PartForm`** (review S4) renders both the create form (grouped rows + the units row) and
  the inline rename strip. Visible change to rename: its bare input became a labelled "Name"
  field with the "Folder" field under it (better a11y; same `part-rename-input` testid). Field
  ids take a per-part suffix on the rename strip so two open strips never collide; the create
  form keeps `part-name-input`. A chip tap fills the field and refocuses it via
  `focusTestId("part-path")` — with two rename strips open that focuses the first `part-path` in
  the DOM; accepted, same edge as the pre-existing `part-rename-input` focus.
- **Part page.** `subtitle = Some(Folder.display(path))` when non-empty, else `None`. The stale
  "reserved for A10's future folder path" comment there is gone with it.
- **Golden.** `fixtures/hinge_pin/features.json` diff is exactly one added `"path": ""` line;
  `parameters.csv` untouched; the fusion-import skill's 84 Python tests pass unchanged (its plan
  snapshot already carried `"part_path": ""`).
- **Verified.** `npx rescript build` clean under `+a`; `npm test` 244/244; core coverage 100 %
  lines (`Folder.res` fully covered); `npm run build` clean; `E2E_PORT=3910 npx playwright test
  --config=e2e/playwright.config.js --project=chromium` **47/47** — the 44 existing specs plus
  `parts.spec.js` ×2 (sections/counts/search/move/re-sort; `a//b` normalises, `?` rejects
  inline, `A/B` snaps to `a/b`) and `export.spec.js` ×1 (folder exports verbatim, `path` right
  after `slug`, no path in `parameters.csv`; the golden test also asserts `doc.part.path === ''`).
  Screenshots (390×844 @2x, dark, throwaway script in the session scratchpad, not committed):
  `#/` with two folders + root, search `bezel` and the no-match line, the create form with chips
  and with the inline `?` rule + dimmed Create, the inline rename with the Folder field, and the
  Part page with `Miata / Interior` in the bar — all looked at; nothing needed fixing.
- **Flake, not this track's:** `EdgeSnapTest`'s "1000 snaps on a huge patch finish quickly" is a
  wall-clock test; it failed twice at ~3.3 s when the full suite ran under `--coverage` while
  other builds shared the CPU, and passed alone and in the plain `npm test` gate every time.
  Untouched here; flagging so nobody chases it as an A10 regression.
- **Not done / v1:** the search query resets on navigation (review N4 — `Route.Parts` could gain
  a `q`); renaming a folder is per-part (N7); no name uniqueness within a folder and the slug
  ignores the folder, so `<slug>.ccpart.zip` names can collide across folders (N6, stated in the
  spec); `a11y.spec.js` needed no change (the search field sits after the bar's Edit/"+" in DOM
  order, so "first Tab lands on a real control" still holds).

## 2026-09-17 — Focus-steal race on the create form (integration)

- **Symptom.** `parts.spec.js` "folder field: a//b normalises…" failed about half the time in
  isolation with `.shell-subtitle` not found after creating a part in `a//b`; it had passed on the
  A10 agent's branch. A 24-run reproduction (throwaway Playwright script, not committed) showed
  the failing runs with name `Normaliseda//b`, path `""`, `document.activeElement` = `part-name`.
- **Root cause (app, not test).** P2a's `focusWhenReady` refocuses `part-name` on every attempt
  across six animation frames after "New part" (needed because the first mounted node is replaced
  a frame later). Playwright's `fill` focuses `part-path` and then inserts text into *whatever is
  focused*; an attempt landing in that gap yanked focus back, so the folder text went into the
  Name field and the part was created at root. A thumb that taps Folder within ~100 ms of
  "New part" hits the same window on a phone.
- **Fix.** `Canvas.userIsTypingElsewhere(target)` (new `document.activeElement` / `tagName`
  bindings): the retry loop stops for good the moment an `INPUT`/`TEXTAREA`/`SELECT` other than
  the target has focus. Buttons deliberately don't count — on desktop the tap that opened the
  form leaves focus on the button, and the form field should still win. No spec change.
- **Verified.** `npx rescript build` clean under `+a`; reproduction 24/24 clean on the fixed
  bundle (was 1–2 failures per 8); `npm test` 244/244; `npm run build` clean; Chromium e2e
  **47/47 twice** (`E2E_PORT=4310`).

## 2026-09-17 — iOS 26/27 standalone: status-bar blur band + bottom dead strip

- **Reported from the phone.** The nav bar goes blurry under a gradient beneath the Dynamic
  Island, and a strip of empty space sits under the frame at the bottom.
- **Cause (research, not guessed).** iOS 26 added, and iOS 27 sharpened, a system-painted Liquid
  Glass "scroll edge" blur over the top of a home-screen web app that combines
  `apple-mobile-web-app-status-bar-style=black-translucent` with `viewport-fit=cover`. It is
  drawn above the web view, extends ~35 pt below the status bar, and no CSS or meta switch turns
  it off (MrClit/fin-app#411, vjt/grappa-irc#2190). The same combination is what makes iOS report
  the *small* viewport for `dvh`/`innerHeight` on Dynamic-Island phones, leaving the dead strip at
  the bottom — the thing ternpike's `body { min-height: 100lvh }` comment already documents
  (nearest WebKit ticket: 301108, the Safari 26 `viewport-fit=cover` regression).
- **Fix.** `index.html`: status bar style `default` (opaque, coloured by `theme-color` =
  `cc-ground`, so it reads as one dark surface with the bar below). `safe-area-inset-top` becomes
  0 in standalone — the bar's `padding-top: env(safe-area-inset-top)` stays for browsers that
  report one. Belt and braces for the strip: `@media (display-mode: standalone)` switches `body`,
  `#root` and `.app-frame` to `100lvh` (a browser tab keeps `100dvh`, where `lvh` would push the
  frame's bottom under Safari's toolbar). Reverses the P1 note above that `black-translucent`
  "stays".
- **Trade-off.** Content no longer scrolls under the status bar in the installed app. On a solid
  `cc-ground` background that is invisible; it also stops our glass bar double-stacking with the
  system's.
- **Verified here.** `npm run build` clean; Chromium e2e 47/47. **Not verifiable here:** the
  effect only exists on a real iPhone (WebKit never runs in this sandbox) — remove and re-add the
  home-screen app after the Pages deploy, since iOS reads the status-bar meta at install time.

## 2026-09-17 — iOS standalone, round 2: `lvh` reverted, viewport readout on Debug

- **Phone report after the previous entry:** "almost worse" — excess scroll on short pages, the
  bottom cut off on long ones. Screenshots show the status bar now painted by iOS with our bar
  below it (the `default` meta did its job) and no blur band.
- **Diagnosis.** The `@media (display-mode: standalone) { … 100lvh }` belt-and-braces was the
  regression. With `black-translucent` the web view covered the whole screen, so ternpike's
  "`lvh` = full screen" was right and `dvh` (screen minus the top inset) was the one that fell
  short. With `default` the web view already *is* screen minus the status bar, so `dvh` is exact
  and `lvh` (still the full screen) overshoots by the status-bar height: a fixed-height frame
  that is ~59 px taller than the viewport scrolls the document on short pages and hides the
  shell's bottom on long ones. Exactly the two symptoms. Reverted; the frame is `100dvh` again.
- **No more guessing.** `#/debug` now has a "Viewport" group that measures, on the device, every
  number iOS can disagree with itself about: mode, `screen`, `inner`, `visualViewport.height`,
  `100vh`/`lvh`/`svh`/`dvh` (hidden fixed probes, `Debug.css`), `position: fixed; inset: 0`,
  `env(safe-area-inset-top/bottom)`, the laid-out `.app-frame` height, and the document's
  client vs scroll height (excess scroll = the difference), plus the user agent (which carries
  the iOS version). "Re-measure viewport" re-runs it after rotating or opening the keyboard.
  `Canvas.res` gained the `innerWidth/innerHeight/screen*/offsetHeight/scrollHeight/clientHeight`
  bindings. `shell.spec.js` asserts the 13 rows render and `100dvh` reads the pinned 844.
- **If the phone still disagrees:** the readout says which unit equals the visible height; the
  frame rule follows it. Candidates in order: `100dvh` (spec §5), `position: fixed; inset: 0`,
  `visualViewport.height` mirrored into a CSS variable (already done for `--vv-height`).
- **Tooling note.** `resq set decl` hung indefinitely on `Canvas.res` for an `@val @scope(...)`
  external (killed after 5 min, file untouched — writes are atomic as promised); appended with a
  heredoc instead. Not reproduced or chased here.

## 2026-09-17 — Settings and Debug were unreachable from the installed app

- **Reported as "Debug? As in Safari inspector".** Fair: nothing linked to `#/settings` or
  `#/debug`, and a home-screen app has no URL bar, so both pages only ever existed for this
  sandbox's Playwright runs. The Snap and wedge toggles were equally unreachable on the phone.
- **Fix.** `Shell` gained a `leading` slot, rendered only when a page has no Back (the root); the
  Parts root puts a gear there (`settings-link`, an anchor to `#/settings`, `aria-label`
  "Settings" — HIG: one bar button on the root). Settings gained a Diagnostics group with a
  "Debug" row (`debug-link`, bug glyph, chevron) and Debug's Back now returns to Settings, not
  Parts, so Back retraces the way in. `.list-row-leading` in `Settings.css` sizes the glyph in
  the slot `Ui.ListThumb` fills on part rows.
- **Verified.** `rescript build` clean; Chromium e2e 47/47 with `shell.spec.js` rewritten to
  reach both pages through the UI and walk Back → Settings → Parts; a11y "first Tab on the root
  lands on a real control" still holds (it is now the gear). Screenshot tour regenerated
  (`12-parts-list`, `09-settings`, `10-debug` show the three changes).

## 2026-09-17 — A12a folder picker (agent/a12-folders)

SPEC §8a A12a built to the pre-build review (`docs/design/a12-folders-review.md`, BUILD WITH
EDITS — B3/B4, S3/S4/S7/S9/S10, N2/N3/N4 are the ones this half touches). Three commits on
`agent/a12-folders` (store + helpers, page + picker, e2e + docs + screenshots); not pushed. A12b
(selection toolbar, folder rename/delete) is untouched — `Ui.ListGroup` only gained `~role`, so
its `~headerTrailing`/`~headerEl` still slot in beside it.

- **Store.** `folder:` docs `{type, path, createdAt, updatedAt}` (N3), root never a doc.
  `ensureFolders(~paths)` is one `allDocs` range on `folder:` + one `bulkDocs` of every missing
  path and ancestor; PouchDB reports a per-doc failure *inside* the result array, so `ok: true`
  is the one success shape and anything else (a 409 from a concurrent writer) counts as already
  existing and is left out of the returned "created" list. Returned order is input order,
  ancestors first (`["a", "a/b", "a/b/c", "a/x"]`). `createPart`/`putPart` call `ensureFolder`
  for a non-empty path before the part write. Five StoreTests. No 409 test: forcing a real
  per-doc conflict needs a writer interleaved between the range read and the bulk write, which
  the LevelDB harness can't stage without reaching into Store's private handle — the code path
  is three lines and reads the documented result shape.
- **`Folder`.** `parent`/`leaf`/`ancestors`/`depth`/`join`/`isUnder` (strict — `isUnder("a",
  ~folder="a")` is false; everything is under the root)/`rebase` (also rewrites `path == from`
  itself, which A12b's `renameFolder` needs)/`validateSegment` (B4). **Beyond the spec's list:**
  `tree(paths)` — paths ∪ ancestors, deduped, root dropped, depth-first — and its comparator
  `compareTree` live in core rather than the page so the picker's ordering rule is tabled and
  under the 100 % gate; a case-twin pair (impossible after `snap`, but the sort must stay total)
  breaks the tie on the exact spelling *per segment*, so a twin still keeps its own children under
  it. `snap` is prefix-wise (S4): each prefix snaps against `existing` ∪ every existing path's own
  ancestors, so `miata/exterior` lands under `Miata` even though only `Miata/Interior` exists.
  Core stays at 100 % lines (`compareTree`'s `(None, _)` arms needed a direct tabled test —
  V8's sort never called it from that side).
- **Migration** runs once off `PartsLoaded`, sequentially inside one promise (S3). Judgment
  calls: the running set is **seeded with the existing folder docs** (their spelling is
  canonical, so a second launch can't re-snap what the first one settled), and "`updatedAt`
  order" is read as `parts` order — updatedAt **desc** — so the most recently touched spelling
  wins a twin. **Deviation:** the message is `FoldersLoaded(folders, saved)`, not
  `FoldersLoaded(array<string>)` — `putPart` bumps `updatedAt` and changes `path` on the re-snapped
  parts, and the page would otherwise show them at their stale spelling/position until reload.
  `saved` is `[]` on every store that never held A10 twins. A failure lands in `model.error`.
- **Picker.** Page-local `picker: option<{target: ForCreate | ForRename(id), selected,
  newFolder}>`; the view switches on `(picker, form)` so it takes over the page exactly as the
  create form does. Options are `<button role="option">`s built through the `react/jsx-runtime`
  record pattern Annotate's `RowButton` set (S7: `data-path`, `aria-selected`, `aria-label` =
  display path, `style.paddingLeft` = 16 + depth × 20 — `JsxDOM.domProps` can't express the
  data attribute). The listed set is `Folder.tree(folders ∪ parts' paths ∪ [selected])` — parts'
  paths are unioned in so a picker opened before `FoldersLoaded` lands still shows every folder
  in use. Create = `join` → `snap` against that same set → `ensureFolder`; the selection becomes
  the snapped path and `folders` gains `created ∪ [path]` (the path itself too, so a 409'd doc
  still shows). `folder-new-error` shows only once the field is non-empty — Create is disabled
  while empty either way, and a rule under a blank field on open is noise. The Folder row is a
  native `<button>` (implicit `role="button"`; no redundant ARIA); in the rename strip the
  `.parts-form-field` wrapper div holds a `.part-folder-field` button drawn like the Name input
  (N4). `title`/`largeTitle`/`leading`/`actions` all switch on `picker`; `Main.view` reads
  `largeTitle` and `leading` from the page (B3), and the Settings gear moved from `Main.res` into
  `PartsList.leading` — `shell.spec.js` still finds it.
- **Focus race, new guard.** `focusWhenReady` keeps `Canvas.userIsTypingElsewhere` (today's
  fix) and adds `Canvas.focusMovedElsewhere(~since, ~target)`: stop once focus sits on a third
  control — neither what had focus when the cmd started nor the target. Found by the e2e, not
  guessed: opening the New Folder field starts a 6-frame loop on `folder-new-name`; tapping
  Create within those frames (Playwright does, a fast thumb can) let the *older* loop refocus the
  field one frame after the tap, so the *newer* loop for the created option saw an editable with
  focus and gave up — then the field unmounted and focus fell to `<body>`. Verified with a
  throwaway focusin/MutationObserver probe (scratchpad, not committed): before, the trace ended
  on `BODY`; after, on `BUTTON#folder-option[Miata]`. The A10 case (a `fill` on the next field)
  still stops the loop, and the desktop "tap leaves focus on the button that opened the form"
  case still lets the field win, since that button is the `since` element.
- **e2e.** `parts.spec.js`: the A10 describe keeps its first test rewritten for the picker (the
  rename move now goes row → picker → option → Done → Save, and asserts the take-over: bar
  title, no rows, no search); its second (`a//b`/`?`/snap on `part-path`) is retired as the spec
  says and its `?`/snap cases live in the new "folders — picker (SPEC §8a A12a)" describe (3
  tests: nesting + Done + create + rename-move with the 20 px indent measured; `a/b` and `?`
  inline, `interior` snapping onto `Interior`, a created-then-Cancelled `Archive` surviving a
  reload; six-deep disables `folder-new` with the Footnote). `createPartIn`/`pickFolder` walk the
  segments (select the option if it exists, else New Folder). `a11y.spec.js` +1 (role/tagName/
  aria-selected, Tab from Cancel → Done → first option, Space selects, reopening focuses the
  selected option). **Deviation:** the spec lists `export.spec.js` as unchanged, but its own
  `createPart` helper filled `part-path`; that helper now walks the picker (six lines), its
  assertions are untouched and the JSON/CSV contract is unchanged (golden diff: none).
- **Verified.** `npx rescript build` clean under `+a`; `npm test` **244 → 265**; core 100 %
  lines (`Folder.res.mjs` 100/100/100/100); `npm run build` clean; Chromium e2e
  `E2E_PORT=4320` **47 → 50, green twice** (42.6 s, 42.8 s). Between those two runs one full run
  and one `shell.spec.js`-only run died with a Chromium **SIGSEGV** at `browser.newContext`
  (`chrome-headless-shell` native stack, no assertion involved). Reproduced against a `git
  archive` build of the untouched base `265674a` in the scratchpad: 1 of 5 `shell.spec.js` runs
  failed the same way. Sandbox/browser, pre-existing, not this branch — flagging so nobody
  chases it as an A12a regression. `features.json`, `parameters.csv`, `fixtures/` untouched.
  Screenshot tour regenerated (`node scripts/screenshot-tour.mjs docs/screenshots
  http://localhost:4320`), `13-folder-picker.png` added (picker with `Miata` → `Interior` and
  the New folder field open); `02-parts-create.png` and `13-folder-picker.png` looked at,
  nothing needed fixing; the tour's `.ccpart.zip` deleted.
- **Not done / A12b.** Empty leaf folders as `· 0` sections (an `Archive` made in the picker
  then Cancelled is a real doc but invisible on the list until A12b — the picker shows it);
  `moveParts`/`deleteParts`/`renameFolder`/`deleteFolder`; `Shell ~footer`; per-row delete stays.
  The `EdgeSnapTest` wall-clock flake under `--coverage` (A10 entry) fired once here too, on the
  full-suite coverage run only; the `src/core` coverage run and plain `npm test` were clean.

## 2026-09-18 — A12b selection toolbar, folder rename / delete (agent/a12-folders)

SPEC §8a A12b built on the merged A12a (`0a790bf`), to the pre-build review
(`docs/design/a12-folders-review.md`: B1/B2/B5, S1/S2/S5/S6/S8/S9/S10 are this half's). Four
commits on `agent/a12-folders` (store; Shell + Ui; page; e2e + docs + screenshots); not pushed.

- **Store.** `folderError`, `moveParts`, `deleteParts`, `deleteFolder`, `renameFolder` as
  specified, one `bulkDocs` per multi-doc write. A per-doc rejection in a bulk result *throws*
  (`JsError.throwWithMessage`) so the page shows its generic storage line — the alternative,
  dropping the rejected doc from the returned list, is a half-move nobody sees. Part docs need
  their `_rev` and `listParts` drops it, so `partDocsOf` does one `part:` range read for the ids
  in play (`moveParts` and `renameFolder` both use it). The recreated folder docs keep
  `createdAt` and bump `updatedAt`; a `from` with no doc (only a hand-edited store) still gets
  its `to` doc; `from == to` is a no-op. Five StoreTests, 265 → 270.
- **Shell footer.** `Shell ~footer` renders a `.shell-footer` wrapper after `<main>` directly in
  `.shell`; the sticky, the glass pseudo-child and the safe-area padding live on that wrapper
  (global.css, added to the three `.shell-topbar::before` selector groups), so the second glass
  surface is Shell-owned like the first and the page supplies only its contents —
  `edit-toolbar` is the content div inside. `Ui.ListGroup` gained `~headerTrailing` /
  `~headerEl` (S1) and exposes `Ui.ListGroup.Header` for the header-only row.
- **Page.** Model gains `selected`, `confirmingDelete`, `folderEdit`; `pickerTarget` gains
  `ForMove(ids)`; `rowState.ConfirmingDelete` and the per-row delete msgs are gone. Sections
  carry a `kind` (`Parts | EmptyLeaf | Intermediate`) derived from every known path
  (`Folder.tree(folders ∪ parts' paths)`): a folder whose parts all fail the query is hidden as
  in A10; an empty one shows when the query is blank or matches its path; Delete only on an
  `EmptyLeaf`, no confirm. The header buttons and picker options share the jsx-runtime record
  pattern (`PathButton`) because `data-path` is what tells one folder's pencil from another's.
- **Judgement calls and deviations.**
  1. **The intermediate header-only row's ids are `parts-folder` / `parts-folder-header`, not
     `parts-section-header`.** The spec lists the A10 "sections with counts … rename moves and
     re-sorts" test as unchanged in A12b, and that test stays in Edit mode after the rename-move
     and asserts one `parts-section-header` with `toHaveText` (strict mode) — `Miata`'s
     header-only row can't share the id without changing that test. Its text is the display path
     with no count: `· 0` on a folder that has content under it would mislead, and counts never
     include descendants.
  2. **Empty state with folders.** With zero parts the empty leaf sections still render under
     `parts-empty` and the capsule — a folder just emptied by the last delete must not vanish
     (S5). Edit is tied to parts > 0 per the spec, so such a folder is renamable/deletable again
     only once a part exists. A v1 gap, not hidden.
  3. **`renameFolder` returns `unit`** as specified, so the page rebases `parts`/`folders`
     locally: the store bumped `updatedAt` on the subtree's parts but the page's copies keep the
     loaded value until reload — only the meta line could show it, and within a section the
     relative order is unchanged (every part in the subtree gets the same stamp). Returning the
     rewritten parts would fix it in six lines if it ever bites.
  4. `NotEmpty` / `Nested` (unreachable from the UI) land in `rowError` as one neutral line
     ("Couldn't rename that folder." / "Couldn't delete that folder.") — no inline copy per N6,
     but not the "talking to storage" line either, since storage did its job.
  5. **Delete strip focus** goes to `parts-delete-cancel` on open — the tapped Delete is replaced
     by the strip, so focus would otherwise fall to `<body>`; Cancel refocuses `parts-delete`.
     The spec left this open.
  6. **Move Done** closes the picker at once and dispatches `moveParts`; `PartsMoved` applies
     the result. Done with the root selected and the parts already there moves nothing and
     announces nothing, but the selection still clears (the spec clears it on Done, not on the
     count); the store call is made either way (no write when nothing moves).
  7. **`focusWhenReady` since-guard.** Enter in the folder-rename field submits from *inside* an
     editable; `Canvas.userIsTypingElsewhere` saw that field — still focused while React
     unmounted it — as "the user moved on" and gave up, so the renamed header's pencil never got
     focus. Found by the e2e (run 1), not guessed. The loop now treats `since` (whatever had
     focus when the cmd started) as never "elsewhere"; A12a's Enter-created New Folder option
     gets the same fix for free. The A10 `fill`-on-another-field case and the A12a third-control
     case still stop it (`since` is a button in both).
  8. **Formatter.** `rescript format` reflows 169 untouched A12a lines in `PartsList.res` (and
     hundreds in `StoreTest.res`) — the files were never format-clean. That noise was reverted
     rather than committed; only hand-written lines changed.
  9. **Screenshot tour.** `08`/`10`/`11` differed by timer/date bytes only (screens A12b doesn't
     touch) and were reverted; `12-parts-list.png` came back byte-identical.
- **Not verified on device.** The keyboard vs. the sticky toolbar (review N5) — no device here;
  Chromium headless draws the glass fill but the blur isn't visible in a screenshot.
- **Verified.** `rescript build` clean under `+a`; `npm test` **265 → 270**; core 100 % lines
  (`Folder.res` untouched — A12a's `rebase`/`isUnder`/`join`/`parent`/`leaf`/`validateSegment`
  were everything A12b needed); Chromium e2e `E2E_PORT=4322` **50 → 54, green twice** (53.0 s,
  51.8 s), no SIGSEGV this time; the `EdgeSnapTest` wall-clock flake fired once under full-suite
  `--coverage` (known). `features.json`, `parameters.csv`, `export.spec.js`, `shell.spec.js`
  untouched. Tour regenerated (`14-parts-edit-toolbar.png`, `15-folder-rename.png` added; the
  `.ccpart.zip` deleted).

## 2026-09-18 — A13 drill-down folder browsing (agent/a13-drilldown)

SPEC §8a A13 built on `dd52e52` to the pre-build review (`docs/design/a13-drilldown-review.md`,
BUILD WITH EDITS — B1–B5, S1–S10 all applied in the spec text this was built from). One agent,
one wave, as the spec asked; four commits on `agent/a13-drilldown` (route + bindings + tests;
Main + Part; the page; e2e + docs + screenshots); not pushed.

- **Route.** `Parts(string)`, `#/f/<seg>/<seg>` per-segment encoded through the new
  `WebApi.Uri` bindings; `parse` decodes inside a `try` and normalises, never validates.
  `Array.sliceToEnd` (named by the spec) is **deprecated in 12.3.1** and `+a` makes that an
  error — `Array.slice(~start=1)` does the same. `src/app/tests/RouteTest.res` is the first test
  outside `core/` and `annotate/`; vitest's `src/**/*Test.res.mjs` glob already picks it up and
  `Route.res.mjs` imports cleanly in node (`Tea` pulls React, nothing touches the DOM at load).
- **Main.** `RouteChanged(Parts(p))` with the page mounted calls `PartsList.update(m,
  FolderChanged(p))` directly and maps the cmd; anything else re-inits. `Part.back` is
  `Parts(part.path)` once loaded, `Parts("")` before.
- **Page.** `folder` / `foldersLoaded` / `newFolder` on the model; `FolderChanged` keeps and
  clears exactly the spec's table and scrolls `.shell` to the top through `Canvas.setScrollTop`.
  The view is one of: "Loading parts…" (until `loaded && foldersLoaded`), `folder-missing`, or
  the search field over either the results (`resultsOf`: folders by leaf in `Folder.compareTree`
  order, then A10's flat sections) or the folder (`folderViewOf`: direct subfolders by
  lower-cased leaf, direct parts `updatedAt` desc). A folder row's outer `<div>` carries
  `data-path`, so it goes through a jsx-runtime `PathDiv` (the `PathButton` / `OptionButton`
  pattern) rather than `Ui.ListRow`; its markup mirrors `Ui.ListRow ~href` exactly (glyph, `<a
  class="list-row-link">` body + chevron, trailing). The glyph slot is 72 px wide so folder and
  part titles align when both groups render. `Ui.ListGroup`'s `~headerTrailing` / `~headerEl`
  and `Ui.ListGroup.Header` (A12b) have no caller now; left in place — Ui.res is shared and they
  are harmless.
- **Judgement calls and deviations.**
  1. **`LoadFailed` also sets `foldersLoaded`.** The spec sets it from `FoldersLoaded` and
     `FoldersFailed` only, but the migration only ever runs off `PartsLoaded` — after a
     `listParts` failure nothing would flip it, and the error line would sit under "Loading
     parts…" for good.
  2. **The New Folder capsule shows at the empty root too** (`01-parts-empty.png` gains the
     secondary capsule under "New part"). The spec's "the root with no parts and no folders shows
     A10's empty state unchanged" reads as *copy + primary capsule unchanged*, and the New Folder
     rule ("present in the folder view whenever the query is blank … absent in an unknown
     folder") names no other exception; the review's §2.6 rationale (a folder should be creatable
     before its first part without hunting) points the same way. One line to drop if the owner
     wants the pre-A13 empty screen back.
  3. **Body order.** At the root: copy (no part anywhere), `new-part` capsule, Folders, Parts,
     New Folder. In a folder: Folders, Parts (or "Empty folder"), `new-part` capsule (no part
     anywhere), New Folder — the spec gives the two orders separately and they differ; both are
     followed as written.
  4. **Edit's "view has rows" predicate reads the folder view, not the results**, so Edit and
     the toolbar stay put while a query is typed (B4's sticky-toolbar concern) and Edit can't
     appear or vanish with each keystroke. The one edge: a folder with nothing in it offers no
     Edit even though a query could surface rows — moving those needs their own folder.
  5. **`EditToggled` closes the New Folder field** (P1's no-leftover-state rule, "any open
     editor"); `QueryChanged` leaves the draft alone (hidden with the capsule while searching,
     back when cleared), as the spec's "nothing else" asks.
  6. **`FolderRenamed` leaves `model.folder` alone.** The renamed row is always a child of the
     folder on screen, so the screen's own path can't change; rebasing it defensively would
     leave the hash stale.
  7. **Search results with a whitespace-only query are the folder view** (`String.trim`), the
     same reading `matchesQuery` already applies.
- **e2e.** Exactly the spec's "Existing specs that change" list: the A10 test, A12a's first, the
  three A12b management tests, `a11y`'s Edit-mode locator (`parts-section` → `parts-list`); the
  A12a picker tests 2–3, `pickFolder` / `createPartIn` / `createEmptyFolder`, `shell.spec.js`
  and `export.spec.js` are byte-identical. New describe "folders — drill-down (SPEC §8a A13)"
  (3 tests) and `a11y` "inside a folder: Tab reaches Back first" (+1). One assertion I wrote
  matched the root's `<h1>Parts</h1>` as well as the group's `<h2>` — pinned to `level: 2`;
  the app was right. Tour reordered per the spec (12 after the seeding, 16/14/15/17 added or
  moved).
- **Verified.** `rescript build` clean under `+a`; `npm test` **270 → 275**; Chromium e2e
  `E2E_PORT=4330` **54 → 58**, green twice. Under full-suite `--coverage` the `EdgeSnapTest`
  wall-clock test (annotate, untouched here) tripped both times — with the e2e run sharing the
  CPU and on a quiet re-run (known, A10 entry); plain `npm test` is clean, and the
  `src/core`-scoped coverage run (A12a's precedent; the coverage `include` is `src/core/**`
  either way) reads `core/` **100 % lines** (156 tests, `Folder.res` untouched). `features.json`,
  `parameters.csv`, `export.spec.js`, `shell.spec.js`, `fixtures/` untouched.
- **Not verified on device.** The scroll-to-top on a folder change (`Canvas.setScrollTop` on
  `.shell`) — headless Chromium at 844 px never scrolls the seeded lists; and the Headline +
  subtitle bar in a folder against a real notch.

## 2026-09-18 — Snapkin: rename and the napkin + lens icon

- **Name.** Product renamed Snapkin (snap a photo · napkin sketch · a small companion). Changed:
  manifest `name`/`short_name`, `<title>`, `apple-mobile-web-app-title`, the A2HS hint, console
  prefixes, README / CLAUDE.md / SPEC.md headers. **Kept as contracts:** the PouchDB database name
  (`caliper-companion` — renaming it would orphan every phone's data), the `features.json` schema
  id and generator name (the import skill and the golden check them), `.ccpart.zip`. Repo name and
  Pages URL are the owner's call.
- **Branding.** `docs/design/branding-snapkin.md` + `mockups/brand-*`: three directions (Napkin,
  Snap, Kin) → owner chose A → five lens riffs (§2a) → four ⌀-line treatments (§2b) → **variant 5,
  treatment (b)**: orange napkin tilted −6° with crease and lifted flap, a live-blue lens cut into
  its face, a horizontal ⌀ dimension in ground with filled arrowheads on the rim and witness ticks.
  The hole is what breaks the "file icon" read; the horizontal drafting dimension is what stops the
  "expand" read; the blue keeps the tile unlike Fusion's.
- **Icons.** `scripts/make-icons.mjs` rewritten from §2b's 1024-space geometry (favicon rounded
  `rx=224`, PNGs full-bleed, mark inside the 80 % safe area); regenerated `public/favicon.svg`,
  `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`. Checked at 512, 180, and the favicon at
  16 / 32 / 64 / 128 (Chromium render). Remove and re-add the home-screen app to pick it up.
- **Open, owner's call:** `generator.name` in `features.json` ("Caliper Companion" → "Snapkin"
  would touch the golden and the skill's check); repo rename.

## 2026-09-18 — A14a hybrid glass: mono tokens, two materials, per-selector fixes (agent/a14-glass)

SPEC §8a A14, the A14a half (tokens, materials, headers, icons, fallbacks); A14b (overlays, icon,
export test, docs) is a sibling branch on disjoint files. Every number below is the reviewed one
(`docs/design/a14-glass-review.md`); where the code and the text disagreed, the code won and it is
listed under "Deviations".

- **Tokens** (`src/theme.css`): the §7 "Glass" column verbatim — ground `#0E0F11`, surface
  `#1B1C1F`, surface-2 `#26272B`, field `#151618`, border `#34363A`, text `#F2F2F0`, text-2
  `#A9ABAF`, text-3 `#8C8F94`, accent = text, accent-pressed `#D9DADB`, accent-ink `#0E0F11`,
  live `#C9CBCE` / live-border `#45484D` / live-wash `#26272B` / live-ink `#F2F2F0`, error
  `#F0605A` / error-ink `#2B0A0A` / error-wash 20 %, photo-mat `#1E1F22`, scrim `#0E0F11cc`.
  Glass: fill `rgba(28,29,32,.55)`, fill-strong `rgba(14,15,17,.70)`, stroke 18 % ink, highlight
  28 % ink, blur 24 px, saturate 1.2. `theme-color` (`index.html`) and the manifest's
  `theme_color` / `background_color` are `#0E0F11`. The semantic names stay: `.btn-primary`,
  focus rings, the bar's icon buttons, `a`, the selected face ring, the picker's check and the
  selection circles all still say `--cc-accent` and now resolve to ivory.
- **Materials** (`src/global.css`). Real `backdrop-filter` on `.shell-topbar::before` and
  `.shell-footer::before` only, at `--glass-fill-strong`. Everything else is the hairline
  material — `--glass-fill` with no filter, 1 px `--glass-stroke`, `inset 0 1px 0
  --glass-highlight`: the base `.btn` capsule and `.btn-secondary`, `.btn-icon`, `.chip`,
  `.list-group` (every one — Parts groups, search sections, the picker's listbox, the create
  form's grouped fields, Capture's custom / recapture cards, Settings, Debug), `.panel` (stroke on
  three edges; `.annotate-tools` went transparent inside it), `.a2hs-hint`. Stroke only, own
  fill: text inputs / select / textarea (`field`), the segmented track (`field`), the toggle
  track (`surface-2`). `.face-card`: `surface-2` mat + a real 1 px stroke. G1 wash on
  `.app-frame` (14 % top-left, 8 % bottom-right radial gradients over ground). Blur count per
  screen, verified by reading the CSS, not the compositor:

  | Screen | Blurred surfaces |
  |---|---|
  | Parts root, folder view, search results, picker, create form | bar (1); + footer toolbar while editing (2) |
  | Part, Capture, Annotate, Settings, Debug | bar (1) |

- **Per-selector fixes**: `.btn-primary` ivory fill / `accent-ink` label, highlight dropped
  (`.btn-danger` and `.btn-plain` drop it too); `.chip[aria-pressed="true"]` ivory fill;
  `.segmented-option[aria-pressed="true"]` = `rgba(242,242,240,.16)` over `field` with a `text`
  label (the one 16 % surface — a lighter glass, not ivory, so the primary stays the one ivory
  capsule on Annotate); `.toggle` on = `text` track + `ground` knob (off = `surface-2` + `text`);
  `.shutter` = `text` disc, `0 0 0 3px ground, 0 0 0 6px text` gap ring, no border;
  `.annotate-tools .annotate-snap[aria-pressed="true"]` = `text` fill + `accent-ink` label (a
  new rule — the on state was a text colour); `.face-card-selected::after` = `text` ring;
  `<select>` chevron `#A9ABAF` at 1.5; `.face-card-scrim` gradient on (14,15,17).
- **Headers / icons / fallbacks**: `Ui.ListGroup ~headerHidden` (→ `Header ~hidden`) puts
  `visually-hidden` on the `<h2>`; PartsList's "Folders" / "Parts" and Part's "Features · n"
  pass it. The headings stay in the accessibility tree, so `parts.spec.js`'s three heading
  counts and the two adjacent `role="list"` names are unchanged. Kept visible: search-section
  paths, Settings, Debug, "Choose Folder". `Icon.res` `strokeWidth="1.5"` (the check badge's CSS
  `stroke-width: 3` still wins). `@supports not` and `prefers-reduced-transparency` blocks
  untouched (they already cover exactly the two blurred surfaces); new `@media
  (prefers-contrast: more)`: those two go opaque `surface` with no filter and `--glass-stroke`
  steps to 28 % ink — the fallback that actually fires on iOS ("Increase Contrast").
- **Contrast**, measured on the built `src/theme.css` with a throwaway node script (WCAG 2.x,
  sRGB; composites computed for the translucent fills). Every pair the spec names clears 4.5:1;
  the two below the line are discussed under "Deviations".

  | Pair | Ratio |
  |---|---|
  | text / text-2 / text-3 on ground | 17.11 / 8.34 / 5.91 |
  | text / text-2 / text-3 on surface | 15.20 / 7.41 / 5.25 |
  | text / text-2 / text-3 on surface-2 | 13.31 / 6.49 / 4.60 |
  | text / text-2 / text-3 on field | 16.15 / 7.87 / 5.58 |
  | text / text-2 / text-3 on glass-fill over the wash peak (36,37,39) | 13.69 / 6.67 / 4.73 |
  | text / text-2 / text-3 on glass-fill over ground | 16.00 / 7.80 / 5.53 |
  | text / text-2 on bare ground at the wash peak (46,47,48) | 11.97 / 5.83 |
  | **text-3 on bare ground at the wash peak** | **4.13** — the "never on bare ground" rule; nothing puts it there (see below) |
  | accent-ink on accent (primary label) / on accent-pressed | 17.11 / 13.70 |
  | live on ground / on surface; live-ink on live-wash | 11.80 / 10.48; 13.31 |
  | error on ground / on surface; error-ink on error (danger label) | 5.96 / 5.29; 5.67 |
  | text on error-wash over surface | 11.52 |
  | text on the bar (fill-strong) over white / pale fixture / ground | 6.46 / 7.20 / 17.11 |
  | **text-2 on the bar over white** | **3.15** — see Deviations |
  | text on the selected segment (16 % ink over field); text-2 on field | 10.31; 7.87 |
  | text on the scrim pill over white | 9.40 |
  | ground check on live badge; ground knob on text track; text knob on surface-2 track | 11.80; 17.11; 13.31 |
  | text on photo-mat | 14.70 |

  `text-3` as text only ever sits on `field` (placeholders), inside a `.list-group` (chevrons)
  or as a ring (the selection circle, the canvas focus ring); the `.slot { color: text-3 }`
  rule is dead CSS (no markup uses `.slot*` any more).
- **Verification**: `npx rescript build` clean, `vitest` 275 / 275 (unchanged), Chromium e2e
  (`E2E_PORT=4360`) **58 / 58 green twice**. Tour into `/tmp/tour-a14a` (all 17), looked at
  `02 03 04 05 07 08 09 10 12 13 14 15 16 17` against `mockups/mono-glass.png`: the primary is
  the one ivory capsule per screen, captured (live ring + badge) vs selected (`text` ring) vs
  empty (dashed) read apart without hue, the Snap pill's on state is a fill, the toggle knob
  survives both states, hidden headers are gone from Parts / Part and kept on Settings / Debug /
  search sections. `docs/screenshots` untouched (A14b regenerates them).
- **Deviations and judgment calls.**
  1. **"Delete n" was never red.** `.edit-toolbar-danger { color: error }` (PartsList.css) tied
     on specificity with `.bar-action { color: accent }` (Part.css, linked later) and lost —
     the pre-A14 screenshot shows it orange. Under mono it came out ivory, so the table's
     "Delete n `error`" row needed `.bar-action.edit-toolbar-danger`. That, and
     `.part-folder-field`'s border (`--cc-border` → `--glass-stroke`, to match the Name input it
     is drawn like), are the two lines in `PartsList.css`, a file in neither agent's list.
  2. **Bar subtitle over a photo.** At the spec's 70 % bar fill, `text-2` over a pure-white
     backdrop is 3.15:1 (`text` is 6.5:1, the pair the spec measured). Only Part's folder-path
     subtitle can scroll over a photo, and only while a white face card is under the bar. Kept
     70 %: an 85 % fill gives 5.4:1 at the cost of most of the glass; the subtitle in `text`
     loses the HIG secondary. Owner's call — flagged, not changed.
  3. `.face-card` takes the stroke as a real border (an inset shadow sits under the photo) and no
     highlight (the photo covers it; the dashed empty card has no edge to highlight). The
     captured / selected rings sit 1 px inside it.
  4. `.toggle-track` takes its stroke as `inset 0 0 0 1px`, not a border — a border would shift
     the 28 px knob's 2 px geometry inside the 52×32 track.
  5. `.shutter` is `--cc-shutter` − 12 px with a 6 px margin, so the 3 + 3 px shadow rings land on
     the 76 px footprint the row was laid out for; the camera-input focus outline offset went
     3 → 8 px to clear the ring.
  6. `.annotate-dimensions .list-group` keeps its opaque `surface-2` (review S9) and inherits the
     base stroke + highlight — one raised card inside the translucent panel.
  7. `prefers-contrast: more` stroke is 28 % per the spec text (the review's S8 said 40 %).
- **Unverified.** Anything device-side: the 24 px blur and `saturate(1.2)` on iOS Safari, that
  "Increase Contrast" really trips `prefers-contrast: more` in a standalone PWA, the
  `.a2hs-hint` material (it only renders on iOS, not in the tour), and the bar over a real
  photo scrolling under it (the tour never scrolls). `prefers-reduced-transparency` is
  untestable on the target.

## 2026-09-18 — A14a merge note (integration)

- Merged `agent/a14-glass` at `7b81ee5`. One change on top: `.shell-subtitle` colour `text-2` →
  `text` (global.css). The A14a builder measured `text-2` on the 70 % bar over pure white at
  3.15:1 — reachable only by the Part page's folder-path subtitle scrolling over a photo — and
  flagged it rather than fixing it; `text` measures 6.46:1 there and the Footnote size keeps the
  hierarchy. `text-3` on bare ground (4.13 at the wash peak) stays as the builder verified: no
  text-3 sits on bare ground.
## 2026-09-18 — A14b: mono canvas/export overlays, the m2 icon, the legibility test

Built on `agent/a14b-overlays` off `a71a3f2` (SPEC.md's post-review A14 text), disjoint from
**A14a**'s tokens/materials/headers work (`theme.css`, `global.css`, `Annotate.css`/`Capture.css`,
`Icon.res:164`, `Ui.res`, `PartsList.res`, `Part.res:428`, `index.html`, `manifest.json` — untouched
here). Per SPEC §8a A14's "Build split" and `docs/design/a14-glass-review.md` §4 (B4/B5/S1/S5).

- **Overlay palette.** New `src/app/Overlay.res`: `ink #F2F2F0 · inkOn #0E0F11 · halo
  rgba(14,15,17,.85) · scrim rgba(14,15,17,.8) · live #C9CBCE · savedAlpha 0.7` — the app-level
  home the review called for (S5), so `export/Render.res` doesn't import "backwards" out of
  `annotate/`. Every literal in `Draw.res:24-30` and `Render.res:205-209` now reads it.
  - `Draw.colourFor` collapses to `ink` for every style: Pending, Selected and Dimmed no longer
    differ by hue (the old accent-orange/live-blue split), only by the pill and by `alphaFor`'s
    group alpha (`Overlay.savedAlpha`, was 0.6). `handle` draws a constant `ink` disc / `inkOn`
    ring+dot regardless of style (ring/dot in the style colour would vanish into an `ink` disc
    now that the disc itself is always `ink`). `snapRing` keeps `Overlay.live` — the one place it
    still paints. `pill`: Pending = `ink` fill / `inkOn` border+label (17:1); Selected/Dimmed =
    `scrim` fill / `ink` label.
  - **`dimension`'s Dimmed pill is deferred past `restore`.** The overlay table wants a Dimmed
    dimension's pill drawn *after* its `savedAlpha` (0.7) group closes, at alpha 1 — a 100 %
    label on a 70 % `scrim` pill inside the group is 3.9:1 on white, not the 9.4:1 the reviewed
    numbers assume. Implementation: a `ref(None)` queues `(text, at)` for Dimmed inside the alpha
    group instead of calling `pill` there; `pill` is then called on the queued value right after
    `ctx->restore`. Pending/Selected already run that group at alpha 1, so drawing their pill in
    place (unchanged) is equivalent — only Dimmed needed the deferral.
  - `Render.res` (export, no per-style distinction — one always-on style): `haloColor`/`lineColor`
    now `Overlay.halo`/`Overlay.ink`; `pillFillColor` `Overlay.ink`; `pillTextColor`/
    `pillBorderColor` `Overlay.inkOn`. **Deviation:** the overlay table's Export row lists Handle
    as "`ink` / `inkOn`", but `Render.res`'s handle is a single filled circle via `fillHaloed`
    (same call as the arrowheads, no separate ring/dot layer the canvas has) — adding an `inkOn`
    ring there would be new geometry, and "the export PNG geometry stays unchanged, only colours
    move" is explicit in this agent's brief. Kept the handle as `ink` fill only; the review's own
    prose version of this row (`a14-glass-review.md` §4 B4) lists "line `ink`, pill `ink`/`inkOn`,
    border `inkOn`" with no separate handle mention, which reads as the same call.
  - `RenderTest.res`: added the tabled case, `contrastRatio(Overlay.inkOn, Overlay.ink) >= 4.5`,
    as its own `describe` block (checks the `Overlay` constants directly, decoupled from whichever
    `Render.pill*Color` binding happens to alias them). **270 → 276 unit tests** (using this
    session's actual pre-A14 count, 275 → 276; `npx vitest run` clean).
- **Export legibility test** (`e2e/specs/export.spec.js`, SPEC §8a A3/A14b). `sampleLegibility`
  now returns `{sawInk, sawHalo}`. `isHalo` unchanged (`r/g/b < 70`, kept at 70 not 60 for the
  documented rounding margin). `isInk` replaces the old amber window
  (`R>200 && G∈[100,190] && B<90`) with `[r,g,b].every(c => c >= 225 && c <= 250) && max−min <= 12`
  — tight enough that the white photo itself (255,255,255) can't pass with no line drawn, which an
  unbounded `>= 200` window would let through. `sawInk` is true only when an ink pixel in the
  sampled column has a halo pixel at some smaller y *and* some larger y (white → halo → ink →
  halo → white), not merely "ink and halo both present somewhere" — implemented as a single top-
  to-bottom pass tracking whether a halo has been seen above, checked against `column.slice(i +
  1).some(isHalo)` below. Test titles "amber line…" → "ink line…"; comment block rewritten.
- **Icon** (`scripts/make-icons.mjs`), the m2 mark ("the lens alone",
  `docs/design/branding-snapkin.md` §7): replaces the orange napkin+lens with a closed ring (r 300
  at 512,512; stroke 64 → outer r 332, inner r 268), a horizontal ⌀ line x 316–708 at y 512 (same
  64 stroke, round caps — "one ink, one weight"), filled arrowheads 112×96 tips at x 252/772 bases
  at 364/660, no ticks; ink `#F2F2F0` on `#0E0F11`. Numbers are `a14-glass-review.md` S1's
  corrected geometry — the pre-review spec draft's stroke-72/±212-line/open-chevron numbers left a
  16 px cap-to-ring gap that rendered as θ at favicon size, and its "safe area" comment was 51 % of
  the box, not 80 %; fixed to "the maskable 80 % circle, r 410" (the ring's outer edge clears it by
  78 px). Regenerated `public/favicon.svg` (`rx 224`), `icon-192.png`, `icon-512.png`,
  `apple-touch-icon.png`; looked at the two PNGs — one closed ring, one line, two filled
  arrowheads, nothing else, legible down to 180 px.
- **Screenshots.** Full tour (`node scripts/screenshot-tour.mjs docs/screenshots
  http://localhost:4361`) against a `vite preview` of this branch. Changed: `06-annotate-pending`
  and `07-annotate-saved` (mono lines/handles/pills in place of accent-orange/live-blue — looked at
  `07`, confirms); `10-debug` changed incidentally (a non-deterministic on-screen counter, not a
  colour). Unchanged, as expected: `05-annotate-loaded` (shot before any dimension exists, nothing
  to recolour) and `11-part-exported` (its face-card thumbnails are static photo crops with a
  status badge — they never call `Draw.res`, and the actual dimensioned render, `Render.res`'s PNG
  inside the downloaded `.ccpart.zip`, isn't itself screenshotted; its ink/halo composite is what
  the legibility test measures instead). Deleted the `.ccpart.zip` the export step drops in the
  output dir. Surrounding chrome is still Dark Sky in this worktree, as expected — A14a's own
  branch carries the tokens/materials.
- **Docs**, scoped to this agent's brief (not SPEC's full Docs bullet — DESIGN §4/§5's per-control
  rewrites and `docs/testids.md` describe A14a's components and were left for that agent / merge
  reconciliation): `DESIGN.md` §2 token table replaced with the Glass column plus `--glass-*` and
  the text-3-never-on-bare-ground rule; §11.1 Materials rewritten around the two blurred surfaces
  + hairline-elsewhere rule (`a14-glass-review.md` B1/B2); §11.2 notes the Parts Folders/Parts
  headers and Part's "Features · n" are hidden, not removed (G5). `palettes-2026-09-17.md` gets a
  one-line "superseded by A14" pointer. `branding-snapkin.md` gains §8 "Adopted": the Glass column
  shipped over §7's own Graphite recommendation (S3's `text-3` contrast finding), what else
  shipped vs. stayed a mock. SPEC.md §13 gains the "Reduce glass" / A15 open question.
- **Verified.** `npx rescript build` clean under `+a` after every source change. `npx vitest run`
  **276/276** (275 + the new `Overlay` contrast case). Chromium e2e, `E2E_PORT=4361 npx playwright
  test --config=e2e/playwright.config.js --project=chromium`, **58/58 green twice**
  (`--workers=1`; see the hazard note below), including both legibility tests (white and black
  photos) against the new `isInk`/`isHalo` predicate.
- **Hazard hit, not a regression.** The default worker count crashed `chrome-headless-shell` with
  a real `SIGSEGV` (signal 11) twice, on two different, unrelated tests each time
  (`parts.spec.js`'s A10 rename test, then `shell.spec.js`'s Settings/Debug test) — never on this
  branch's own `export.spec.js` or `Overlay`-adjacent tests. A concurrent agent's own `vite
  preview`/Chromium processes were running in this same sandbox at the time (port 4360, a sibling
  `a14-glass` worktree) — read as sandbox resource contention, not a code defect. `--workers=1`
  reproduced clean, twice, with no other change.
- **Not verified.** No device/Safari pass (Chromium only, per this branch's scope). The blur-count
  table and the built-CSS contrast measurements SPEC's Docs bullet also asks for are about
  `global.css`'s materials, which this agent didn't touch — left to A14a / the conductor's merge
  pass, which also reconciles this entry with A14a's own LOGBOOK section.

## 2026-09-18 — A14 integration close-out

- Merged `agent/a14b-overlays` at `fe02c8f` on top of A14a (LOGBOOK union-merged). Combined build:
  `rescript build` clean, vitest 276/276, Chromium e2e 58/58 (`--workers=1`, port 4363), Vite clean.
  Screenshot tour regenerated on the combined build (mono UI + mono overlays) into
  `docs/screenshots/`.
- **Icon fix on top of A14b.** The first cut's ⌀ line (x 316–708, round caps) let each r 32 cap poke
  past the arrowhead's slope, which is only ±27 px tall at x 316 — a visible notch at every size.
  Now x 340–684 with butt caps, ending where the head is already ±37 px; heads unchanged. The
  generator's comment says why.
- Looked at: `07-annotate-saved` (ink dimensions on halo, Snap on = ivory fill, disabled primary
  reads as disabled), `12-parts-list`, `08-part-features`, `16`, `14`, and the 512 / 180 icons.

## 2026-09-18 — Phone report after A14: two Edit-mode fixes

- **Selection tick floated left of the disc (iOS).** `.part-select:checked::after` was
  `position: absolute` inside a `display: grid` checkbox that was not itself positioned; Chromium
  resolves that to the static position (centred by `place-items`), WebKit to the nearest
  positioned ancestor — the row — so the tick sat at the row's left edge. Both pseudo-elements now
  share `grid-area: 1 / 1` and no positioning; the Chromium screenshot is byte-identical, which is
  the expected signature of a WebKit-only bug. Not verifiable here (no WebKit).
- **Move picker preselected the root.** `draftPathFor(ForMove)` returned `""`; now the selected
  parts' common folder when they share one, else the folder being viewed (search results can mix
  folders). The root-level A12b test passed before and after because its parts *are* at root; the
  A13 drill-down test now asserts `Miata/Interior` is preselected when moving from inside it.

## 2026-09-18 — S2 splash: Fusion blue on the mono glass (adopted)

- Owner picked **S2 Live** from `branding-snapkin.md` §9 (icon unchanged). Blue means one thing —
  measured or verified geometry — and the mono "ivory fill = tappable" rule stays.
- **Changed.** `Overlay.res` `ink` and `live` → autodeskBlue-400 `#38ABDF` (lines, handles, pill
  text, snap ring; 7.36:1 on ground, 5.32 / 7.11 vs the halo on the pale / dark fixture; the 500
  step is 4.19 on the pale halo, too thin for a line). `theme.css` live family → the Autodesk
  steps (400 / 900 / 100 / 500) plus `--cc-live-fill #0696D7` and `--cc-live-fill-pressed
  #0684BE` (ground label 5.80 / 4.61). `global.css`: chip on, selected segment → live fill with a
  ground label; selected face ring → `live` (captured and selected now both ring blue, selected
  keeps its stronger ring). `Annotate.css`: Snap on → live fill. `export.spec.js`: `isInk` now
  matches the blue ±18 per channel instead of near-white; the halo-above-and-below rule stays, and
  both fixtures pass. `DESIGN.md` §2 rows and the branding doc's adopted line.
- **Unchanged.** Blur budget, the ivory primary, the icon, `features.json`, the export geometry.
- **Verified.** rescript build clean; vitest 276/276 (the `RenderTest` contrast case now measures
  ink #38ABDF vs inkOn #0E0F11 = 7.36); Chromium e2e 58/58; tour regenerated.

## 2026-09-18 — A16a motion: push/pop page transitions, take-over rises, press scale (agent/a16-motion)

SPEC §8a A16a, built to `docs/design/a16-motion-review.md` (B1–B4, S1–S9 folded in). A16b (the
segmented indicator, the selection-circle stagger, the canvas eases) is not here.

- **Tokens** (`theme.css`): `--cc-motion-nav 350ms`, `--cc-motion-sheet 280ms`, `--cc-ease-out`
  (= `--cc-ease`, one curve two names), `--cc-ease-in cubic-bezier(0.4, 0, 1, 1)`,
  `--cc-ease-standard cubic-bezier(0.2, 0, 0, 1)`. `--cc-motion` 160 and `--cc-motion-press` 80
  unchanged. No spring, no overshoot.
- **Runtime.** `WebApi.Document` (`data-nav` on `documentElement`), `WebApi.ViewTransition`
  (`startFn` feature check, `@send start`, `finished`), `WebApi.flushSync` (`react-dom`).
  `Motion.res` is the spec's generation-counted dispatch verbatim: `data-nav` set before `start`,
  cleared on both `finished` branches only if no newer transition began; unsupported → plain
  dispatch, no attribute. `Route.depth` (Parts 1 + folder depth, Settings 2, Debug 3, Part 10,
  Capture 11, **Annotate 12**), `Route.direction: (t, t) => Push | Pop | Fade`, `directionAttr`
  → `push` / `pop` / `fade`; `Route.subscribe` keeps `prev` and dispatches through
  `Motion.transition`, so the chevron, folder rows, `Route.push` and the browser's own
  back/forward all animate. `Shell.scrollToTop` (moved from `PartsList`; written as
  `Tea.Effect(fn)` — a constructor over a lambda — because `Tea.effect(...)` at top level would
  be weakly typed under the value restriction, `cmd` being invariant through `array`) is batched
  on every cross-page `RouteChanged` in `Main` and still by `FolderChanged`.
- **Every animation** (all zeroed under `prefers-reduced-motion`: CSS by global.css §12's 0 ms
  block, the view-transition pseudos by §15's `animation: none !important` — the API still runs
  and the swap is a ≈ 2-frame cut):

  | What | Duration | Easing | Reduced motion |
  |---|---|---|---|
  | Push: old root `cc-nav-out` (→ −30 %, opacity 0.6), new root `cc-nav-in` (from +100 %) | 350 ms | `--cc-ease-out`, `both` | `animation: none !important` |
  | Pop: old `cc-nav-back-out` (→ +100 %, `z-index: 1`, over the new), new `cc-nav-back-in` (from −30 %, 0.6) | 350 ms | `--cc-ease-out`, `both` | same |
  | Fade (same depth): old `cc-fade-out`, new `cc-fade-in` | 200 ms | old `--cc-ease-in`, new `--cc-ease-out` | same |
  | Create form `.parts-form`, folder picker `.folder-picker`: `cc-rise` (24 px up + fade) on mount | 280 ms | `--cc-ease-out` | 0 ms |
  | Edit toolbar `.shell-footer`: `cc-rise-footer` (from `translateY(100%)`) on mount | 280 ms | `--cc-ease-out` | 0 ms |
  | Press: `.btn` 0.97, `.chip` 0.97, `.face-card` 0.985, `.list-row:has(> .list-row-link:active)` 0.985 (the row, not the text-only link) | 80 ms | linear | 0 ms |

  Nothing transforms `.shell` or `.app-frame`; the nav CSS is on the `(root)` pseudos only. No
  exit animations (an unmount is a cut). The press scale is `.btn:active`, not `button:active` —
  bare buttons (segmented options, `button.list-row`) must not move. There is no `.folder-row`
  class: folder rows are `.list-row` + `.list-row-link`, so the `:has` rule covers them.
- **Measured** (scratchpad probe, the repo's Playwright Chromium, 390×844, the spec's
  `addInitScript` recorder plus timestamps): **push** `ready` 20–32 ms after the call, `finished`
  379–400 ms; old(root) `animation-name: cc-nav-out`, new(root) `cc-nav-in`, `animation-duration
  0.35s`. **Pop** `cc-nav-back-out` / `cc-nav-back-in`, old `z-index: 1`, `finished` 379–400 ms;
  a screenshot 150 ms into a pop shows the leaving Part screen sliding out *over* the dimmed,
  parallaxed Parts screen (and mid-push the new screen over the old). **Reduce:** both names
  `none`, `animation-duration 0s`, `finished` 42–50 ms after the call (`ready` at 18–30 ms — the
  swap itself is ≈ 2 frames). **Double Back** (Capture → two `history.back()` in one task): the
  first transition's `ready` rejects `AbortError` and its `finished` fulfils at 4 ms (callback
  still ran), the second runs its full pop (378 ms), `data-nav` is null afterwards under both
  settings — the counter works. Under `reduce` the coalesced second `hashchange` saw the same
  route twice (`Parts("") → Parts("")`) and logged a `fade` — harmless (two identical
  snapshots), noted. **Entrances:** `.shell-footer` `cc-rise-footer 0.28s cubic-bezier(0.2, 0.8,
  0.2, 1)`, still `position: sticky`; `.parts-form` / `.folder-picker` `cc-rise 0.28s`; `.btn`
  `transition: background-color, opacity, transform 0.08s linear`.
- **Playwright.** `reducedMotion` is not a first-class test option (only `colorScheme` is) — set
  directly under `use` it is *silently ignored* (measured: `matchMedia` false, the push logged
  `cc-nav-out`), so the config sets `use.contextOptions.reducedMotion: 'reduce'` and the spec's
  `test.use` overrides go through `contextOptions` too. `motion.spec.js` (chromium only): push /
  pop logged with the nav slides under `no-preference`; the same pair logs `none` under `reduce`;
  `html` loses `data-nav` (retrying); the toolbar, form and picker have a non-`none`
  `animation-name` on entry; and the one `no-preference` A6 case — a MutationObserver on the
  canvas records every `data-autofit` value, which passes through `fitting` to `fitted`. That
  case waits for `data-nav` to clear before tapping: a page is non-interactive while a transition
  runs (the pseudo-tree takes the pointer events), and the first draft's taps were swallowed by
  the 350 ms Capture → Annotate push. No existing spec changed.
- **Tour.** `scripts/screenshot-tour.mjs`'s `shot` now waits until no `data-nav` is set and no
  animation is `running` before its 150 ms settle — the tour waits, never the app.
- **Docs.** `DESIGN.md` §6 (the two exceptions, the token names, the handle scale-in struck) and
  §11.1 "Interaction feel" (the press scale).
- **Verified.** rescript build clean; vitest 276 → 281 (`RouteTest`: depth and direction for
  every pair the UI can produce, Capture → Annotate = push, Settings → Debug → Back); Chromium
  e2e 58 → 62, green twice; the tour (into a temp dir, not committed) renders `02`, `13` and
  `14` fully settled — no shot catches a rise or a slide mid-way. WebKit cannot launch here
  (e2e/README.md) — the iOS 18 push/pop, the footer's blur riding the rise, and the pop stacking
  are to be eyeballed once on the phone.

## 2026-09-18 — A16b motion: segmented indicator, selection-circle stagger, canvas eases (agent/a16-motion)

SPEC §8a A16b, on top of A16a (same branch). No `view-transition-name`, no `Motion.transition`,
no new dependency, nothing `position: fixed`, nothing bounces, no permanent frame loop.

- **Segmented indicator** (`Ui.res`, `global.css` §8). `Ui.Segmented` renders one
  `<span class="segmented-indicator" aria-hidden>` first and the group carries `data-index`
  (the selected option's position, `Array.findIndex`) and `data-count` through a jsx-runtime
  record component (`Segmented.Group`, the `PathDiv` route — `JsxDOM.domProps` cannot express a
  data attribute; `aria-label` is an optional record field). CSS as specified: `.segmented
  { position: relative }`, options `position: relative; z-index: 1`, the pressed option's
  background is now `transparent` (label colour unchanged), the indicator is absolute at
  2 px / 2 px / 2 px with `border-radius: inherit`, `--cc-live-fill`, and `transition:
  transform var(--cc-motion) var(--cc-ease-standard)`; widths `[data-count="n"]` =
  `calc((100% − 4px − (n − 1) × 4px) / n)` for n = 2, 3, 4 and offsets `[data-index="i"]` =
  `translateX(calc(i × 100% + i × 4px))` for i = 0…3. One addition: `[data-index="-1"]` hides
  the indicator (a `selected` outside `options`; no caller does it — every site passes an enum
  key — but a capsule parked on the first option would be a lie). The Snap pill and the hidden
  units `<select>` are untouched. Under `reduce`: §12's zero-duration block.
- **Selection-circle stagger** (`PartsList.css`). `.part-select` enters by `cc-select-in`
  (opacity 0 → 1, `translateX(−8px)` → 0) over `--cc-motion` `--cc-ease-out` with
  `animation-fill-mode: backwards`, and `.part-row-selectable:nth-child(2…7) .part-select`
  get `animation-delay` 20…120 ms, `:nth-child(n + 8)` 140 ms — pure CSS, no `--i` from the
  view (the rows are the `.list-group`'s direct children; the hidden header is outside it).
  Reading of "up to 8 rows": rows past the eighth share the last delay rather than dropping
  to 0, so no later row ever leads an earlier one. **§12 change:** the global reduced-motion
  block now also zeroes `animation-delay` (`!important`) — a 140 ms stagger of 0 ms
  animations would still be a stagger. The 8 px slide is the one transform inside a
  `.list-group` (A16a's "only take-overs rise"): the 24 px circle sits centred in its own
  44 px box, so −8 px never leaves the row or the group's clip.
- **Snap ring ease** (`Draw.snapRing`): `progress` goes through `Viewport.ease` (the §11.1
  curve) — the one line the review asked for. Geometry (1 → 1.6, fade) and `ringMs` 150
  unchanged; the `now`-based loop is the existing `frames` cmd, which stops scheduling at
  progress 1 and single-ticks under reduced motion (`matchMedia` read once per animation start).
- **Pill settle** (`Annotate.res`, `Draw.res`, `Viewport.res`, `Canvas.res`): the model gains
  `settle: option<{gen, id, progress}>` + `settleGen`, `SettleTick` through `frames(~ms=160)`
  (`settleCmd`), minted in `Saved(Ok)` for the landed dimension's id. `drawScene` passes
  `~pillScale=Viewport.settleScale(progress)` (new, pure: `1 + 0.04 × (1 − ease(p))`,
  clamped; two unit cases) to `Draw.dimension` for that one Dimmed dimension, which hands it to
  `Draw.pill ~scale` — the pill draws inside `save / translate / scale / translate / restore`
  about its own centre (two new `@send` bindings `Canvas.Ctx.translate` / `scale`), after the
  alpha group's `restore` like every Dimmed pill. Because `Tea.use` runs cmds synchronously
  inside `dispatch`, the reduced-motion single tick lands before React commits: the first
  paint after a Save is already the resting pill (measured below — no `scale` call at all).
- **Reading-field ring** (`Annotate.css`): `[data-testid="reading"]:focus { animation:
  cc-ring-fade 400ms var(--cc-ease-out) }`, keyframes `box-shadow: 0 0 0 4px var(--cc-accent)`
  → `transparent` — the `input:focus` outline (2 px, offset 0) stays underneath, so the visible
  ring is the 2 px beyond it. Restarts on each focus (fine). §6's handle scale-in stays struck.
- **Every A16b animation** (all zeroed under `prefers-reduced-motion`):

  | What | Duration | Easing | Reduced motion |
  |---|---|---|---|
  | Segmented `.segmented-indicator` transform between options | 160 ms (`--cc-motion`) | `--cc-ease-standard` | §12: 0 ms |
  | `.part-select` `cc-select-in` (opacity 0 → 1, −8 px → 0), +20 ms per row to 140 ms | 160 ms | `--cc-ease-out`, `backwards` | §12: 0 ms duration **and** delay |
  | Snap ring (canvas): radius 1 → 1.6×, alpha 1 → 0, progress eased | 150 ms (`ringMs`) | `Viewport.ease` (= `--cc-ease`) | `frames` single-ticks → never drawn |
  | Saved pill settle (canvas): scale 1.04 → 1 | 160 ms (`settleMs`) | `Viewport.ease` via `settleScale` | single tick → drawn at 1 on the first paint |
  | Reading field `cc-ring-fade` (box-shadow 4 px accent → transparent) on `:focus` | 400 ms | `--cc-ease-out` | §12: 0 ms |

- **Measured** (scratchpad Playwright probe against the preview, 390×844, `requestAnimationFrame`,
  `globalAlpha` and `ctx.scale` wrapped in-page): **Snap ring, `no-preference`** (three runs): 10–11 rAF
  callbacks per ring, 8–9 frames that draw it, the ring gone **154–174 ms after the tap** (last
  drawn frame 138–158 ms; `ringMs` 150 plus the click-to-first-frame latency), and **0 rAF
  callbacks in the second after it settles** (also 0 in [tap + 300, tap + 1300] ms). The alpha
  samples are the curve: 1 − ease = 0.57 at 24 ms, 0.28 at 40, 0.14 at 56, 0.07 at 73, 0.04 at
  89, 0.02 at 106, 0.01 at 122, 0.00 at 139 — most of the fade is over by a third of the way,
  the landing is soft. **Pill settle, `no-preference`:** 11 `ctx.scale` calls after Enter,
  the first 25 ms after the keypress (the write landing) at 1.0400, then 1.0236, 1.0120,
  1.0064, 1.0035, 1.0019, 1.0010, 1.0004, 1.0001, 1.0000 at 180 ms, the settle frame (no
  scale call) at 196 ms, and **0 rAF callbacks in the second after that**; 24 rAF callbacks
  in total after Enter — the settle's 11, the A6 restore tween's and the canvas-focus retries.
  **`reduce`:** the ring **0 rAF callbacks, 0 ring frames** — `data-snapped` still
  `true,false`, so the tap snapped and the ring was simply never drawn (final state on the
  first frame); the settle **0 `scale` calls** (the pill is at rest on the first paint after
  the Save — `Tea.use` runs the single tick inside `dispatch`, before the commit), 2 rAF
  callbacks after Enter that are not `frames` (the canvas-focus retries, pre-existing) and 0
  in [Enter + 300, Enter + 1300] ms.
- **Playwright** (`motion.spec.js`, chromium only, `contextOptions.reducedMotion` as A16a
  found): under `no-preference` — three parts, Edit → the first three `.part-select` have
  `animation-delay` `[0, 0.02, 0.04]` s and `animation-name: cc-select-in`; under `reduce` — the
  create form's Units group has `data-count="2"`, `data-index` 0 → 1 on pressing "in", the
  indicator's computed transform differs between the two states and its `translateX` is its
  own width + 4 px (polled), and the pressed option's background is transparent; the reading
  field is focused after p2 with `animation-name: cc-ring-fade`. No existing spec changed.
- **Verified.** rescript build clean; vitest 281 → 283; Chromium e2e 62 → 65, green twice; the
  tour's `07-annotate-saved` and `14-parts-edit-toolbar` (temp dir, not committed) are **pixel-identical** to the same tour run
  against a build of the A16a merge (`b237452`, served on a second port; diffed with
  Playwright's bundled pngjs) — motion adds nothing to the resting look. Of the other 15 shots,
  12 are identical too; `08` and `10` differ in a duration / timestamp readout (run time, not
  the build), and `06-annotate-pending` differs in the Kind control's selected capsule by
  **sub-pixel edge anti-aliasing only**: vertical extent identical (y 1404–1479 at 2×), the
  left and right edges within 0.5 device px (0.25 CSS px) — flex snaps each option box while
  the indicator sits at the fractional `calc` width (116.67 px for three options). Inherent to
  a transformed capsule standing in for a laid-out one; imperceptible, noted.
  WebKit cannot launch here — the glide, the stagger and the ring fade are to be eyeballed once
  on the phone.

## 2026-09-18 — A17-i adaptive layout: size classes, the Shell column, Part's two columns, hover (agent/a17-adaptive)

SPEC §8a A17-i on `8dbcb48`, with `docs/design/a17-adaptive-review.md` (B1, S1–S4, S8, S9, S10)
applied. A17-ii (Annotate medium / expanded, Escape, `adaptive.spec.js`, wide `07`, DESIGN §12)
is not here. No new dependency, no `%raw`, no `position: fixed`, no container query, no
`transform` / `overflow` on any ancestor of the two sticky bars or the new sticky aside — `.shell`
stays the one scroll container.

**What changed.**
- `theme.css`: the size-class table (compact < 600 / medium 600–1023 / expanded ≥ 1024) as the
  header's comment block; 600 and 1024 appear elsewhere only in `@media` preludes (theme.css's
  page-x steps, global.css §16, Part.css, Capture.css). Tokens `--cc-column` 720,
  `--cc-column-narrow` 560, `--cc-column-wide` 1120, `--cc-panel` 420 (A17-ii's),
  `--cc-bar-height` = `tap-min + safe-area-top`, `--glass-fill-hover` = `rgba(38, 39, 43, .55)`;
  `--cc-page-x` 16 → 20 → 24 by class. Type scale untouched.
- `Shell.res`: `~column: column=Column` (`Column | Narrow | Wide | Bleed`) → `data-column` on
  `.shell`, rendered through a jsx-runtime record component (`Shell.Root`, the `PathDiv` route —
  `JsxDOM.domProps` cannot express a data attribute). `PartsList.column` (narrow while the create
  form or the folder picker is up, else the 720 column) sits beside `largeTitle`; `Main.view` maps
  Part → `Wide`, Capture → `Column`, Settings / Debug → `Narrow`, Annotate → `Bleed`.
- `global.css` §16 (new, after §15): `--col` from `data-column` (wide is 720 at medium, 1120 at
  ≥ 1024), `.shell-content` / `.shell-large-title` at `width: 100%; max-width: var(--col);
  margin-inline: auto`; the bar and the footer stay full-bleed and their contents align to the
  column with the review's S8 expression; `.btn-block` capped at 400 and centred; `.face-grid` /
  `.face-grid-dense` 3-up at ≥ 600; the hover block under `(hover: hover) and (pointer: fine)`.
- `Part.res` (review S3): root `.stack-lg.part-columns`; the Found branch is
  `.part-gallery` (grid, or Edit mode's list) + `.part-aside.stack-lg` (features, Export, timer).
  `Part.css` at ≥ 1024: the `minmax(0, 1fr) minmax(320px, 380px)` grid with `align-items: start`,
  the error `p` spanning both, the gallery's grid `auto-fill minmax(200px, 1fr)`, the aside sticky
  at `bar-height + page-x` with `align-self: start`.
- `Part.res` / `Part.css`: the Hands-on timer `<p>` gains `part-timer` and centres at ≥ 600 —
  the `adaptive-after-*` boards centre it under the capped Export; at compact it stays
  left-aligned under the full-width capsule as before (the 390 `08` is byte-identical).
- `Capture.css` at ≥ 600: `.shutter-block` centred at 480. `Settings.res` / `Debug.res`:
  nothing — the narrow column is the Shell's. Debug keeps its 13 viewport rows (no size-class row
  added; `shell.spec.js:36` unchanged).
- `scripts/screenshot-tour.mjs`: `TOUR_ONLY=12,08,04` writes only those shots as
  `${W}x${H}-<name>.png`; the whole tour still runs and every `shot()` still settles the page, so
  later steps see the same timing; a filtered run does not save the export zip.
- `scripts/screenshot-tour.mjs`, the `17-parts-search` step: **a pre-existing race, found because
  the 1440 run hits it every time.** `page.goto('#/')` from `#/f/Miata` and the `fill('clip')`
  right after it: `hashchange` lands asynchronously and, since A16, inside a view transition,
  so the fill runs first, the results even render, and then `Main.RouteChanged` →
  `PartsList.FolderChanged("")` (PartsList.res:621–630) sets `query: ""` and the field empties.
  At 1440 × 900 the transition's snapshot is bigger, the window wider, and
  `expectVisible(parts-section-header)` times out; at 390 it is a coin toss (today's first phone
  run shot the cleared state). Reproduced on the untouched `8dbcb48` built in a second worktree
  and served on :4396: the same `TimeoutError` at the same step after 16 shots. Fix: wait for the
  root's `Miata` folder row before typing — the wait the `12` step already uses. With it the
  390 `17` is byte-identical to the committed one (A14's `ce817a6`).

**Measured (Playwright Chromium, the probe in the A17-i report; `hasTouch: false, isMobile:
false` at 1440, the project's touch at 820 and 390).**

| Screen | Before (the spec's `adaptive-before-*` state) | After 1440 × 900 | After 820 × 1180 |
|---|---|---|---|
| Parts root (`12`) | rows 1408 wide edge to edge (1440), 788 (820); bar gear at x 8 | `.shell-content` 720 at x 360, centre offset 0; Large Title at 384; rows 670 wide at x 385; leading button x 376, its 24 px glyph at 386 (review S8: 376 / 386); New Folder 400 at x 520 (centred) | 720 at x 50 (centre offset 0); button 62 / glyph 72; New Folder 400 at x 210 |
| Create form / picker | full width | `data-column="narrow"`, 560 at x 440 | 560 at x 130 |
| Part (`08`) | two 696 px cards, features + Export below the fold (1440); 386 px squares (820) | `data-column="wide"`, content 1120 at x 160; `.part-columns` grid `668px 380px`; three 212 px cards + "Capture" (the four `.face-card`s); aside 380 at (876, 68), `position: sticky; top: 68px`; Export 380 wide (≤ 400); Back button at x 176 | 720 at x 50, `.part-columns` stays `flex`; grid `216px 216px 216px`; Export 400 at x 210 |
| Part sticky (B1) | — | `.shell.scrollTop = 1000` (gallery given `min-height: 3000px` for the probe): aside top **68** = bar 44 + page-x 24; the gallery's top −932 (B1's stretch figure, now the gallery's, not the aside's) | n/a (single column) |
| Capture (`04`) | 2-up 696 px kind cards (1440), 386 (820) | 720 column at x 360; kind grid `213.3px × 3`; shutter block 480 at x 480 (centred); From library 195 wide | grid `216px × 3`; shutter block 480 at x 170 |
| Settings / Debug | full width | 560 at x 440; 13 viewport rows | 560 at x 130 |
| Hover | none | part row `background` transparent → `rgba(38, 39, 43, 0.55)` on `hover()`; `.list-row-link` cursor `pointer` | unchanged under touch (`hover: none`) |
| 390 × 844 | — | every box identical to before: content 390 at 0, leading 8 / glyph 18, h1 at 16, grid `171px 171px`, Export 358, `.part-columns` `flex` — `data-column` is present but inert |

**Screenshots.** Phone tour (390 × 844, DSF 2) into a temp dir against `docs/screenshots/`:
`12`, `08`, `04`, `13`, `14` byte-identical (and `01`–`05`, `07`, `09`, `15`–`17`); `06`, `10`, `11`
differ in the time-dependent pixels only (a 7 × 10 px box at the timer digit for `11`; Debug's
readouts at y 125–135 for `10`; the reading field's caret area for `06`) — nothing in
`docs/screenshots/*.png` is touched. Wide, `TOUR_DSF=1`, `TOUR_ONLY=12,08,04`, both runs end to end:
`docs/screenshots/wide/desktop/1440x900-{12-parts-list,08-part-features,04-capture}.png` and
`docs/screenshots/wide/ipad/820x1180-{12-parts-list,08-part-features,04-capture}.png`, looked at
against `adaptive-after-desktop-parts`, `-desktop-part`, `-ipad-portrait-part`: the column, the
bar contents, the 3 × 212 / 3 × 216 cards, the aside at y 68, Export 380 / 400, and the centred
timer all match; the Back chevron sits at x 186 on the desktop Part shot where the board drew it
at ≈ 198 — the board's bar used the 720 column's inset, the app uses the wide column's
(`(1440 − 1120) / 2 + 24 − 8 = 176` for the button), consistent with the Parts bar. No zip left
behind.

**Tests.** `npx rescript build` clean (warnings are errors); vitest 283 / 283 unchanged; the full
Chromium suite `E2E_PORT=4395 … --project=chromium --workers=1` 65 / 65, run twice after the
tokens / pages commits and twice more on the final build (timer class, tour wait). No spec
changed; `shell.spec.js` still counts 13 Debug rows. WebKit cannot launch in this sandbox
(`e2e/README.md`) — iPadOS Safari's rendering of the `max()` bar padding, the sticky aside inside
the `.shell` scroller and `(hover: hover)` with a trackpad are to be eyeballed on the iPad.

**Deviations and calls.**
- The footer keeps its compact floor (`page-x`) in the shared bar / footer padding expression
  where the spec has `space-2` for both: with `space-2` the Move / Delete pair would sit 12 px
  further out than at compact for the 600–712 px band (iPhone landscape), where the 720 column is
  wider than the window. Above that the two expressions agree.
- The hover rule adds `button.list-row:hover:active { background: var(--cc-surface-2) }` — the
  spec's `button.list-row:hover:not([aria-selected="true"])` (0-3-1) outranks
  `button.list-row:active` (0-2-1), so a press would have shown the 55 % fill, not the opaque
  surface-2 the spec describes as the press. `.face-card:hover` excludes `.face-card-empty`, as
  the spec's own "the empty dashed card is never repainted" asks.
- The tour's wide files are `${W}x${H}-<full shot name>.png` (e.g. `1440x900-12-parts-list.png`)
  rather than the bare id — the id is the prefix, so the spec's `${W}x${H}-${id}` still matches
  as a glob, and the file says what it is.
- The timer centring at ≥ 600 is not in the spec's text; it is on every board, and a left-aligned
  footnote 160 px from a centred capsule read as a mistake. Compact unchanged.
- `rescript format` rewrites files this repo does not format (239 lines of churn in
  `PartsList.res`); the ReScript edits here are hand-formatted to match their neighbours.

## 2026-09-18 — A17-ii adaptive layout: Annotate medium / expanded, Escape, `adaptive.spec.js`, wide `07`, DESIGN §12 (agent/a17-adaptive)

SPEC §8a A17-ii on `7a7481d` (A17-i merged), with `docs/design/a17-adaptive-review.md` B2, B3, S5,
S6, S7, S11, S12 and N5 applied. No new dependency, no `%raw`, no `position: fixed`, no container
query, nothing that binds under 600; `.shell` stays the one scroll container — the Annotate panel's
own `overflow-y` at expanded is the single exception, and the page then has nothing left to scroll.

**What changed.**
- `Annotate.css` only, for the layout. Medium (≥ 600): `.annotate-stage { height: max(300px,
  min(var(--vv-height, 100dvh) * 0.55, 720px)) }`. Expanded under `(min-width: 1024px) and
  (min-aspect-ratio: 1/1)`: `.annotate` is the grid `minmax(0, 1fr) var(--cc-panel)`, `gap: 0`,
  all four of `.shell-content`'s paddings undone by its margins, `min-height: 0` (over the compact
  `calc(100% + …)`), `height: calc(var(--vv-height, 100dvh) - var(--cc-bar-height))` — review B2
  as written; the stage `height: auto; min-height: 0; margin: page-x` (the left one keeps
  `env(safe-area-inset-left)`); the panel `min-height: 0; overflow-y: auto; overscroll-behavior:
  contain; border-width: 0 0 0 1px; border-radius: 0; box-shadow: none` and `padding-left:
  var(--cc-page-x)` (the compact rule's left padding carries the left safe-area inset — a
  right-hand column should not). The tools strip is already the panel's first child.
- Canvas sizing, confirmed and untouched (review S11): `CanvasView`'s `ResizeObserver` reports
  `getBoundingClientRect` width *and* height as `ViewSized`, `refit` calls `Viewport.fit(~viewW,
  ~viewH)`, `drawScene` resizes the backing store from both — a height-driven cell resizes it
  (backing 972 × 808 at 1440 × 900) and the untouched A6 pair re-fits.
- Escape (review S7): `WebApi.Keyboard` — `type event`, `key`, `defaultPrevented`, `isComposing`,
  `preventDefault`, `onKeyDown` (`@as("keydown")` on `addEventListener`) and `subscribe`, a
  `Tea.effect` registering the document listener once and dispatching only when `!defaultPrevented
  && !isComposing && key == "Escape"`. `Main.msg` gains `KeyPressed(string)`, `init` batches the
  subscription beside `Route.subscribe`, `update` routes `KeyPressed("Escape")` into the mounted
  page by a direct `update` call (the `FolderChanged` shape); Annotate / Settings / Debug are a
  no-op. `PartsList.Escape` = the first of the picker's New Folder field → `NewFolderCancel`,
  picker → `PickerCancel`, form → `FormCancel`, `confirmingDelete` → `DeleteCancel`, a `Renaming`
  row → `RenameCancel(id)` (new `renamingRow` helper over `rowStates`), folder rename →
  `FolderRenameCancel`, the root New Folder field → `NewFolderCancel`, else nothing; `Part.Escape`
  = `pendingDelete` → `FaceDeleteCancelled`; `Capture.Escape` = `RecaptureConfirm` →
  `RecaptureCancelClicked`, else `customDraft` → `CustomCancel`. The three `update`s are `let rec`
  so the arm re-enters the page's own Cancel msg and its focus handling rides along. The folder
  rename strip's own Escape now calls `preventDefault`.
- `e2e/specs/adaptive.spec.js`: the 1440 block (`hasTouch: false, isMobile: false`, review B3) and
  the 820 block (touch kept), eight tests — the Parts column ≤ 720 and centred in `.shell` (± 2)
  at both sizes; Part's two `.part-columns` tracks, Export ≤ 400 and the aside's top at bar + page-x
  (68) after `.shell` scrolls 1000 (the gallery stretched to 3000 px by `evaluate`, the A17-i
  probe's fixture — one face is not enough content to scroll at 1440 × 900); Annotate at 1440 with
  the canvas's right edge ≤ the panel's left, the canvas ≥ 600 tall, `.shell.scrollHeight ===
  clientHeight` before and after two taps that land as pending points with the reading focused,
  the panel `overflow-y: auto`; hover on a part row changing its computed background and the
  link's `cursor: pointer`; Escape closing the picker, then the form, then a no-op; the 820 face
  grid with three tracks, a card ≤ 240 and `.part-columns` not a grid; the 820 canvas ≥ 500 tall
  with the panel below it. `e2e/README.md` gained one clause for the per-describe viewport.
- `docs/screenshots/wide/{desktop,ipad}/…-07-annotate-saved.png` and DESIGN.md §12.

**Measured (Playwright Chromium; `hasTouch: false, isMobile: false` at 1440 and the 1024-wide
short window, the project's touch elsewhere; `--vv-height` = the viewport height).**

| Viewport | `.annotate` | Stage = canvas | Panel | `.shell` scroll / client | After p1, p2 |
|---|---|---|---|---|---|
| 1440 × 900 | grid `1020px 420px`, margin `-24 -24 -20`, min-height 0 | 972 × 808 at (24, 68), right edge 996; backing 972 × 808 | x 1020, 420 × 856, `overflow-y: auto` (856 / 856: the content fits) | **900 / 900** | `data-autofit="fitted"`, both points inside, reading focused, still 900 / 900 |
| 1180 × 820 (iPad landscape) | grid `760px 420px` | 712 × 728 at (24, 68) — the board's figure | x 760, 420 × 776 | 820 / 820 | fitted, inside, focused |
| 1024 × 500 (a short window) | grid | 556 × 408 | 420 × 456, scrollHeight 594 — **the panel scrolls itself** (`scrollTop = 200` clamps to 138, the tools strip at y −78) | 500 / 500 | — |
| 1024 × 1366 (13-inch portrait) | `flex` — stacked, the aspect gate | 976 × 720 (the cap) at (24, 68) | full width at y 800 | 1395 / 1366 (the page scrolls) | fitted, inside, focused |
| 820 × 1180 (iPad portrait) | `flex` — stacked | 780 × 649 at (20, 64) | full width at y 733 | 1320 / 1180 (the page scrolls) | fitted, inside, focused |
| 390 × 844 | `flex`, margin `0 -16 -20`, min-height `calc(100% + 20px)` | 358 × 300 at (16, 60) | y 372, 390 wide, `overflow-y: visible` | 967 / 844 | as before |

**Screenshots.** `TOUR_ONLY=07 TOUR_DSF=1` at `1440x900` into `docs/screenshots/wide/desktop/` and
at `820x1180` into `wide/ipad/`, both tours end to end, looked at against
`adaptive-after-desktop-annotate.png` and the iPad boards: the 972 × 808 stage at (24, 68), the
420 panel at 1020 with its left hairline, the tools strip on top, Reading / Name / chips / Kind /
Save / Clear / Dimensions in order; the stacked 649-tall stage over the full-width panel at 820.
Phone tour (390 × 844, DSF 2) into a temp dir twice: `05`, `07` and eleven others byte-identical to
`docs/screenshots/`, the two runs identical to each other on `05`, `06`, `07`, `11`. `06` differs
from the committed one by 420 px in the kind row (CSS y 702–740: a sub-pixel raster of the
segmented indicator's edge — A17-i's note placed its `06` diff at the reading caret) and `11` at
the timer digit; `10` differs between any two runs (Debug's readouts). To settle `06`, the untouched
base `7a7481d` was built from `git archive` in the scratchpad and toured on :4399: its `06` and `11`
are byte-identical to this branch's, and its `06` differs from the committed one by the same 420 px
— the committed `06` predates the drift, nothing at 390 is touched here, and nothing in
`docs/screenshots/*.png` is regenerated.

**Tests.** `npx rescript build` clean (warnings are errors); vitest 283 / 283 unchanged; the full
Chromium suite `E2E_PORT=4398 … --project=chromium --workers=1` **73 / 73, twice** (65 before + 8).
No existing spec changed; `shell.spec.js` still counts 13 Debug rows. WebKit cannot launch in this
sandbox (`e2e/README.md`) — to be eyeballed on the iPad: the grid following the on-screen keyboard
through `--vv-height` (and the panel's `overscroll-behavior: contain` in Safari), the
`(min-aspect-ratio: 1/1)` gate on a 13-inch iPad in portrait, a hardware keyboard's Escape, and
`(hover: hover)` with a trackpad.

**Deviations and calls.**
- The panel's `padding-left: var(--cc-page-x)` at expanded is not in the spec's rule: the compact
  panel padding adds `env(safe-area-inset-left)` on the left, which belongs to a sheet spanning
  the screen, not a right-hand column. Zero in the sandbox and on every iPad, so the boards'
  numbers hold either way.
- The stage margin keeps `env(safe-area-inset-left)` on its left where the spec has a bare
  `margin: var(--cc-page-x)` — same reasoning, same zero on every target.
- `PartsList.Escape` also closes the root New Folder field (last in precedence), beyond the spec's
  list: it is an inline editor like the others and its input has no Escape of its own.
- `WebApi.Keyboard.subscribe` returns a `Tea.cmd` from the binding module (the spec's
  `Keyboard.subscribe(k => KeyPressed(k))` in `Main.init`); `Timers.everySecond` is the precedent
  for a binding that hands back a cmd.
- The `Renaming`-row Cancel and the folder rename Cancel are mutually exclusive by construction
  (one inline editor at a time, A12b review S9), so their order in the arm never decides anything.
- The name chips at expanded stay the horizontal scroll strip (`.chip-row`'s existing
  `overflow-x: auto`, three chips visible in the 420 panel) where the desktop board wraps them
  into three rows. The component is untouched by A17 and the strip scrolls at 390 too; wrapping
  it is a call for the owner, not this pass.
- `rescript format` rewrites files this repo does not format; the ReScript edits are
  hand-formatted to match their neighbours, as in A17-i.

## 2026-09-18 — UX polish: depth, shape, release motion, scroll-edge bar (claude/caliper-companion-ux-polish)

Owner request, two passes, CSS only (no ReScript, no markup, no test-id change). The full list is
DESIGN.md §13; the calls worth remembering:

- **Why it read as boxy:** every surface shared one bright 1 px outline over one fill (a
  wireframe), empty tiles were dashed drop-zones, and the bare `button` rule's inset highlight drew
  a ghost capsule round every unselected segmented option and every `<button>` list row. Fixed at
  the source (`box-shadow: none` on `.segmented-option` / `.list-row`), then strokes halved and
  depth added.
- **§6 amended:** "nothing bounces, no spring" → two overshoot curves on small things only
  (`--cc-ease-spring`, `--cc-ease-glide`), and an asymmetric press (80 ms in, 320 ms out) — the
  release transition lives on the base rule, the press one on `:active`.
- **A14 reversed in two places:** the switch's on-track is the live fill (was ivory track + ground
  knob), and a captured face card has no live ring (badge only) — on Part every card is captured.
- **Scroll-edge bar:** resting state `opacity: 0` with keyframes going *to* 1 — a page too short to
  scroll has an inactive scroll timeline where the animation contributes nothing (measured: with
  `from { opacity: 0 }` the short Parts list kept full glass while Annotate's was clear). Measured
  0 / 0.5 / 1 at scroll 0 / 12 / 200; 1 throughout under reduced motion; 0 on a non-scrolling page.
- **Bug fixed in passing:** `.parts-search-clear` was centred with `translateY(-50%)`, which the
  `.btn:active` scale replaced — the button jumped 22 px on press. Now auto margins.
- **`scripts/screenshot-tour.mjs`:** the settle check ignores non-`DocumentTimeline` animations —
  a scroll-driven animation reports `running` forever and hung the tour.
- **Tests:** vitest 283 / 283; Chromium e2e 71 / 73 with 2 workers. The two failures
  (`parts.spec.js:86` wedge toggle persists, `annotate.spec.js:600` snap pill survives a reload)
  are a **pre-existing flake**: the untouched base built from `git archive HEAD` fails the same
  pair 7 / 12 under `--repeat-each=6 --workers=1`, this branch 6 / 12 — a settings write racing
  `page.reload()` / `goto`. Not fixed here. WebKit not run. `docs/screenshots/` (17 phone, 8 wide)
  regenerated.
- **Environment:** the asdf default Node (20.3.0) is below ReScript 12's floor (20.11); everything
  here ran with `ASDF_NODEJS_VERSION=22.16.0`. An `npm install` under 20.3 silently skips
  `@rescript/darwin-arm64`.
- **To eyeball on the phone:** the scroll-edge bar in Safari 26, the knob stretch and shutter press
  under a real finger, and whether 9 % strokes hold up outdoors.

## 2026-09-18 — Phone testing over Tailscale (owner call)

The phone loop is `npm run dev` + `tailscale serve --bg 3000` → https://mac-mini.tail128d00.ts.net
(tailnet only), not a push and a wait on the GitHub deploy — CLAUDE.md "Testing on the phone".
`vite.config.js` gained `server.allowedHosts: ['.ts.net']`: measured 403 for the tailnet Host header
before, 200 after, still 403 for any other host. Dev server only; `build` / `preview` untouched.
Serve had to be enabled once for the tailnet in the admin console. The tailnet origin has its own
PouchDB.

## 2026-09-18 — Demo video (`scripts/demo-tour.mjs`)

A 66 s phone-portrait walkthrough of the golden path with a cursor overlay, subtitle pills and
human pacing: new part (with the units segment flipped so the thumb glides) → capture → two edge
taps → reading → name chip → save → back → export. Motion is deliberately NOT reduced; the A16
pushes, the A6 fit tween and the polish-pass press/release are the point of the video.

- `--rehearse` walks the **same** route with the dressing off (no cursor travel, dwell or
  subtitles) and verifies every selector. First attempt only verified visibility without clicking,
  so it could not reach past the create form — rehearsal has to perform the navigation.
- The overlays carry a `view-transition-name`, which lifts them out of the root snapshot during a
  page push; without it the leaving screen's snapshot slides away carrying a ghost cursor.
- **The first canvas tap was being swallowed.** `data-autofit` is not a readiness signal (it reads
  `none` all through the load) — `data-image-size` is, and even after it the stage is still sizing
  for a beat, so a tap computed against the old box misses the image. `tapNormalized` now waits for
  `pending-points` to reach an expected count and retries with fresh geometry, failing loudly after
  four attempts. Recording needs no retries (its pauses cover it); rehearsal retries once.
- The shutter is driven through a real `filechooser` event, not `setInputFiles`, so the click in
  the video is the click a user makes. The export step waits for the actual download
  (`norcold_freezer_hinge_pin.ccpart.zip`) and warns if none arrives.
- Playwright writes WebM; `docs/demo/snapkin-demo.mp4` is that file through ffmpeg (H.264, CRF 24,
  faststart, 618 KB) because WebM does not play everywhere a demo gets pasted. The `.webm` is not
  committed.

## 2026-09-24 — Custom domain readiness: the Pages build follows Settings › Pages

- Dwight asked about pointing `app.`/`beta.snapkin.tools` or `snapkin.tools/app|beta` at the Pages
  site, and whether that needs Cloudflare. Checked 2026-09-24: `snapkin.tools` DNS is Squarespace
  (`nsc1–4.squarespacedns.com`), the apex serves Squarespace's "Coming Soon" parking page, `app` and
  `beta` are NXDOMAIN, and there are no CAA records. A subdomain needs one `CNAME` →
  `m0n01d.github.io` at Squarespace and no Cloudflare. ~~A path needs a proxy on the apex (a
  Cloudflare Worker, after a nameserver move, because partial CNAME setup is Business+) or a
  `m0n01d.github.io` user site on the apex.~~ Struck the same day: this repo's own Pages site can
  take the apex (A/AAAA records to GitHub), and then it serves any path in its artifact, such as
  the landing at `/` and the app at `/app/` (PR #2's proposal). A proxy is needed only when the
  apex is hosted somewhere other than GitHub. A user site on the apex serves project sites only at
  `/<repo-name>`, and it moves every other project site on the account under the apex too.
- The github.io → custom-domain 301 that PR #2's entry could not confirm from GitHub's docs is
  measured: `jekyll.github.io/jekyll/` → `jekyllrb.com/`, `mermaid-js.github.io/mermaid/` →
  `mermaid.js.org/`, path kept.
- `pages.yml` should run `configure-pages` before the build and pass its `base_path` as `VITE_BASE`
  (`/caliper-companion` today, `""` once a domain is saved; `vite.config.js` already maps `""` to
  `/`). Without it, saving a domain leaves a blank page until someone edits the workflow. Verified:
  both values build and pass `scripts/pages-smoke.mjs` under `vite preview` (SW scope = base,
  controlled, offline relaunch). README has the switch runbook. **The session token still cannot
  write `.github/workflows/`** (push refused again 2026-09-24, no `workflow` scope), so the 7-line
  edit rides in the PR body for Dwight to apply on the branch.
- Open for Dwight: the layout. Each tester's parts live in that origin's PouchDB, and v0 has no
  sync or import, so any later move of the app strands them. `app.snapkin.tools` keeps the app's
  origin independent of wherever the landing lives. `snapkin.tools` + `/app/` gives one URL, but
  ties the app's origin to this Pages site: moving the landing to another host later would need a
  proxy or strand the parts. My recommendation is `app.snapkin.tools`.
- `claude/**` pushes deploy to the same single Pages slot. Run 83 (a `claude/` push) cancelled
  `main`'s run 82, and on 2026-09-24 run 89 (`claude/keen-cray-m75xyi`) replaced run 88 (this
  branch) on the live site eight minutes later. That is fine for dev, but not once testers use
  the URL.
- Gotcha: killing `npx vite preview` by its PID leaves the `node` child on :3000. `ss` is not
  installed in the cloud sandbox, so check with `lsof -iTCP:3000 -sTCP:LISTEN` and kill that PID.
