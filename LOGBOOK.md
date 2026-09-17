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
