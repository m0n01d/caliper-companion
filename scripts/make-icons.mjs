// scripts/make-icons.mjs — the app icon, from one hand-written SVG.
//
//   node scripts/make-icons.mjs
//
// Writes public/favicon.svg (rounded, for browser tabs) and full-bleed PNGs
// (iOS and the manifest mask the corners themselves): icon-192.png,
// icon-512.png, apple-touch-icon.png (180). Rendered with the bundled Chromium
// so there's no image dependency.
//
// The mark is m2, "the lens alone" (SPEC §8a A14b; docs/design/
// branding-snapkin.md §7 "Icons" — m2 over m1's busy napkin+lens+⌀, m3's
// bare-dimension "expand" reading and m4's napkin silhouette): a closed
// ring with a horizontal ⌀ dimension drawn across it in the same ink,
// filled arrowheads at the rim, no ticks — the drafting idiom, not a UI
// "expand" glyph, and one colour at one weight so it reads at a 16 px
// clear tile. Numbers are `docs/design/a14-glass-review.md` S1 (the
// board's `brand-mono.html:108-110` re-weighted for a system-glyph
// stroke, not the earlier draft's, which drew a θ at favicon size). One
// ink `#F2F2F0` on `#0E0F11` (DESIGN.md §2).
import { chromium } from 'playwright'
import fs from 'node:fs'

const GROUND = '#0E0F11', INK = '#F2F2F0'

// Ring: r 300 centred (512, 512), stroke 64 (outer r 332, 180–844; inner r
// 268, 244–780). ⌀ line: x 340–684 at y 512, stroke 64 (the same weight as
// the ring — "one ink, one weight"), butt caps: each end sits inside an
// arrowhead, where the head is already wider than the line (±37 px at
// x 340), so the line and the heads read as one continuous shape. A round
// cap would poke past the head's slope (only ±27 px tall at x 316) and draw
// a notch — the first cut of this icon did exactly that.
// Arrowheads: filled, 112 (tip-to-base) × 96 (base width), tips at x 252 /
// 772 (8 px inside the inner ring), bases at x 364 / 660.
//
// `rounded` only for the SVG favicon; PNGs stay square so platform masks
// apply. Safe zone: the ring's outer edge (r 332) sits 78 px inside
// Android's maskable circle, ⌀ 80 % (r 410; 102–922 on the axes) — the
// real constraint; iOS only clips corners. (An earlier draft's "205–819,
// 80 %" was the 60 % box, and this file's own comment once said
// "250–774 … 80 %", which is 51 % — both wrong; fixed here.)
const svg = (rounded) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" ${rounded ? 'rx="224"' : ''} fill="${GROUND}"/>
  <circle cx="512" cy="512" r="300" fill="none" stroke="${INK}" stroke-width="64"/>
  <path d="M340 512L684 512" fill="none" stroke="${INK}" stroke-width="64"/>
  <path d="M252 512L364 464L364 560Z" fill="${INK}"/>
  <path d="M772 512L660 464L660 560Z" fill="${INK}"/>
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
