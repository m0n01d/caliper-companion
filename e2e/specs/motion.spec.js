// motion.spec.js — SPEC §8a A16a (motion). Chromium only, like
// export.spec.js: WebKit cannot launch in this sandbox (e2e/README.md).
//
// Every route change goes through `Motion.res`: `html[data-nav]` is set to
// `push` / `pop` / `fade` (`Route.direction`), `document.startViewTransition`
// swaps the screen, and the attribute is cleared once `finished` settles.
// The pseudo-elements' computed styles are readable only between `ready`
// and `finished` (≈ 2 frames under `reduce`), so polling them from the test
// side is a race (review B4). Instead `context.addInitScript` patches
// `Document.prototype.startViewTransition` *in the page* and logs, per
// call, the `data-nav` at the call and `::view-transition-old(root)`'s
// `animation-name` at `ready`; the assertions read that log, never the
// live pseudo. `playwright.config.js` sets `reducedMotion: 'reduce'` for
// the whole suite; the `no-preference` blocks here are the only e2e that
// see the real animations — including the A6 fit tween, which the global
// `reduce` otherwise single-ticks (review S9).
import {test, expect} from '@playwright/test'
import {fileURLToPath} from 'node:url'

const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
const endJpg = repoRoot + 'fixtures/hinge_pin/end.jpg'

// The recorder from SPEC A16 (review J8). `rec.names` is `null` until
// `ready`, so readers poll for it.
const recorder = `
  window.__vt = []
  const orig = Document.prototype.startViewTransition
  Document.prototype.startViewTransition = function (cb) {
    const rec = {nav: document.documentElement.dataset.nav ?? null, names: null}
    window.__vt.push(rec)
    const t = orig.call(this, cb)
    t.ready.then(
      () => { rec.names = getComputedStyle(document.documentElement, '::view-transition-old(root)').animationName },
      () => { rec.names = 'skipped' },
    )
    return t
  }`

const readLog = page => page.evaluate(() => window.__vt.map(r => [r.nav, r.names]))

