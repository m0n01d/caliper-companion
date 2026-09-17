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
