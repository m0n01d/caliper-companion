// faces.spec.js — SPEC §8a A7 custom faces, end to end (the A7 Playwright
// bullet): add a custom `left_side` face on plane Side, capture `side.jpg`
// into it, dimension it, export → the zip holds `faces/left_side.jpg` and
// `faces/left_side_dimensioned.png`, `features.json` carries that face with
// `kind: "side"`, `label: "left_side"`; a duplicate label is rejected
// inline; default faces' paths are unchanged. Plus the rest of A7's
// acceptance list: recapture-by-face (same-kind faces coexist), chip
// removal while empty, delete from the Part page, and pre-A7 face docs
// (no `label`) reading back as their kind.
//
// Chromium only where an export is involved: `navigator.share` doesn't
// exist there, so export takes the download-anchor fallback (see
// export.spec.js's header). Testids per docs/testids.md.
import {test, expect} from '@playwright/test'
import {unzipSync} from 'fflate'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
const FIXTURE_TOP = 'fixtures/hinge_pin/top.jpg'
const FIXTURE_SIDE = 'fixtures/hinge_pin/side.jpg'
const ANNOTATE_URL = /#\/parts\/[^/]+\/faces\/[^/]+\/?$/

const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'faces-e2e-'))

// -- helpers (same shapes as export.spec.js) --------------------------------

async function createPart(page, name) {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+\/?$/, {timeout: 10_000})
  return page.url().match(/#\/parts\/([^/?#]+)/)[1]
}

async function captureInto(page, partId, label, fixture) {
  await page.goto(`/#/parts/${partId}/capture`)
  await page.setInputFiles(`[data-testid="capture-file-${label}"]`, fixture)
  await page.waitForURL(ANNOTATE_URL, {timeout: 10_000})
}

// Opens the "+ Custom" card, names the face, picks the plane, adds it, and
// checks the new chip is selected with its own always-mounted inputs.
async function addCustomChip(page, label, plane) {
  await page.getByTestId('custom-face').click()
  await expect(page.getByTestId('custom-face-card')).toBeVisible()
  await page.getByTestId('custom-face-label').fill(label)
  await page.getByTestId(`custom-face-plane-${plane}`).click()
  await expect(page.getByTestId(`custom-face-plane-${plane}`)).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByTestId('custom-face-error')).toHaveCount(0)
  await expect(page.getByTestId('custom-face-add')).toBeEnabled()
  await page.getByTestId('custom-face-add').click()
  await expect(page.getByTestId('custom-face-card')).toHaveCount(0)
  // The chip row's `aria-pressed` was dropped for the layout-A face-card
  // grid (`Ui.FaceCard` has no such prop — Capture.res's module-end notes,
  // "Ui gaps"); an unsaved custom chip with no face yet still has no image,
  // so it stays the plain `Empty` look either way — selection is checked
  // via the card's accessible name instead (Capture.res's `cardAriaLabel`).
  await expect(page.getByTestId(`capture-chip-${label}`)).toHaveAccessibleName(new RegExp(`${label}.*selected`))
  await expect(page.locator(`[data-testid="capture-file-${label}"]`)).toHaveCount(1)
  await expect(page.locator(`[data-testid="library-file-${label}"]`)).toHaveCount(1)
}

async function clickNormalizedPoint(page, nx, ny) {
  const canvas = page.getByTestId('annotate-canvas')
  const box = await canvas.boundingBox()
  if (!box) throw new Error('annotate-canvas has no bounding box (not visible?)')
  const raw = await canvas.getAttribute('data-transform')
  const [scale, tx, ty] = (raw ?? '1,0,0').split(',').map(Number)
  const [imgW, imgH] = ((await canvas.getAttribute('data-image-size')) ?? '1x1').split('x').map(Number)
  await page.mouse.click(box.x + tx + nx * imgW * scale, box.y + ty + ny * imgH * scale)
}

async function addDimension(page, {p1, p2, reading, name}) {
  await clickNormalizedPoint(page, p1[0], p1[1])
  await clickNormalizedPoint(page, p2[0], p2[1])
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
  return unzipSync(fs.readFileSync(savedPath))
}

