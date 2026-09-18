// capture.spec.js — SPEC §8 M3 acceptance: the face picker, the
// camera/library file-input flow, EXIF orientation (SPEC §5's most common
// bug in this class of app), and the recapture-confirmation dialog.
//
// Written against docs/testids.md's "Parts list" / "Part" / "Capture"
// contracts. Those first two sections are owned by other in-flight agents
// (M2 UI) — at the time this spec was written, `PartsList.res`/`Part.res`
// are still the M6 stubs (no `new-part` form, no `face-<kind>` tile), so
// every test here is expected to fail at the `createPart` helper until
// that work lands. See the M3 agent's report / LOGBOOK.md for what was
// verified another way in the meantime (an ad-hoc script driving
// `Store.createPart` directly against a running `vite` dev server).
import {test, expect} from '@playwright/test'
import {unzipSync} from 'fflate'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

// Fills the Parts-list create form and opens the resulting part, per
// docs/testids.md's "Parts list" contract. `new-part` opens the form,
// `part-create` submits it, and the new `part-row` is clicked to
// navigate to the Part screen — this spec doesn't assume the create
// action itself navigates there, since that's not documented.
const createPart = async (page, name) => {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  await expect(page).toHaveURL(/#\/parts\/[^/]+$/)
  return page.url().split('/parts/')[1].split(/[/?#]/)[0]
}

const goToCapture = async page => {
  await page.getByTestId('capture-face').click()
  await expect(page).toHaveURL(/#\/parts\/[^/]+\/capture$/)
}

// The oriented pixel size, read off the Part page's `face-<kind>` tile —
// SPEC M3 bullet 2 asks for it "in the capture row text or a `data-size`
// attribute on the face tile"; the Capture page (this agent's own file)
// renders it in its own row text (see Capture.res's `sizeText`), but the
// assertion in this test happens back on the *Part* page's tile per the
// task brief, whose exact markup belongs to the Part page's own agent —
// so this reads either a `data-size` attribute or the tile's plain text.
const tileSize = async (page, kind) => {
  const tile = page.getByTestId(`face-${kind}`)
  await expect(tile).toBeVisible()
  const attr = await tile.getAttribute('data-size')
  return attr ?? (await tile.innerText())
}

const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'capture-e2e-'))

// A synthetic "photo": `width`x`height` JPEG built on an in-page <canvas>
// (a flat background plus a dark circle, so it isn't a degenerate
// single-colour image) and handed back as a Buffer for `setInputFiles`.
async function makeSyntheticJpegBuffer(page, {width, height}) {
  const base64 = await page.evaluate(async ({width, height}) => {
    const canvas = document.createElement('canvas')
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext('2d')
    ctx.fillStyle = '#8899aa'
    ctx.fillRect(0, 0, width, height)
    ctx.fillStyle = '#111318'
    ctx.beginPath()
    ctx.arc(width * 0.3, height * 0.45, Math.min(width, height) * 0.12, 0, Math.PI * 2)
    ctx.fill()
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.9))
    const buf = await blob.arrayBuffer()
    const bytes = new Uint8Array(buf)
    let binary = ''
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
    return btoa(binary)
  }, {width, height})
  return Buffer.from(base64, 'base64')
}

// Exports the current part (chromium's download-anchor fallback — see
// export.spec.js's own header comment) and unzips the result, purely to
// read back `faces/<kind>.jpg`'s byte length: SPEC §8a A4's "the original
// attachment's bytes, verbatim" (Bundle.res) means that entry *is* the
// stored attachment, so this is the one way to check its size without
// exposing anything new from Capture.res itself.
async function exportAndUnzip(page, dir, label) {
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByTestId('export').click(),
  ])
  const savedPath = path.join(dir, `${label}.ccpart.zip`)
  await download.saveAs(savedPath)
  return unzipSync(fs.readFileSync(savedPath))
}

test.describe('capture', () => {
  test('EXIF orientation: end.jpg (rotated) -> 1200x1600, top.jpg -> 1600x1200', async ({page}) => {
    const partId = await createPart(page, 'Hinge Pin EXIF')
    await goToCapture(page)

    await page.setInputFiles('[data-testid="capture-file-end"]', 'fixtures/hinge_pin/end.jpg')
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-end')).toBeVisible()
    expect(await tileSize(page, 'end')).toContain('1200')
    expect(await tileSize(page, 'end')).toContain('1600')

    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid="capture-file-top"]', 'fixtures/hinge_pin/top.jpg')
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-top')).toBeVisible()
    expect(await tileSize(page, 'top')).toContain('1600')
    expect(await tileSize(page, 'top')).toContain('1200')
  })

  test('recapture: capturing the same kind twice shows the dialog; confirm replaces it', async ({page}) => {
    const partId = await createPart(page, 'Hinge Pin Recapture')
    await goToCapture(page)

    await page.setInputFiles('[data-testid="capture-file-top"]', 'fixtures/hinge_pin/top.jpg')
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)

    await page.goto(`/#/parts/${partId}/capture`)
    await page.setInputFiles('[data-testid="capture-file-top"]', 'fixtures/hinge_pin/top.jpg')

    await expect(page.getByTestId('recapture-confirm')).toBeVisible()
    await expect(page.getByTestId('recapture-keep')).toBeVisible()
    await expect(page.getByTestId('recapture-cancel')).toBeVisible()

    await page.getByTestId('recapture-confirm').click()
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-top')).toHaveCount(1)
  })

  test('capture-note is visible', async ({page}) => {
    await createPart(page, 'Hinge Pin Note')
    await goToCapture(page)
    await expect(page.getByTestId('capture-note')).toBeVisible()
  })
})

// SPEC §8a A4: photos over `Capture.maxLongEdge` (2048px) are redrawn and
// re-encoded at capture time, not left at their original size.
test.describe('capture — SPEC §8a A4 (cap stored photos at 2048px)', () => {
  test('a 4000x3000 photo is stored capped at 2048x1536, smaller than the input', async ({
    page,
    browserName,
  }) => {
    test.skip(
      browserName !== 'chromium',
      'export-by-download assertion is chromium-only — see e2e/README.md',
    )

    const dir = tmpDir()
    const partId = await createPart(page, 'A4 Oversized Photo')
    await goToCapture(page)

    const inputBuffer = await makeSyntheticJpegBuffer(page, {width: 4000, height: 3000})
    await page.setInputFiles('[data-testid="capture-file-top"]', {
      name: 'oversized.jpg',
      mimeType: 'image/jpeg',
      buffer: inputBuffer,
    })
    await expect(page).toHaveURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)

    // The part page's face tile reflects the *stored* size (SPEC §8a A4:
    // "the capture row / face tile size text reflects the stored size").
    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-top')).toBeVisible()
    const size = await tileSize(page, 'top')
    expect(size).toContain('2048')
    expect(size).toContain('1536')

    // And the stored attachment itself — not just its reported dimensions
    // — is smaller than the 4000x3000 input.
    const entries = await exportAndUnzip(page, dir, 'a4-oversized')
    expect(entries['faces/top.jpg'].byteLength).toBeLessThan(inputBuffer.byteLength)
  })
})
