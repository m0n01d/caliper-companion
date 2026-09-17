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
