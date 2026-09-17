// e2e/playwright.config.js — Playwright config for the app shell (SPEC §8
// M6, §10). Tests run against the *built* `dist/` (`npm run e2e` builds
// first) so the offline test exercises the real stamped service worker, not
// Vite's dev-server bypass.
import {defineConfig, devices} from '@playwright/test'
import {fileURLToPath} from 'node:url'

// Repo root — one level up from this file. `webServer.command` needs it
// explicitly: Playwright runs that command with this config file's own
// directory (e2e/) as its cwd, and `vite preview` resolves `dist/` (and
// `vite.config.js`) relative to *its* cwd, not the shell's. Without this,
// `vite preview` binds the port fine but serves 404s for everything from a
// nonexistent `e2e/dist/`, and the webServer health check times out waiting
// for a page it's never going to get.
const repoRoot = fileURLToPath(new URL('..', import.meta.url))

export default defineConfig({
  // Both relative to this config file's own directory (e2e/), not the cwd.
  testDir: 'specs',
  outputDir: '.results',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list']],
  timeout: 30_000,
  webServer: {
    command: 'npx vite preview --port 3000 --strictPort',
    cwd: repoRoot,
    url: 'http://localhost:3000',
    reuseExistingServer: true,
  },
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      // Safari's real engine — what iOS actually ships. See e2e/README.md
      // for whether it can launch in this environment.
      name: 'webkit',
      use: {
        ...devices['iPhone 13'],
        viewport: {width: 390, height: 844},
      },
    },
    {
      name: 'chromium',
      use: {
        browserName: 'chromium',
        viewport: {width: 390, height: 844},
        hasTouch: true,
        isMobile: true,
      },
    },
  ],
})
