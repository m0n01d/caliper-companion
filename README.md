# Snapkin

Repo `caliper-companion` — the product is **Snapkin** (renamed 2026-09-18): snap a photo, jot the
dimensions on it like a napkin sketch, export to Fusion. Older docs and the `features.json` schema
id keep the old name on purpose (the export contract and the on-device database name never change).
Annotated-photo caliper capture for reverse engineering small parts. Exports features.json for the Fusion 360 MCP.

## Develop

```sh
npm install
npm run dev          # ReScript watch + Vite on :3000
npm test             # ReScript build + vitest (core/ + store/ unit tests)
npm run e2e          # build + Playwright (Chromium; WebKit where its libs exist)
```

## Test on a phone (GitHub Pages)

`.github/workflows/pages.yml` builds and publishes `dist/` to GitHub Pages on every push to `main`
or a `claude/**` branch, at `https://m0n01d.github.io/caliper-companion/`. iOS needs HTTPS for the
service worker, `navigator.share`, and the DeviceOrientation permission prompt, so this is the route
for real-device testing. Repo settings it depends on (already set): Pages › Source = GitHub Actions,
and the `github-pages` environment allows `claude/*` branches to deploy.

The build is parameterized by `VITE_BASE` (default `/`). CI takes it from `actions/configure-pages`'
`base_path`, so it follows Settings › Pages: `/caliper-companion` on the github.io URL, empty (→ `/`)
once a custom domain is saved. To reproduce the project-site build locally:

```sh
VITE_BASE=/caliper-companion/ npm run build
VITE_BASE=/caliper-companion/ npx vite preview --port 3000 --strictPort
node scripts/pages-smoke.mjs http://localhost:3000/caliper-companion/   # SW scope + offline relaunch
node scripts/pages-smoke.mjs https://m0n01d.github.io/caliper-companion/ # same, against the live site
```

### Custom domain (e.g. `app.snapkin.tools`)

`snapkin.tools` DNS is at Squarespace. A subdomain needs one record there and no proxy:

1. Verify the domain for the account first: https://github.com/settings/pages › **Add a domain** →
   `snapkin.tools`, then add the TXT record it shows (`_github-pages-challenge-m0n01d`) and keep it.
   This stops another account's Pages site from claiming a subdomain that points at GitHub.
2. Squarespace › Domains › `snapkin.tools` › DNS › DNS Settings › Custom records: type `CNAME`, host
   `app`, data `m0n01d.github.io` (the account host, never the repo name).
3. Repo › Settings › Pages › Custom domain: `app.snapkin.tools` › Save. Then run **Deploy to GitHub
   Pages** on `main` (Actions › Run workflow). Saving the domain does not rebuild. Until the rebuild,
   the live build asks for `/caliper-companion/assets/…` and shows a blank page.
4. Tick **Enforce HTTPS** when it is offered. GitHub's docs say HTTPS can take up to an hour, and
   the checkbox up to 24 hours.
5. `node scripts/pages-smoke.mjs https://app.snapkin.tools/`

GitHub then 301-redirects `m0n01d.github.io/caliper-companion/…` to the new host. The new host is a
new origin with its own PouchDB, so parts made on the github.io URL stay behind. Export them first.

The apex is independent of the app. Point `snapkin.tools` (and `www`) at whatever hosts the
marketing site: a second Pages repo with the custom domain `snapkin.tools` (four `A` records to
185.199.108–111.153, four `AAAA` to 2606:50c0:8000–8003::153, and `www` CNAME `m0n01d.github.io`),
or Squarespace, where it points today. Moving the marketing site later never moves the app's origin.

## Import into Fusion without Claude

Every export bundle carries `parameters.csv` next to `features.json` (SPEC §8a A11), so you can get
a part's dimensions into Fusion 360 without the MCP skill at all:

1. Install [Parameter I/O](https://apps.autodesk.com/FUSION/en/Detail/Index?id=1801418194626000805)
   from the Fusion App Store (free, Autodesk's own add-in) — once per machine.
2. In Fusion: **Utilities → ParameterIO → Import**, then pick `parameters.csv` from the unzipped
   bundle. It creates a user parameter per feature (or updates one by name if it already exists),
   named and valued straight from the CSV — no manual typing.
3. Canvases are still manual: **Insert → Canvas**, one per face, using that face's
   `faces/<label>_dimensioned.png`.

The Claude skill (`docs/fusion/IMPORT-SKILL-SPEC.md`) does both of these steps automatically from
the same bundle — this path is for when Claude isn't in the loop.
