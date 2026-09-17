#!/usr/bin/env node
// scripts/screenshot.mjs — headless screenshot of one route, for later
// agents' and the PR's before/after shots (claude-conventions CLAUDE.md
// "PRs": screenshots are non-negotiable for any UI-touching PR).
//
// Usage:
//   node scripts/screenshot.mjs <hash> <outputPath> [baseURL]
//   node scripts/screenshot.mjs '#/settings' docs/screenshots/settings.png
//
// Assumes a server is already running at baseURL (default
// http://localhost:3000 — `npx vite preview --port 3000 --strictPort`
// against a built `dist/`, same as the e2e config, so the shot matches what
// e2e exercises).
import {chromium} from 'playwright'
import {mkdirSync} from 'node:fs'
import {dirname, resolve} from 'node:path'

const [, , hashArg, outArg, baseUrlArg] = process.argv

if (!hashArg || !outArg) {
  console.error('usage: node scripts/screenshot.mjs <hash> <outputPath> [baseURL]')
  process.exit(1)
}

const hash = hashArg.startsWith('#') ? hashArg : `#${hashArg}`
const baseURL = baseUrlArg || 'http://localhost:3000'
const outPath = resolve(outArg)

// Playwright browsers in this environment live outside the default cache
// dir (`$PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`, already set) — the
// explicit executablePath is a fallback for anywhere that isn't set.
const FALLBACK_EXECUTABLE = '/opt/pw-browsers/chromium'

const launch = async () => {
  try {
    return await chromium.launch()
  } catch {
    return await chromium.launch({executablePath: FALLBACK_EXECUTABLE})
  }
}

const browser = await launch()
try {
  const page = await browser.newPage({viewport: {width: 390, height: 844}})
  await page.goto(`${baseURL}/${hash}`)
  await page.waitForLoadState('networkidle')
  mkdirSync(dirname(outPath), {recursive: true})
  await page.screenshot({path: outPath, fullPage: true})
  console.log(outPath)
} finally {
  await browser.close()
}
