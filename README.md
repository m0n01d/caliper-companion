# caliper-companion
Annotated-photo caliper capture for reverse engineering small parts. Exports features.json for the Fusion 360 MCP.

## Develop

```sh
npm install
npm run dev          # ReScript watch + Vite on :3000
npm test             # ReScript build + vitest (core/ + store/ unit tests)
npm run e2e          # build + Playwright (Chromium; WebKit where its libs exist)
```

## Test on a phone (GitHub Pages)

`.github/workflows/pages.yml` builds and publishes `dist/` to GitHub Pages on every push to
`main` or a `claude/**` branch, at `https://m0n01d.github.io/caliper-companion/`. iOS needs HTTPS
for the service worker, `navigator.share`, and the DeviceOrientation permission prompt, so this is
the route for real-device testing. Pages must be enabled with Source = GitHub Actions (the
workflow tries to enable it itself).

The site lives under a subpath, so the build is parameterized by `VITE_BASE` (default `/`):

```sh
VITE_BASE=/caliper-companion/ npm run build
VITE_BASE=/caliper-companion/ npx vite preview --port 3000 --strictPort
node scripts/pages-smoke.mjs http://localhost:3000/caliper-companion/   # SW scope + offline relaunch
node scripts/pages-smoke.mjs https://m0n01d.github.io/caliper-companion/ # same, against the live site
```
