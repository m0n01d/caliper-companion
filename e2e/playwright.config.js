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

// E2E_PORT lets parallel runs (agents, CI shards) avoid sharing :3000 — a
// squatter on the port makes reuseExistingServer test the wrong build.
const port = Number(process.env.E2E_PORT || 3000)

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
    command: `npx vite preview --port ${port} --strictPort`,
    cwd: repoRoot,
    url: `http://localhost:${port}`,
    reuseExistingServer: true,
  },
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
    // SPEC §8a A16: every route change is a View Transitions push / pop /
    // fade (350 / 200 ms). `reduce` emulates the media feature only — the
    // API still runs, but global.css §15's `!important` rule makes it a cut
    // (≈ 2 frames), the CSS rises / press scales drop to 0 ms (§12), and
    // Annotate's `frames` single-ticks the A5/A6 tweens. No existing
    // assertion observes any of that (every post-navigation read is
    // `page.url()`, a URL wait, a retrying `expect` or an auto-waiting
    // locator). motion.spec.js opts back into `no-preference` where it
    // needs the real animations. Note the nesting: `reducedMotion` is a
    // BrowserContext option but not a first-class test option (only
    // `colorScheme` is) — set directly under `use` it is silently ignored,
    // so it goes through `contextOptions`.
    contextOptions: {reducedMotion: 'reduce'},
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
