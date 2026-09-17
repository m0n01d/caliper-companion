// scripts/screenshot-tour.mjs — drive the golden path and screenshot every
// screen for the PR (claude-conventions "PRs": screenshots are non-negotiable).
//
//   npm run build && npx vite preview --port 3000 --strictPort &
//   node scripts/screenshot-tour.mjs [outDir=docs/screenshots] [baseURL=http://localhost:3000]
//
// Seeds through the real UI (no direct DB writes) using the data-testid
// contract in docs/testids.md, at the SPEC's 390×844 portrait viewport.
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'

const outDir = process.argv[2] || 'docs/screenshots'
const baseURL = process.argv[3] || 'http://localhost:3000'
fs.mkdirSync(outDir, { recursive: true })

const browser = await chromium.launch()
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
})
const page = await context.newPage()
const shot = async (name) => {
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(150)
  const p = path.join(outDir, `${name}.png`)
  await page.screenshot({ path: p })
  console.log('wrote', p)
}
const byId = (id) => page.getByTestId(id)

await page.goto(`${baseURL}/#/`)
await shot('01-parts-empty')

await byId('new-part').click()
await byId('part-name').fill('Norcold freezer hinge pin')
await shot('02-parts-create')
await byId('part-create').click()
await page.waitForURL(/#\/parts\/[^/]+$/)
const partId = page.url().split('/parts/')[1].split(/[/?#]/)[0]
await shot('03-part-empty')

await page.goto(`${baseURL}/#/parts/${partId}/capture`)
await shot('04-capture')
for (const kind of ['top', 'side', 'end']) {
  await page.goto(`${baseURL}/#/parts/${partId}/capture`)
  await page.setInputFiles(`[data-testid="capture-file-${kind}"]`, `fixtures/hinge_pin/${kind}.jpg`)
  await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
}
// Now on the END face (EXIF-rotated → portrait).
const canvas = byId('annotate-canvas')
await expectVisible(canvas)
await shot('05-annotate-loaded')

async function expectVisible(loc) { await loc.waitFor({ state: 'visible' }) }
async function clickNorm(nx, ny) {
  const box = await canvas.boundingBox()
  const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
  const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
  await page.mouse.click(box.x + tx + nx * w * s, box.y + ty + ny * h * s)
}
async function addDim(p1, p2, reading, name, kindId) {
  await clickNorm(...p1)
  await clickNorm(...p2)
  if (kindId) await byId(kindId).click()
  await byId('reading').fill(reading)
  await byId('reading').press('Enter')
  await byId('name').fill(name)
  await byId('name').press('Enter')
  await page.waitForTimeout(150)
}
await clickNorm(0.55, 0.18)
await clickNorm(0.55, 0.42)
await byId('kind-diameter').click()
await byId('reading').fill('6.51')
await shot('06-annotate-pending')
await byId('reading').press('Enter')
await byId('name').fill('pin_dia')
await byId('name').press('Enter')
await page.waitForTimeout(150)
await addDim([0.2, 0.55], [0.85, 0.55], '42.18', 'overall_l', 'kind-length')
await shot('07-annotate-saved')

await page.goto(`${baseURL}/#/parts/${partId}`)
await expectVisible(byId('feature-row').first())
await shot('08-part-features')

await page.goto(`${baseURL}/#/settings`)
await shot('09-settings')
await page.goto(`${baseURL}/#/debug`)
await shot('10-debug')

// Export → download (no navigator.share in headless Chromium) → part page shows outcome.
await page.goto(`${baseURL}/#/parts/${partId}`)
await expectVisible(byId('export'))
const dl = page.waitForEvent('download')
await byId('export').click()
const d = await dl
await d.saveAs(path.join(outDir, d.suggestedFilename()))
await shot('11-part-exported')
await page.goto(`${baseURL}/#/`)
await shot('12-parts-list')

// SPEC §8a A12a: the folder picker from the create form — two nested
// folders made through New Folder (each nests under the selection), then
// the field opened once more so the shot shows it.
await byId('new-part').click()
await byId('part-name').fill('Window switch bezel')
await byId('part-folder-row').click()
for (const segment of ['Miata', 'Interior']) {
  await byId('folder-new').click()
  await byId('folder-new-name').fill(segment)
  await byId('folder-new-create').click()
  await expectVisible(byId('folder-new'))
}
await byId('folder-new').click()
await byId('folder-new-name').fill('Dashboard')
await shot('13-folder-picker')
await browser.close()
