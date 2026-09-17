// export.spec.js — SPEC §10 golden path + M5 bullet 3 (kind-conflict
// blocks export). Chromium only: `navigator.share` doesn't exist there
// (SPEC/M5: "chromium has no navigator.share"), so every export in this
// file takes the download-anchor fallback (Bundle.deliver / Share.res) and
// is observed via Playwright's `download` event, never the share sheet.
//
// ** Status as written (see the M5 agent's report): the Parts list,
// Capture and Annotate pages (src/app/pages/PartsList.res, Capture.res,
// Annotate.res) are still SPEC-M6 stubs from a different track — none of
// them render the testids this spec drives (`new-part`, `part-name`,
// `capture-file-<kind>`, `annotate-canvas`, `reading`, `name`, `kind-*`,
// …). This spec is written against docs/testids.md and the M5 brief's
// literal golden-path steps so it's ready the moment those pages land; it
// cannot pass yet, and running it today fails immediately in
// `createPart()` waiting on `new-part`. Two things here are best-effort
// guesses at a still-unwritten contract, flagged so whoever lands the
// Annotate/Parts pages can reconcile them:
//   1. `clickNormalizedPoint` assumes `annotate-canvas`'s `data-transform`
//      attribute is `"scale,tx,ty"` describing an affine map from the
//      untransformed canvas-local pixel space (normalized point × the
//      canvas's CSS size) to the currently visible (zoomed/panned)
//      canvas-local pixel space — i.e. `screenX = box.x + tx + nx *
//      box.width * scale`. `docs/testids.md` doesn't spell out the
//      attribute's semantics (only that the canvas exists), so this is a
//      reading of the M5 brief's own words, not a verified contract.
//   2. `createPart` assumes part creation navigates to `#/parts/:id`
//      (this app's "cross-page navigation is a Route.push cmd" pattern,
//      CLAUDE.md) rather than staying on the list.
import {test, expect} from '@playwright/test'
import {unzipSync} from 'fflate'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const FIXTURE_TOP = 'fixtures/hinge_pin/top.jpg'
const GOLDEN_PATH = 'fixtures/hinge_pin/features.json'

const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'export-e2e-'))

// -- helpers ----------------------------------------------------------------

async function createPart(page, name) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  // See header comment (1): assumes create navigates to the new part page.
  await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
  const match = page.url().match(/#\/parts\/([^/?#]+)/)
  if (!match) {
    throw new Error(`createPart: could not read partId from URL ${page.url()}`)
  }
  return match[1]
}

async function captureTopFace(page, partId) {
  await page.goto(`/#/parts/${partId}/capture`)
  await page.setInputFiles('[data-testid=capture-file-top]', FIXTURE_TOP)
  // Assumed: capturing a face navigates straight to its annotate page.
  await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+\/?$/, {timeout: 10_000})
}

// See header comment (2) — best-effort pending the real Annotate contract.
async function clickNormalizedPoint(page, nx, ny) {
  const canvas = page.getByTestId('annotate-canvas')
  const box = await canvas.boundingBox()
  if (!box) throw new Error('annotate-canvas has no bounding box (not visible?)')
  // data-transform maps IMAGE pixels to canvas CSS pixels (screen = img * scale + t);
  // data-image-size is the oriented bitmap size, so a normalized point is first
  // scaled to image pixels. Same mapping as annotate.spec.js.
  const raw = await canvas.getAttribute('data-transform')
  const [scale, tx, ty] = (raw ?? '1,0,0').split(',').map(Number)
  const [imgW, imgH] = ((await canvas.getAttribute('data-image-size')) ?? '1x1').split('x').map(Number)
  const x = box.x + tx + nx * imgW * scale
  const y = box.y + ty + ny * imgH * scale
  await page.mouse.click(x, y)
}

// Two taps (p1, p2), then reading + Enter + name + Enter (SPEC M4: "Enter
// in the reading field moves focus to the name field; Enter in the name
// field saves"). `kindTestId` is clicked before the reading is typed, when
// the dimension isn't the segmented control's default (length).
async function addDimension(page, {p1, p2, reading, name, kindTestId}) {
  await clickNormalizedPoint(page, p1[0], p1[1])
  await clickNormalizedPoint(page, p2[0], p2[1])
  if (kindTestId) {
    await page.getByTestId(kindTestId).click()
  }
  await page.getByTestId('reading').fill(reading)
  await page.getByTestId('reading').press('Enter')
  await page.getByTestId('name').fill(name)
  await page.getByTestId('name').press('Enter')
}

async function exportAndUnzip(page, dir, label) {
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByTestId('export').click(),
  ])
  const savedPath = path.join(dir, `${label}.ccpart.zip`)
  await download.saveAs(savedPath)
  const bytes = fs.readFileSync(savedPath)
  return {entries: unzipSync(bytes), bytes}
}

// Index of the single line that differs between two texts, or -1 if none /
// more than one differs (mirrors core/tests/FeaturesDocumentTest.res's own
// "re-export differs only on exportedAt" check, at the app level).
function onlyDifferingLineIndex(a, b) {
  const linesA = a.split('\n')
  const linesB = b.split('\n')
  if (linesA.length !== linesB.length) return -2
  const diffs = []
  linesA.forEach((line, i) => {
    if (line !== linesB[i]) diffs.push(i)
  })
  return diffs.length === 1 ? diffs[0] : -1
}

