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

export default defineConfig({
  base: '/',
  server: {
    port: 3000,
    strictPort: true,
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
        const precacheUrls = assetFiles.map(f => `/assets/${f}`)
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
