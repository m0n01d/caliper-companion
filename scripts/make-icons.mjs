// scripts/make-icons.mjs — the app icon, from one hand-written SVG.
//
//   node scripts/make-icons.mjs
//
// Writes public/favicon.svg (rounded, for browser tabs) and full-bleed PNGs
// (iOS and the manifest mask the corners themselves): icon-192.png,
// icon-512.png, apple-touch-icon.png (180). Rendered with the bundled Chromium
// so there's no image dependency.
//
// The mark is Snapkin's napkin: an orange napkin tilted −6° with a crease and
// a lifted flap, a live-blue lens cut into its face, and a ⌀ dimension drawn
// across the lens in ground — filled arrowheads on the rim, witness ticks —
// the drafting idiom, not the UI "expand" glyph. Geometry and the reasoning
// behind every number: docs/design/branding-snapkin.md §2 / §2a / §2b
// (direction A, variant 5, treatment b). Colours are DESIGN.md §2 tokens
// (Dark Sky); the two accents carry the app's own rule — accent = tappable
// (the napkin), live = verified (the lens).
import { chromium } from 'playwright'
import fs from 'node:fs'

const GROUND = '#15181D', ACCENT = '#FF7F2A', LIVE = '#5AC1F2'
const CREASE = '#FF8E45', FLAP = '#FFC59A'

// `rounded` only for the SVG favicon; PNGs stay square so platform masks apply.
// Everything sits inside 250–774 of the 1024 box: the 80 % safe area iOS's
// squircle mask and Android's maskable icons both leave alone.
const svg = (rounded) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" ${rounded ? 'rx="224"' : ''} fill="${GROUND}"/>
  <g transform="rotate(-6 512 512)">
    <path d="M250 306Q250 250 306 250L626 250L774 398L774 718Q774 774 718 774L386 774Q250 774 250 638Z" fill="${ACCENT}"/>
    <path d="M250 306Q250 250 306 250L626 250L250 626Z" fill="${CREASE}"/>
    <path d="M626 250L626 398L774 398Z" fill="${FLAP}"/>
    <circle cx="512" cy="530" r="178" fill="${LIVE}"/>
    <g transform="translate(512 530)" fill="${GROUND}" stroke="${GROUND}" stroke-linecap="round" stroke-linejoin="round">
      <path d="M-122 0L122 0" fill="none" stroke-width="34"/>
      <path d="M-174 0L-110 -28L-110 28Z" stroke-width="10"/>
      <path d="M174 0L110 -28L110 28Z" stroke-width="10"/>
      <path d="M-178 -46V46M178 -46V46" fill="none" stroke-width="30"/>
    </g>
  </g>
</svg>
`

fs.writeFileSync('public/favicon.svg', svg(true))
console.log('wrote public/favicon.svg')

const preinstalled = '/opt/pw-browsers/chromium'
const executablePath = process.env.PW_CHROMIUM || (fs.existsSync(preinstalled) ? preinstalled : undefined)
const browser = await chromium.launch(executablePath ? { executablePath } : {})
const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 })

// Render at each size from the vector (crisper than resampling one PNG).
const outputs = [['public/icon-512.png', 512], ['public/icon-192.png', 192], ['public/apple-touch-icon.png', 180]]
for (const [file, size] of outputs) {
  await page.setViewportSize({ width: size, height: size })
  await page.setContent(`<html><body style="margin:0;background:${GROUND}"><img src="data:image/svg+xml;utf8,${encodeURIComponent(svg(false))}" width="${size}" height="${size}" style="display:block"></body></html>`)
  await page.locator('img').screenshot({ path: file, type: 'png' })
  console.log('wrote', file)
}
await browser.close()
