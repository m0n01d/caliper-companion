// scripts/make-icons.mjs — the app icon, from one hand-written SVG.
//
//   node scripts/make-icons.mjs
//
// Writes public/favicon.svg (rounded, for browser tabs) and full-bleed PNGs
// (iOS and the manifest mask the corners themselves): icon-192.png,
// icon-512.png, apple-touch-icon.png (180). Rendered with the bundled Chromium
// so there's no image dependency. Glyph = the app's own dimension mark: two
// caliper jaws joined by a dimension line in amber (tappable), with the teal
// "reading" bar above (verified). Colours are DESIGN.md §2 tokens.
import { chromium } from 'playwright'
import fs from 'node:fs'

const GROUND = '#17181A', AMBER = '#F2A33A', TEAL = '#4FD1B1'

// `rounded` only for the SVG favicon; PNGs stay square so platform masks apply.
const svg = (rounded) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <rect width="512" height="512" ${rounded ? 'rx="112"' : ''} fill="${GROUND}"/>
  <g fill="none" stroke="${AMBER}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round">
    <line x1="120" y1="292" x2="392" y2="292"/>
    <line x1="120" y1="212" x2="120" y2="372"/>
    <line x1="392" y1="212" x2="392" y2="372"/>
    <path d="M172 250 L120 292 L172 334"/>
    <path d="M340 250 L392 292 L340 334"/>
  </g>
  <rect x="196" y="126" width="120" height="30" rx="15" fill="${TEAL}"/>
</svg>
`

fs.writeFileSync('public/favicon.svg', svg(true))

const preinstalled = '/opt/pw-browsers/chromium'
const executablePath = process.env.PW_CHROMIUM || (fs.existsSync(preinstalled) ? preinstalled : undefined)
const browser = await chromium.launch(executablePath ? { executablePath } : {})
const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 })
await page.setContent(`<html><body style="margin:0;background:${GROUND}">${svg(false)}</body></html>`)
const full = await page.locator('svg').screenshot({ type: 'png' })

// Downscale by re-rendering at each size (crisper than resampling one PNG).
const outputs = [['public/icon-512.png', 512], ['public/icon-192.png', 192], ['public/apple-touch-icon.png', 180]]
for (const [file, size] of outputs) {
  await page.setViewportSize({ width: size, height: size })
  await page.setContent(`<html><body style="margin:0;background:${GROUND}"><img src="data:image/svg+xml;utf8,${encodeURIComponent(svg(false))}" width="${size}" height="${size}" style="display:block"></body></html>`)
  await page.locator('img').screenshot({ path: file, type: 'png' })
  console.log('wrote', file)
}
void full
await browser.close()