// Parts → Part is the first push a fresh install makes (a created part
// navigates to its page); Back is the matching pop.
async function createPart(page, name = 'Hinge pin') {
  await page.goto('/')
  await page.getByTestId('new-part').click()
  await page.getByTestId('part-name').fill(name)
  await page.getByTestId('part-create').click()
  await page.waitForURL(/#\/parts\/[^/]+$/)
  return page.url().match(/#\/parts\/([^/]+)$/)[1]
}

async function pushThenPop(page) {
  await page.addInitScript(recorder)
  await createPart(page)
  await page.getByRole('button', {name: 'Back'}).click()
  await page.waitForURL(/#\/$/)
  // One entry per route change; `names` lands at `ready`, a frame later.
  await expect.poll(() => page.evaluate(() => window.__vt.length)).toBe(2)
  await expect.poll(() => page.evaluate(() => window.__vt.every(r => r.names !== null))).toBe(true)
  // The attribute is gone once `finished` settles (retrying).
  await expect(page.locator('html')).not.toHaveAttribute('data-nav')
  return readLog(page)
}

test.describe('motion — SPEC §8a A16a', () => {
  test.skip(({browserName}) => browserName !== 'chromium', 'this suite is written for chromium only — see e2e/README.md')

  test.describe('with animations (no-preference)', () => {
    // `reducedMotion` is not a first-class test option — it goes through
    // `contextOptions` (see playwright.config.js).
    test.use({contextOptions: {reducedMotion: 'no-preference'}})

    test('Parts → Part is a push and Back is a pop, each one view transition with the nav slides', async ({page}) => {
      const log = await pushThenPop(page)
      expect(log.map(([nav]) => nav)).toEqual(['push', 'pop'])
      expect(log[0][1]).toContain('cc-nav-out')
      expect(log[1][1]).toContain('cc-nav-back-out')
    })

    // SPEC §8a A6 under the real rAF loop (review S9): the fit after p2
    // passes through `fitting` before `fitted`. A MutationObserver on the
    // canvas records every `data-autofit` value the tween writes, because
    // polling a 160 ms state from the test side could miss it.
    test('the A6 fit still tweens: data-autofit passes through fitting', async ({page}) => {
      const partId = await createPart(page)
      await page.goto(`/#/parts/${partId}/capture`)
      await page.setInputFiles('[data-testid=capture-file-end]', endJpg)
      await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
      // The Capture → Annotate push is a 350 ms view transition here, and a
      // page is non-interactive while one runs (the `::view-transition`
      // pseudo-tree takes the pointer events) — wait for it to settle before
      // tapping, or the taps are swallowed.
      await expect(page.locator('html')).not.toHaveAttribute('data-nav')
      const canvas = page.getByTestId('annotate-canvas')
      await expect(canvas).toHaveAttribute('data-image-size', '1200x1600')
      await expect(canvas).toHaveAttribute('data-autofit', 'none')
      await canvas.evaluate(el => {
        window.__autofit = [el.getAttribute('data-autofit')]
        new MutationObserver(() => window.__autofit.push(el.getAttribute('data-autofit'))).observe(el, {
          attributes: true,
          attributeFilter: ['data-autofit'],
        })
      })
      // Two taps 60 px apart on a horizontal line through the middle of the
      // image, at the fit scale (annotate.spec.js's `placePair`).
      const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
      const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
      const box = await canvas.boundingBox()
      const half = 30 / (w * s)
      for (const n of [{x: 0.5 - half, y: 0.45}, {x: 0.5 + half, y: 0.45}]) {
        await page.mouse.click(box.x + n.x * w * s + tx, box.y + n.y * h * s + ty)
      }
      await expect(canvas).toHaveAttribute('data-autofit', 'fitted')
      const seen = await page.evaluate(() => window.__autofit)
      expect(seen).toContain('fitting')
      expect(seen[seen.length - 1]).toBe('fitted')
    })

    // SPEC §8a A16b: the selection circles enter 20 ms later per row
    // (`cc-select-in`, PartsList.css). Read under `no-preference`: §12
    // zeroes `animation-delay` with the durations under `reduce`.
    test('Edit mode staggers the selection circles: increasing animation-delay down the list', async ({page}) => {
      for (const name of ['Hinge pin', 'Bushing', 'Washer']) await createPart(page, name)
      await page.goto('/')
      await page.getByTestId('parts-edit').click()
      const circles = page.getByTestId('part-select')
      await expect(circles).toHaveCount(3)
      const delays = await circles.evaluateAll(els => els.map(el => parseFloat(getComputedStyle(el).animationDelay)))
      expect(delays).toEqual([0, 0.02, 0.04])
      expect(await circles.first().evaluate(el => getComputedStyle(el).animationName)).toBe('cc-select-in')
    })
  })

  test.describe('under reduced motion (the suite default)', () => {
    test.use({contextOptions: {reducedMotion: 'reduce'}})

    test('the same push and pop log animation-name none and still clear data-nav', async ({page}) => {
      const log = await pushThenPop(page)
      expect(log).toEqual([
        ['push', 'none'],
        ['pop', 'none'],
      ])
    })

    // The take-overs animate on mount via CSS (`cc-rise`, `cc-rise-footer`);
    // the name is on the computed style whatever the duration.
    test('the Edit toolbar, the create form and the folder picker enter with an animation', async ({page}) => {
      await createPart(page)
      await page.goto('/')
      await page.getByTestId('parts-edit').click()
      const footer = page.locator('.shell-footer')
      await expect(footer.getByTestId('edit-toolbar')).toBeVisible()
      expect(await footer.evaluate(el => getComputedStyle(el).animationName)).not.toBe('none')
      await page.getByTestId('parts-edit').click()
      await page.getByTestId('new-part').click()
      const form = page.locator('.parts-form')
      await expect(form).toBeVisible()
      expect(await form.evaluate(el => getComputedStyle(el).animationName)).not.toBe('none')
      await page.getByTestId('part-folder-row').click()
      const picker = page.getByTestId('folder-picker')
      await expect(picker).toBeVisible()
      expect(await picker.evaluate(el => getComputedStyle(el).animationName)).not.toBe('none')
    })

    // SPEC §8a A16b: one `.segmented-indicator` glides between options on a
    // transform; `data-index` / `data-count` on the group drive its offset
    // and width (global.css §8). Under `reduce` the transition is 0 ms, so
    // the computed transform is the landed one.
    test('the segmented indicator moves with data-index: its transform differs between two pressed states', async ({page}) => {
      await page.goto('/')
      await page.getByTestId('new-part').click()
      const group = page.getByRole('group', {name: 'Units'})
      const indicator = group.locator('.segmented-indicator')
      await expect(group).toHaveAttribute('data-count', '2')
      await expect(group).toHaveAttribute('data-index', '0')
      const before = await indicator.evaluate(el => getComputedStyle(el).transform)
      await group.getByRole('button', {name: 'in', exact: true}).click()
      await expect(group).toHaveAttribute('data-index', '1')
      await expect(group.getByRole('button', {name: 'in', exact: true})).toHaveAttribute('aria-pressed', 'true')
      const after = await indicator.evaluate(el => getComputedStyle(el).transform)
      expect(after).not.toBe(before)
      // One option plus the 4 px gap: the indicator's own width + 4.
      await expect
        .poll(async () => {
          const [width, tx] = await indicator.evaluate(el => [
            el.getBoundingClientRect().width,
            new DOMMatrixReadOnly(getComputedStyle(el).transform).e,
          ])
          return Math.abs(tx - (width + 4)) < 1
        })
        .toBe(true)
      // The pressed option is flat now: the fill is the indicator's.
      expect(
        await group.getByRole('button', {name: 'in', exact: true}).evaluate(el => getComputedStyle(el).backgroundColor),
      ).toBe('rgba(0, 0, 0, 0)')
    })

    // SPEC §8a A16b: the reading field takes focus after p2 with the
    // one-shot `cc-ring-fade` (Annotate.css). The name is on the computed
    // style whatever the duration.
    test('the reading field takes focus after p2 with the ring fade', async ({page}) => {
      const partId = await createPart(page)
      await page.goto(`/#/parts/${partId}/capture`)
      await page.setInputFiles('[data-testid=capture-file-end]', endJpg)
      await page.waitForURL(/#\/parts\/[^/]+\/faces\/[^/]+$/)
      await expect(page.locator('html')).not.toHaveAttribute('data-nav')
      const canvas = page.getByTestId('annotate-canvas')
      await expect(canvas).toHaveAttribute('data-image-size', '1200x1600')
      await expect(canvas).toHaveAttribute('data-autofit', 'none')
      const [s, tx, ty] = (await canvas.getAttribute('data-transform')).split(',').map(Number)
      const [w, h] = (await canvas.getAttribute('data-image-size')).split('x').map(Number)
      const box = await canvas.boundingBox()
      const half = 30 / (w * s)
      for (const n of [{x: 0.5 - half, y: 0.45}, {x: 0.5 + half, y: 0.45}]) {
        await page.mouse.click(box.x + n.x * w * s + tx, box.y + n.y * h * s + ty)
      }
      const reading = page.getByTestId('reading')
      await expect(reading).toBeFocused()
      expect(await reading.evaluate(el => getComputedStyle(el).animationName)).toBe('cc-ring-fade')
    })
  })
})