const DEFAULTS = ['top', 'side', 'end', 'detail']

test.describe('custom faces (SPEC §8a A7)', () => {
  test('left_side on plane Side: capture, dimension, export — label paths + JSON, defaults unchanged', async ({
    page,
    browserName,
  }) => {
    test.skip(browserName !== 'chromium', 'export-by-download assertion is chromium-only — see e2e/README.md')

    const dir = tmpDir()
    const partId = await createPart(page, 'Hinge pin')

    // A default face first, so the same export proves the default paths
    // are exactly what they were before A7.
    await captureInto(page, partId, 'top', FIXTURE_TOP)
    await addDimension(page, {p1: [0.17, 0.45], p2: [0.81, 0.45], reading: '42.18', name: 'overall_l'})

    await page.goto(`/#/parts/${partId}/capture`)
    await addCustomChip(page, 'left_side', 'side')
    await page.setInputFiles('[data-testid="capture-file-left_side"]', FIXTURE_SIDE)
    await page.waitForURL(ANNOTATE_URL, {timeout: 10_000})
    // The annotate title shows the label ("left_side · Hinge pin", first
    // letter capitalised for display — SPEC A7 bullet 4).
    await expect(page.locator('.shell-title')).toHaveText('Left_side · Hinge pin')
    await addDimension(page, {p1: [0.3, 0.3], p2: [0.34, 0.3], reading: '1.8', name: 'wall'})

    // Part page: slots and the features table's faces column show labels.
    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-top')).toBeVisible()
    await expect(page.getByTestId('face-left_side')).toBeVisible()
    await expect(page.getByTestId('face-left_side')).toContainText('left_side')
    await expect(page.getByTestId('face-left_side')).toContainText('1600')
    await expect(page.getByTestId('feature-row').filter({hasText: 'wall'})).toContainText('left_side')
    await expect(page.getByTestId('feature-row').filter({hasText: 'overall_l'})).toContainText('top')

    const entries = await exportAndUnzip(page, dir, 'custom')
    expect(Object.keys(entries).sort()).toEqual(
      [
        'features.json',
        'parameters.csv',
        'faces/top.jpg',
        'faces/top_dimensioned.png',
        'faces/left_side.jpg',
        'faces/left_side_dimensioned.png',
      ].sort(),
    )
    expect(entries['faces/left_side.jpg'].byteLength).toBe(fs.readFileSync(FIXTURE_SIDE).byteLength)

    const doc = JSON.parse(Buffer.from(entries['features.json']).toString('utf8'))
    expect(doc.schema).toBe('caliper-companion/features/1')
    expect(doc.faces.map(f => [f.kind, f.label, f.image, f.annotated])).toEqual([
      ['top', 'top', 'faces/top.jpg', 'faces/top_dimensioned.png'],
      ['side', 'left_side', 'faces/left_side.jpg', 'faces/left_side_dimensioned.png'],
    ])
    // `label` sits right after `kind` (SPEC §8a A7 JSON delta).
    expect(Object.keys(doc.faces[1]).slice(0, 3)).toEqual(['id', 'kind', 'label'])
    const wall = doc.features.find(f => f.name === 'wall')
    expect(wall.faceIds).toEqual([doc.faces[1].id])
    expect(wall.value).toBe(1.8)
  })

  test('duplicate or invalid labels are rejected inline; an empty custom chip can be removed', async ({page}) => {
    const partId = await createPart(page, 'Label rules')
    await page.goto(`/#/parts/${partId}/capture`)
    await addCustomChip(page, 'left_side', 'side')

    // Still only a chip (no face yet) — and already taken.
    await page.getByTestId('custom-face').click()
    const nameField = page.getByTestId('custom-face-label')
    await nameField.fill('left_side')
    await expect(page.getByTestId('custom-face-error')).toBeVisible()
    await expect(page.getByTestId('custom-face-error')).toContainText('left_side')
    await expect(page.getByTestId('custom-face-add')).toBeDisabled()
    // A default face's label is taken even before it's captured.
    await nameField.fill('top')
    await expect(page.getByTestId('custom-face-error')).toBeVisible()
    await expect(page.getByTestId('custom-face-add')).toBeDisabled()
    // The feature-name rule applies (SPEC §6.2: lower-case, starts with a letter).
    await nameField.fill('Left')
    await expect(page.getByTestId('custom-face-error')).toBeVisible()
    await nameField.fill('2nd')
    await expect(page.getByTestId('custom-face-error')).toBeVisible()
    await nameField.fill('pi')
    await expect(page.getByTestId('custom-face-error')).toBeVisible()
    // Enter with an invalid name does nothing.
    await nameField.press('Enter')
    await expect(page.getByTestId('custom-face-card')).toBeVisible()
    // A fresh valid name clears the error; Cancel closes the card without adding.
    await nameField.fill('underside')
    await expect(page.getByTestId('custom-face-error')).toHaveCount(0)
    await expect(page.getByTestId('custom-face-add')).toBeEnabled()
    await page.getByTestId('custom-face-cancel').click()
    await expect(page.getByTestId('custom-face-card')).toHaveCount(0)
    await expect(page.getByTestId('capture-chip-underside')).toHaveCount(0)

    // Enter adds (enterkeyhint="done").
    await page.getByTestId('custom-face').click()
    await page.getByTestId('custom-face-label').fill('underside')
    await page.getByTestId('custom-face-label').press('Enter')
    // See `addCustomChip`'s own comment above: no `aria-pressed` on the
    // layout-A face card, selection is in the accessible name instead.
    await expect(page.getByTestId('capture-chip-underside')).toHaveAccessibleName(/underside.*selected/)
    await expect(page.locator('[data-testid="capture-file-underside"]')).toHaveCount(1)

    // Removing an empty custom chip drops it and its inputs; the defaults stay.
    await page.getByTestId('capture-chip-left_side').click()
    await expect(page.getByTestId('custom-face-remove')).toBeVisible()
    await page.getByTestId('custom-face-remove').click()
    await expect(page.getByTestId('capture-chip-left_side')).toHaveCount(0)
    await expect(page.locator('[data-testid="capture-file-left_side"]')).toHaveCount(0)
    await expect(page.getByTestId('capture-chip-underside')).toHaveCount(1)
    for (const kind of DEFAULTS) {
      await expect(page.locator(`[data-testid="capture-file-${kind}"]`)).toHaveCount(1)
      await expect(page.locator(`[data-testid="library-file-${kind}"]`)).toHaveCount(1)
    }
    // A default chip never offers Remove.
    await page.getByTestId('capture-chip-top').click()
    await expect(page.getByTestId('custom-face-remove')).toHaveCount(0)
  })

  test('recapture is by face: side and left_side coexist; a captured custom face persists and is deleted from Part', async ({
    page,
  }) => {
    const partId = await createPart(page, 'Coexist')
    await captureInto(page, partId, 'side', FIXTURE_SIDE)

    await page.goto(`/#/parts/${partId}/capture`)
    await addCustomChip(page, 'left_side', 'side')
    await page.setInputFiles('[data-testid="capture-file-left_side"]', FIXTURE_SIDE)
    await page.waitForURL(ANNOTATE_URL, {timeout: 10_000})
    await addDimension(page, {p1: [0.3, 0.3], p2: [0.34, 0.3], reading: '1.8', name: 'wall'})

    // Later visit: the captured custom chip is derived from the store, is
    // no longer removable here, and recapturing into it replaces *that*
    // face — not "the side face".
    await page.goto(`/#/parts/${partId}/capture`)
    await expect(page.getByTestId('capture-chip-left_side')).toBeVisible()
    await page.getByTestId('capture-chip-left_side').click()
    await expect(page.getByTestId('custom-face-remove')).toHaveCount(0)
    await page.setInputFiles('[data-testid="capture-file-left_side"]', FIXTURE_SIDE)
    await expect(page.getByTestId('recapture-confirm')).toBeVisible()
    await page.getByTestId('recapture-keep').click()
    await page.waitForURL(ANNOTATE_URL, {timeout: 10_000})
    await expect(page.locator('.shell-title')).toHaveText('Left_side · Coexist')
    await expect(page.getByTestId('dimension-count')).toHaveText('1')

    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('face-side')).toHaveCount(1)
    await expect(page.getByTestId('face-left_side')).toHaveCount(1)
    await expect(page.getByTestId('feature-row')).toHaveCount(1)

    // Delete from the Part page: edit mode → Remove on the row → inline
    // confirm. Its dimension goes with it (Store.deleteFace).
    await page.getByTestId('faces-edit').click()
    await expect(page.getByTestId('faces-edit-list')).toBeVisible()
    await page.getByTestId('face-left_side').getByTestId('face-remove').click()
    await expect(page.getByTestId('face-delete-confirm')).toBeVisible()
    await page.getByTestId('face-delete-cancel').click()
    await expect(page.getByTestId('face-delete-confirm')).toHaveCount(0)
    await expect(page.getByTestId('face-left_side')).toHaveCount(1)
    await page.getByTestId('face-left_side').getByTestId('face-remove').click()
    await page.getByTestId('face-delete-confirm').click()
    await expect(page.getByTestId('face-left_side')).toHaveCount(0)
    await expect(page.getByTestId('face-side')).toHaveCount(1)
    await expect(page.getByTestId('feature-row')).toHaveCount(0)
    await page.getByTestId('faces-edit').click()
    await expect(page.getByTestId('faces-edit-list')).toHaveCount(0)
    await expect(page.getByTestId('face-side')).toBeVisible()

    await page.reload()
    await expect(page.getByTestId('face-side')).toBeVisible()
    await expect(page.getByTestId('face-left_side')).toHaveCount(0)
  })

  // The owner's phone already holds face docs written before A7 — no
  // `label`. Seeded straight into PouchDB (same shape annotate.spec.js's
  // `openViaPouch` uses) and read back through the real pages.
  test('a face doc written before A7 (no label) reads back as its kind', async ({page}) => {
    await page.goto('/')
    await page.addScriptTag({path: repoRoot + 'node_modules/pouchdb/dist/pouchdb.js'})
    const base64 = fs.readFileSync(repoRoot + FIXTURE_SIDE).toString('base64')
    const ids = await page.evaluate(async base64 => {
      const db = new window.PouchDB('caliper-companion')
      const now = new Date().toISOString()
      const partId = 'part:' + crypto.randomUUID()
      const faceId = 'face:' + crypto.randomUUID()
      await db.put({
        _id: partId, type: 'part', partId, name: 'Legacy pin', slug: 'legacy_pin', units: 'mm',
        notes: '', anchors: [], createdAt: now, updatedAt: now,
      })
      await db.put({
        _id: faceId, type: 'face', partId, kind: 'side', imageAttachment: 'image.jpg',
        pixelWidth: 1600, pixelHeight: 1200, levelDegrees: null, outline: null,
        capturedAt: now, updatedAt: now,
        _attachments: {'image.jpg': {content_type: 'image/jpeg', data: base64}},
      })
      await db.close()
      return {partId, faceId}
    }, base64)

    await page.goto(`/#/parts/${ids.partId}`)
    await expect(page.getByTestId('face-side')).toBeVisible()
    await expect(page.getByTestId('face-side')).toContainText('1600')

    await page.goto(`/#/parts/${ids.partId}/capture`)
    await expect(page.getByTestId('capture-chip-side')).toBeVisible()
    await expect(page.getByTestId(/^capture-chip-/)).toHaveCount(4)
    await expect(page.locator('[data-testid="capture-file-side"]')).toHaveCount(1)

    await page.goto(`/#/parts/${ids.partId}/faces/${ids.faceId}`)
    await expect(page.locator('.shell-title')).toHaveText('Side · Legacy pin')
  })
})
