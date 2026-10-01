// scripts/pages-smoke.mjs — prove a deployed (or previewed) build works as a
// PWA at the path it is served from: the service worker registers with the
// right scope, takes control, and the app still launches with the network off.
// The build has a relative base (vite.config.js), so one dist/ must pass at
// the root and under a subfolder alike; VITE_BASE has no effect on it.
//
//   node scripts/pages-smoke.mjs [url]
//   node scripts/pages-smoke.mjs http://localhost:3000/                    # after npm run build && npx vite preview
//   node scripts/pages-smoke.mjs http://localhost:8000/caliper-companion/  # the same dist/ copied to <dir>/caliper-companion/, then python3 -m http.server 8000 -d <dir>
//   node scripts/pages-smoke.mjs https://app.snapkin.tools/
//
// Exits non-zero when the offline reload fails or a page error was logged.
import { chromium } from 'playwright'
import fs from 'node:fs'

const url = process.argv[2] || 'http://localhost:3000/'
const preinstalled = '/opt/pw-browsers/chromium'
const executablePath = process.env.PW_CHROMIUM || (fs.existsSync(preinstalled) ? preinstalled : undefined)
const browser = await chromium.launch(executablePath ? { executablePath } : {})
const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
const page = await context.newPage()
const errors = []
page.on('pageerror', e => errors.push(String(e)))
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()) })

await page.goto(url)
try {
  await page.getByTestId('new-part').waitFor({ timeout: 15000 })
} catch (e) {
  console.error(JSON.stringify({ url, stage: 'first-load', status: 'no app shell', errors: errors.slice(0, 5) }))
  await browser.close()
  process.exit(1)
}
await page.evaluate(() => navigator.serviceWorker.ready)
await page.reload() // first load is registered-but-not-controlling
await page.getByTestId('new-part').waitFor()
const controlled = await page.evaluate(() => !!navigator.serviceWorker.controller)
const scope = await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.scope)
await context.setOffline(true)
await page.reload()
let offlineOk = false
try { await page.getByTestId('new-part').waitFor({ timeout: 5000 }); offlineOk = true } catch {}
await browser.close()
console.log(JSON.stringify({ url, controlled, scope, offlineOk, errors: errors.slice(0, 3) }))
process.exit(controlled && offlineOk && errors.length === 0 ? 0 : 1)
