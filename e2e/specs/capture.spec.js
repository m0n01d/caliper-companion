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
