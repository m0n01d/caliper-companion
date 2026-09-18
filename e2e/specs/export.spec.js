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
import zlib from 'node:zlib'

const FIXTURE_TOP = 'fixtures/hinge_pin/top.jpg'
const GOLDEN_PATH = 'fixtures/hinge_pin/features.json'

const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'export-e2e-'))

// -- helpers ----------------------------------------------------------------

async function createPart(page, name, folder) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  if (folder !== undefined) {
    // SPEC §8a A12a: the Folder field is a picker now — walk the path's
    // segments, making each with New Folder (a new one nests under the
    // selection), then Done. Same walk as parts.spec.js's `pickFolder`.
    await page.getByTestId('part-folder-row').click()
    for (const segment of folder.split('/')) {
      await page.getByTestId('folder-new').click()
      await page.getByTestId('folder-new-name').fill(segment)
      await page.getByTestId('folder-new-create').click()
      await expect(page.getByTestId('folder-new-name')).toHaveCount(0)
    }
    await page.getByTestId('folder-picker-done').click()
  }
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
  // Wait for the previous save's store write to land before tapping again:
  // a tap that arrives while a save is in flight can be wiped when the save
  // completes and clears the entry (SPEC §8a A6 note in LOGBOOK).
  const before = Number((await page.getByTestId('dimension-count').textContent()) || '0')
  await clickNormalizedPoint(page, p1[0], p1[1])
  await clickNormalizedPoint(page, p2[0], p2[1])
  if (kindTestId) {
    await page.getByTestId(kindTestId).click()
  }
  await page.getByTestId('reading').fill(reading)
  await page.getByTestId('reading').press('Enter')
  await page.getByTestId('name').fill(name)
  await page.getByTestId('name').press('Enter')
  await expect(page.getByTestId('dimension-count')).toHaveText(String(before + 1))
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
      ['features.json', 'parameters.csv', 'faces/top.jpg', 'faces/top_dimensioned.png'].sort(),
    )

    const featuresText = Buffer.from(first.entries['features.json']).toString('utf8')
    const doc = JSON.parse(featuresText)

    expect(doc.schema).toBe('caliper-companion/features/1')
    expect(doc.app.name).toBe('Caliper Companion')
    expect(doc.part.slug).toBe('norcold_freezer_hinge_pin')
    // SPEC §8a A10: a root part exports `"path": ""`, the golden's own line.
    expect(doc.part.path).toBe('')

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

    // SPEC §8a A11: parameters.csv rides next to features.json — no
    // header, one line per feature in the same order, 4 comma-separated
    // fields, expression == "<value> <unit>".
    const csvText = Buffer.from(first.entries['parameters.csv']).toString('utf8')
    expect(csvText.endsWith('\n')).toBe(true)
    expect(csvText.endsWith('\n\n')).toBe(false)
    const csvLines = csvText.split('\n').filter(line => line !== '')
    expect(csvLines).toHaveLength(doc.features.length)
    expect(csvLines.map(line => line.split(',')[0])).toEqual(names)
    csvLines.forEach((line, i) => {
      const fields = line.split(',')
      expect(fields).toHaveLength(4)
      expect(fields[1]).toBe(doc.part.units)
      expect(fields[2]).toBe(`${doc.features[i].value} ${doc.part.units}`)
    })

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

  test('a part in a folder exports its path verbatim (SPEC §8a A10)', async ({page, browserName}) => {
    test.skip(browserName !== 'chromium', 'this suite is written for chromium only — see e2e/README.md')

    const dir = tmpDir()
    const partId = await createPart(page, 'Window switch bezel', 'Miata/Interior')
    await captureTopFace(page, partId)
    await addDimension(page, {p1: [0.2, 0.3], p2: [0.6, 0.3], reading: '12.4', name: 'overall_w'})

    await page.goto(`/#/parts/${partId}`)
    await expect(page.locator('.shell-subtitle')).toHaveText('Miata / Interior')
    const {entries} = await exportAndUnzip(page, dir, 'folder')
    const doc = JSON.parse(Buffer.from(entries['features.json']).toString('utf8'))
    expect(doc.part.path).toBe('Miata/Interior')
    // `path` sits right after `slug` (FeaturesDocument.encodePart key order).
    const keys = Object.keys(doc.part)
    expect(keys[keys.indexOf('slug') + 1]).toBe('path')
    // A11's parameters.csv carries no path — its header line is unchanged.
    const csv = Buffer.from(entries['parameters.csv']).toString('utf8')
    expect(csv.includes('Miata')).toBe(false)
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

// -- render legibility (SPEC §8a A3) ----------------------------------------
//
// A3's whole point: the pre-amendment navy overlay (#14213d) was unreadable
// on a dark photo. Proving it needs actual pixels, not just the pure
// geometry RenderTest.res already covers — so this builds two flat JPEGs
// in-page (an all-white one, an all-black one), runs them through the real
// capture -> annotate -> export pipeline, and decodes the resulting PNG
// itself (a small pure-JS PNG reader below, `zlib.inflateSync` doing the
// deflate half — no new npm package) to sample actual pixel values.

// A flat `color` JPEG, `width`x`height`, built on an in-page <canvas> and
// handed back as a Buffer — passed to `setInputFiles` as a synthetic
// "photo" (no fixture file needed for an all-white/all-black background).
async function makeFlatJpegBuffer(page, {width, height, color}) {
  const base64 = await page.evaluate(async ({width, height, color}) => {
    const canvas = document.createElement('canvas')
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext('2d')
    ctx.fillStyle = color
    ctx.fillRect(0, 0, width, height)
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.92))
    const buf = await blob.arrayBuffer()
    const bytes = new Uint8Array(buf)
    let binary = ''
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
    return btoa(binary)
  }, {width, height, color})
  return Buffer.from(base64, 'base64')
}

