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
