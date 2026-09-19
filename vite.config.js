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

// Where the app is served from. '/' for local/dev and any root deploy; a
// GitHub Pages project site lives under '/<repo>/' (set VITE_BASE in CI).
// Everything that hard-codes a root path reads this: Vite's own asset URLs,
// the service worker's app shell + precache list (stamped below), and the
// SW registration in Index.res (via the __CC_BASE__ define).
const rawBase = process.env.VITE_BASE || '/'
const base = `/${rawBase.replace(/^\/+|\/+$/g, '')}/`.replace('//', '/')
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
        const precacheUrls = assetFiles.map(f => `${base}assets/${f}`)
        const src = await fs.readFile(swPath, 'utf8')
        const stamped = src
          .replace("'__CACHE_VERSION__'", JSON.stringify(`caliper-companion-${sha}`))
          .replace("'__PRECACHE_URLS__'", JSON.stringify(precacheUrls))
          .replace("'__BASE__'", JSON.stringify(base))
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
    __CC_BASE__: JSON.stringify(base),
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
