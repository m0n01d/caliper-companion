// Generates the hinge_pin fixture JPEGs with the bundled Chromium. Synthetic
// "photos": a flat background, a bar-shaped part, and a dark hole at a known
// normalized position so tests can assert tap → point conversions.
//
//   node fixtures/make-fixtures.mjs
//
// end.jpg is written LANDSCAPE (1600×1200) with EXIF Orientation = 6 (rotate
// 90° CW to display), so a correct `imageOrientation: "from-image"` decode
// yields a 1200×1600 PORTRAIT bitmap. See fixtures/README.md for the expected
// oriented coordinates.
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const out = path.join(here, 'hinge_pin')
fs.mkdirSync(out, { recursive: true })

const W = 1600, H = 1200
// Hole centre as a fraction of the STORED (pre-rotation) image.
export const HOLE = { x: 0.30, y: 0.45 }

// The sandbox preinstalls one Chromium at /opt/pw-browsers/chromium; fall back
// to it when the Playwright-pinned build isn't downloaded.
const preinstalled = '/opt/pw-browsers/chromium'
const executablePath = process.env.PW_CHROMIUM || (fs.existsSync(preinstalled) ? preinstalled : undefined)
const browser = await chromium.launch(executablePath ? { executablePath } : {})
const page = await browser.newPage()

async function render(label, color) {
  const dataUrl = await page.evaluate(([w, h, label, color, hole]) => {
    const c = document.createElement('canvas'); c.width = w; c.height = h
    const ctx = c.getContext('2d')
    ctx.fillStyle = '#d9d4c7'; ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = color
    ctx.fillRect(w * 0.17, h * 0.35, w * 0.64, h * 0.20)
    ctx.fillStyle = '#1b1b1b'
    ctx.beginPath(); ctx.arc(w * hole.x, h * hole.y, Math.min(w, h) * 0.05, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = '#111'; ctx.font = `${Math.round(h * 0.05)}px sans-serif`
    ctx.fillText(label, w * 0.04, h * 0.10)
    return c.toDataURL('image/jpeg', 0.85)
  }, [W, H, label, color, HOLE])
  return Buffer.from(dataUrl.split(',')[1], 'base64')
}

// Minimal APP1/EXIF segment carrying only Orientation (tag 0x0112) = 6.
function withOrientation6(jpeg) {
  if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new Error('not a JPEG')
  const app1 = Buffer.from([
    0xff, 0xe1, 0x00, 0x22,                 // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00,     // "Exif\0\0"
    0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF: little-endian, IFD0 at 8
    0x01, 0x00,                             // 1 entry
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, // Orientation SHORT 1 = 6
    0x00, 0x00, 0x00, 0x00,                 // next IFD: none
  ])
  return Buffer.concat([jpeg.subarray(0, 2), app1, jpeg.subarray(2)])
}

fs.writeFileSync(path.join(out, 'top.jpg'), await render('TOP', '#8a7a5a'))
fs.writeFileSync(path.join(out, 'side.jpg'), await render('SIDE', '#6b7c58'))
fs.writeFileSync(path.join(out, 'end.jpg'), withOrientation6(await render('END (EXIF 6)', '#b85c38')))
await browser.close()
console.log('wrote', fs.readdirSync(out).join(', '))
