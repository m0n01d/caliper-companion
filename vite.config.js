import { defineConfig } from 'vite'
import path from 'path'

// Mirrors ternpike/vite.config.js minus the Elm plugin and backend URL logic.
// The service worker is stamped at build time with the git SHA and the hashed
// asset list so the very first visit populates the offline cache (see
// public/sw.js for why).
const commitSha =
  process.env.WORKERS_CI_COMMIT_SHA ||
  process.env.CF_PAGES_COMMIT_SHA ||
  process.env.GITHUB_SHA ||
  'dev'
const sha = commitSha.slice(0, 8)

// One build serves any path. `base: './'` is Vite's relative base: every URL
// it writes into dist/index.html (entry JS and CSS, manifest, icons) is
// relative to the document. Routing is hash-based (src/app/Route.res), so the
// document is always the app root, and those URLs resolve inside whatever
// folder dist/ is served from: `/` at app.snapkin.tools, `/caliper-companion/`
// on a GitHub project-site path. The rest of the build is relative too: the
// manifest's start_url and scope (`./`), the SW registration in Index.res
// (`./sw.js`), and sw.js itself, which takes its base from its own URL.
//
// VITE_BASE is ignored on purpose. .github/workflows/pages.yml still sets
// VITE_BASE=/<repo>/ on every deploy, and agent tokens cannot edit workflow
// files. When Pages moved the app to the root of app.snapkin.tools, that value
// pointed index.html at /caliper-companion/assets/, which is a 404, and the app
// was a blank page (LOGBOOK 2026-10-01). A relative base cannot go stale that
// way, so this file never reads VITE_BASE.
const base = './'
console.log(`[caliper-companion] base=${base} sha=${sha}`)

export default defineConfig({
  base,
  server: {
    port: 3000,
    strictPort: true,
    // `tailscale serve 3000` proxies with the tailnet Host header
    // (mac-mini.<tailnet>.ts.net); Vite answers 403 to unknown hosts.
    // Dev server only — tailnet names, nothing public.
    allowedHosts: ['.ts.net'],
  },
  plugins: [
    {
      name: 'stamp-sw-cache-name',
      apply: 'build',
      async writeBundle() {
        const fs = await import('node:fs/promises')
        const path = await import('node:path')
        const swPath = path.resolve('dist/sw.js')
        const assetsDir = path.resolve('dist/assets')
        const assetFiles = await fs.readdir(assetsDir).catch(() => [])
        // Relative, like every other URL in dist/. sw.js resolves each entry
        // against the folder it is served from (its runtime BASE).
        const precacheUrls = assetFiles.map(f => `assets/${f}`)
        const src = await fs.readFile(swPath, 'utf8')
        const stamped = src
          .replace("'__CACHE_VERSION__'", JSON.stringify(`caliper-companion-${sha}`))
          .replace("'__PRECACHE_URLS__'", JSON.stringify(precacheUrls))
        await fs.writeFile(swPath, stamped)
      },
    },
  ],
  resolve: {
    alias: {
      // PouchDB's package entry does not resolve cleanly under Vite's ESM
      // pipeline; ternpike pins the browser bundle the same way.
      pouchdb: path.resolve('./node_modules/pouchdb/dist/pouchdb.js'),
    },
  },
  define: {
    __BUILD_SHA__: JSON.stringify(commitSha),
    __APP_VERSION__: JSON.stringify(process.env.npm_package_version || '0.1.0'),
  },
  build: {
    outDir: 'dist',
    rollupOptions: {
      output: {
        entryFileNames: `assets/[name].${sha}.js`,
        chunkFileNames: `assets/[name].${sha}.js`,
        assetFileNames: `assets/[name].${sha}.[ext]`,
      },
    },
  },
})
