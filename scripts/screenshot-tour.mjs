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

// TOUR_VIEWPORT=1440x900 TOUR_DSF=1 shoots the same tour at another size
// (SPEC §8a A17); the default stays the SPEC's phone viewport.
const viewport = (() => {
  const m = /^(\d+)x(\d+)$/.exec(process.env.TOUR_VIEWPORT || '')
  return m ? { width: Number(m[1]), height: Number(m[2]) } : { width: 390, height: 844 }
})()
// TOUR_ONLY=12,08,04 (A17): write only the shots whose name starts with one
// of these ids, as `${W}x${H}-<name>.png`. The whole tour still runs —
// later steps depend on earlier seeding — and every `shot()` still settles
// the page, so the steps after a skipped shot see the same timing.
const only = (process.env.TOUR_ONLY || '').split(',').map((s) => s.trim()).filter(Boolean)
const wanted = (name) => only.length === 0 || only.some((id) => name.startsWith(id))
const fileFor = (name) => (only.length === 0 ? `${name}.png` : `${viewport.width}x${viewport.height}-${name}.png`)

const browser = await chromium.launch()
const context = await browser.newContext({
  viewport,
  deviceScaleFactor: Number(process.env.TOUR_DSF || 2),
  isMobile: true,
  hasTouch: true,
})
const page = await context.newPage()
const shot = async (name) => {
  await page.waitForLoadState('networkidle')
  // SPEC §8a A16: route changes slide (350 ms) and take-overs rise (280 ms)
  // in this real-Chromium context — settle here, in the tour, never in the
  // app: wait until no view transition is in flight (`data-nav` is cleared
  // on `finished`) and no CSS animation or transition is still running.
  // Time-based ones only: the nav bar's scroll-driven glass fade
  // (global.css §2, `cc-bar-glass`) sits on a ScrollTimeline and reports
  // `running` for as long as the page exists.
  await page.waitForFunction(
    () =>
      !document.documentElement.hasAttribute('data-nav') &&
      document
        .getAnimations()
        .every((a) => !(a.timeline instanceof DocumentTimeline) || a.playState !== 'running'),
  )
  await page.waitForTimeout(150)
  if (!wanted(name)) return
  const p = path.join(outDir, fileFor(name))
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
// The zip lands beside the phone shots (the PR's export sample); a filtered
// wide run writes only its PNGs.
if (only.length === 0) await d.saveAs(path.join(outDir, d.suggestedFilename()))
await shot('11-part-exported')
await page.goto(`${baseURL}/#/`)

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

// SPEC §8a A12b: finish that part in Miata / Interior, add a second one
// there and an empty Archive (made in the picker, then Cancelled).
await byId('folder-new-cancel').click()
await byId('folder-picker-done').click()
await byId('part-create').click()
await page.waitForURL(/#\/parts\/[^/]+$/)
await page.goto(`${baseURL}/#/`)
await byId('new-part').click()
await byId('part-name').fill('Door card clip')
await byId('part-folder-row').click()
await page.locator('[data-testid="folder-option"][data-path="Miata/Interior"]').click()
await byId('folder-picker-done').click()
await byId('part-create').click()
await page.waitForURL(/#\/parts\/[^/]+$/)
await page.goto(`${baseURL}/#/`)
await byId('new-part').click()
await byId('part-folder-row').click()
await byId('folder-new').click()
await byId('folder-new-name').fill('Archive')
await byId('folder-new-create').click()
await byId('folder-picker-cancel').click()
await page.getByRole('button', { name: 'Cancel' }).click()

// SPEC §8a A13: the list is a folder browser. The root (Norcold, plus the
// folder rows Archive and Miata); Miata / Interior as a pushed screen; Edit
// mode there with both rows checked — the bottom toolbar reads Move 2 /
// Delete 2; the Interior row in inline rename from inside Miata; and a
// search from the root, whose results are the flat full-path sections.
await page.goto(`${baseURL}/#/`)
await expectVisible(page.locator('[data-testid="folder-row"][data-path="Miata"]'))
await shot('12-parts-list')
await page.goto(`${baseURL}/#/f/Miata/Interior`)
await expectVisible(byId('part-row').first())
await shot('16-parts-folder')
await byId('parts-edit').click()
await byId('part-select').nth(0).check()
await byId('part-select').nth(1).check()
await page.evaluate(() => document.activeElement?.blur())
await shot('14-parts-edit-toolbar')
await byId('parts-edit').click()
await page.goto(`${baseURL}/#/f/Miata`)
await expectVisible(page.locator('[data-testid="folder-row"][data-path="Miata/Interior"]'))
await byId('parts-edit').click()
await page.locator('[data-testid="folder-rename"][data-path="Miata/Interior"]').click()
await expectVisible(byId('folder-rename-input'))
await shot('15-folder-rename')
await page.goto(`${baseURL}/#/`)
// Wait for the root to be mounted before typing (the same wait as `12`):
// `hashchange` lands asynchronously and, since A16, inside a view
// transition, so a `fill` issued straight after `goto` runs first and
// `PartsList.FolderChanged("")` then clears the query — reliably at
// 1440 × 900, where the transition's snapshot is bigger (A17-i found it).
await expectVisible(page.locator('[data-testid="folder-row"][data-path="Miata"]'))
await byId('parts-search').fill('clip')
await expectVisible(byId('parts-section-header'))
await shot('17-parts-search')
await browser.close()