// A minimal PNG reader: signature + chunks -> IHDR (width/height/bitDepth/
// colorType) + concatenated IDAT -> `zlib.inflateSync` -> per-scanline
// unfilter (PNG spec's five filter types: None/Sub/Up/Average/Paeth).
// Handles what `OffscreenCanvas`/`<canvas>` `convertToBlob("image/png")`
// actually emits: 8-bit, non-interlaced, truecolor (RGB) or truecolor+alpha
// (RGBA) — the two colour types Render.res's export path can produce.
function decodePng(buffer) {
  let offset = 8 // past the 8-byte PNG signature
  let width = 0
  let height = 0
  let bitDepth = 0
  let colorType = 0
  const idatChunks = []
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset)
    const type = buffer.toString('ascii', offset + 4, offset + 8)
    const dataStart = offset + 8
    const data = buffer.subarray(dataStart, dataStart + length)
    if (type === 'IHDR') {
      width = data.readUInt32BE(0)
      height = data.readUInt32BE(4)
      bitDepth = data.readUInt8(8)
      colorType = data.readUInt8(9)
    } else if (type === 'IDAT') {
      idatChunks.push(data)
    } else if (type === 'IEND') {
      break
    }
    offset = dataStart + length + 4 // + 4-byte CRC
  }
  if (bitDepth !== 8) {
    throw new Error(`decodePng: unsupported bit depth ${bitDepth}`)
  }
  const channels = {0: 1, 2: 3, 4: 2, 6: 4}[colorType]
  if (!channels) {
    throw new Error(`decodePng: unsupported color type ${colorType}`)
  }

  const raw = zlib.inflateSync(Buffer.concat(idatChunks))
  const rowBytes = width * channels
  const pixels = Buffer.alloc(height * rowBytes)
  let rawOffset = 0
  let prevRowStart = -1
  for (let y = 0; y < height; y++) {
    const filterType = raw[rawOffset]
    rawOffset += 1
    const rowStart = y * rowBytes
    for (let x = 0; x < rowBytes; x++) {
      const filt = raw[rawOffset + x]
      const a = x >= channels ? pixels[rowStart + x - channels] : 0
      const b = prevRowStart >= 0 ? pixels[prevRowStart + x] : 0
      const c = prevRowStart >= 0 && x >= channels ? pixels[prevRowStart + x - channels] : 0
      let recon
      switch (filterType) {
        case 0:
          recon = filt
          break
        case 1:
          recon = filt + a
          break
        case 2:
          recon = filt + b
          break
        case 3:
          recon = filt + ((a + b) >> 1)
          break
        case 4: {
          const p = a + b - c
          const pa = Math.abs(p - a)
          const pb = Math.abs(p - b)
          const pc = Math.abs(p - c)
          const pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
          recon = filt + pr
          break
        }
        default:
          throw new Error(`decodePng: unsupported filter type ${filterType}`)
      }
      pixels[rowStart + x] = recon & 0xff
    }
    rawOffset += rowBytes
    prevRowStart = rowStart
  }
  return {width, height, channels, pixels}
}

