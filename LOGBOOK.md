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
