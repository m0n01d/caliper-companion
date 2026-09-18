// adaptive.spec.js — SPEC §8a A17 (adaptive layout) acceptance at the two
// sizes the phone suite never sees: 1440 × 900 (expanded — desktop, iPad
// landscape) and 820 × 1180 (medium — iPad portrait). Every other spec
// stays at the chromium project's 390 × 844; compact is untouched by A17.
//
// The 1440 block sets `hasTouch: false, isMobile: false` (review B3): with
// the project's `hasTouch: true` Chromium reports `(hover: hover)` false
// and `(pointer: coarse)` true whatever `isMobile` says, so global.css
// §16's hover block never matches and its assertion could not pass while
// the CSS is right. The 820 block keeps the project's touch — it is an
// iPad. `viewport`, `hasTouch` and `isMobile` are first-class test
// options, so the config's `contextOptions.reducedMotion: 'reduce'`
// survives both blocks (review N5).
import {test, expect} from '@playwright/test'
import {fileURLToPath} from 'node:url'

const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
const endJpg = repoRoot + 'fixtures/hinge_pin/end.jpg'

// theme.css: `--cc-bar-height` = `--cc-tap-min` (44) + safe-area-top (0
// here); `--cc-page-x` is 24 at expanded. The sticky aside sits at their
// sum (Part.css, review B1).
const BAR = 44
const PAGE_X_EXPANDED = 24

// ── setup ──────────────────────────────────────────────────────────────

async function createPart(page, name = 'Hinge pin') {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+$/)
  return page.url().match(/#\/parts\/([^/]+)$/)[1]
}

// The same flow annotate.spec.js's `openViaUi` runs: one part, the END
// face from the fixture (EXIF-rotated → 1200 × 1600 oriented).
async function captureEnd(page, partId) {
  await page.goto(`/#/parts/${partId}/capture`)
  await page.setInputFiles('[data-testid=capture-file-end]', endJpg)
  await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
  await expect(page.getByTestId('annotate-canvas')).toHaveAttribute('data-image-size', '1200x1600')
}

// ── geometry helpers ───────────────────────────────────────────────────

const tracks = loc =>
  loc.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(' ').filter(Boolean))

// `.shell-content` is `margin-inline: auto` inside `.shell` (global.css
// §16), so "centred" is measured against the scroller's own content box
// — its client width, which excludes a classic scrollbar.
async function shellCentreOffset(page, loc) {
  const b = await loc.boundingBox()
  const shell = await page.locator('.shell').evaluate(el => {
    const r = el.getBoundingClientRect()
    return {left: r.left + el.clientLeft, width: el.clientWidth}
  })
  return b.x + b.width / 2 - (shell.left + shell.width / 2)
}

const shellScroll = page =>
  page.locator('.shell').evaluate(el => ({scrollHeight: el.scrollHeight, clientHeight: el.clientHeight}))

// The canvas publishes `data-transform="scale,tx,ty"` (image px → canvas
// CSS px) and `data-image-size="WxH"`; a normalized point's screen
// position follows (annotate.spec.js's `screenOf`).
async function tapNormalized(page, n) {
  const canvas = page.getByTestId('annotate-canvas')
  const box = await canvas.boundingBox()
  const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
  const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
  await page.mouse.click(box.x + tx + n.x * w * s, box.y + ty + n.y * h * s)
}

// ── expanded: 1440 × 900, a pointer ────────────────────────────────────

