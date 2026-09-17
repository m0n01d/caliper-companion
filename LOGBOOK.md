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