const pixelAt = (png, x, y) => {
  const idx = (y * png.width + x) * png.channels
  return {r: png.pixels[idx], g: png.pixels[idx + 1], b: png.pixels[idx + 2]}
}

// Scans a vertical column at `xFrac`*width, `± spanPx` around `yFrac`*height
// (the dimension line's own y, for the horizontal line this suite always
// draws), and reports whether the ink line and its halo are legible there:
// not merely present anywhere in the column, but composited correctly —
// white → halo → ink → halo → white, top to bottom. `sawInk` is true only
// for an ink pixel that has a halo pixel at some smaller y *and* a halo
// pixel at some larger y in the same column (SPEC §8a A14b).
//
// Thresholds: the ink line is exactly `Overlay.ink` #F2F2F0 = (242,242,240)
// even after PNG's lossless re-encode, so `isInk` uses a tight window
// (every channel in [225, 250], max−min <= 12) rather than an unbounded
// "channel >= 200", which would pass the white photo itself
// (255,255,255) with no line drawn at all. The halo (`Overlay.halo`,
// cc-ground at 85 %) composited over a pure-white background works out to
// ≈(50,51,53) and over black to ≈(12,13,14) — both comfortably under a
// literal "<70" on every channel (kept from the pre-mono scheme; the
// code's 70, not 60, for a documented rounding margin), and nowhere near
// white or ink.
function sampleLegibility(png, {xFrac, yFrac, spanPx}) {
  const cx = Math.round(png.width * xFrac)
  const cy = Math.round(png.height * yFrac)
  const isHalo = ({r, g, b}) => r < 70 && g < 70 && b < 70
  const isInk = ({r, g, b}) =>
    [r, g, b].every(c => c >= 225 && c <= 250) && Math.max(r, g, b) - Math.min(r, g, b) <= 12

  const column = []
  for (let y = Math.max(0, cy - spanPx); y <= Math.min(png.height - 1, cy + spanPx); y++) {
    column.push(pixelAt(png, cx, y))
  }

  const sawHalo = column.some(isHalo)
  let haloAbove = false
  let sawInk = false
  for (let i = 0; i < column.length; i++) {
    const px = column[i]
    if (isInk(px) && haloAbove && column.slice(i + 1).some(isHalo)) sawInk = true
    if (isHalo(px)) haloAbove = true
  }

  return {sawInk, sawHalo}
}

test.describe('render legibility (SPEC §8a A3)', () => {
  for (const bg of [
    {name: 'white', color: '#ffffff'},
    {name: 'black', color: '#000000'},
  ]) {
    test(`ink line + halo are both visible on an all-${bg.name} photo`, async ({
      page,
      browserName,
    }) => {
      test.skip(browserName !== 'chromium', 'this suite is written for chromium only — see e2e/README.md')

      const dir = tmpDir()
      const partId = await createPart(page, `Legibility ${bg.name}`)
      const jpegBuffer = await makeFlatJpegBuffer(page, {width: 800, height: 600, color: bg.color})

      await page.goto(`/#/parts/${partId}/capture`)
      await page.setInputFiles('[data-testid=capture-file-top]', {
        name: `${bg.name}.jpg`,
        mimeType: 'image/jpeg',
        buffer: jpegBuffer,
      })
      await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+\/?$/, {timeout: 10_000})

      // A horizontal dimension roughly through the image's middle, so a
      // vertical sample column crosses the line/halo cleanly (SPEC §8a A3
      // bullet 1's arrowheads/handles sit only near the endpoints, and the
      // pill sits centred on the line — this samples a quarter of the way
      // along the line, clear of both).
      await addDimension(page, {
        p1: [0.2, 0.5],
        p2: [0.8, 0.5],
        reading: '10.00',
        name: 'd',
      })

      await page.goto(`/#/parts/${partId}`)
      const {entries} = await exportAndUnzip(page, dir, `legibility-${bg.name}`)
      const png = decodePng(Buffer.from(entries['faces/top_dimensioned.png']))

      const {sawInk, sawHalo} = sampleLegibility(png, {xFrac: 0.35, yFrac: 0.5, spanPx: 25})
      expect(sawInk).toBe(true)
      expect(sawHalo).toBe(true)
    })
  }
})