test.describe('export (M5)', () => {
  test('golden path: capture, annotate, export, re-export (SPEC §10)', async ({page, browserName}) => {
    test.skip(browserName !== 'chromium', 'this suite is written for chromium only — see e2e/README.md')

    const dir = tmpDir()
    const partId = await createPart(page, 'Norcold freezer hinge pin')
    await captureTopFace(page, partId)

    const overallL = {p1: [0.17, 0.45], p2: [0.81, 0.45]}
    const pinDia = {p1: [0.3, 0.35], p2: [0.3, 0.55]}
    const headH = {p1: [0.5, 0.35], p2: [0.5, 0.55]}

    await addDimension(page, {...overallL, reading: '42.18', name: 'overall_l'})
    await addDimension(page, {
      ...pinDia,
      reading: '6.51',
      name: 'pin_dia',
      kindTestId: 'kind-diameter',
    })
    await addDimension(page, {...headH, reading: '4.2', name: 'head_h'})

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('export')).toBeVisible()

    const first = await exportAndUnzip(page, dir, 'first')

    expect(Object.keys(first.entries).sort()).toEqual(
      ['features.json', 'faces/top.jpg', 'faces/top_dimensioned.png'].sort(),
    )

    const featuresText = Buffer.from(first.entries['features.json']).toString('utf8')
    const doc = JSON.parse(featuresText)

    expect(doc.schema).toBe('caliper-companion/features/1')
    expect(doc.app.name).toBe('Caliper Companion')
    expect(doc.part.slug).toBe('norcold_freezer_hinge_pin')

    expect(doc.faces).toHaveLength(1)
    expect(doc.faces[0].kind).toBe('top')
    expect(doc.faces[0].pixelWidth).toBe(1600)
    expect(doc.faces[0].pixelHeight).toBe(1200)
    expect(doc.faces[0].renderScale).toBe(1)

    const names = doc.features.map(f => f.name)
    expect(names).toEqual([...names].sort())
    expect(names).toEqual(['head_h', 'overall_l', 'pin_dia'])
    doc.features.forEach(f => expect(f.flagged).toBe(false))

    const byName = Object.fromEntries(doc.features.map(f => [f.name, f]))
    expect(byName.overall_l.value).toBe(42.18)
    expect(byName.pin_dia.value).toBe(6.51)
    expect(byName.head_h.value).toBe(4.2)

    const expectClose = (actual, expected) => expect(Math.abs(actual - expected)).toBeLessThanOrEqual(0.01)
    const assertMeasurement = (feature, expectedP1, expectedP2) => {
      const m = feature.measurements[0]
      expectClose(m.p1[0], expectedP1[0])
      expectClose(m.p1[1], expectedP1[1])
      expectClose(m.p2[0], expectedP2[0])
      expectClose(m.p2[1], expectedP2[1])
    }
    assertMeasurement(byName.overall_l, overallL.p1, overallL.p2)
    assertMeasurement(byName.pin_dia, pinDia.p1, pinDia.p2)
    assertMeasurement(byName.head_h, headH.p1, headH.p2)

    expect(Number.isInteger(doc.telemetry.handsOnSeconds)).toBe(true)
    expect(doc.telemetry.handsOnSeconds).toBeGreaterThanOrEqual(0)

    // PNG IHDR: 8-byte signature + 4-byte length + 4-byte "IHDR" = 16, then
    // width (4 bytes) then height (4 bytes), big-endian.
    const png = Buffer.from(first.entries['faces/top_dimensioned.png'])
    const ihdrWidth = png.readUInt32BE(16)
    const ihdrHeight = png.readUInt32BE(20)
    expect(ihdrWidth).toBe(1600)
    expect(ihdrHeight).toBe(1200)
    expect(png.byteLength).toBeGreaterThan(20 * 1024)

    const golden = JSON.parse(fs.readFileSync(GOLDEN_PATH, 'utf8'))
    expect(Object.keys(doc)).toEqual(Object.keys(golden))

    const second = await exportAndUnzip(page, dir, 'second')
    const secondText = Buffer.from(second.entries['features.json']).toString('utf8')
    const diffLine = onlyDifferingLineIndex(featuresText, secondText)
    expect(diffLine).toBeGreaterThanOrEqual(0)
    expect(featuresText.split('\n')[diffLine]).toContain('"exportedAt"')
  })

  test('kind conflict blocks export and names the feature (SPEC M5 bullet 3)', async ({
    page,
    browserName,
  }) => {
    test.skip(browserName !== 'chromium', 'this suite is written for chromium only — see e2e/README.md')

    const partId = await createPart(page, 'Conflict test part')
    await captureTopFace(page, partId)

    await addDimension(page, {
      p1: [0.2, 0.3],
      p2: [0.4, 0.3],
      reading: '1.8',
      name: 'wall',
      kindTestId: 'kind-length',
    })
    await addDimension(page, {
      p1: [0.2, 0.6],
      p2: [0.4, 0.6],
      reading: '2.0',
      name: 'wall',
      kindTestId: 'kind-depth',
    })

    await page.goto(`/#/parts/${partId}`)

    let downloadFired = false
    page.once('download', () => {
      downloadFired = true
    })

    await page.getByTestId('export').click()
    await expect(page.getByTestId('export-error')).toBeVisible()
    await expect(page.getByTestId('export-error')).toContainText('wall')

    await page.waitForTimeout(2_000)
    expect(downloadFired).toBe(false)
  })
})