test.describe('adaptive — expanded (1440 × 900, pointer)', () => {
  test.use({viewport: {width: 1440, height: 900}, hasTouch: false, isMobile: false})

  test('Parts: the list sits in the 720 column, centred', async ({page}) => {
    await createPart(page)
    await page.goto('/')
    await expect(page.getByTestId('part-row')).toHaveCount(1)
    await expect(page.locator('.shell')).toHaveAttribute('data-column', 'column')
    const content = page.locator('.shell-content')
    const box = await content.boundingBox()
    expect(box.width).toBeLessThanOrEqual(720)
    expect(Math.abs(await shellCentreOffset(page, content))).toBeLessThanOrEqual(2)
  })

  test('Part: two grid tracks, the aside sticks under the bar, Export caps at 400', async ({page}) => {
    await createPart(page)
    await expect(page.getByTestId('capture-face')).toBeVisible()
    await expect(page.locator('.shell')).toHaveAttribute('data-column', 'wide')
    expect(await tracks(page.locator('.part-columns'))).toHaveLength(2)

    const exportBox = await page.getByTestId('export').boundingBox()
    expect(exportBox.width).toBeLessThanOrEqual(400)

    // The sticky (Part.css, review B1): give the gallery column something
    // to scroll past, scroll the shell, and the aside stays put at
    // bar + page-x — with the default `stretch` it would have scrolled
    // away with its row.
    await page.locator('.part-gallery').evaluate(el => {
      el.style.minHeight = '3000px'
    })
    await page.locator('.shell').evaluate(el => {
      el.scrollTop = 1000
    })
    await expect
      .poll(async () => (await page.locator('.part-aside').boundingBox()).y)
      .toBeCloseTo(BAR + PAGE_X_EXPANDED, 0)
    expect((await page.locator('.part-aside').boundingBox()).y).toBeCloseTo(BAR + PAGE_X_EXPANDED, 0)
  })

  test('Annotate: the panel sits to the right of the canvas, the canvas is ≥ 600 tall, the page does not scroll', async ({
    page,
  }) => {
    const partId = await createPart(page)
    await captureEnd(page, partId)
    await expect(page.locator('.shell')).toHaveAttribute('data-column', 'bleed')

    const canvas = await page.getByTestId('annotate-canvas').boundingBox()
    const panel = await page.locator('.annotate .panel').boundingBox()
    expect(canvas.x + canvas.width).toBeLessThanOrEqual(panel.x)
    expect(canvas.height).toBeGreaterThanOrEqual(600)
    const shell = await shellScroll(page)
    expect(shell.scrollHeight).toBe(shell.clientHeight)
    // The panel scrolls itself, not the page (review B2).
    await expect(page.locator('.annotate .panel')).toHaveCSS('overflow-y', 'auto')

    // The canvas sized itself from the taller cell (ResizeObserver →
    // ViewSized → refit, review S11): two taps land as pending points and
    // the A6 fit frames them with the reading focused, as on the phone.
    await tapNormalized(page, {x: 0.55, y: 0.18})
    await tapNormalized(page, {x: 0.55, y: 0.42})
    await expect(page.getByTestId('reading')).toBeFocused()
    await expect(page.getByTestId('pending-points')).toHaveText(/^[\d.]+,[\d.]+;[\d.]+,[\d.]+$/)
    const after = await shellScroll(page)
    expect(after.scrollHeight).toBe(after.clientHeight)
  })

  test('hover on a part row changes its background', async ({page}) => {
    await createPart(page)
    await page.goto('/')
    const row = page.getByTestId('part-row').first()
    await expect(row).toBeVisible()
    const background = () => row.evaluate(el => getComputedStyle(el).backgroundColor)
    const rest = await background()
    await row.hover()
    await expect.poll(background).not.toBe(rest)
    await expect(row.locator('.list-row-link')).toHaveCSS('cursor', 'pointer')
  })

  test('Escape closes the folder picker, then the create form', async ({page}) => {
    await page.goto('/')
    await page.getByTestId('new-part').click()
    await page.getByTestId('part-name').fill('Window switch bezel')
    await page.getByTestId('part-folder-row').click()
    await expect(page.getByTestId('folder-picker-list')).toBeVisible()

    // Outermost first (PartsList.Escape): the picker goes, the form stays.
    await page.keyboard.press('Escape')
    await expect(page.getByTestId('folder-picker-list')).toHaveCount(0)
    await expect(page.getByTestId('part-name')).toBeVisible()

    await page.keyboard.press('Escape')
    await expect(page.getByTestId('part-name')).toHaveCount(0)
    await expect(page.getByTestId('new-part')).toBeVisible()

    // Nothing open: a third Escape is a no-op, not an error.
    await page.keyboard.press('Escape')
    await expect(page.getByTestId('new-part')).toBeVisible()
  })
})

// ── medium: 820 × 1180, an iPad in portrait (touch kept) ───────────────

test.describe('adaptive — medium (820 × 1180, touch)', () => {
  test.use({viewport: {width: 820, height: 1180}})

  test('Parts: the list sits in the 720 column, centred', async ({page}) => {
    await createPart(page)
    await page.goto('/')
    await expect(page.getByTestId('part-row')).toHaveCount(1)
    const content = page.locator('.shell-content')
    const box = await content.boundingBox()
    expect(box.width).toBeLessThanOrEqual(720)
    expect(Math.abs(await shellCentreOffset(page, content))).toBeLessThanOrEqual(2)
  })

  test('Part: the face grid is 3-up with cards ≤ 240', async ({page}) => {
    const partId = await createPart(page)
    await captureEnd(page, partId)
    await page.goto(`/#/parts/${partId}`)
    await expect(page.getByTestId('capture-face')).toBeVisible()
    // Single column at medium: `.part-columns` is the plain `.stack-lg`.
    await expect(page.locator('.part-columns')).not.toHaveCSS('display', 'grid')
    expect(await tracks(page.locator('.face-grid'))).toHaveLength(3)
    const card = await page.locator('.face-card').first().boundingBox()
    expect(card.width).toBeLessThanOrEqual(240)
  })

  test('Annotate: the canvas is ≥ 500 tall over the panel', async ({page}) => {
    const partId = await createPart(page)
    await captureEnd(page, partId)
    const canvas = await page.getByTestId('annotate-canvas').boundingBox()
    const panel = await page.locator('.annotate .panel').boundingBox()
    expect(canvas.height).toBeGreaterThanOrEqual(500)
    // Stacked, not side by side: the panel starts below the canvas.
    expect(panel.y).toBeGreaterThanOrEqual(canvas.y + canvas.height)
  })
})
